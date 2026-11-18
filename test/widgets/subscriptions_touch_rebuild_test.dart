import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/subscriptions_tab.dart';
import 'package:keqdroid/services/rule_list_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

final _subs = [
  for (var i = 0; i < 3; i++)
    Subscription(
      id: 's$i',
      name: 'Provider $i',
      url: 'https://$i.example',
      usedBytes: 6353261407,
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    ),
];

class _FakeSubs extends SubscriptionsNotifier {
  @override
  Future<List<Subscription>> build() async => _subs;
}

class _FakeSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

class _FakeVpn extends VpnStateNotifier {
  @override
  Future<VpnState> build() async =>
      const VpnState(status: VpnStatus.disconnected);
}

class _FakeRuleLists extends RuleListsNotifier {
  @override
  Map<String, RuleListStatus> build() => const {};
}

Future<void> _pump(WidgetTester tester) async {
  PlatformBootstrap.debugIsDesktopOverride = false;
  addTearDown(() => PlatformBootstrap.debugIsDesktopOverride = null);
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  final storage = await buildStorageService();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
        subscriptionsProvider.overrideWith(_FakeSubs.new),
        settingsNotifierProvider.overrideWith(_FakeSettings.new),
        vpnStateProvider.overrideWith(_FakeVpn.new),
        ruleListsProvider.overrideWith(_FakeRuleLists.new),
        vpnEngineProvider.overrideWithValue(
          VpnEngine.withBackend(FakeTunnelBackend()),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ru'),
        home: const SubscriptionsTab(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// на Pixel 6a первый кадр свайпа с подписок обратно на серверы стоил 43-49 мс: палец ложится на карточку,
// список готовит перетаскивание и перестраивает все карточки (трасса 18.11.2026)
void main() {
  testWidgets('касание карточки не пересобирает карточки списка', (tester) async {
    await _pump(tester);
    expect(find.text('Provider 0'), findsOneWidget);

    final rebuilt = <Widget>[];
    debugOnRebuildDirtyWidget = (e, _) => rebuilt.add(e.widget);
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('Provider 0')));
    await tester.pump(const Duration(milliseconds: 16));
    debugOnRebuildDirtyWidget = null;

    expect(
      rebuilt.whereType<SliverReorderableList>(),
      isNotEmpty,
      reason: 'касание дошло до списка и он перестроился',
    );
    expect(rebuilt.whereType<Text>(), isEmpty);

    await gesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets('карточку по-прежнему можно перетащить на другое место', (tester) async {
    await _pump(tester);
    final first = tester.getCenter(find.text('Provider 0'));
    final step = tester.getCenter(find.text('Provider 1')).dy - first.dy;
    final gesture = await tester.startGesture(first);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(0, step * 0.15));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.text('Provider 1')).dy,
      lessThan(tester.getCenter(find.text('Provider 0')).dy),
    );
  });
}
