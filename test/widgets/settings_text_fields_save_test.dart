import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/ping_test_config.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/settings_tab.dart';
import 'package:keqdroid/services/vpn_engine.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

// введённое в поле настроек не должно пропадать молча, если ушли без Enter:
// на телефоне клавиатуру закрывают кнопкой назад, и поле так и остаётся в фокусе
class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this._settings);
  final AppSettings _settings;
  final saves = <AppSettings>[];

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> save(AppSettings settings) async {
    saves.add(settings);
    state = AsyncData(settings);
  }
}

// pumpAndSettle не годится: в настройках живёт бесконечная анимация
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<_FakeSettings> _pumpSettings(
  WidgetTester tester,
  AppSettings settings,
) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final storage = await buildStorageService();
  final fake = _FakeSettings(settings);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
        settingsNotifierProvider.overrideWith(() => fake),
        vpnEngineProvider.overrideWithValue(
          VpnEngine.withBackend(FakeTunnelBackend()),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: buildAppTheme(
          buildPresetScheme(themePresetFor(settings), Brightness.light),
        ),
        home: const SettingsTab(),
      ),
    ),
  );
  await _frames(tester);
  return fake;
}

Future<void> _open(WidgetTester tester, List<String> path) async {
  for (final item in path) {
    final finder = find.text(item).first;
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await _frames(tester);
  }
}

Finder _field(String label) => find.widgetWithText(TextField, label);

Future<void> _type(WidgetTester tester, String label, String text) async {
  await tester.ensureVisible(_field(label));
  await tester.pump();
  await tester.enterText(_field(label), text);
  await tester.pump();
}

void _unfocus() => FocusManager.instance.primaryFocus?.unfocus();

// системная кнопка назад: первое нажатие закрывает клавиатуру само, фокус остаётся в поле
Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await _frames(tester);
}

const _xmuxOn = AppSettings(xrayCore: XrayCoreSettings(xmuxEnabled: true));
const _coreSettings = ['Advanced', 'Core settings'];

void main() {
  group('Core settings', () {
    testWidgets('Enter сохраняет один раз', (tester) async {
      final fake = await _pumpSettings(tester, _xmuxOn);
      await _open(tester, _coreSettings);
      await _type(tester, 'Max concurrency', '8');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _frames(tester);

      expect(fake.saves.map((s) => s.xrayCore.xmuxMaxConcurrency), ['8']);
    });

    testWidgets('потеря фокуса сохраняет', (tester) async {
      final fake = await _pumpSettings(tester, _xmuxOn);
      await _open(tester, _coreSettings);
      await _type(tester, 'Max concurrency', '8');
      _unfocus();
      await _frames(tester);

      expect(fake.saves.last.xrayCore.xmuxMaxConcurrency, '8');
    });

    testWidgets('уход с экрана с фокусом в поле сохраняет', (tester) async {
      final fake = await _pumpSettings(tester, _xmuxOn);
      await _open(tester, _coreSettings);
      await _type(tester, 'Max concurrency', '8');
      await _systemBack(tester);
      await _frames(tester);

      expect(fake.saves, isNotEmpty);
      expect(fake.saves.last.xrayCore.xmuxMaxConcurrency, '8');
      // соседние поля и переключатель не задеты
      expect(fake.saves.last.xrayCore.xmuxEnabled, isTrue);
      expect(fake.saves.last.xrayCore.xmuxMaxConnections, '');
    });

    testWidgets('без правки уход ничего не пишет', (tester) async {
      final fake = await _pumpSettings(tester, _xmuxOn);
      await _open(tester, _coreSettings);
      await tester.ensureVisible(_field('Max concurrency'));
      await tester.pump();
      await tester.showKeyboard(_field('Max concurrency'));
      await tester.pump();
      await _systemBack(tester);
      await _frames(tester);

      expect(fake.saves, isEmpty);
    });

    // AnimatedCrossFade прячет поля в ExcludeFocus, и это тоже потеря фокуса
    testWidgets('выключили XMUX посреди ввода: введённое не пропало', (tester) async {
      final fake = await _pumpSettings(tester, _xmuxOn);
      await _open(tester, _coreSettings);
      await _type(tester, 'Max concurrency', '8');
      await tester.ensureVisible(find.text('Enable XMUX'));
      await tester.pump();
      await tester.tap(find.text('Enable XMUX'));
      await _frames(tester);

      expect(fake.saves.last.xrayCore.xmuxEnabled, isFalse);
      expect(fake.saves.last.xrayCore.xmuxMaxConcurrency, '8');
    });

    testWidgets('DNS-серверы: уход с экрана сохраняет', (tester) async {
      final fake = await _pumpSettings(
        tester,
        const AppSettings(xrayCore: XrayCoreSettings(dnsUseCustom: true)),
      );
      await _open(tester, _coreSettings);
      await _type(tester, 'DNS servers', 'https://9.9.9.9/dns-query');
      await _systemBack(tester);
      await _frames(tester);

      expect(fake.saves.last.xrayCore.dnsServers, 'https://9.9.9.9/dns-query');
    });
  });

  group('Отдельный резолвер для direct-доменов', () {
    const label = 'Split resolver for direct domains';

    testWidgets('со своим DNS из одного сервера не показан: он бы ничего не менял',
        (tester) async {
      await _pumpSettings(
        tester,
        const AppSettings(
          xrayCore: XrayCoreSettings(
            dnsUseCustom: true,
            dnsServers: 'https+local://8.8.8.8/dns-query',
          ),
        ),
      );
      await _open(tester, _coreSettings);
      expect(find.text(label), findsNothing);
    });

    testWidgets('с двумя своими серверами показан', (tester) async {
      await _pumpSettings(
        tester,
        const AppSettings(
          xrayCore: XrayCoreSettings(dnsUseCustom: true, dnsServers: '1.1.1.1, 8.8.8.8'),
        ),
      );
      await _open(tester, _coreSettings);
      expect(find.text(label), findsOneWidget);
    });

    testWidgets('без своего DNS показан: прямые домены идут в системный резолвер',
        (tester) async {
      await _pumpSettings(tester, const AppSettings());
      await _open(tester, _coreSettings);
      expect(find.text(label), findsOneWidget);
    });
  });

  group('LAN Proxy', () {
    const lanOn = AppSettings(lanSharing: true);

    testWidgets('логин сохраняется по потере фокуса', (tester) async {
      final fake = await _pumpSettings(tester, lanOn);
      await _type(tester, 'Username', ' guest ');
      _unfocus();
      await _frames(tester);

      expect(fake.saves.last.lanUsername, 'guest');
    });

    testWidgets('переход в соседнее поле сохраняет первое', (tester) async {
      final fake = await _pumpSettings(tester, lanOn);
      await _type(tester, 'Username', 'guest');
      await _type(tester, 'Password', 'secret');
      _unfocus();
      await _frames(tester);

      expect(fake.saves.last.lanUsername, 'guest');
      expect(fake.saves.last.lanPassword, 'secret');
    });

    testWidgets('неверный порт не сохраняется', (tester) async {
      final fake = await _pumpSettings(tester, lanOn);
      await _type(tester, 'SOCKS5 port', '70000');
      _unfocus();
      await _frames(tester);

      expect(fake.saves.where((s) => s.lanSocksPort == 70000), isEmpty);
    });
  });

  group('Server ping', () {
    const custom = AppSettings(pingTestTarget: PingTestConfig.targetCustom);

    testWidgets('свой адрес сохраняется при уходе с экрана', (tester) async {
      final fake = await _pumpSettings(tester, custom);
      await _open(tester, const ['Advanced', 'Server ping']);
      await _type(tester, 'URL', 'https://example.com/generate_204');
      await _systemBack(tester);
      await _frames(tester);

      expect(
        fake.saves.last.pingTestUrlCustom,
        'https://example.com/generate_204',
      );
    });

    testWidgets('неверный адрес по потере фокуса не сохраняется', (tester) async {
      final fake = await _pumpSettings(tester, custom);
      await _open(tester, const ['Advanced', 'Server ping']);
      await _type(tester, 'URL', 'http://127.0.0.1/');
      _unfocus();
      await _frames(tester);

      expect(fake.saves, isEmpty);
      expect(
        find.text('Invalid or unsafe URL (no localhost or private networks)'),
        findsOneWidget,
      );
    });
  });
}
