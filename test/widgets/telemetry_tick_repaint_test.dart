import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/main.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/providers/halloween_provider.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/shared/ui/liquid_nav.dart';
import 'package:keqdroid/shared/ui/stat_strip.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

class _NoHalloween extends HalloweenActiveNotifier {
  @override
  bool build() => false;
}

class _Backend extends FakeTunnelBackend {
  final ctrl = StreamController<VpnState>.broadcast();
  VpnState current = VpnState.disconnected;

  @override
  Stream<VpnState> get stateStream => ctrl.stream;

  @override
  Future<VpnState> getCurrentState() async => current;

  void emit(VpnState s) {
    current = s;
    ctrl.add(s);
  }
}

VpnState _connected(int seconds) => VpnState(
  status: VpnStatus.connected,
  uploadSpeed: 100,
  downloadSpeed: 2048,
  totalUpload: 1000 + seconds,
  totalDownload: 5000 + seconds * 2048,
  duration: Duration(seconds: seconds),
);

// на экране 2h 5m, 0 B/s и 3.02 GB, а байты и секунды под ними уже другие
VpnState _quiet(int seconds, int extraBytes) => VpnState(
  status: VpnStatus.connected,
  uploadSpeed: 0,
  downloadSpeed: 0,
  totalUpload: 1000 + extraBytes,
  totalDownload: 3243000000 + extraBytes,
  duration: Duration(hours: 2, minutes: 5, seconds: seconds),
);

bool _inside<T extends Widget>(RenderObject ro) {
  final creator = ro.debugCreator;
  if (creator is! DebugCreator) return false;
  if (creator.element.widget is T) return true;
  var found = false;
  creator.element.visitAncestorElements((e) {
    found = e.widget is T;
    return !found;
  });
  return found;
}

Future<_Backend> _pumpHome(
  WidgetTester tester, {
  required VpnState state,
  bool modern = false,
}) async {
  PlatformBootstrap.debugIsDesktopOverride = false;
  addTearDown(() => PlatformBootstrap.debugIsDesktopOverride = null);
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);

  final sub = Subscription(
    id: 'sub0',
    name: 'Provider',
    url: 'https://example.com/0',
    autoUpdate: false,
  );
  final servers = [
    for (var i = 0; i < 6; i++)
      ServerItem(
        id: 's$i',
        config:
            'vless://00000000-0000-4000-8000-000000000000@198.51.100.$i:443'
            '?type=tcp&security=reality&pbk=k&sni=example.com#Server%20$i',
        type: ServerItemType.subscription,
        subscriptionId: 'sub0',
        subscriptionName: 'Provider',
        addedAt: DateTime(2026, 11, 1),
      ),
  ];
  final storage = await tester.runAsync(
    () => buildStorageService(
      initialValues: {
        'keqdis_servers_v2': jsonEncode([for (final s in servers) s.toJson()]),
        'keqdis_subscriptions': jsonEncode([sub.toJson()]),
        'keqdis_active_server': 's1',
        if (modern) 'keqdis_settings': jsonEncode({'modernConnectPanel': true}),
      },
    ),
  );
  final backend = _Backend();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage!),
        halloweenActiveProvider.overrideWith(_NoHalloween.new),
        exitIpProvider.overrideWith((ref) async => null),
        updateInfoProvider.overrideWith((ref) async => null),
        vpnEngineProvider.overrideWithValue(VpnEngine.withBackend(backend)),
      ],
      child: const KeqdroidApp(home: VpnHomeScreen()),
    ),
  );
  backend.emit(state);
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(find.byType(LiquidBottomNav), findsOneWidget);
  expect(find.byType(StatStrip), findsOneWidget);
  return backend;
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 1));
}

// счётчик и время приходят раз в 1,5-2 с, и на Pixel 6a каждый такой кадр опаздывал:
// тик перерисовывал нижнюю панель вместе с шапкой (трасса 18.11.2026)
void main() {
  testWidgets('тик телеметрии не перерисовывает нижнюю панель', (tester) async {
    final backend = await _pumpHome(tester, state: _connected(10));

    var navPaints = 0;
    var stripPaints = 0;
    debugOnProfilePaint = (ro) {
      if (_inside<LiquidBottomNav>(ro)) navPaints++;
      if (_inside<StatStrip>(ro)) stripPaints++;
    };
    debugProfilePaintsEnabled = true;
    addTearDown(() {
      debugProfilePaintsEnabled = false;
      debugOnProfilePaint = null;
    });

    backend.emit(_connected(11));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    debugProfilePaintsEnabled = false;
    debugOnProfilePaint = null;

    expect(
      stripPaints,
      greaterThan(0),
      reason: 'тик дошёл до строки статистики',
    );
    expect(navPaints, 0);

    await _unmount(tester);
  });

  // на 400 МГц такой тик стоил 12-13 мс раскладки и перерисовки ради того же текста
  for (final modern in [false, true]) {
    testWidgets('тик без видимых перемен не трогает строку и время, '
        '${modern ? 'модерн' : 'легаси'}', (tester) async {
      final backend = await _pumpHome(
        tester,
        state: _quiet(10, 0),
        modern: modern,
      );
      expect(find.textContaining('3.02 GB'), findsOneWidget);
      expect(find.textContaining('2h 5m'), findsOneWidget);

      final rebuilt = <Widget>[];
      var stripPaints = 0;
      debugOnRebuildDirtyWidget = (e, _) => rebuilt.add(e.widget);
      debugOnProfilePaint = (ro) {
        if (_inside<StatStrip>(ro)) stripPaints++;
      };
      debugProfilePaintsEnabled = true;
      addTearDown(() {
        debugOnRebuildDirtyWidget = null;
        debugProfilePaintsEnabled = false;
        debugOnProfilePaint = null;
      });

      backend.emit(_quiet(11, 4096));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      debugOnRebuildDirtyWidget = null;
      debugProfilePaintsEnabled = false;
      debugOnProfilePaint = null;

      expect(rebuilt.where((w) => w is StatStrip || w is Text), isEmpty);
      expect(stripPaints, 0);

      await _unmount(tester);
    });
  }
}
