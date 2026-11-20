import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/names_fallback.dart';
import 'package:keqdroid/services/vpn_engine.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

// Запасной режим целиком, через VpnStateNotifier: по имени не идёт, а по адресу идёт,
// и сервер переподключается так, что адрес ищет само ядро (жалоба 20.11, белые списки)

const _server = 'wl';

ServerItem _item() => ServerItem(
  id: _server,
  type: ServerItemType.manual,
  config:
      'vless://00000000-0000-4000-8000-000000000000@198.51.100.50:443'
      '?type=tcp&security=tls&sni=example.com#wl',
);

class _Backend extends FakeTunnelBackend {
  final _states = StreamController<VpnState>.broadcast();
  VpnState current = VpnState.disconnected;
  final configs = <String>[];

  @override
  Stream<VpnState> get stateStream => _states.stream;

  @override
  Future<VpnState> getCurrentState() async => current;

  @override
  Future<void> startSession(TunnelSessionRequest request) async {
    configs.add(request.xrayConfig);
    current = const VpnState(status: VpnStatus.connected);
  }

  @override
  Future<void> stopSession() async {
    current = VpnState.disconnected;
    _states.add(VpnState.disconnected);
  }

  @override
  void dispose() {
    unawaited(_states.close());
    super.dispose();
  }
}

late DateTime _now;
final _verdicts = <NamesVerdict>[];
var _probes = 0;

Future<({ProviderContainer container, _Backend backend})> _connected({
  ServerItem? server,
  AppSettings settings = const AppSettings(),
}) async {
  final storage = await buildStorageService();
  await storage.saveSettings(settings);
  await storage.saveServers([server ?? _item()]);
  await storage.setActiveServerId(_server);
  final backend = _Backend();
  final container = ProviderContainer(
    overrides: [
      storageProvider.overrideWithValue(storage),
      vpnEngineProvider.overrideWithValue(VpnEngine.withBackend(backend)),
    ],
  );
  addTearDown(container.dispose);
  container.read(serversProvider);
  await container.read(vpnStateProvider.future);
  for (var i = 0; i < 300; i++) {
    if (container.read(serversProvider).servers.isNotEmpty) break;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  await container.read(vpnStateProvider.notifier).connect();
  expect(container.read(vpnStateProvider).value?.status, VpnStatus.connected);
  return (container: container, backend: backend);
}

ServerItem _stored(ProviderContainer c) =>
    c.read(serversProvider).servers.firstWhere((s) => s.id == _server);

Future<void> _check(ProviderContainer c) =>
    c.read(vpnStateProvider.notifier).debugNamesFallbackCheck();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _now = DateTime(2026, 11, 21, 12);
    _verdicts.clear();
    _probes = 0;
    VpnStateNotifier.debugNamesFallbackClock = () => _now;
    VpnStateNotifier.debugNamesProbe = (_) async {
      _probes++;
      return _verdicts.isEmpty ? NamesVerdict.fine : _verdicts.removeAt(0);
    };
  });

  tearDown(() {
    VpnStateNotifier.debugNamesFallbackClock = null;
    VpnStateNotifier.debugNamesProbe = null;
  });

  test(
    'two misses by name with the address fine switch the server over',
    () async {
      final rig = await _connected();
      expect(rig.backend.configs.single, isNot(contains('targetStrategy')));

      _verdicts.addAll([NamesVerdict.namesBroken, NamesVerdict.namesBroken]);
      await _check(rig.container);
      expect(_stored(rig.container).namesFallbackAt, isNull);
      await _check(rig.container);

      expect(_stored(rig.container).namesFallbackAt, _now);
      expect(rig.backend.configs, hasLength(2));
      expect(rig.backend.configs.last, contains('"targetStrategy": "UseIPv4"'));

      // в запасном режиме проверка больше не ходит: снимает его срок
      await _check(rig.container);
      expect(_probes, 2);
    },
  );

  test('a single miss followed by a fine check changes nothing', () async {
    final rig = await _connected();
    _verdicts.addAll([NamesVerdict.namesBroken, NamesVerdict.fine]);
    await _check(rig.container);
    await _check(rig.container);
    _verdicts.add(NamesVerdict.namesBroken);
    await _check(rig.container);
    expect(_stored(rig.container).namesFallbackAt, isNull);
    expect(rig.backend.configs, hasLength(1));
  });

  test('a server that answers nothing at all is not switched', () async {
    final rig = await _connected();
    _verdicts.addAll([NamesVerdict.unreachable, NamesVerdict.unreachable]);
    await _check(rig.container);
    await _check(rig.container);
    expect(_stored(rig.container).namesFallbackAt, isNull);
    expect(rig.backend.configs, hasLength(1));
  });

  test('the switch lasts a day, then the server connects as before', () async {
    final day = await _connected(
      server: _item().copyWith(
        namesFallbackAt: _now.subtract(const Duration(hours: 23)),
      ),
    );
    expect(day.backend.configs.single, contains('"targetStrategy"'));

    final later = await _connected(
      server: _item().copyWith(
        namesFallbackAt: _now.subtract(const Duration(hours: 25)),
      ),
    );
    expect(later.backend.configs.single, isNot(contains('targetStrategy')));
  });

  test(
    'with unmatched traffic not through the VPN the check stays away',
    () async {
      final rig = await _connected(
        settings: const AppSettings(
          finalOutbound: AppSettings.finalOutboundDirect,
        ),
      );
      _verdicts.addAll([NamesVerdict.namesBroken, NamesVerdict.namesBroken]);
      await _check(rig.container);
      await _check(rig.container);
      expect(_probes, 0);
      expect(_stored(rig.container).namesFallbackAt, isNull);
    },
  );

  group('NamesFallback', () {
    test('verdict', () {
      expect(
        NamesFallback.verdict(byName: true, byAddress: false),
        NamesVerdict.fine,
      );
      expect(
        NamesFallback.verdict(byName: false, byAddress: true),
        NamesVerdict.namesBroken,
      );
      expect(
        NamesFallback.verdict(byName: false, byAddress: false),
        NamesVerdict.unreachable,
      );
    });

    test('the core inbound answering for a dead exit is not delivery', () {
      expect(
        NamesFallback.deliveredByAddress((status: 200, error: null)),
        isTrue,
      );
      expect(
        NamesFallback.deliveredByAddress((status: 301, error: null)),
        isTrue,
      );
      expect(
        NamesFallback.deliveredByAddress((status: 503, error: null)),
        isFalse,
      );
      expect(
        NamesFallback.deliveredByAddress((status: null, error: 'timeout')),
        isFalse,
      );
    });

    test('the server keeps the mark through storage', () {
      final at = DateTime.utc(2026, 11, 21, 3);
      final back = ServerItem.fromJson(
        _item().copyWith(namesFallbackAt: at).toJson(),
      );
      expect(back.namesFallbackAt, at);
      expect(ServerItem.fromJson(_item().toJson()).namesFallbackAt, isNull);
      expect(back.copyWith(namesFallbackAt: null).namesFallbackAt, isNull);
    });
  });
}
