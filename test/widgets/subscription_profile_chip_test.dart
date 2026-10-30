import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/routing_profile.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/models/traffic_route.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/subscriptions_tab.dart';
import 'package:keqdroid/services/rule_list_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

class _FakeSubs extends SubscriptionsNotifier {
  @override
  Future<List<Subscription>> build() async => const [
        Subscription(id: 'a', name: 'Gaming VPN', url: 'https://a.example'),
      ];
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

RoutingProfile _games({bool enabled = true}) => RoutingProfile(
      id: 'games',
      name: 'Игры',
      enabled: enabled,
      subscriptionIds: const ['a'],
      routes: const [TrafficRoute(id: 'r', sites: 'twitch.tv')],
    );

Future<void> _pump(
  WidgetTester tester,
  List<RoutingProfile> profiles, {
  List<TrafficRoute> mainRoutes = const [],
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  final storage = await buildStorageService();
  await storage.saveRoutingProfiles(profiles);
  await storage.saveRoutes(mainRoutes);
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

void main() {
  testWidgets('на телевизоре карточка подписки сворачивается пультом', (tester) async {
    PlatformBootstrap.debugIsTelevisionOverride = true;
    addTearDown(() => PlatformBootstrap.debugIsTelevisionOverride = null);
    await _pump(tester, const []);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SubscriptionsTab)),
    );
    Focus.of(tester.element(find.byIcon(Icons.expand_more_rounded).first))
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(container.read(collapsedSubscriptionCardsProvider)['a'], isTrue);
  });

  testWidgets('без профиля плашки нет', (tester) async {
    await _pump(tester, const []);
    expect(find.text('Gaming VPN'), findsOneWidget);
    expect(find.byIcon(Icons.alt_route_rounded), findsNothing);
  });

  testWidgets('выключенный профиль подписку не забирает, плашки нет',
      (tester) async {
    await _pump(tester, [_games(enabled: false)]);
    expect(find.text('Игры'), findsNothing);
  });

  testWidgets('плашка профиля ведёт в маршрутизацию, профиль раскрыт',
      (tester) async {
    await _pump(tester, [_games()]);
    expect(find.text('Игры'), findsOneWidget);
    await tester.tap(find.text('Игры'));
    await tester.pumpAndSettle();
    expect(find.text('Маршрутизация'), findsWidgets);
    expect(find.text('twitch.tv'), findsOneWidget);
  });

  testWidgets('под длинным «Основным» экран открывается на карточке профиля',
      (tester) async {
    // столько строк, что карточка профиля в первом кадре ещё не построена
    await _pump(tester, [_games()], mainRoutes: [
      for (var i = 0; i < 30; i++)
        TrafficRoute(id: 'm$i', sites: 'site$i.example'),
    ]);
    await tester.tap(find.text('Игры'));
    await tester.pumpAndSettle();
    expect(find.text('Игры').hitTestable(), findsOneWidget);
    expect(find.text('twitch.tv').hitTestable(), findsOneWidget);
    expect(find.text('Основной').hitTestable(), findsNothing);
  });

  testWidgets('влезающую карточку экран поднимает только до кнопки внизу',
      (tester) async {
    await _pump(tester, [
      _games(),
      const RoutingProfile(id: 'work', name: 'Работа'),
    ]);
    await tester.tap(find.text('Игры'));
    await tester.pumpAndSettle();
    final card =
        tester.getRect(find.byKey(const ValueKey('routing-profile-games')));
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    // 96 под кнопкой «Новый профиль»
    expect(card.bottom, lessThanOrEqualTo(screen.height - 96 + 0.5));
    expect(card.top, greaterThan(200), reason: 'не к верху: сдвиг минимальный');
  });
}
