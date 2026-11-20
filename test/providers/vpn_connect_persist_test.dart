import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/routing_rule.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/vpn_engine.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

/// Что connect() пишет на диск, когда по ходу подключения меняет настройку.
///
/// Внутри connect() списки маршрутизации уже в виде для ядра: структурные
/// правила сложены в текстовые поля, неизвестные geo-коды выброшены. Записать
/// этот вид в настройки значило навсегда приклеить правила к спискам — после
/// этого выключенное правило всё равно работало, а его значения на каждом
/// подключении дописывались в поле ещё раз.
///
/// Сохраняют по ходу подключения две ветки: автостарт без прав на Windows
/// (TUN → прокси) и первый вход в режим прокси на Android (логин и пароль).
/// Ветка Android на этой машине не исполняется, но пишет через ту же функцию.
class _Backend extends FakeTunnelBackend {
  VpnState current = VpnState.disconnected;

  @override
  Future<VpnState> getCurrentState() async => current;

  /// Права администратора не дали — автостарт уходит в прокси.
  @override
  Future<bool> requestTunnelPermission() async => false;

  @override
  Future<void> startSession(TunnelSessionRequest request) async {
    current = const VpnState(status: VpnStatus.connected);
  }
}

final _server = ServerItem(
  id: 'srv-1',
  type: ServerItemType.manual,
  config:
      'vless://00000000-0000-4000-8000-000000000000@198.51.100.10:443'
      '?type=tcp&security=none#test',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'автостарт без прав сохраняет режим прокси, а списки — как их ввели',
    () async {
      final storage = await buildStorageService();
      await storage.saveServers([_server]);
      await storage.setActiveServerId(_server.id);
      await storage.saveSettings(
        AppSettings(
          connectionMode: ConnectionMode.tun.storageValue,
          directRules: 'vk.com',
          blockedRules: 'doubleclick.net',
        ),
      );
      await storage.saveRules(const [
        RoutingRule(
          id: 'r1',
          name: 'my rule',
          type: RuleType.domain,
          values: ['rule.example'],
          action: RuleAction.direct,
        ),
      ]);

      final container = ProviderContainer(
        overrides: [
          storageProvider.overrideWithValue(storage),
          vpnEngineProvider.overrideWithValue(
            VpnEngine.withBackend(_Backend()),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(serversProvider);
      await container.read(vpnStateProvider.future);

      await container
          .read(vpnStateProvider.notifier)
          .connect(autostartTunFallback: true);

      final saved = await storage.getSettings();
      expect(saved.connectionMode, ConnectionMode.proxy.storageValue);
      expect(
        saved.directRules,
        'vk.com',
        reason: 'структурное правило осталось правилом, а не записью поля',
      );
      expect(saved.blockedRules, 'doubleclick.net');
      expect(
        container.read(settingsNotifierProvider).value?.directRules,
        'vk.com',
        reason: 'экран маршрутизации показывает то же, что на диске',
      );
    },
    skip: Platform.isWindows ? false : 'ветка автостарта только на Windows',
  );
}
