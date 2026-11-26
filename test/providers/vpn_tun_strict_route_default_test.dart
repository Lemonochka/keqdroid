import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/vpn_engine.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

class _Backend extends FakeTunnelBackend {
  VpnState current = VpnState.disconnected;
  TunnelSessionRequest? session;

  @override
  Future<VpnState> getCurrentState() async => current;

  @override
  Future<void> startSession(TunnelSessionRequest request) async {
    session = request;
    current = VpnState(status: VpnStatus.connected, activeMode: request.mode);
  }

  @override
  Future<void> stopSession() async {
    current = VpnState.disconnected;
  }
}

final _server = ServerItem(
  id: 'srv-1',
  type: ServerItemType.manual,
  config:
      'vless://00000000-0000-4000-8000-000000000000@198.51.100.10:443'
      '?type=tcp&security=tls&sni=example.com#test',
);

Map<String, dynamic> _xrayTunSettings(String xrayConfig) {
  final inbounds = (jsonDecode(xrayConfig) as Map)['inbounds'] as List;
  final tun = inbounds.cast<Map<String, dynamic>>().firstWhere(
    (i) => i['tag'] == 'tun-in',
  );
  return (tun['settings'] as Map).cast<String, dynamic>();
}

Map<String, dynamic> _mihomoTunSettings(String mihomoConfig) =>
    ((jsonDecode(mihomoConfig) as Map)['tun'] as Map).cast<String, dynamic>();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'по умолчанию в TUN строгая маршрутизация включена на обоих ядрах',
    () async {
      if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;

      final backend = _Backend();
      final storage = await buildStorageService();
      await storage.saveServers([_server]);
      await storage.setActiveServerId(_server.id);
      await storage.saveSettings(
        const AppSettings(connectionMode: 'tun', vpnCore: 'xray'),
      );

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
      if (Platform.isWindows) {
        expect(
          _xrayTunSettings(
            backend.session!.xrayConfig,
          )['autoSystemWfpBlockLeak'],
          ['dns', 'misconfigtun'],
        );
      }

      await container.read(vpnStateProvider.notifier).disconnect();
      await storage.saveSettings(
        const AppSettings(connectionMode: 'tun', vpnCore: 'mihomo'),
      );
      await container.read(vpnStateProvider.notifier).connect();
      expect(
        _mihomoTunSettings(backend.session!.mihomoConfig!)['strict-route'],
        isTrue,
      );
    },
  );

  test(
    'прежнее значение auto с диска включает строгую маршрутизацию, а off выключает',
    () async {
      if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;

      final backend = _Backend();
      final storage = await buildStorageService(
        initialValues: {
          'keqdis_settings': jsonEncode({
            'connectionMode': 'tun',
            'vpnCore': 'mihomo',
            'tun': {'strictRoute': 'auto'},
          }),
        },
      );
      await storage.saveServers([_server]);
      await storage.setActiveServerId(_server.id);

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
      expect(
        _mihomoTunSettings(backend.session!.mihomoConfig!)['strict-route'],
        isTrue,
      );

      await container.read(vpnStateProvider.notifier).disconnect();
      await storage.saveSettings(
        AppSettings.fromJson(const {
          'connectionMode': 'tun',
          'vpnCore': 'mihomo',
          'tun': {'strictRoute': 'off'},
        }),
      );
      await container.read(vpnStateProvider.notifier).connect();
      expect(
        _mihomoTunSettings(
          backend.session!.mihomoConfig!,
        ).containsKey('strict-route'),
        isFalse,
      );
    },
  );
}
