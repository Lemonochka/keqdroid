import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/exit_ip_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';

import '../helpers/test_storage.dart';

class _Connected extends VpnStateNotifier {
  @override
  Future<VpnState> build() async => const VpnState(status: VpnStatus.connected);
}

final _server = ServerItem(
  id: 'srv-1',
  type: ServerItemType.manual,
  config:
      'vless://00000000-0000-4000-8000-000000000000@198.51.100.10:443'
      '?type=tcp&security=none#test',
);

/// Флаг выхода в статусе. После повторного входа в приложение на Android
/// первый запрос уходил без пароля локального входа (его подтягивают из
/// сервиса чуть позже) и получал отказ; повтора не было, и флаг не появлялся
/// до следующего подключения.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> container(
    Future<ExitIp?> Function(int port) lookup,
  ) async {
    final storage = await buildStorageService();
    await storage.saveServers([_server]);
    await storage.setActiveServerId(_server.id);
    final c = ProviderContainer(
      overrides: [
        storageProvider.overrideWithValue(storage),
        vpnStateProvider.overrideWith(_Connected.new),
        exitIpLookupProvider.overrideWithValue(lookup),
      ],
    );
    addTearDown(c.dispose);
    c.read(serversProvider);
    await c.read(vpnStateProvider.future);
    return c;
  }

  test(
    'неудачный первый запрос повторяется, и флаг появляется',
    () async {
      var calls = 0;
      final c = await container((_) async {
        calls++;
        return calls == 1
            ? null
            : const ExitIp(ip: '203.0.113.7', countryCode: 'NL');
      });
      final sub = c.listen(exitIpProvider, (_, _) {});
      addTearDown(sub.close);

      final exit = await c.read(exitIpProvider.future);
      expect(calls, 2);
      expect(exit?.countryCode, 'NL');
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'полученный ответ не запрашивается заново, когда шапку пересобрали',
    () async {
      var calls = 0;
      final c = await container((_) async {
        calls++;
        return const ExitIp(ip: '203.0.113.7', countryCode: 'NL');
      });
      // Шапка ушла с экрана и вернулась: подписчиков на миг не было вовсе.
      var sub = c.listen(exitIpProvider, (_, _) {});
      await c.read(exitIpProvider.future);
      sub.close();
      await Future<void>.delayed(Duration.zero);
      sub = c.listen(exitIpProvider, (_, _) {});
      addTearDown(sub.close);

      expect((await c.read(exitIpProvider.future))?.ip, '203.0.113.7');
      expect(calls, 1);
    },
  );

  // смена сервера на ходу не рвёт подключение: спроси выход сразу, ответил бы ещё прежний сервер
  test(
    'пока сервер меняется на ходу, выход не спрашивается, после смены спрашивается заново',
    () async {
      var country = 'PL';
      var calls = 0;
      final c = await container((_) async {
        calls++;
        return ExitIp(ip: '203.0.113.$calls', countryCode: country);
      });
      final sub = c.listen(exitIpProvider, (_, _) {});
      addTearDown(sub.close);
      expect((await c.read(exitIpProvider.future))?.countryCode, 'PL');

      c.read(vpnServerSwitchInProgressProvider.notifier).set(true);
      expect(await c.read(exitIpProvider.future), isNull);
      expect(calls, 1);

      country = 'FI';
      c.read(vpnServerSwitchInProgressProvider.notifier).set(false);
      expect((await c.read(exitIpProvider.future))?.countryCode, 'FI');
      expect(calls, 2);
    },
  );
}
