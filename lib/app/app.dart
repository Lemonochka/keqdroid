import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keqdroid/l10n/app_localizations.dart';

import '../models/app_settings.dart';
import '../providers/providers.dart';
import '../utils/app_locale.dart';

const kSeedFallback = Color(0xFFFFAEBC);

class ThemePreset {
  final String id;
  final String name;
  final Color seed;
  const ThemePreset({
    required this.id,
    required this.name,
    required this.seed,
  });
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
];

ThemePreset resolveThemePreset(String id) {
  return kThemePresets.firstWhere(
    (p) => p.id == id,
    orElse: () => kThemePresets.first,
  );
}

ColorScheme buildPresetScheme(ThemePreset preset, Brightness brightness) {
  return ColorScheme.fromSeed(
    seedColor: preset.seed,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
}

ThemeData _buildAppTheme(ColorScheme scheme) {
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    cardTheme: const CardThemeData(surfaceTintColor: Colors.transparent),
    appBarTheme: const AppBarTheme(surfaceTintColor: Colors.transparent),
    navigationBarTheme:
        const NavigationBarThemeData(surfaceTintColor: Colors.transparent),
    bottomSheetTheme:
        const BottomSheetThemeData(surfaceTintColor: Colors.transparent),
    dialogTheme: const DialogThemeData(surfaceTintColor: Colors.transparent),
  );
}

class KeqdisApp extends StatelessWidget {
  final Widget home;
  const KeqdisApp({super.key, required this.home});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final lightScheme = (lightDynamic ??
                ColorScheme.fromSeed(
                  seedColor: kSeedFallback,
                  brightness: Brightness.light,
                ))
            .harmonized();

        final darkScheme = (darkDynamic ??
                ColorScheme.fromSeed(
                  seedColor: kSeedFallback,
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
    final preset = resolveThemePreset(settings.themePresetId);
    final customLight = buildPresetScheme(preset, Brightness.light);
    final customDark = buildPresetScheme(preset, Brightness.dark);
    final useSystem = settings.followSystemTheme;

    final locale = localeFromSettings(settings);

    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      debugShowCheckedModeBanner: false,
      themeMode: settings.darkTheme ? ThemeMode.dark : ThemeMode.light,
      theme: _buildAppTheme(useSystem ? lightScheme : customLight),
      darkTheme: _buildAppTheme(useSystem ? darkScheme : customDark),
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

