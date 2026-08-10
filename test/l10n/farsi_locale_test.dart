import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/app_locale.dart';
import 'package:keqdroid/utils/bidi.dart';

void main() {
  group('Farsi locale', () {
    testWidgets('strings come from the Persian bundle', (tester) async {
      late AppLocalizations l10n;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fa'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              l10n = AppLocalizations.of(context)!;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(l10n.localeName, 'fa');
      expect(l10n.navServers, 'سرورها');
      expect(l10n.navSubscriptions, 'اشتراک‌ها');
      expect(l10n.settingsRoutingTitle, 'قوانین مسیریابی');
      // Термины сверены с иранским клиентом Hiddify, а не переведены дословно.
      expect(l10n.settingsRoutingFinalProxy, 'پروکسی');
      expect(l10n.settingsRoutingFinalDirect, 'دور زدن');
      expect(l10n.settingsRoutingFinalBlock, 'مسدود');
    });

    testWidgets('layout flips to right-to-left', (tester) async {
      late TextDirection direction;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fa'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              direction = Directionality.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(direction, TextDirection.rtl);
    });

    test('technical values are isolated from the RTL paragraph', () {
      // Без изолята «621.8 / ∞ GiB» в персидском абзаце показывается как
      // «GiB ∞ / 621.8», а пинг — как «ms 266».
      const usage = '621.8 / ∞ GiB';
      final wrapped = ltrIsolate(usage);

      expect(wrapped.codeUnitAt(0), 0x2066);
      expect(wrapped.codeUnitAt(wrapped.length - 1), 0x2069);
      expect(wrapped.substring(1, wrapped.length - 1), usage);
      // Пустое значение не превращается в два невидимых символа.
      expect(ltrIsolate(''), isEmpty);
    });

    test('language picker knows Farsi', () {
      const settings = AppSettings(appLanguageCode: 'fa');

      expect(appLanguageLabel(settings, systemLabel: 'system'), 'فارسی');
      expect(localeFromSettings(settings), const Locale('fa'));
    });

    test('placeholders survive translation', () async {
      // Плейсхолдеры — контракт с кодом: потеряется имя, и строка не соберётся.
      final fa = await AppLocalizations.delegate.load(const Locale('fa'));

      expect(fa.vpnConnectedTo('سرور من'), contains('سرور من'));
      expect(fa.subscriptionsEveryHours(6), contains('6'));
      expect(fa.connectionsCount(0), 'بدون اتصال');
      expect(fa.connectionsCount(3), contains('3'));
    });
  });
}
