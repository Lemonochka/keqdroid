import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/main.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/providers/halloween_provider.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/servers_tab.dart';
import 'package:keqdroid/screens/settings_tab.dart';
import 'package:keqdroid/screens/subscriptions_tab.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/shared/ui/liquid_wave.dart';
import 'package:keqdroid/shared/ui/server_row.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

class _NoSubs extends SubscriptionsNotifier {
  @override
  Future<List<Subscription>> build() async => const [];
}

class _NoHalloween extends HalloweenActiveNotifier {
  @override
  bool build() => false;
}

class _Connected extends VpnStateNotifier {
  @override
  Future<VpnState> build() async =>
      const VpnState(status: VpnStatus.connected);
}

// вкладку за краем PageView может и не построить вовсе: тогда тикать там нечему.
// не valuesOf: тот подписал бы вкладку на TickerMode, и её пересобирал бы уже тест
bool _ticking(WidgetTester tester, Type tab) {
  final found = find.byType(tab, skipOffstage: false).evaluate();
  return found.isNotEmpty &&
      TickerMode.getValuesNotifier(found.single).value.enabled;
}

void main() {
  testWidgets('анимации, в том числе гифки подписок, идут только на видимой вкладке',
      (tester) async {
    PlatformBootstrap.debugIsDesktopOverride = false;
    addTearDown(() => PlatformBootstrap.debugIsDesktopOverride = null);
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final storage = await tester.runAsync(buildStorageService);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage!),
          subscriptionsProvider.overrideWith(_NoSubs.new),
          halloweenActiveProvider.overrideWith(_NoHalloween.new),
          exitIpProvider.overrideWith((ref) async => null),
          updateInfoProvider.overrideWith((ref) async => null),
          vpnEngineProvider.overrideWithValue(
            VpnEngine.withBackend(FakeTunnelBackend()),
          ),
        ],
        child: const KeqdroidApp(home: VpnHomeScreen()),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_ticking(tester, ServersTab), isTrue);
    expect(_ticking(tester, SubscriptionsTab), isFalse);
    expect(_ticking(tester, SettingsTab), isFalse);

    // на середине свайпа видны обе соседние вкладки, и обе живые
    final gesture = await tester.startGesture(const Offset(300, 450));
    await gesture.moveBy(const Offset(-150, 0));
    await tester.pump();
    expect(_ticking(tester, ServersTab), isTrue);
    expect(_ticking(tester, SubscriptionsTab), isTrue);
    await gesture.moveBy(const Offset(-200, 0));
    await gesture.up();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_ticking(tester, ServersTab), isFalse);
    expect(_ticking(tester, SubscriptionsTab), isTrue);
    expect(_ticking(tester, SettingsTab), isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets(
      'вода в шапке стоит за чужой вкладкой, а свайп туда и обратно не пересобирает список',
      (tester) async {
    PlatformBootstrap.debugIsDesktopOverride = false;
    addTearDown(() => PlatformBootstrap.debugIsDesktopOverride = null);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    final subs = [
      for (var s = 0; s < 2; s++)
        Subscription(
          id: 'sub$s',
          name: 'Provider $s',
          url: 'https://example.com/$s',
          autoUpdate: false,
        ),
    ];
    final servers = [
      for (var s = 0; s < 2; s++)
        for (var i = 0; i < 6; i++)
          ServerItem(
            id: 's$s-$i',
            config: 'vless://00000000-0000-4000-8000-000000000000@198.51.100.$i:443'
                '?type=tcp&security=reality&pbk=k&sni=example.com#Server%20$s-$i',
            type: ServerItemType.subscription,
            subscriptionId: 'sub$s',
            subscriptionName: 'Provider $s',
            addedAt: DateTime(2026, 11, 1),
          ),
    ];
    final storage = await tester.runAsync(() => buildStorageService(initialValues: {
          'keqdis_servers_v2': jsonEncode([for (final s in servers) s.toJson()]),
          'keqdis_subscriptions': jsonEncode([for (final s in subs) s.toJson()]),
          'keqdis_active_server': 's0-0',
        }));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage!),
          halloweenActiveProvider.overrideWith(_NoHalloween.new),
          exitIpProvider.overrideWith((ref) async => null),
          updateInfoProvider.overrideWith((ref) async => null),
          vpnEngineProvider.overrideWithValue(
            VpnEngine.withBackend(FakeTunnelBackend()),
          ),
          vpnStateProvider.overrideWith(_Connected.new),
        ],
        child: const KeqdroidApp(home: VpnHomeScreen()),
      ),
    );
    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    await frames(60);
    expect(find.byType(ServerRow), findsWidgets);
    final clock = tester
        .widget<LiquidWave>(find.byType(LiquidWave, skipOffstage: false).first)
        .clock;
    expect(clock.muted, isFalse);

    var rowBuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is ServerRow) rowBuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    // страница доезжает до места дольше полсекунды, ждём с запасом
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1500);
    await frames(120);
    expect(_ticking(tester, ServersTab), isFalse);
    expect(clock.muted, isTrue);

    await tester.fling(find.byType(PageView), const Offset(300, 0), 1500);
    await frames(120);
    expect(_ticking(tester, ServersTab), isTrue);
    expect(clock.muted, isFalse);

    expect(rowBuilds, 0);

    debugOnRebuildDirtyWidget = null;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });
}
