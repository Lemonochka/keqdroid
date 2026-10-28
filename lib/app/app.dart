import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' as ui show DisplayFeature;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:material_color_utilities/material_color_utilities.dart' as mcu;

import '../models/app_font.dart';
import '../models/app_settings.dart';
import '../models/icon_shape.dart';
import '../platform/platform_bootstrap.dart';
import '../platform/vpn_native_bridge.dart';
import '../providers/providers.dart';
import '../shared/ui/expressive.dart';
import '../shared/ui/expressive_elements.dart';
import '../shared/ui/haptics.dart';
import '../shared/ui/kawaii_decorations.dart';
import '../shared/ui/liquid_toast.dart';
import '../shared/ui/server_avatar.dart';
import '../shared/ui/tv_focus.dart';
import '../utils/app_locale.dart';

const kSeedFallback = Color(0xFFFFAEBC);

final rootNavigatorKey = GlobalKey<NavigatorState>();

class ThemePreset {
  final String id;
  final String name;
  final Color seed;

  final ColorScheme Function(Brightness)? schemeBuilder;

  final bool flair;

  final KawaiiFlavor? kawaii;

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

// одна тыквенная палитра дала бы близнеца Amber, а такие пары убраны (см. _kRetiredPresets):
// отличие держит фиолетовая; насыщенность фона 14 вместо 6 у простых тем, иначе фиолетовый не читается
ColorScheme _pumpkinNightScheme(Brightness brightness) {
  final pumpkin = mcu.Hct.fromInt(0xFFFF7518);
  final d = mcu.DynamicScheme(
    sourceColorHct: pumpkin,
    variant: mcu.Variant.tonalSpot,
    isDark: brightness == Brightness.dark,
    primaryPalette: mcu.TonalPalette.of(pumpkin.hue, 48),
    secondaryPalette: mcu.TonalPalette.of(300, 24),
    tertiaryPalette: mcu.TonalPalette.of(290, 40),
    neutralPalette: mcu.TonalPalette.of(295, 14),
    neutralVariantPalette: mcu.TonalPalette.of(295, 16),
  );
  Color c(mcu.DynamicColor role) => Color(role.getArgb(d));
  return ColorScheme.fromSeed(
    seedColor: const Color(0xFFFF7518),
    brightness: brightness,
  ).copyWith(
    primary: c(mcu.MaterialDynamicColors.primary),
    onPrimary: c(mcu.MaterialDynamicColors.onPrimary),
    primaryContainer: c(mcu.MaterialDynamicColors.primaryContainer),
    onPrimaryContainer: c(mcu.MaterialDynamicColors.onPrimaryContainer),
    secondary: c(mcu.MaterialDynamicColors.secondary),
    onSecondary: c(mcu.MaterialDynamicColors.onSecondary),
    secondaryContainer: c(mcu.MaterialDynamicColors.secondaryContainer),
    onSecondaryContainer: c(mcu.MaterialDynamicColors.onSecondaryContainer),
    tertiary: c(mcu.MaterialDynamicColors.tertiary),
    onTertiary: c(mcu.MaterialDynamicColors.onTertiary),
    tertiaryContainer: c(mcu.MaterialDynamicColors.tertiaryContainer),
    onTertiaryContainer: c(mcu.MaterialDynamicColors.onTertiaryContainer),
    surface: c(mcu.MaterialDynamicColors.surface),
    onSurface: c(mcu.MaterialDynamicColors.onSurface),
    onSurfaceVariant: c(mcu.MaterialDynamicColors.onSurfaceVariant),
    surfaceDim: c(mcu.MaterialDynamicColors.surfaceDim),
    surfaceBright: c(mcu.MaterialDynamicColors.surfaceBright),
    surfaceContainerLowest: c(mcu.MaterialDynamicColors.surfaceContainerLowest),
    surfaceContainerLow: c(mcu.MaterialDynamicColors.surfaceContainerLow),
    surfaceContainer: c(mcu.MaterialDynamicColors.surfaceContainer),
    surfaceContainerHigh: c(mcu.MaterialDynamicColors.surfaceContainerHigh),
    surfaceContainerHighest: c(mcu.MaterialDynamicColors.surfaceContainerHighest),
    outline: c(mcu.MaterialDynamicColors.outline),
    outlineVariant: c(mcu.MaterialDynamicColors.outlineVariant),
    inverseSurface: c(mcu.MaterialDynamicColors.inverseSurface),
    inversePrimary: c(mcu.MaterialDynamicColors.inversePrimary),
    surfaceTint: c(mcu.MaterialDynamicColors.surfaceTint),
    onInverseSurface: c(mcu.MaterialDynamicColors.inverseOnSurface),
  );
}

const kThemePresets = <ThemePreset>[
  ThemePreset(id: 'ocean', name: 'Ocean', seed: Color(0xFF3A86FF)),
  ThemePreset(id: 'sunset', name: 'Sunset', seed: Color(0xFFEF476F)),
  ThemePreset(id: 'violet', name: 'Violet', seed: Color(0xFF7B2CBF)),
  ThemePreset(id: 'amber', name: 'Amber', seed: Color(0xFFFB8500)),
  ThemePreset(id: 'mono', name: 'Monochrome', seed: Color(0xFF607D8B)),
  ThemePreset(id: 'mint', name: 'Mint', seed: Color(0xFF2EC4B6)),
  ThemePreset(id: 'rose', name: 'Rose', seed: Color(0xFFE76FAD)),
  // id остался с двухцветной версии, он сохранён у людей в настройках
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
  ThemePreset(
    id: 'pumpkin_night',
    name: 'Pumpkin Night',
    seed: Color(0xFFFF7518),
    schemeBuilder: _pumpkinNightScheme,
  ),
];

// удалённые темы живут в настройках и бэкапах, таблицу не трогать
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

const String kCustomThemePresetId = 'custom';

const Color kCustomThemeDefaultSeed = Color(0xFF7B2CBF);

const kCustomThemeVariants = <String, DynamicSchemeVariant>{
  'tonalSpot': DynamicSchemeVariant.tonalSpot,
  'vibrant': DynamicSchemeVariant.vibrant,
  'fidelity': DynamicSchemeVariant.fidelity,
};

DynamicSchemeVariant parseThemeVariant(String raw) =>
    kCustomThemeVariants[raw.trim()] ?? DynamicSchemeVariant.tonalSpot;

Color? parseThemeSeed(String raw) {
  var hex = raw.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length != 6 && hex.length != 8) return null;
  final value = int.tryParse(hex, radix: 16);
  if (value == null) return null;
  return Color(hex.length == 6 ? 0xFF000000 | value : value | 0xFF000000);
}

String formatThemeSeed(Color color) =>
    (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

// по id кешируются схемы, поэтому цвет и вариант зашиты в него
ThemePreset customThemePreset(
  Color seed, {
  DynamicSchemeVariant variant = DynamicSchemeVariant.tonalSpot,
}) =>
    ThemePreset(
      id: '$kCustomThemePresetId:${formatThemeSeed(seed)}:${variant.name}',
      name: '#${formatThemeSeed(seed)}',
      seed: seed,
      variant: variant,
    );

ThemePreset themePresetFor(AppSettings settings) {
  if (settings.themePresetId == kCustomThemePresetId) {
    return customThemePreset(
      parseThemeSeed(settings.customThemeSeed) ?? kCustomThemeDefaultSeed,
      variant: parseThemeVariant(settings.customThemeVariant),
    );
  }
  return resolveThemePreset(settings.themePresetId);
}

final Map<(String, Brightness), ColorScheme> _presetSchemeCache = {};

const int _presetSchemeCacheLimit = 48;

ColorScheme buildPresetScheme(ThemePreset preset, Brightness brightness) {
  if (_presetSchemeCache.length >= _presetSchemeCacheLimit) {
    _presetSchemeCache.clear();
  }
  return _presetSchemeCache.putIfAbsent((preset.id, brightness), () {
    final custom = preset.schemeBuilder;
    if (custom != null) return custom(brightness);
    return ColorScheme.fromSeed(
      seedColor: preset.seed,
      brightness: brightness,
      dynamicSchemeVariant: preset.variant,
    );
  });
}

ColorScheme applyAmoledBlack(ColorScheme scheme) {
  if (scheme.brightness != Brightness.dark) return scheme;
  return scheme.copyWith(
    surface: Colors.black,
    surfaceDim: Colors.black,
  );
}

typedef _AppThemeKey = ({
  ColorScheme scheme,
  bool flair,
  String? fontFamily,
  IconShape iconShape,
  ServerIconPalette iconPalette,
});

final Map<_AppThemeKey, ThemeData> _appThemeCache = {};
const int _appThemeCacheLimit = 8;

ThemeData buildAppTheme(
  ColorScheme scheme, {
  bool flair = false,
  String? fontFamily,
  IconShape iconShape = IconShape.circle,
  ServerIconPalette iconPalette = ServerIconPalette.themed,
}) {
  final key = (
    scheme: scheme,
    flair: flair,
    fontFamily: fontFamily,
    iconShape: iconShape,
    iconPalette: iconPalette,
  );
  final cached = _appThemeCache[key];
  if (cached != null) return cached;
  final built =
      _buildAppTheme(scheme, flair, fontFamily, iconShape, iconPalette);
  if (_appThemeCache.length >= _appThemeCacheLimit) _appThemeCache.clear();
  return _appThemeCache[key] = built;
}

ThemeData _buildAppTheme(
  ColorScheme scheme,
  bool flair,
  String? fontFamily,
  IconShape iconShape,
  ServerIconPalette iconPalette,
) {
  final components = buildExpressiveComponentThemes(scheme);
  final expressiveText = buildExpressiveTextTheme(scheme.brightness);
  final textTheme = fontFamily == null
      ? expressiveText
      : expressiveText.apply(fontFamily: fontFamily);

  final tv = TvFocus.enabled;
  ButtonStyle? tvButtons(ButtonStyle? base) =>
      tv ? TvFocus.buttonStyle(scheme, base) : base;

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    iconButtonTheme:
        tv ? IconButtonThemeData(style: TvFocus.buttonStyle(scheme)) : null,
    extensions: [
      ExpressiveIconShapeTheme(shape: iconShape),
      ServerIconPaletteTheme(palette: iconPalette),
    ],
    textTheme: textTheme,
    chipTheme: components.chip,
    filledButtonTheme:
        FilledButtonThemeData(style: tvButtons(components.filledButton.style)),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: tvButtons(components.outlinedButton.style),
    ),
    textButtonTheme:
        TextButtonThemeData(style: tvButtons(components.textButton.style)),
    floatingActionButtonTheme: components.fab.copyWith(
      extendedTextStyle: textTheme.titleMedium,
    ),
    listTileTheme: components.listTile,
    inputDecorationTheme: components.inputDecoration,
    fontFamily: fontFamily,
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
    // dynamic_color работает только с флагом Material You (Pixel),
    // на Realme, OneUI и прочих системный акцент читаем сами
    final systemAccent = ref.watch(systemAccentColorProvider).value;
    final fallbackSeed = systemAccent ?? kSeedFallback;
    // держит провайдер живым: списки по ссылкам обновляются раз в сутки и без открытого экрана
    ref.listen(ruleListsProvider, (_, _) {});

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

// фон окна Android идёт от системной темы, и на HyperOS под навигацией была белая полоса
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
    AppHaptics.enabled = settings.hapticFeedback;
    final preset = themePresetFor(settings);
    final customLight = buildPresetScheme(preset, Brightness.light);
    final customDark = buildPresetScheme(preset, Brightness.dark);
    ColorScheme dark(ColorScheme scheme) =>
        settings.amoledBlack ? applyAmoledBlack(scheme) : scheme;
    final useSystem = settings.followSystemTheme;
    final flair = !useSystem && preset.flair;

    final font = resolveAppFont(settings.fontId);
    final fontFamily = font.family ?? (flair ? 'Comfortaa' : null);
    final iconShape = IconShape.fromId(settings.iconShapeId);
    final iconPalette = settings.serverIconThemeColors
        ? ServerIconPalette.themed
        : ServerIconPalette.protocol;

    final locale = localeFromSettings(settings);

    _syncAndroidWindowBackground(
      settings.darkTheme
          ? dark(useSystem ? darkScheme : customDark).surface
          : (useSystem ? lightScheme : customLight).surface,
    );

    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      debugShowCheckedModeBanner: false,
      themeMode: settings.darkTheme ? ThemeMode.dark : ThemeMode.light,
      // анимация темы пересобирает всё дерево на каждом кадре, на Pixel 6a это 55 мс на кадр
      themeAnimationDuration: Duration.zero,
      theme: buildAppTheme(useSystem ? lightScheme : customLight,
          flair: flair,
          fontFamily: fontFamily,
          iconShape: iconShape,
          iconPalette: iconPalette),
      darkTheme: buildAppTheme(dark(useSystem ? darkScheme : customDark),
          flair: flair,
          fontFamily: fontFamily,
          iconShape: iconShape,
          iconPalette: iconPalette),
      builder: (context, child) {
        final content = (!flair || child == null)
            ? (child ?? const SizedBox.shrink())
            : KawaiiOverlay(
                flavor: preset.kawaii ?? KawaiiFlavor.sakura,
                child: child,
              );
        final theme = Theme.of(context);
        final icons =
            theme.brightness == Brightness.dark ? Brightness.light : Brightness.dark;
        // панель навигации по теме приложения: без этого её красит прошивка по теме системы,
        // и на HyperOS после обновления под кнопками оставалась белая полоса до перезагрузки.
        // строку состояния тоже: стоит задать одну панель, и Pixel 6a в тёмной теме
        // перекрасил значки сверху в тёмные (apr=LIGHT_STATUS_BARS)
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarIconBrightness: icons,
            statusBarBrightness: theme.brightness,
            systemNavigationBarColor: theme.colorScheme.surface,
            systemNavigationBarIconBrightness: icons,
          ),
          child: _UiZoom(
            scale: settings.uiScale * _baseUiScale,
            child: _VisibilityTickerGate(child: LiquidToastHost(child: content)),
          ),
        );
      },
      locale: locale,
      localeResolutionCallback: (deviceLocale, supported) =>
          resolveAppLocale(locale, deviceLocale, supported),
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

// на телефоне 100% ползунка рисуются как 0.85: системный масштаб у многих и так крупный
double get _baseUiScale =>
    PlatformBootstrap.isDesktop || PlatformBootstrap.isTelevision ? 1.0 : 0.85;

class _UiZoom extends StatelessWidget {
  final double scale;
  final Widget child;
  const _UiZoom({required this.scale, required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest / scale;
        return FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: size,
            child: MediaQuery(
              data: mq.copyWith(
                size: size,
                devicePixelRatio: mq.devicePixelRatio * scale,
                padding: mq.padding / scale,
                viewPadding: mq.viewPadding / scale,
                viewInsets: mq.viewInsets / scale,
                systemGestureInsets: mq.systemGestureInsets / scale,
                displayFeatures: [
                  for (final f in mq.displayFeatures)
                    ui.DisplayFeature(
                      bounds: Rect.fromPoints(
                        f.bounds.topLeft / scale,
                        f.bounds.bottomRight / scale,
                      ),
                      type: f.type,
                      state: f.state,
                    ),
                ],
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
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
