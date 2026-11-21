import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/ui/desktop/desktop_connection_mode.dart';

// TUN без прав администратора на Windows: вместо перезапуска от администратора один раз ставится служба

const _vpn = MethodChannel('keqdroid_vpn_channel');
const _service = MethodChannel('keqdroid/tun_service');

class _Vpn extends VpnStateNotifier {
  // autostartTunFallback каждого вызова
  final connects = <bool>[];

  @override
  Future<VpnState> build() async =>
      const VpnState(status: VpnStatus.disconnected);

  @override
  Future<void> connect({bool autostartTunFallback = false}) async =>
      connects.add(autostartTunFallback);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> serviceCalls;
  late List<String> windowCalls;
  late bool elevated;
  late Map<String, Object?> status;
  late Map<String, Object?> install;

  setUp(() {
    serviceCalls = [];
    windowCalls = [];
    elevated = false;
    status = {'installed': false, 'trusted': false};
    install = {'ok': true};
    messenger.setMockMethodCallHandler(_vpn, (call) async {
      if (call.method == 'requestTunnelPermission') return elevated;
      if (call.method == 'restoreMainWindow') {
        windowCalls.add(call.method);
        return true;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(_service, (call) async {
      serviceCalls.add(call.method);
      if (call.method == 'status') return status;
      if (call.method == 'install') {
        if (install['ok'] == true) {
          status = {'installed': true, 'trusted': true};
        }
        return install;
      }
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(_vpn, null);
    messenger.setMockMethodCallHandler(_service, null);
  });

  Future<bool?> run(
    WidgetTester tester,
    Future<void> Function(WidgetTester) act, {
    Future<bool> Function(BuildContext) go = ensureWindowsTunService,
  }) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await go(context),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await act(tester);
    await tester.pumpAndSettle();
    return result;
  }

  group('Windows', () {
    testWidgets('без службы спрашивает, ставит и пускает в TUN', (
      tester,
    ) async {
      final result = await run(tester, (t) async {
        expect(find.text('Service for TUN'), findsOneWidget);
        expect(find.textContaining('installed once'), findsOneWidget);
        await t.tap(find.text('Install the service'));
      });
      expect(result, isTrue);
      expect(serviceCalls, ['status', 'install', 'status']);
    });

    testWidgets('отказ в окне оставляет режим как был', (tester) async {
      final result = await run(tester, (t) async {
        await t.tap(find.text('Cancel'));
      });
      expect(result, isFalse);
      expect(serviceCalls, ['status']);
    });

    testWidgets('после обновления приложения просит обновить службу', (
      tester,
    ) async {
      status = {'installed': true, 'trusted': false};
      final result = await run(tester, (t) async {
        expect(find.text('Update the service'), findsOneWidget);
        await t.tap(find.text('Update the service'));
      });
      expect(result, isTrue);
    });

    testWidgets('с готовой службой и с правами окна нет', (tester) async {
      status = {'installed': true, 'trusted': true};
      expect(await run(tester, (_) async {}), isTrue);
      expect(find.byType(AlertDialog), findsNothing);

      elevated = true;
      serviceCalls.clear();
      expect(await run(tester, (_) async {}), isTrue);
      expect(serviceCalls, isEmpty);
    });

    testWidgets('неудачная установка говорит об этом', (tester) async {
      install = {'ok': false, 'cancelled': false};
      final result = await run(tester, (t) async {
        await t.tap(find.text('Install the service'));
      });
      expect(result, isFalse);
      expect(find.text('Could not install the service'), findsOneWidget);
    });

    // подключение на старте, из трея и горячей клавишей: окно могло лежать в трее
    testWidgets('из трея сперва показывает окно, потом спрашивает', (
      tester,
    ) async {
      final result = await run(
        tester,
        (t) async {
          expect(windowCalls, ['restoreMainWindow']);
          expect(find.text('Service for TUN'), findsOneWidget);
          await t.tap(find.text('Install the service'));
        },
        go: (context) => ensureTunReadyToConnect(
          context,
          AppSettings(connectionMode: ConnectionMode.tun.storageValue),
          showWindow: true,
        ),
      );
      expect(result, isTrue);
      expect(serviceCalls, ['status', 'install', 'status']);
    });

    testWidgets('со службой или в Proxy окно из трея не достаёт', (
      tester,
    ) async {
      status = {'installed': true, 'trusted': true};
      expect(
        await run(
          tester,
          (_) async {},
          go: (context) => ensureTunReadyToConnect(
            context,
            AppSettings(connectionMode: ConnectionMode.tun.storageValue),
            showWindow: true,
          ),
        ),
        isTrue,
      );

      status = {'installed': false, 'trusted': false};
      serviceCalls.clear();
      expect(
        await run(
          tester,
          (_) async {},
          go: (context) => ensureTunReadyToConnect(
            context,
            const AppSettings(),
            showWindow: true,
          ),
        ),
        isTrue,
      );
      expect(serviceCalls, isEmpty);
      expect(windowCalls, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('нажатие в открытом окне окно не трогает', (tester) async {
      await run(tester, (t) async {
        await t.tap(find.text('Cancel'));
      });
      expect(windowCalls, isEmpty);
    });

    group('подключение на старте', () {
      late _Vpn vpn;
      late VpnStatus status;
      setUp(() {
        vpn = _Vpn();
        status = VpnStatus.disconnected;
      });

      Future<void> start(
        WidgetTester tester,
        AppSettings settings,
        Future<void> Function(WidgetTester) act,
      ) => run(
        tester,
        act,
        go: (context) async {
          await connectOnStartup(
            context,
            settings: settings,
            vpn: vpn,
            status: () => status,
          );
          return true;
        },
      );

      final tun = AppSettings(connectionMode: ConnectionMode.tun.storageValue);

      testWidgets('TUN без службы: окно, вопрос, служба, подключение', (
        tester,
      ) async {
        await start(tester, tun, (t) async {
          expect(windowCalls, ['restoreMainWindow']);
          expect(vpn.connects, isEmpty, reason: 'ждёт ответа');
          await t.tap(find.text('Install the service'));
        });
        expect(serviceCalls, ['status', 'install', 'status']);
        expect(vpn.connects, [true]);
      });

      testWidgets('отказ подключает как раньше, connect сам уйдёт в Proxy', (
        tester,
      ) async {
        await start(tester, tun, (t) async {
          await t.tap(find.text('Cancel'));
        });
        expect(vpn.connects, [true]);
      });

      testWidgets('пока висел вопрос, подключили из трея: второго нет', (
        tester,
      ) async {
        await start(tester, tun, (t) async {
          status = VpnStatus.connected;
          await t.tap(find.text('Install the service'));
        });
        expect(vpn.connects, isEmpty);
      });

      testWidgets('Proxy и TUN со службой подключаются без вопроса', (
        tester,
      ) async {
        await start(tester, const AppSettings(), (_) async {});
        expect(serviceCalls, isEmpty);

        status = VpnStatus.disconnected;
        final ready = {'installed': true, 'trusted': true};
        messenger.setMockMethodCallHandler(_service, (call) async {
          serviceCalls.add(call.method);
          return ready;
        });
        await start(tester, tun, (_) async {});
        expect(serviceCalls, ['status']);
        expect(find.byType(AlertDialog), findsNothing);
        expect(windowCalls, isEmpty);
        expect(vpn.connects, [true, true]);
      });
    });
  }, skip: !Platform.isWindows);
}
