import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/app_logger.dart';
import '../models/app_settings.dart';
import '../tunnel/linux_core_paths.dart';
import '../tunnel/macos_core_paths.dart';
import '../tunnel/windows_core_paths.dart';
import '../utils/geo_asset_index.dart';
import '../utils/geo_rule_sanitizer.dart';

class GeoAssetService {
  GeoAssetService._();

  static Future<GeoAssetIndex>? _cached;

  static Future<GeoAssetIndex> index() => _cached ??= _load();

  static void invalidate() => _cached = null;

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

  static Future<String?> geoDir() => _geoDir();

  static Future<String?> _geoDir() async {
    if (Platform.isAndroid) {
      return (await getApplicationSupportDirectory()).path;
    }
    if (Platform.isWindows) return WindowsCorePaths.geoAssetDir();
    if (Platform.isLinux) return LinuxCorePaths.geoAssetDir();
    if (Platform.isMacOS) return MacosCorePaths.geoAssetDir();
    return null;
  }

  static Future<AppSettings> sanitizeRules(AppSettings settings) async {
    final assets = await index();
    final result = stripUnknownGeoTokens(settings, assets);
    if (result.dropped.isNotEmpty) {
      final trimmedBase =
          !assets.hasFullGeoip &&
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

  static Future<bool> hasFullGeoip() async => (await index()).hasFullGeoip;
}
