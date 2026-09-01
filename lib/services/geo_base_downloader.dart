import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../core/app_logger.dart';
import '../utils/geo_asset_index.dart';
import 'geo_asset_service.dart';

/// Догружает ПОЛНУЮ базу `geoip.dat` поверх вшитой урезанной.
///
/// В APK едет база на четыре кода — ровно те, что приложение выпускает само
/// (`tool/geo_lite.dart`). Полная база v2fly весит 23.5 МБ, и 58% её объёма —
/// пять стран, которых нет ни в одном правиле по умолчанию. Возить их в каждой
/// установке ради тех, кто напишет `geoip:br`, — плохая сделка; отдать по
/// кнопке тем, кому надо, — хорошая.
///
/// Почему нельзя было выкинуть базу целиком и качать всегда: это VPN-клиент,
/// его ставят там, где сеть уже режут. Первое подключение не должно зависеть от
/// похода на GitHub — туннеля ещё нет, а хост может быть недоступен именно
/// поэтому. Вшитый минимум гарантирует, что из коробки работает всё, что
/// приложение обещает своими же пресетами.
///
/// Только Android: десктопные сборки возят полную базу рядом с исполняемым
/// файлом, качать там нечего.
class GeoBaseDownloader {
  GeoBaseDownloader._();

  static const _owner = 'Lemonochka';
  static const _repo = 'keqdroid';

  /// Имя ассета в релизе. Рядом обязан лежать `<имя>.sha256` — как у остальных
  /// ассетов, иначе установка отклоняется.
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

  /// Адреса ассета и его контрольной суммы в ПОСЛЕДНЕМ релизе.
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

    String? find(String name) {
      for (final a in assets) {
        if (a is Map && a['name'] == name) {
          final url = a['browser_download_url'];
          if (url is String && url.isNotEmpty) return url;
        }
      }
      return null;
    }

    final url = find(assetName);
    final shaUrl = find('$assetName.sha256');
    if (url == null || shaUrl == null) {
      throw const GeoBaseDownloadException(
        'the latest release does not carry geoip.dat with its checksum',
      );
    }
    return (url, shaUrl);
  }

  static Future<String> _expectedSha256(Dio dio, String url) async {
    final res = await dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    // Сайдкар бывает и голым хешем, и строкой в стиле `sha256sum`:
    // `<hash>  <file>`. Берём первое шестнадцатеричное слово нужной длины.
    final match = RegExp(r'\b[0-9a-fA-F]{64}\b').firstMatch(res.data ?? '');
    if (match == null) {
      throw const GeoBaseDownloadException('checksum file is unreadable');
    }
    return match.group(0)!;
  }
}

class GeoBaseDownloadException implements Exception {
  const GeoBaseDownloadException(this.message);
  final String message;

  @override
  String toString() => message;
}
