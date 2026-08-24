import 'awg_profile.dart';
import 'custom_clash_config.dart';
import 'custom_xray_config.dart';

/// Делит текст, который пользователь вставил (буфер, файл, QR, deep link), на
/// конфиги серверов.
///
/// Резать по строкам можно далеко не всё:
///  - AmneziaWG `.conf` — единый блок с переводами строк;
///  - готовый конфиг xray — тоже единый блок (json с отступами), а массив
///    таких объектов это сразу несколько серверов;
///  - готовый конфиг Clash — единый блок, и режется он хуже всех: в YAML нет
///    ни фигурной скобки в начале, ни строки-ссылки, поэтому построчный разбор
///    превращал один профиль в десятки «неподдерживаемых форматов»;
///  - список ссылок — вот он построчно.
List<String> splitServerImportPayload(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const [];
  if (AwgProfile.isAwgConfig(text)) return [text];

  // Clash — раньше xray, как и в `validateServerConfig`: json-конфиг Clash тоже
  // начинается с '{', и xray-разбор забрал бы его себе.
  if (CustomClashConfig.looksLikeClash(text)) {
    final clash = CustomClashConfig.extractConfigs(text);
    // Пусто — конфиг похож на clash, но негоден (нет узлов, нет групп у
    // провайдеров, битый YAML). Отдаём целиком: точную причину назовёт
    // `CustomClashConfig.describeProblem` на валидации, а построчно она
    // превратилась бы в «Unsupported format» на каждой строке.
    return clash.isNotEmpty ? clash : [text];
  }

  final custom = CustomXrayConfig.extractConfigs(text);
  if (custom.isNotEmpty) return custom;

  // json, который конфигом не оказался (sing-box, ответ панели): отдаём целиком
  // — так пользователь получит одну внятную причину отказа, а не по ошибке на
  // каждую строку разбитого json.
  if (text.startsWith('{') || text.startsWith('[')) return [text];

  return text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}
