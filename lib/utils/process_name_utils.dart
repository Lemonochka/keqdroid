import 'package:path/path.dart' as p;

/// нормализует ввод/путь к имени процесса для sing-box (например `Telegram.exe`).
/// регистр важен: sing-box сравнивает process_name через map-lookup без
/// приведения к нижнему регистру, так что сравнение чувствительно к регистру.
/// на windows имя процесса хранит реальный регистр (`Telegram.exe`), и если
/// его занизить — правило не совпадёт и трафик уйдёт мимо прокси.
String normalizeProcessName(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '';
  s = s.replaceAll('"', '');
  if (s.contains(r'\') || s.contains('/')) {
    s = p.basename(s);
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
