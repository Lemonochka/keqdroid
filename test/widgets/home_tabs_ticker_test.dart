import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/main.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/providers/halloween_provider.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/servers_tab.dart';
import 'package:keqdroid/screens/settings_tab.dart';
import 'package:keqdroid/screens/subscriptions_tab.dart';
import 'package:keqdroid/services/vpn_engine.dart';

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

// вкладку за краем PageView может и не построить вовсе: тогда тикать там нечему
bool _ticking(WidgetTester tester, Type tab) {
  final found = find.byType(tab, skipOffstage: false).evaluate();
  return found.isNotEmpty && TickerMode.valuesOf(found.single).enabled;
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
        child: const KeqdisApp(home: VpnHomeScreen()),
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
}
