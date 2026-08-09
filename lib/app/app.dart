import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keqdroid/l10n/app_localizations.dart';

import '../models/app_font.dart';
import '../models/app_settings.dart';
import '../providers/providers.dart';
import '../shared/ui/expressive.dart';
import '../shared/ui/haptics.dart';
import '../shared/ui/kawaii_decorations.dart';
import '../utils/app_locale.dart';

const kSeedFallback = Color(0xFFFFAEBC);

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

  const ThemePreset({
    required this.id,
    required this.name,
    required this.seed,
    this.schemeBuilder,
    this.flair = false,
    this.kawaii,
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

const kThemePresets = <ThemePreset>[
  ThemePreset(id: 'ocean', name: 'Ocean', seed: Color(0xFF3A86FF)),
  ThemePreset(id: 'forest', name: 'Forest', seed: Color(0xFF2A9D8F)),
  ThemePreset(id: 'sunset', name: 'Sunset', seed: Color(0xFFEF476F)),
  ThemePreset(id: 'violet', name: 'Violet', seed: Color(0xFF7B2CBF)),
  ThemePreset(id: 'amber', name: 'Amber', seed: Color(0xFFFB8500)),
  ThemePreset(id: 'mono', name: 'Monochrome', seed: Color(0xFF607D8B)),
  ThemePreset(id: 'ruby', name: 'Ruby', seed: Color(0xFFDC2F45)),
  ThemePreset(id: 'mint', name: 'Mint', seed: Color(0xFF2EC4B6)),
  ThemePreset(id: 'cobalt', name: 'Cobalt', seed: Color(0xFF4361EE)),
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
  ),
  ThemePreset(
    id: 'lavender_milk',
    name: 'Milky Lavender ☁',
    seed: Color(0xFFB39DF2),
    schemeBuilder: _lavenderMilkScheme,
    flair: true,
    kawaii: KawaiiFlavor.lavender,
  ),
];

ThemePreset resolveThemePreset(String id) {
  return kThemePresets.firstWhere(
    (p) => p.id == id,
    orElse: () => kThemePresets.first,
  );
}

ColorScheme buildPresetScheme(ThemePreset preset, Brightness brightness) {
  final custom = preset.schemeBuilder;
  if (custom != null) return custom(brightness);
  return ColorScheme.fromSeed(
    seedColor: preset.seed,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
}

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

ThemeData buildAppTheme(
  ColorScheme scheme, {
  bool flair = false,
  String? fontFamily,
}) {
  // Токены M3 Expressive: шкала форм, выразительные веса типографики и
  // компонентные темы. Экраны, пока живущие на хардкоде, от этого не ломаются —
  // они просто ещё не переехали (см. миграцию по этапам).
  final components = buildExpressiveComponentThemes(scheme);
  final expressiveText = buildExpressiveTextTheme(scheme.brightness);

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    textTheme: fontFamily == null
        ? expressiveText
        : expressiveText.apply(fontFamily: fontFamily),
    chipTheme: components.chip,
    filledButtonTheme: components.filledButton,
    outlinedButtonTheme: components.outlinedButton,
    textButtonTheme: components.textButton,
    floatingActionButtonTheme: components.fab,
    listTileTheme: components.listTile,
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
    appBarTheme: const AppBarTheme(surfaceTintColor: Colors.transparent),
    navigationBarTheme: components.navigationBar,
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

    final locale = localeFromSettings(settings);

    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      debugShowCheckedModeBanner: false,
      themeMode: settings.darkTheme ? ThemeMode.dark : ThemeMode.light,
      theme: buildAppTheme(useSystem ? lightScheme : customLight,
          flair: flair, fontFamily: fontFamily),
      darkTheme: buildAppTheme(dark(useSystem ? darkScheme : customDark),
          flair: flair, fontFamily: fontFamily),
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
        return _VisibilityTickerGate(child: content);
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
      home: home,
    );
  }
}

/// Глушит тикеры всего поддерева, когда десктопный UI не на экране (окно скрыто
/// в трей и меню трея закрыто). На платформах без трея desktopUiVisibleProvider
/// всегда true — TickerMode включён, поведение не меняется.
class _VisibilityTickerGate extends ConsumerWidget {
  final Widget child;
  const _VisibilityTickerGate({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(desktopUiVisibleProvider);
    return TickerMode(enabled: visible, child: child);
  }
}
