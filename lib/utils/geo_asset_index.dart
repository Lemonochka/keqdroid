import 'dart:io';

import 'geo_dat_reader.dart';

class GeoAssetIndex {
  const GeoAssetIndex({required this.geoipCodes, required this.geositeCodes});

  // пустой индекс отключает проверку: лучше отдать конфиг ядру, чем выкинуть рабочее правило
  static const empty = GeoAssetIndex(geoipCodes: {}, geositeCodes: {});

  final Set<String> geoipCodes;
  final Set<String> geositeCodes;

  bool get isEmpty => geoipCodes.isEmpty && geositeCodes.isEmpty;

  // по числу кодов: во вшитой базе их 4, в полной v2fly 263
  static const fullGeoipCodeThreshold = 32;

  bool get hasFullGeoip => geoipCodes.length >= fullGeoipCodeThreshold;

  static Future<GeoAssetIndex> fromDirectory(String dir) async {
    final geoip = await readCodes(File(geoipPath(dir)));
    final geosite = await readCodes(File(geositePath(dir)));
    return GeoAssetIndex(geoipCodes: geoip, geositeCodes: geosite);
  }

  static String geoipPath(String dir) =>
      '$dir${Platform.pathSeparator}geoip.dat';

  static String geositePath(String dir) =>
      '$dir${Platform.pathSeparator}geosite.dat';

  static Future<Set<String>> readCodes(File file) => GeoDatReader.codes(file);
}
