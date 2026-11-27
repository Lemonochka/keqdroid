import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/providers/halloween_provider.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/servers_tab.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/ui/desktop/connect_rehearsal_host.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

// Репетиция подключения на Windows: копия шапки и строки сервера проигрывает
// подключение под вкладками, чтобы шейдеры собрались до настоящего нажатия.
// Настоящий VPN, курсор и ввод она трогать не должна.

class _FakeServers extends ServersNotifier {
  @override
  ServersState build() => ServersState(
    servers: [
      ServerItem(
        id: 'pl',
        config:
            'vless://00000000-0000-0000-0000-000000000000@pl.example'
            '.com:443#Poland',
        type: ServerItemType.manual,
        pingMs: 44,
        lastTestedAt: DateTime(2026),
      ),
    ],
    activeServerId: 'pl',
  );
}

class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this._settings);
  final AppSettings _settings;
  @override
  Future<AppSettings> build() async => _settings;
}

class _RealVpn extends VpnStateNotifier {
  static var connects = 0;

  @override
  Future<VpnState> build() async => VpnState.disconnected;

  @override
  Future<void> connect({bool autostartTunFallback = false}) async => connects++;

  void put(VpnState next) => state = AsyncData(next);
}

class _NoHalloween extends HalloweenActiveNotifier {
  @override
  bool build() => false;
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  bool enabled = true,
  bool modern = true,
}) async {
  tester.view.physicalSize = const Size(1280, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _RealVpn.connects = 0;
  final storage = await tester.runAsync(buildStorageService);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage!),
        serversProvider.overrideWith(_FakeServers.new),
        settingsNotifierProvider.overrideWith(
          () => _FakeSettings(
            const AppSettings().copyWith(modernConnectPanel: modern),
          ),
        ),
        vpnStateProvider.overrideWith(_RealVpn.new),
        halloweenActiveProvider.overrideWith(_NoHalloween.new),
        exitIpProvider.overrideWith((ref) async => null),
        vpnEngineProvider.overrideWithValue(
          VpnEngine.withBackend(FakeTunnelBackend()),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ConnectRehearsalHost(
            enabled: enabled,
            startAfter: const Duration(seconds: 1),
            child: const ColoredBox(
              color: Colors.white,
              child: Center(child: Text('tabs')),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return ProviderScope.containerOf(
    tester.element(find.byType(ConnectRehearsalHost)),
  );
}

Finder get _rehearsal => find.byType(ConnectRehearsal, skipOffstage: false);

VpnStatus? _shownStatus(WidgetTester tester) {
  final inside = find
      .descendant(of: _rehearsal, matching: find.byType(Material))
      .first;
  return ProviderScope.containerOf(
    tester.element(inside),
  ).read(vpnStateProvider).value?.status;
}

Future<void> _advance(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets(
    'проигрывает подключение в своей копии, настоящий VPN не трогается',
    (tester) async {
      final cursors = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.mouseCursor,
        (call) async {
          cursors.add(call.arguments);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.mouseCursor,
          null,
        ),
      );
      final root = await _pump(tester);
      expect(_rehearsal, findsNothing);

      await _advance(tester, 1100);
      expect(_rehearsal, findsOneWidget);
      expect(root.read(connectRehearsalProvider), isTrue);
      // копия лежит под содержимым и закрыта фоном
      final stack = tester.widget<Stack>(
        find
            .descendant(
              of: find.byType(ConnectRehearsalHost),
              matching: find.byType(Stack),
            )
            .first,
      );
      expect(stack.children.last, isA<KeyedSubtree>());
      expect(find.text('tabs').hitTestable(), findsOneWidget);

      final seen = <VpnStatus?>{};
      for (var t = 0; t < 8400; t += 50) {
        await tester.pump(const Duration(milliseconds: 50));
        if (_rehearsal.evaluate().isNotEmpty) seen.add(_shownStatus(tester));
        expect(
          root.read(vpnStateProvider).value?.status,
          VpnStatus.disconnected,
        );
        // мышь в MouseTracker после кадра наводилась бы на настоящее окно в той же точке
        expect(RendererBinding.instance.mouseTracker.mouseIsConnected, isFalse);
      }
      expect(
        seen,
        containsAll([
          VpnStatus.connecting,
          VpnStatus.connected,
          VpnStatus.disconnected,
        ]),
      );
      await _advance(tester, 500);
      expect(_rehearsal, findsNothing);
      expect(root.read(connectRehearsalProvider), isFalse);
      expect(
        _RealVpn.connects,
        0,
        reason: 'нажатие в копии ушло в настоящий VPN',
      );
      // курсор окна копия не трогала ни разу: на Windows он один на всё окно
      expect(cursors, isEmpty);
    },
  );

  testWidgets('пока водят мышью, ждёт; потом начинает', (tester) async {
    await _pump(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(10, 10));
    for (var t = 0; t < 3000; t += 200) {
      await mouse.moveTo(Offset(10 + t / 100, 10));
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(_rehearsal, findsNothing);
    await _advance(tester, 2600);
    expect(_rehearsal, findsOneWidget);
    await _advance(tester, 9000);
  });

  testWidgets('настоящее подключение останавливает репетицию', (tester) async {
    final root = await _pump(tester);
    await _advance(tester, 1500);
    expect(_rehearsal, findsOneWidget);
    (root.read(vpnStateProvider.notifier) as _RealVpn).put(
      const VpnState(status: VpnStatus.connecting),
    );
    await tester.pump();
    expect(_rehearsal, findsNothing);
    expect(root.read(connectRehearsalProvider), isFalse);
    await _advance(tester, 6000);
    expect(_rehearsal, findsNothing);
  });

  testWidgets('VPN уже включён: не начинает', (tester) async {
    final root = await _pump(tester);
    (root.read(vpnStateProvider.notifier) as _RealVpn).put(VpnState.connected);
    await _advance(tester, 3000);
    expect(_rehearsal, findsNothing);
    expect(root.read(connectRehearsalProvider), isFalse);
  });

  testWidgets('не на Windows не начинает', (tester) async {
    await _pump(tester, enabled: false);
    await _advance(tester, 3000);
    expect(_rehearsal, findsNothing);
  });

  testWidgets('легаси-шапка тоже проигрывается', (tester) async {
    await _pump(tester, modern: false);
    await _advance(tester, 2600);
    expect(_rehearsal, findsOneWidget);
    expect(_shownStatus(tester), VpnStatus.connected);
    await _advance(tester, 7500);
    expect(_rehearsal, findsNothing);
  });

  testWidgets('в трее ждёт открытия окна, а клик посреди репетиции гасит её', (
    tester,
  ) async {
    final root = await _pump(tester);
    root.read(desktopWindowVisibleProvider.notifier).set(false);
    await _advance(tester, 2500);
    expect(_rehearsal, findsNothing);
    expect(root.read(connectRehearsalProvider), isFalse);

    root.read(desktopWindowVisibleProvider.notifier).set(true);
    await _advance(tester, 1500);
    expect(_rehearsal, findsOneWidget);

    await tester.tapAt(const Offset(100, 100));
    await tester.pump();
    expect(_rehearsal, findsNothing);
    expect(root.read(connectRehearsalProvider), isFalse);
  });
}
