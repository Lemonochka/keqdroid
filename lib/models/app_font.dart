/// Опции шрифта интерфейса. Выбор применяется поверх любой темы.
///
/// `family == null` — системный шрифт по умолчанию (Roboto/San Francisco/…).
/// Остальные — bundled-шрифты: каждый объявлен в `pubspec.yaml` (`fonts:`),
/// лежит в `assets/fonts/` вместе с OFL-лицензией и обязан покрывать кириллицу
/// (UI есть на русском/немецком). CJK-глифов в них нет — китайский текст падает
/// на системный фолбэк, как и с Comfortaa.
class AppFont {
  final String id;

  /// Отображаемое имя. Для `system` — плейсхолдер, в UI заменяется на
  /// локализованную строку; у остальных это имя семейства (имя собственное).
  final String label;

  /// Значение для `ThemeData.fontFamily`. `null` — системный шрифт.
  final String? family;

  const AppFont({required this.id, required this.label, this.family});
}

const String kDefaultFontId = 'system';

const List<AppFont> kAppFonts = <AppFont>[
  AppFont(id: kDefaultFontId, label: 'System'),
  AppFont(id: 'comfortaa', label: 'Comfortaa', family: 'Comfortaa'),
  AppFont(id: 'montserrat', label: 'Montserrat', family: 'Montserrat'),
  AppFont(id: 'rubik', label: 'Rubik', family: 'Rubik'),
];

/// Возвращает опцию по id; неизвестный/устаревший id → системный шрифт.
AppFont resolveAppFont(String id) =>
    kAppFonts.firstWhere((f) => f.id == id, orElse: () => kAppFonts.first);
