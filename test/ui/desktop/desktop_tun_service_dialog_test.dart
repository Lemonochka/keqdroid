import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/ui/desktop/desktop_connection_mode.dart';

// TUN без прав администратора на Windows: вместо перезапуска от администратора один раз ставится служба

const _vpn = MethodChannel('keqdroid_vpn_channel');
const _service = MethodChannel('keqdroid/tun_service');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> serviceCalls;
  late bool elevated;
  late Map<String, Object?> status;
  late Map<String, Object?> install;

  setUp(() {
    serviceCalls = [];
    elevated = false;
    status = {'installed': false, 'trusted': false};
    install = {'ok': true};
    messenger.setMockMethodCallHandler(_vpn, (call) async {
      if (call.method == 'requestTunnelPermission') return elevated;
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
    Future<void> Function(WidgetTester) act,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  result = await ensureWindowsTunService(context),
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
  }, skip: !Platform.isWindows);
}
