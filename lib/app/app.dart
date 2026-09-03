import 'dart:async';
import 'dart:io' show Platform;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keqdroid/l10n/app_localizations.dart';

import '../models/app_font.dart';
import '../models/app_settings.dart';
import '../models/icon_shape.dart';
import '../platform/vpn_native_bridge.dart';
import '../providers/providers.dart';
import '../shared/ui/expressive.dart';
import '../shared/ui/expressive_elements.dart';
import '../shared/ui/haptics.dart';
import '../shared/ui/kawaii_decorations.dart';
import '../utils/app_locale.dart';

const kSeedFallback = Color(0xFFFFAEBC);

/// Корневой навигатор приложения.
///
/// Нужен тем, кто живёт вне дерева виджетов и всё-таки обязан показать диалог:
/// меню трея на Windows — нативное (его рисует сама система), а переключение в
/// TUN спрашивает про перезапуск с правами администратора. Спросить не у кого,
/// если контекста нет.
final rootNavigatorKey = GlobalKey<NavigatorState>();

class ThemePreset {
  final String id;
  final String name;
  final Color seed;

  /// Кастомная схема вместо одноцветного fromSeed.
  final ColorScheme Function(Brightness)? schemeBuilder;

  /// «Финтифлюшки»: свой шрифт, сильнее скругления, анимированный оверлей.
  final bool flair;

  /// Палитра kawaii-оверлея (стикеры и дождик из частиц); только у flair-тем.
  final KawaiiFlavor? kawaii;

  /// Как палитра строится из сида.
  ///
  /// `tonalSpot` — то же, чем строит Material You сам Android, и потому дефолт:
  /// иначе тема «Ocean» рядом с синей системной выглядит кислотной, хотя сид у
  /// них почти один. Дело в контейнерных ролях: `fidelity` держится за сид и в
  /// тёмной схеме кладёт в `primaryContainer` его же, на полной насыщенности
  /// (`#4c8eff` против `#2b4678` у tonalSpot), а на контейнерах держится
  /// заливка всех кружков-иконок, чипов и кнопок — светится сразу весь экран.
  ///
  /// Kawaii-темам `fidelity` оставлен намеренно: там леденцовый цвет и есть
  /// смысл темы, а поверхности под него подобраны вручную.
  final DynamicSchemeVariant variant;

  const ThemePreset({
    required this.id,
    required this.name,
    required this.seed,
    this.schemeBuilder,
    this.flair = false,
    this.kawaii,
    this.variant = DynamicSchemeVariant.tonalSpot,
  });
}

/// Kawaii «Sakura»: однотонная клубнично-молочная пастель (намеренно чистый
/// розовый kawaii-кор, без второго «небесного» цвета).
/// База — fromSeed, чтобы тона/контрасты остались корректными по Material 3;
/// вручную только фоновые поверхности: кремово-розовые вместо нейтрально-серых
/// в светлой, тёмная — сливовая с розовым тинтом. Контрасты onSurface не
/// страдают: тона близки к исходным.
ColorScheme _sakuraScheme(Brightness brightness) {
  final pink = ColorScheme.fromSeed(
    seedColor: const Color(0xFFFF8FB8),
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  final light = brightness == Brightness.light;
  return pink.copyWith(
    surface: light ? const Color(0xFFFFF4F8) : const Color(0xFF251721),
    surfaceContainerLowest:
        light ? const Color(0xFFFBE7EF) : const Color(0xFF1B1017),
    surfaceContainerHigh:
        light ? const Color(0xFFFFFFFF) : const Color(0xFF382431),
    surfaceContainer:
        light ? const Color(0xFFFFF8FB) : const Color(0xFF2E1D28),
  );
}

/// Kawaii «Milky Lavender»: лавандово-молочная пастель, устроена как сакура.
ColorScheme _lavenderMilkScheme(Brightness brightness) {
  final lavender = ColorScheme.fromSeed(
    seedColor: const Color(0xFFB39DF2),
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  final light = brightness == Brightness.light;
  return lavender.copyWith(
    surface: light ? const Color(0xFFF7F3FE) : const Color(0xFF1F1930),
    surfaceContainerLowest:
        light ? const Color(0xFFEFE7FB) : const Color(0xFF161126),
    surfaceContainerHigh:
        light ? const Color(0xFFFFFFFF) : const Color(0xFF2F2749),
    surfaceContainer:
        light ? const Color(0xFFFAF7FF) : const Color(0xFF272040),
  );
}

/// Пресеты, которые с виду разные, а на выходе давали одну и ту же схему.
///
/// Так вышло из-за `tonalSpot`: он строит палитру по ТОНУ сида и нормализует
/// насыщенность, поэтому два непохожих на глаз цвета с близким тоном дают
/// одинаковые роли. Замер разницы по акцентным ролям (0..255): Forest↔Mint —
/// 0.5, Sunset↔Ruby — 2.3, Ocean↔Cobalt — 3.7, тогда как у заведомо разных тем
/// разрыв 10 и больше. То есть в списке лежали три пары одинаковых плиток.
///
/// Оставлены Mint, Sunset и Ocean; Forest, Ruby и Cobalt убраны — см.
/// [_kRetiredPresets], который уводит их прежних владельцев к близнецу, а не к
/// дефолту.
const kThemePresets = <ThemePreset>[
  ThemePreset(id: 'ocean', name: 'Ocean', seed: Color(0xFF3A86FF)),
  ThemePreset(id: 'sunset', name: 'Sunset', seed: Color(0xFFEF476F)),
  ThemePreset(id: 'violet', name: 'Violet', seed: Color(0xFF7B2CBF)),
  ThemePreset(id: 'amber', name: 'Amber', seed: Color(0xFFFB8500)),
  ThemePreset(id: 'mono', name: 'Monochrome', seed: Color(0xFF607D8B)),
  ThemePreset(id: 'mint', name: 'Mint', seed: Color(0xFF2EC4B6)),
  ThemePreset(id: 'rose', name: 'Rose', seed: Color(0xFFE76FAD)),
  // id остался «sakura_sky» с двухцветных времён: он сохранён в настройках
  // пользователей, смена уронила бы их на дефолтный ocean.
  ThemePreset(
    id: 'sakura_sky',
    name: 'Sakura ✿',
    seed: Color(0xFFFF8FB8),
    schemeBuilder: _sakuraScheme,
    flair: true,
    kawaii: KawaiiFlavor.sakura,
    variant: DynamicSchemeVariant.fidelity,
  ),
  ThemePreset(
    id: 'lavender_milk',
    name: 'Milky Lavender ☁',
    seed: Color(0xFFB39DF2),
    schemeBuilder: _lavenderMilkScheme,
    flair: true,
    kawaii: KawaiiFlavor.lavender,
    variant: DynamicSchemeVariant.fidelity,
  ),
];

/// Удалённые пресеты → тот из оставшихся, который выглядит так же.
///
/// Без этой таблицы `resolveThemePreset` уронил бы их владельцев на дефолтный
/// Ocean, то есть человек с зелёной темой обнаружил бы синюю — при том что
/// удалили мы ровно КОПИЮ его темы и внешне меняться не должно ничего. Id живут
/// в сохранённых настройках и в резервных копиях, поэтому таблица остаётся
/// навсегда, а не до следующего релиза.
const _kRetiredPresets = <String, String>{
  'forest': 'mint',
  'ruby': 'sunset',
  'cobalt': 'ocean',
};

ThemePreset resolveThemePreset(String id) {
  final live = _kRetiredPresets[id] ?? id;
  return kThemePresets.firstWhere(
    (p) => p.id == live,
    orElse: () => kThemePresets.first,
  );
}

/// Готовые схемы пресетов: ключ — (id, яркость).
///
/// `ColorScheme.fromSeed` — это полный расчёт динамической схемы по HCT, и
/// стоит он не наносекунды: двенадцать пресетов на десктопе считаются 8 мс
/// (замер), на телефоне втрое дольше. А считать их приходится ЦЕЛИКОМ и на
/// каждом кадре: экран выбора темы строит все двенадцать превью сразу, а
/// `AnimatedTheme` внутри MaterialApp пересобирает поддерево на каждом кадре
/// перехода светлая↔тёмная. То есть расчёт палитр выпадал ровно на те 350 мс,
/// когда пользователь смотрит на анимацию, — отсюда и рывки при смене темы.
///
/// Кешировать безопасно: функция чистая, `ColorScheme` неизменяем, а размер
/// кеша сверху ограничен числом пресетов на две яркости.
final Map<(String, Brightness), ColorScheme> _presetSchemeCache = {};

ColorScheme buildPresetScheme(ThemePreset preset, Brightness brightness) =>
    _presetSchemeCache.putIfAbsent((preset.id, brightness), () {
      final custom = preset.schemeBuilder;
      if (custom != null) return custom(brightness);
      return ColorScheme.fromSeed(
        seedColor: preset.seed,
        brightness: brightness,
        dynamicSchemeVariant: preset.variant,
      );
    });

/// Чёрный AMOLED-фон поверх любой тёмной схемы.
///
/// На OLED выключенный пиксель не светится, поэтому чистый чёрный экономит
/// заряд и даёт настоящую бесконечную глубину. Светлую схему не трогаем —
/// белым по белому смотреть нечего.
///
/// Чернеет ТОЛЬКО фон. Уровни surfaceContainer остаются как в обычной тёмной
/// теме — на них держится вся иерархия M3 (карточка над фоном, шторка над
/// карточкой, вставка внутри карточки).
///
/// Первая версия тянула к чёрному и лестницу тоже, «чтобы было темнее». Это
/// ошибка: разница между карточкой и фоном схлопывалась до едва заметного
/// оттенка, и карточки сливались с фоном. Фон опускается, а карточки стоят на
/// месте — значит контраст между ними не падает, а РАСТЁТ по сравнению с
/// обычной тёмной темой. Ради этого AMOLED-режим и включают.
ColorScheme applyAmoledBlack(ColorScheme scheme) {
  if (scheme.brightness != Brightness.dark) return scheme;
  return scheme.copyWith(
    surface: Colors.black,
    // surfaceDim — тот же фон в «приглушённом» состоянии, иначе он остался бы
    // светлее самого фона.
    surfaceDim: Colors.black,
  );
}

/// Ключ кеша готовых тем.
typedef _AppThemeKey = ({
  ColorScheme scheme,
  bool flair,
  String? fontFamily,
  IconShape iconShape,
});

/// Собранные `ThemeData` — по одной на набор аргументов.
///
/// Сборка темы стоит дорого: `ThemeData` разрешает десятки компонентных
/// подтем, а рядом строится ещё и выразительная шкала типографики. На кадре,
/// где меняется настройка, `_ThemedApp` собирает СРАЗУ ДВЕ темы — светлую и
/// тёмную, — и замер на Pixel 6a показал 35–48 мс сборки на этом кадре. При
/// бюджете 16.7 мс это два-три пропущенных кадра ровно в момент нажатия:
/// именно они читались рывком в начале перехода.
///
/// Кешируется по полному набору аргументов, а `ThemeData` неизменяема, так что
/// отдавать один и тот же объект безопасно — и даже полезно: `AnimatedTheme`
/// сверяет темы по идентичности и не перезапускает анимацию впустую.
///
/// Кеш маленький и с потолком: пользователь ходит между двумя-тремя палитрами,
/// а вот динамические схемы Android меняются вместе с обоями, и держать их все
/// вечно незачем.
final Map<_AppThemeKey, ThemeData> _appThemeCache = {};
const int _appThemeCacheLimit = 8;

ThemeData buildAppTheme(
  ColorScheme scheme, {
  bool flair = false,
  String? fontFamily,
  IconShape iconShape = IconShape.circle,
}) {
  final key = (
    scheme: scheme,
    flair: flair,
    fontFamily: fontFamily,
    iconShape: iconShape,
  );
  final cached = _appThemeCache[key];
  if (cached != null) return cached;
  final built = _buildAppTheme(scheme, flair, fontFamily, iconShape);
  // Простое вытеснение целиком: набор ключей крошечный, и держать LRU ради
  // восьми записей дороже, чем изредка пересобрать тему.
  if (_appThemeCache.length >= _appThemeCacheLimit) _appThemeCache.clear();
  return _appThemeCache[key] = built;
}

ThemeData _buildAppTheme(
  ColorScheme scheme,
  bool flair,
  String? fontFamily,
  IconShape iconShape,
) {
  // Токены M3 Expressive: шкала форм, выразительные веса типографики и
  // компонентные темы. Экраны, пока живущие на хардкоде, от этого не ломаются —
  // они просто ещё не переехали (см. миграцию по этапам).
  final components = buildExpressiveComponentThemes(scheme);
  final expressiveText = buildExpressiveTextTheme(scheme.brightness);
  final textTheme = fontFamily == null
      ? expressiveText
      : expressiveText.apply(fontFamily: fontFamily);

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    // Форма кружков-иконок едет расширением темы: так её видит любой
    // ExpressiveIconBadge, не таща за собой ни настройки, ни провайдеры.
    extensions: [ExpressiveIconShapeTheme(shape: iconShape)],
    textTheme: textTheme,
    chipTheme: components.chip,
    filledButtonTheme: components.filledButton,
    outlinedButtonTheme: components.outlinedButton,
    textButtonTheme: components.textButton,
    // Подпись расширенного FAB — `titleMedium`: выразительное обновление увело
    // её с `labelLarge`. Стиль берём из УЖЕ собранной шкалы, а не собираем в
    // компонентной теме: там нет ни выбранного шрифта, ни его метрик.
    floatingActionButtonTheme: components.fab.copyWith(
      extendedTextStyle: textTheme.titleMedium,
    ),
    listTileTheme: components.listTile,
    inputDecorationTheme: components.inputDecoration,
    // Шрифт приходит из выбора пользователя (см. _ThemedApp): flair-пресеты по
    // умолчанию несут Comfortaa, но пользователь может сменить его в любой теме.
    // Прочие «финтифлюшки» (усиленные скругления) остаются привязаны к flair.
    fontFamily: fontFamily,
    // flair поднимает скругления на шаг вверх по той же шкале — не произвольные
    // числа, как было, а следующий токен формы.
    cardTheme: flair
        ? components.card.copyWith(
            shape: ExpressiveShape.border(ExpressiveShape.largeIncreased),
          )
        : components.card,
    appBarTheme: components.appBar,
    navigationBarTheme: components.navigationBar,
    popupMenuTheme: components.popupMenu,
    segmentedButtonTheme: components.segmentedButton,
    progressIndicatorTheme: components.progressIndicator,
    sliderTheme: components.slider,
    bottomSheetTheme: components.sheet,
    dialogTheme: flair
        ? components.dialog.copyWith(
            shape: ExpressiveShape.border(ExpressiveShape.extraLargeIncreased),
          )
        : components.dialog,
    snackBarTheme: components.snackBar,
  );
}

class KeqdisApp extends ConsumerWidget {
  final Widget home;
  const KeqdisApp({super.key, required this.home});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Запасной сид «динамических цветов». Плагин dynamic_color отдаёт схему
    // только на устройствах с официальным флагом Material You (Pixel); на
    // Realme/ColorOS, OneUI и прочих он молчит, хотя системный акцент у них есть.
    // Читаем его нативно и используем как сид, чтобы «следовать цветам системы»
    // работало и там. Нет акцента (Android < 12 / не Android) — фирменный fallback.
    final systemAccent = ref.watch(systemAccentColorProvider).value;
    final fallbackSeed = systemAccent ?? kSeedFallback;

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final lightScheme = (lightDynamic ??
                ColorScheme.fromSeed(
                  seedColor: fallbackSeed,
                  brightness: Brightness.light,
                ))
            .harmonized();

        final darkScheme = (darkDynamic ??
                ColorScheme.fromSeed(
                  seedColor: fallbackSeed,
                  brightness: Brightness.dark,
                ))
            .harmonized();

        return _ThemedApp(
          lightScheme: lightScheme,
          darkScheme: darkScheme,
          home: home,
        );
      },
    );
  }
}

/// Фон окна Android держим равным поверхности приложения.
///
/// `NormalTheme` в `styles.xml` наследуется от `Theme.Light`/`Theme.Black`, то
/// есть переключается СИСТЕМНОЙ тёмной темой. Тема приложения выбирается своей
/// настройкой и с системной не связана: у человека со светлой системой и тёмным
/// приложением фон окна оставался белым. Виден он там, где поверхность Flutter
/// не достаёт до края экрана, — на HyperOS под панелью навигации остаётся
/// полоска в несколько пикселей, и она светилась белым поперёк всего низа.
///
/// Зовётся из `build`, поэтому дедуплицируется по цвету и уходит в нативку
/// отложенно: дёргать канал во время сборки дерева нельзя.
Color? _lastWindowBackground;

void _syncAndroidWindowBackground(Color surface) {
  if (!Platform.isAndroid || surface == _lastWindowBackground) return;
  _lastWindowBackground = surface;
  scheduleMicrotask(
    () => VpnNativeBridge.setWindowBackgroundColor(surface.toARGB32()),
  );
}

class _ThemedApp extends ConsumerWidget {
  final ColorScheme lightScheme;
  final ColorScheme darkScheme;
  final Widget home;

  const _ThemedApp({
    required this.lightScheme,
    required this.darkScheme,
    required this.home,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();
    // Единственная точка синхронизации флага отдачи: присваивание идемпотентно
    // и ничего не перестраивает, зато обработчикам нажатий не нужен ref.
    AppHaptics.enabled = settings.hapticFeedback;
    final preset = resolveThemePreset(settings.themePresetId);
    final customLight = buildPresetScheme(preset, Brightness.light);
    final customDark = buildPresetScheme(preset, Brightness.dark);
    ColorScheme dark(ColorScheme scheme) =>
        settings.amoledBlack ? applyAmoledBlack(scheme) : scheme;
    final useSystem = settings.followSystemTheme;
    // Финтифлюшки только когда пресет реально применён (системные цвета
    // выключены): следуем той же логике, что и палитра.
    final flair = !useSystem && preset.flair;

    // Выбранный шрифт применяется в любой теме. Оставлен системный дефолт —
    // flair-пресеты сохраняют фирменный Comfortaa.
    final font = resolveAppFont(settings.fontId);
    final fontFamily = font.family ?? (flair ? 'Comfortaa' : null);
    final iconShape = IconShape.fromId(settings.iconShapeId);

    final locale = localeFromSettings(settings);

    // Фон окна Android — под ту схему, которая реально на экране (см.
    // [_syncAndroidWindowBackground]).
    _syncAndroidWindowBackground(
      settings.darkTheme
          ? dark(useSystem ? darkScheme : customDark).surface
          : (useSystem ? lightScheme : customLight).surface,
    );

    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      debugShowCheckedModeBanner: false,
      themeMode: settings.darkTheme ? ThemeMode.dark : ThemeMode.light,
      // Тема переключается МГНОВЕННО, без покадрового лерпа. Это не экономия на
      // красоте, а замер: штатный `AnimatedTheme` пересобирает всё поддерево на
      // каждом кадре перехода, а поддерево здесь — три живых вкладки PageView
      // плюс открытый поверх экран. Один такой пересбор стоит 55 мс на Pixel 6a,
      // и двадцать один кадр подряд по 55 мс — это не анимация, а затор: кадры
      // уходили с задержкой 230–280 мс, и смена темы выглядела зависанием.
      //
      // Пересбор при смене темы неизбежен, но нужен он ровно один. Так и
      // сделано: одна короткая задержка вместо трёхсот миллисекунд каши.
      themeAnimationDuration: Duration.zero,
      theme: buildAppTheme(useSystem ? lightScheme : customLight,
          flair: flair, fontFamily: fontFamily, iconShape: iconShape),
      darkTheme: buildAppTheme(dark(useSystem ? darkScheme : customDark),
          flair: flair, fontFamily: fontFamily, iconShape: iconShape),
      builder: (context, child) {
        final content = (!flair || child == null)
            ? (child ?? const SizedBox.shrink())
            : KawaiiOverlay(
                flavor: preset.kawaii ?? KawaiiFlavor.sakura,
                child: child,
              );
        // Пока окно скрыто в трее (не видно и меню трея не открыто) — глушим ВСЕ
        // тикеры поддерева: волну-хедер, «дыхание» и полноэкранный kawaii-оверлей
        // (иначе он рендерил 60fps за кадром и жёг CPU в трее). Возвращается сам,
        // как только окно/меню снова на экране. См. desktopUiVisibleProvider.
        final gated = _VisibilityTickerGate(child: content);
        if (settings.uiScale == 1.0) return gated;
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: _ScaledTextScaler(mq.textScaler, settings.uiScale),
          ),
          child: gated,
        );
      },
      locale: locale,
      localeResolutionCallback: (deviceLocale, supported) {
        if (locale != null) {
          return supported.contains(locale) ? locale : const Locale('en');
        }
        if (deviceLocale != null) {
          for (final l in supported) {
            if (l.languageCode == deviceLocale.languageCode) return l;
          }
        }
        return supported.first;
      },
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      navigatorKey: rootNavigatorKey,
      home: home,
    );
  }
}

/// Глушит тикеры всего поддерева, когда десктопный UI не на экране (окно скрыто
/// в трей и меню трея закрыто). На платформах без трея desktopUiVisibleProvider
/// всегда true — TickerMode включён, поведение не меняется.
/// Системный масштаб текста, домноженный на [AppSettings.uiScale].
///
/// Обёртка вокруг системного, а не `TextScaler.linear(factor)`: на Android 14+
/// системное масштабирование НЕЛИНЕЙНО — крупный текст растёт медленнее мелкого,
/// чтобы заголовки не разносили вёрстку. Линейный множитель вместо системного
/// эту кривую стёр бы, и у того, кто выкрутил шрифт в системе, интерфейс поехал
/// бы сильнее, чем он просил.
///
/// `==`/`hashCode` обязательны: [MediaQuery] сравнивает данные, и объект без
/// равенства заставлял бы перестраивать всё поддерево на каждый кадр.
class _ScaledTextScaler extends TextScaler {
  const _ScaledTextScaler(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  // Реализовать обязаны: геттер в [TextScaler] абстрактный, хотя и помечен
  // устаревшим. Отсюда и ignore — не «мы игнорируем устаревшее», а «без него
  // класс не компилируется».
  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * factor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ScaledTextScaler &&
          other.base == base &&
          other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}

class _VisibilityTickerGate extends ConsumerWidget {
  final Widget child;
  const _VisibilityTickerGate({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(desktopUiVisibleProvider);
    return TickerMode(enabled: visible, child: child);
  }
}
