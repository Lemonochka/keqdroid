import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../core/app_logger.dart';
import '../utils/geo_asset_index.dart';
import 'geo_asset_service.dart';
import 'update_service.dart';

/// Догружает полную базу `geoip.dat` поверх вшитой урезанной.
///
/// В APK едет база на четыре кода — те, что приложение выпускает само. Полная
/// весит 23.5 МБ, и 58% её объёма это пять стран, которых нет ни в одном
/// правиле по умолчанию: возить их в каждой установке ради тех, кто напишет
/// `geoip:br`, — плохая сделка.
///
/// Выкинуть базу целиком и качать всегда нельзя: это VPN-клиент, его ставят там,
/// где сеть уже режут, и первое подключение не должно зависеть от похода на
/// GitHub — туннеля ещё нет, а хост может быть недоступен поэтому.
///
/// Только Android: десктоп возит полную базу рядом с исполняемым файлом.
class GeoBaseDownloader {
  GeoBaseDownloader._();

  static const _owner = 'Lemonochka';
  static const _repo = 'keqdroid';

  /// Имя ассета в релизе. Его хеш — в `<имя>.sha256` рядом или в общем
  /// `SHA256SUMS` релиза; без хеша установка отклоняется.
  static const assetName = 'geoip.dat';

  static bool isFullBase(GeoAssetIndex index) => index.hasFullGeoip;

  /// Есть ли вообще смысл показывать кнопку.
  static bool get isSupported => Platform.isAndroid;

  /// Скачать и поставить полную базу. Бросает при любой неудаче — вызывающий
  /// показывает причину человеку.
  static Future<void> install({
    void Function(double progress)? onProgress,
    Dio? client,
  }) async {
    final dir = await GeoAssetService.geoDir();
    if (dir == null) {
      throw const GeoBaseDownloadException('geo directory is unknown');
    }

    final dio = client ?? Dio();
    final (url, shaUrl) = await _resolveUrls(dio);

    // Качаем во временный файл рядом с целью: подменять базу под работающим
    // ядром нельзя, а переименование в пределах каталога атомарно.
    final target = File(p.join(dir, assetName));
    final temp = File('${target.path}.part');
    if (temp.existsSync()) await temp.delete();

    try {
      await dio.download(
        url,
        temp.path,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(received / total);
        },
      );

      final expected = await _expectedSha256(dio, shaUrl);
      final actual = (await sha256.bind(temp.openRead()).first).toString();
      if (expected.toLowerCase() != actual.toLowerCase()) {
        throw GeoBaseDownloadException(
          'checksum mismatch: expected $expected, got $actual',
        );
      }

      final size = await temp.length();
      await temp.rename(target.path);
      // Индекс кодов кэшируется на процесс — без сброса санитайзер продолжит
      // выбрасывать правила по старому, урезанному списку.
      GeoAssetService.invalidate();
      AppLogger.instance.info(
        'Full geoip base installed ($size bytes) from $url',
      );
    } catch (e) {
      if (temp.existsSync()) {
        try {
          await temp.delete();
        } catch (_) {
          // Остался огрызок — перезапишется следующей попыткой.
        }
      }
      if (e is GeoBaseDownloadException) rethrow;
      throw GeoBaseDownloadException('$e');
    }
  }

  /// Адреса ассета и его контрольной суммы в последнем релизе.
  ///
  /// Именно в последнем, а не в релизе текущей версии приложения: гео-база —
  /// это данные, а не код, они не привязаны к версии клиента, и свежие списки
  /// нужнее совпадения тегов.
  static Future<(String, String)> _resolveUrls(Dio dio) async {
    final Response<dynamic> res;
    try {
      res = await dio.get<dynamic>(
        'https://api.github.com/repos/$_owner/$_repo/releases/latest',
        options: Options(headers: {'Accept': 'application/vnd.github+json'}),
      );
    } catch (e) {
      throw GeoBaseDownloadException('release lookup failed: $e');
    }

    final assets = (res.data is Map ? res.data['assets'] : null);
    if (assets is! List) {
      throw const GeoBaseDownloadException('release has no assets');
    }

    final urls = urlsFromAssets(assets);
    if (urls == null) {
      throw const GeoBaseDownloadException(
        'the latest release does not carry geoip.dat with its checksum',
      );
    }
    return urls;
  }

  /// Адреса базы и её хеша среди ассетов релиза; null — чего-то из двух нет.
  ///
  /// Хеш ищется тем же правилом, что у апдейтера: свой `.sha256` или общий
  /// `SHA256SUMS`. Раньше здесь понимали только первое, и релиз с одним общим
  /// файлом оставил бы кнопку «скачать полную базу» без хеша.
  @visibleForTesting
  static (String, String)? urlsFromAssets(List<dynamic> assets) {
    String? urlOf(Object? asset) {
      if (asset is! Map) return null;
      final url = asset['browser_download_url'];
      return url is String && url.isNotEmpty ? url : null;
    }

    String? baseUrl;
    for (final a in assets) {
      if (a is Map && a['name'] == assetName) baseUrl = urlOf(a);
    }
    final checksumUrl = urlOf(UpdateService.checksumAssetFor(
      [
        for (final a in assets)
          if (a is Map) Map<String, dynamic>.from(a),
      ],
      assetName,
    ));
    if (baseUrl == null || checksumUrl == null) return null;
    return (baseUrl, checksumUrl);
  }

  static Future<String> _expectedSha256(Dio dio, String url) async {
    final res = await dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    // Голый хеш своего `.sha256` или строка `<hash>  geoip.dat` из общего
    // `SHA256SUMS` — разбор тот же, что у апдейтера.
    final hash = UpdateService.extractSha256(res.data ?? '', assetName);
    if (hash == null) {
      throw const GeoBaseDownloadException('checksum file is unreadable');
    }
    return hash;
  }
}

class GeoBaseDownloadException implements Exception {
  const GeoBaseDownloadException(this.message);
  final String message;

  @override
  String toString() => message;
}
