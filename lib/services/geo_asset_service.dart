import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/app_logger.dart';
import '../models/app_settings.dart';
import '../tunnel/linux_core_paths.dart';
import '../tunnel/windows_core_paths.dart';
import '../utils/geo_asset_index.dart';
import '../utils/geo_rule_sanitizer.dart';

/// Находит geoip.dat/geosite.dat там же, где их читает ядро, и чистит по ним
/// списки маршрутизации перед генерацией конфига.
class GeoAssetService {
  GeoAssetService._();

  static Future<GeoAssetIndex>? _cached;

  /// Индекс кодов geo-баз. Кэшируется на процесс: файлы едут в сборке и в
  /// рантайме не меняются, а разбор дёргается на каждое подключение.
  static Future<GeoAssetIndex> index() => _cached ??= _load();

  /// Сбросить кэш индекса. Нужен после подмены базы на диске — иначе
  /// санитайзер продолжит судить о правилах по старому списку кодов.
  static void invalidate() => _cached = null;

  /// Только для тестов: сбросить кэш.
  static void resetCacheForTests() => invalidate();

  static Future<GeoAssetIndex> _load() async {
    try {
      final dir = await _geoDir();
      if (dir == null) return GeoAssetIndex.empty;
      final index = await GeoAssetIndex.fromDirectory(dir);
      AppLogger.instance.debug(
        'Geo assets in $dir: ${index.geoipCodes.length} geoip, '
        '${index.geositeCodes.length} geosite codes',
      );
      return index;
    } catch (e) {
      AppLogger.instance.warn('Geo asset index unavailable: $e');
      return GeoAssetIndex.empty;
    }
  }

  /// Каталог, из которого ядро читает geo-базы. Нужен ещё и панели
  /// «Внутренности» — она показывает размеры и даты этих же файлов.
  static Future<String?> geoDir() => _geoDir();

  static Future<String?> _geoDir() async {
    if (Platform.isAndroid) {
      // Нативная часть распаковывает базы в filesDir (XrayGeoAssets) и туда же
      // указывает ядру XRAY_LOCATION_ASSET; path_provider отдаёт этот каталог.
      return (await getApplicationSupportDirectory()).path;
    }
    if (Platform.isWindows) return WindowsCorePaths.geoAssetDir();
    if (Platform.isLinux) return LinuxCorePaths.geoAssetDir();
    return null;
  }

  /// Настройки для генераторов конфига без geo-правил, которых нет в базах.
  /// Выброшенное пишем в лог — правило исчезает из маршрутизации молча, и это
  /// единственный след, по которому можно понять, почему.
  static Future<AppSettings> sanitizeRules(AppSettings settings) async {
    final assets = await index();
    final result = stripUnknownGeoTokens(settings, assets);
    if (result.dropped.isNotEmpty) {
      // Отдельная подсказка про урезанную базу: «правило исчезло» и «страны в
      // базе нет, её надо догрузить» — разные диагнозы, а выглядят одинаково.
      final trimmedBase = !assets.hasFullGeoip &&
          result.dropped.any((t) => t.toLowerCase().startsWith('geoip:'));
      AppLogger.instance.warn(
        'Routing rules: dropped ${result.dropped.length} geo entries missing '
        'from the bundled geoip/geosite databases (they would abort the core '
        'at config load): ${result.dropped.join(', ')}'
        '${trimmedBase ? ' — the bundled country database is the trimmed one; '
            'download the full base in Settings -> About -> Internals' : ''}',
      );
    }
    return result.settings;
  }

  /// Полная ли база стран сейчас на диске — по ней экран «Внутренности»
  /// решает, предлагать ли догрузку.
  static Future<bool> hasFullGeoip() async => (await index()).hasFullGeoip;
}
