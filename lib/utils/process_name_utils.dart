import 'dart:math' as math;

/// нормализует ввод/путь к имени процесса для sing-box (например `Telegram.exe`).
/// регистр важен: sing-box сравнивает process_name через map-lookup без
/// приведения к нижнему регистру, так что сравнение чувствительно к регистру.
/// на windows имя процесса хранит реальный регистр (`Telegram.exe`), и если
/// его занизить — правило не совпадёт и трафик уйдёт мимо прокси.
String normalizeProcessName(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '';
  s = s.replaceAll('"', '');
  final cut = math.max(s.lastIndexOf(r'\'), s.lastIndexOf('/'));
  if (cut >= 0) {
    // Отрезаем по ОБОИМ разделителям, а не средствами `path`.
    //
    // `p.basename` работает в стиле ТЕКУЩЕЙ платформы, а имя сюда может
    // приехать с чужой: список сплит-туннелирования переносится между машинами
    // через резервную копию настроек. На Linux `\` разделителем не считается, и
    // виндовый путь возвращался целиком — запись «C:\...\Discord.exe» переставала
    // схлопываться с «Discord.exe» и превращалась во второе приложение в списке.
    s = s.substring(cut + 1);
  }
  if (!s.toLowerCase().endsWith('.exe')) {
    s = '$s.exe';
  }
  return s;
}

/// варианты имени для правил sing-box: исходный регистр и, если отличается,
/// нижний — на случай значений, сохранённых старой версией в нижнем регистре.
List<String> processNameMatchVariants(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return const [];
  final lower = trimmed.toLowerCase();
  return trimmed == lower ? [trimmed] : [trimmed, lower];
}
