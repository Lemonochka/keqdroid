import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/routing_profile.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/traffic_route.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

/// Подключение берёт маршруты и «Всё остальное» профиля подписки, к которой
/// относится сервер; без включённого профиля работает «Основной».
class _Backend extends FakeTunnelBackend {
  VpnState current = VpnState.disconnected;
  TunnelSessionRequest? session;

  @override
  Future<VpnState> getCurrentState() async => current;

  @override
  Future<void> startSession(TunnelSessionRequest request) async {
    session = request;
    current = const VpnState(status: VpnStatus.connected);
  }
}

const _config =
    'vless://00000000-0000-4000-8000-000000000000@198.51.100.10:443'
    '?type=tcp&security=none#test';

final _fromSub = ServerItem(
  id: 'srv-sub',
  type: ServerItemType.subscription,
  subscriptionId: 'sub-games',
  config: _config,
);
final _manual = ServerItem(
  id: 'srv-manual',
  type: ServerItemType.manual,
  config: _config,
);

const _mainRoutes = [
  TrafficRoute(
    id: 'm',
    sites: 'main-direct.example',
    target: RouteTarget.direct,
  ),
];

RoutingProfile _games({bool enabled = true}) => RoutingProfile(
  id: 'games',
  name: 'Игры',
  enabled: enabled,
  subscriptionIds: const ['sub-games'],
  finalOutbound: AppSettings.finalOutboundDirect,
  routes: const [
    TrafficRoute(
      id: 'p',
      sites: 'profile-block.example',
      target: RouteTarget.block,
    ),
  ],
);

List<Map<String, dynamic>> _rules(String xray) => [
  for (final r
      in ((jsonDecode(xray) as Map)['routing'] as Map)['rules'] as List)
    (r as Map).cast<String, dynamic>(),
];

Future<({String xray, StorageService storage})> _connect(
  ServerItem server, {
  List<RoutingProfile> profiles = const [],
}) async {
  final backend = _Backend();
  final storage = await buildStorageService();
  await storage.saveServers([server]);
  await storage.setActiveServerId(server.id);
  await storage.saveRoutes(_mainRoutes);
  await storage.saveRoutingProfiles(profiles);
  final container = ProviderContainer(
    overrides: [
      storageProvider.overrideWithValue(storage),
      vpnEngineProvider.overrideWithValue(VpnEngine.withBackend(backend)),
    ],
  );
  addTearDown(container.dispose);
  container.read(serversProvider);
  await container.read(vpnStateProvider.future);
  await container.read(vpnStateProvider.notifier).connect();
  return (xray: backend.session!.xrayConfig, storage: storage);
}

String? _finalTag(String xray) =>
    _rules(xray).firstWhere((r) => r['ruleTag'] == 'final')['outboundTag']
        as String?;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'без профилей всё как раньше: маршруты и «Всё остальное» основные',
    () async {
      final r = await _connect(_fromSub);
      expect(r.xray, contains('main-direct.example'));
      expect(_finalTag(r.xray), 'proxy');
    },
  );

  test(
    'сервер подписки с профилем берёт его маршруты и «Всё остальное»',
    () async {
      final r = await _connect(_fromSub, profiles: [_games()]);
      expect(r.xray, contains('profile-block.example'));
      expect(r.xray, isNot(contains('main-direct.example')));
      expect(_finalTag(r.xray), 'direct');
    },
  );

  test('«Всё остальное» профиля не попадает в сохранённые настройки', () async {
    final r = await _connect(_fromSub, profiles: [_games()]);
    expect(
      (await r.storage.getSettings()).finalOutbound,
      AppSettings.finalOutboundProxy,
    );
  });

  test('выключенный профиль уступает «Основному»', () async {
    final r = await _connect(_fromSub, profiles: [_games(enabled: false)]);
    expect(r.xray, contains('main-direct.example'));
    expect(r.xray, isNot(contains('profile-block.example')));
    expect(_finalTag(r.xray), 'proxy');
  });

  test('свой сервер вне подписок идёт по «Основному»', () async {
    final r = await _connect(_manual, profiles: [_games()]);
    expect(r.xray, contains('main-direct.example'));
    expect(_finalTag(r.xray), 'proxy');
  });
}
