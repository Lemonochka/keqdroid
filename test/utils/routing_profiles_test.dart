import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/routing_profile.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/traffic_route.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/rule_list_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/utils/provider_routing.dart';
import 'package:keqdroid/utils/routing_profiles.dart';

import '../helpers/test_storage.dart';

const _games = RoutingProfile(
  id: 'games',
  name: 'Игры',
  subscriptionIds: ['sub-a', 'sub-b'],
  finalOutbound: AppSettings.finalOutboundDirect,
  routes: [
    TrafficRoute(
      id: 'steam',
      apps: ['steam.exe'],
      content: RouteContent.allTraffic,
      target: RouteTarget.direct,
    ),
  ],
);
const _work = RoutingProfile(
  id: 'work',
  name: 'Работа',
  enabled: false,
  subscriptionIds: ['sub-c'],
);

ServerItem _server({String? subscriptionId}) => ServerItem(
      id: 's',
      type: subscriptionId == null
          ? ServerItemType.manual
          : ServerItemType.subscription,
      subscriptionId: subscriptionId,
      config: 'vless://00000000-0000-4000-8000-000000000000@a.example:443'
          '?type=tcp&security=tls#a',
    );

class _FakeVpn extends VpnStateNotifier {
  @override
  Future<VpnState> build() async =>
      const VpnState(status: VpnStatus.disconnected);
}

/// Списки «уже скачаны и свежие»: синхронизация только сверяет их и чистит
/// лишнее, а что велено оставить, записывается.
class _FakeLists extends RuleListService {
  Set<String>? kept;

  @override
  Future<RuleListStatus> status(String url) async =>
      RuleListStatus(url: url, domains: 1, updatedAt: DateTime.now());

  @override
  Future<RuleListStatus> refresh(String url) => status(url);

  @override
  Future<void> prune(Set<String> keepUrls) async => kept = keepUrls;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('профиль сервера', () {
    test('свой сервер и подписка без профиля идут по «Основному»', () {
      expect(profileForServer(const [_games], _server()), isNull);
      expect(
        profileForServer(const [_games], _server(subscriptionId: 'other')),
        isNull,
      );
    });

    test('подписка с включённым профилем берёт его', () {
      expect(
        profileForServer(const [_work, _games], _server(subscriptionId: 'sub-b'))
            ?.id,
        'games',
      );
    });

    test('выключенный профиль уступает «Основному»', () {
      expect(
        profileForServer(const [_work], _server(subscriptionId: 'sub-c')),
        isNull,
      );
    });
  });

  test('отмеченная подписка уходит из прежнего профиля', () {
    final moved = withSubscriptions(const [_games, _work], 'work', ['sub-b']);
    expect(moved.firstWhere((p) => p.id == 'games').subscriptionIds, ['sub-a']);
    expect(moved.firstWhere((p) => p.id == 'work').subscriptionIds, ['sub-b']);
  });

  test('маршрут заменяется на месте или добавляется в конец, удаляется по id',
      () {
    const a = TrafficRoute(id: 'a', sites: 'a.example');
    const b = TrafficRoute(id: 'b', sites: 'b.example');
    const a2 = TrafficRoute(id: 'a', sites: 'a2.example');
    expect(withRoute(const [a, b], a2), const [a2, b]);
    expect(withRoute(const [a], b), const [a, b]);
    expect(withoutRoute(const [a, b], 'a'), const [b]);
  });

  test('профиль переживает запись и чтение, пропущенные поля по умолчанию',
      () async {
    final storage = await buildStorageService();
    await storage.saveRoutingProfiles(const [_games, _work]);
    final back = await storage.getRoutingProfiles();
    expect(
      [for (final p in back) p.toJson()],
      [_games.toJson(), _work.toJson()],
    );

    final bare = RoutingProfile.fromJson({'id': 'x'});
    expect(bare.enabled, isTrue);
    expect(bare.finalOutbound, AppSettings.finalOutboundProxy);
    expect(bare.subscriptionIds, isEmpty);
    expect(bare.routes, isEmpty);
  });

  test('без профилей хранилище отдаёт пустой список', () async {
    final storage = await buildStorageService();
    expect(await storage.getRoutingProfiles(), isEmpty);
  });

  test('новый профиль забирает свои подписки у других', () async {
    final storage = await buildStorageService();
    await storage.saveRoutingProfiles(const [_games]);
    final container = ProviderContainer(
      overrides: [storageProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);
    await container.read(routingProfilesProvider.notifier).add(
          RoutingProfile.create(name: 'Новый', subscriptionIds: ['sub-a']),
        );
    final saved = await storage.getRoutingProfiles();
    expect(saved.first.subscriptionIds, ['sub-b']);
    expect(saved.last.subscriptionIds, ['sub-a']);
  });

  test('скачанные списки маршрутов профиля не вычищаются', () async {
    final storage = await buildStorageService();
    await storage.saveRoutes(const [
      TrafficRoute(id: 'm', sites: 'https://lists.example/main.txt'),
    ]);
    await storage.saveRoutingProfiles(const [
      RoutingProfile(
        id: 'p',
        name: 'Профиль',
        enabled: false,
        routes: [
          TrafficRoute(id: 'r', sites: 'https://lists.example/profile.txt'),
        ],
      ),
    ]);
    final lists = _FakeLists();
    final container = ProviderContainer(
      overrides: [
        storageProvider.overrideWithValue(storage),
        ruleListServiceProvider.overrideWithValue(lists),
        vpnStateProvider.overrideWith(_FakeVpn.new),
      ],
    );
    addTearDown(container.dispose);
    container.listen(ruleListsProvider, (_, _) {});
    for (var i = 0; i < 40 && lists.kept == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(lists.kept, {
      'https://lists.example/main.txt',
      'https://lists.example/profile.txt',
    });
  });

  group('профиль от провайдера', () {
    const rules = ProviderRoutingRules(
      name: 'Провайдер',
      finalOutbound: AppSettings.finalOutboundDirect,
      routes: [
        TrafficRoute(id: 'provider-proxy', sites: 'geosite:youtube'),
      ],
    );

    test('подписка без профиля получает профиль провайдера', () {
      final next = withProviderRouting(
        const [_games],
        subscriptionId: 'sub-x',
        fallbackName: 'Подписка',
        routing: rules,
      );
      expect(next.map((p) => p.id), ['games', 'provider-sub-x']);
      final p = next.last;
      expect(p.name, 'Провайдер');
      expect(p.subscriptionIds, ['sub-x']);
      expect(p.providerSubscriptionId, 'sub-x');
      expect(p.finalOutbound, AppSettings.finalOutboundDirect);
      expect(p.routes.single.sites, 'geosite:youtube');
    });

    test('без имени профиль зовётся как подписка', () {
      final next = withProviderRouting(
        const [],
        subscriptionId: 'sub-x',
        fallbackName: 'Подписка',
        routing: const ProviderRoutingRules(
          name: null,
          finalOutbound: AppSettings.finalOutboundProxy,
          routes: [],
        ),
      );
      expect(next.single.name, 'Подписка');
    });

    test('обновление меняет профиль на месте', () {
      const old = RoutingProfile(
        id: 'provider-sub-x',
        name: 'Старое',
        subscriptionIds: ['sub-x'],
        providerSubscriptionId: 'sub-x',
      );
      final next = withProviderRouting(
        const [old, _games],
        subscriptionId: 'sub-x',
        fallbackName: 'Подписка',
        routing: rules,
      );
      expect(next.map((p) => p.id), ['provider-sub-x', 'games']);
      expect(next.first.name, 'Провайдер');
    });

    test('свой профиль подписки провайдер не трогает, а свой профиль провайдера уходит', () {
      const orphan = RoutingProfile(
        id: 'provider-sub-a',
        name: 'Провайдер',
        providerSubscriptionId: 'sub-a',
      );
      final next = withProviderRouting(
        const [_games, orphan],
        subscriptionId: 'sub-a',
        fallbackName: 'Подписка',
        routing: rules,
      );
      expect(next.map((p) => p.id), ['games']);
      expect(next.single.subscriptionIds, ['sub-a', 'sub-b']);
    });

    test('off убирает профиль провайдера и только его', () {
      const provider = RoutingProfile(
        id: 'provider-sub-x',
        name: 'Провайдер',
        subscriptionIds: ['sub-x'],
        providerSubscriptionId: 'sub-x',
      );
      final next = withProviderRouting(
        const [_games, provider, _work],
        subscriptionId: 'sub-x',
        fallbackName: 'Подписка',
        routing: const ProviderRoutingOff(),
      );
      expect(next.map((p) => p.id), ['games', 'work']);
      expect(
        withoutProviderProfileOf(const [_games, provider], 'sub-x').map((p) => p.id),
        ['games'],
      );
    });

    test('метка провайдера переживает сохранение, правка её снимает', () {
      const provider = RoutingProfile(
        id: 'provider-sub-x',
        name: 'Провайдер',
        subscriptionIds: ['sub-x'],
        providerSubscriptionId: 'sub-x',
      );
      final restored = RoutingProfile.fromJson(provider.toJson());
      expect(restored.providerSubscriptionId, 'sub-x');
      expect(provider.copyWith(name: 'x').providerSubscriptionId, 'sub-x');
      expect(provider.asOwn().providerSubscriptionId, isNull);
      expect(_games.toJson().containsKey('providerSubscription'), isFalse);
    });

    test('правка через хранилище делает профиль провайдера своим', () async {
      const provider = RoutingProfile(
        id: 'provider-sub-x',
        name: 'Провайдер',
        subscriptionIds: ['sub-x'],
        providerSubscriptionId: 'sub-x',
      );
      final storage = await buildStorageService();
      await storage.saveRoutingProfiles(const [provider, _games]);
      final container = ProviderContainer(
        overrides: [storageProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(routingProfilesProvider.notifier);
      await container.read(routingProfilesProvider.future);

      await notifier.rename('provider-sub-x', 'Моё');
      final profiles = await storage.getRoutingProfiles();
      expect(profiles.first.name, 'Моё');
      expect(profiles.first.providerSubscriptionId, isNull);
      expect(profiles.last.providerSubscriptionId, isNull);

      await storage.saveRoutingProfiles(const [provider, _games]);
      container.invalidate(routingProfilesProvider);
      await container.read(routingProfilesProvider.future);
      await container
          .read(routingProfilesProvider.notifier)
          .dropProviderProfileOf('sub-x');
      expect((await storage.getRoutingProfiles()).map((p) => p.id), ['games']);
    });
  });
}
