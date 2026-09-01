import 'dart:io';

import 'geo_dat_reader.dart';

/// Список кодов, которые реально лежат в geoip.dat / geosite.dat.
///
/// Зачем: списки маршрутизации — свободный текст, и `geosite:sberbank`
/// (нет в базе v2fly) выглядит для пользователя ровно так же, как
/// `geosite:yandex` (есть). Xray же на неизвестном коде НЕ игнорирует правило,
/// а падает на разборе конфига целиком — SOCKS-инбаунд не поднимается, и
/// подключение умирает с безымянным «SOCKS5 port 2080 not ready». Индекс
/// позволяет выкинуть такие токены до старта ядра и, главное, показать их
/// пользователю в экране роутинга (см. `unknownGeoTokens`).
///
/// Разбор формата — в [GeoDatReader].
class GeoAssetIndex {
  const GeoAssetIndex({
    required this.geoipCodes,
    required this.geositeCodes,
  });

  /// Пустой индекс: базы не найдены/не прочитались. Валидация при нём
  /// отключается — лучше отдать конфиг ядру как есть, чем выкинуть рабочее
  /// правило по итогам неудачного чтения.
  static const empty = GeoAssetIndex(geoipCodes: {}, geositeCodes: {});

  /// Коды в нижнем регистре (в файлах они заглавные, в правилах — как придётся).
  final Set<String> geoipCodes;
  final Set<String> geositeCodes;

  bool get isEmpty => geoipCodes.isEmpty && geositeCodes.isEmpty;

  /// Порог, за которым база geoip считается полной.
  ///
  /// Судим по числу кодов, а не по флажку в настройках: флажок разъезжается с
  /// тем, что реально лежит на диске (файл подменили, откатили, восстановили из
  /// бэкапа), а коды — это и есть сам файл. Во вшитой урезанной базе их четыре,
  /// в полной v2fly — 263, поэтому любой порог между ними надёжен.
  static const fullGeoipCodeThreshold = 32;

  /// Полная ли база стран на диске. Урезанная едет в APK, полная догружается
  /// (`GeoBaseDownloader`) — и от этого зависит, стоит ли объяснять человеку
  /// пропавшее правило нехваткой базы.
  bool get hasFullGeoip => geoipCodes.length >= fullGeoipCodeThreshold;

  /// Читает обе базы из каталога [dir] (там, где их ищет само ядро через
  /// `XRAY_LOCATION_ASSET`). Отсутствующий файл — пустое множество, не ошибка.
  static Future<GeoAssetIndex> fromDirectory(String dir) async {
    final geoip = await readCodes(File(geoipPath(dir)));
    final geosite = await readCodes(File(geositePath(dir)));
    return GeoAssetIndex(geoipCodes: geoip, geositeCodes: geosite);
  }

  static String geoipPath(String dir) =>
      '$dir${Platform.pathSeparator}geoip.dat';

  static String geositePath(String dir) =>
      '$dir${Platform.pathSeparator}geosite.dat';

  /// Коды верхнего уровня из одного .dat. Пустое множество, если файла нет
  /// или он не похож на v2fly-protobuf.
  static Future<Set<String>> readCodes(File file) => GeoDatReader.codes(file);
}
