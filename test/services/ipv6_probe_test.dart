import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/tun_settings.dart';
import 'package:keqdroid/services/ping_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/tunnel/tunnel_backend.dart';
import 'package:keqdroid/tunnel/vpn_backend.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

typedef _Probe = ({
  String id,
  bool success,
  int? latencyMs,
  String error,
  int? httpStatus,
});

// отвечает только тем серверам, у которых «есть IPv6», и только на адрес проверки IPv6
class _Ipv6ExitBackend extends FakeTunnelBackend {
  _Ipv6ExitBackend(this.carrying);

  final Set<String> carrying;
  final urls = <String>[];

  @override
  Future<List<_Probe>?> xrayUrlTestMulti({
    required String config,
    required List<(String id, int port)> probes,
    VpnBackend core = VpnBackend.xray,
    String testUrl = 'https://connectivitycheck.gstatic.com/generate_204',
    int timeoutMs = 15000,
    bool keepAlive = true,
    int concurrency = 16,
    UrlTestProgress? onEach,
  }) async {
    urls.add(testUrl);
    return [
      for (final (id, _) in probes)
        (
          id: id,
          success: testUrl == PingService.ipv6ProbeUrl && carrying.contains(id),
          latencyMs: 100,
          error: '',
          httpStatus: 200,
        ),
    ];
  }
}

ServerItem _server(String id, {DateTime? checkedAt, bool? ipv6}) => ServerItem(
  id: id,
  config:
      'vless://00000000-0000-4000-8000-000000000000@192.0.2.${id.codeUnitAt(0) % 200}:443'
      '?type=tcp&security=none#$id',
  type: ServerItemType.manual,
  addedAt: DateTime(2026),
  ipv6CheckedAt: checkedAt,
  ipv6Exit: ipv6,
);

PingResult _ping(String id, {bool ok = true}) => PingResult(
  serverId: id,
  serverName: id,
  success: ok,
  latencyMs: ok ? 90 : null,
);

void main() {
  const viaVpn = AppSettings(tun: TunSettings(ipv6: TunSettings.ipv6Vpn));
  final now = DateTime(2026, 11, 19, 12);

  group('кого проверять', () {
    test('пока IPv6 не пускают через VPN, никого', () {
      for (final mode in [TunSettings.ipv6Close, TunSettings.ipv6Bypass]) {
        expect(
          PingService.dueForIpv6Probe(
            [_server('a')],
            [_ping('a')],
            AppSettings(tun: TunSettings(ipv6: mode)),
            now,
          ),
          isEmpty,
        );
      }
    });

    test(
      'живых, ни разу не проверенных или проверенных больше суток назад',
      () {
        final servers = [
          _server('a'),
          _server('b', checkedAt: now.subtract(const Duration(hours: 2))),
          _server('c', checkedAt: now.subtract(const Duration(hours: 25))),
          _server('d'),
        ];
        final due = PingService.dueForIpv6Probe(
          servers,
          [_ping('a'), _ping('b'), _ping('c'), _ping('d', ok: false)],
          viaVpn,
          now,
        );
        // упавший замер про IPv6 не говорит ничего, его прежний ответ остаётся
        expect([for (final s in due) s.id], ['a', 'c']);
      },
    );
  });

  test(
    'проверка ходит на адрес только с IPv6 и отдаёт ответ по серверу',
    () async {
      final backend = _Ipv6ExitBackend({'a'});
      PingService.debugMultiPingSupported = true;
      PingService.debugEngine = VpnEngine.withBackend(backend);
      addTearDown(() {
        PingService.debugMultiPingSupported = null;
        PingService.debugEngine = null;
      });

      final probed = await PingService.probeIpv6Exits([
        _server('a'),
        _server('b'),
      ], viaVpn);
      expect(probed, {'a': true, 'b': false});
      expect(backend.urls, everyElement(PingService.ipv6ProbeUrl));
    },
  );

  test('адрес проверки по https: http замер сам переделывает в https', () {
    expect(
      PingService.ipv6ProbeUrl,
      startsWith('https://'),
      reason:
          'с http://ipv6.msftconnecttest.com проверка молча отвечала «нет IPv6» '
          'у каждого сервера: https он не держит',
    );
  });

  test('ответ ложится на сервер и переживает запись', () async {
    final storage = await buildStorageService();
    await storage.saveServers([
      _server('a'),
      _server('b'),
      _server('c', ipv6: true),
    ]);

    final out = await storage.applyIpv6Probe({'a': true, 'b': false}, now);
    final byId = {for (final s in out) s.id: s};
    expect(byId['a']!.ipv6Exit, isTrue);
    expect(byId['b']!.ipv6Exit, isFalse);
    expect(byId['a']!.ipv6CheckedAt, now);
    // не проверенный в этот раз сервер хранит прошлый ответ
    expect(byId['c']!.ipv6Exit, isTrue);
    expect(byId['c']!.ipv6CheckedAt, isNull);

    final reread = {for (final s in await storage.getServers()) s.id: s};
    expect(reread['a']!.ipv6Exit, isTrue);
    expect(reread['b']!.ipv6Exit, isFalse);
    expect(reread['a']!.ipv6CheckedAt, now);
  });

  test('сервер без проверки пишется без лишних ключей', () {
    final json = _server('a').toJson();
    expect(json.containsKey('ipv6Exit'), isFalse);
    expect(json.containsKey('ipv6CheckedAt'), isFalse);
    final back = ServerItem.fromJson(
      _server('a', ipv6: false, checkedAt: now).toJson(),
    );
    expect(back.ipv6Exit, isFalse);
    expect(back.ipv6CheckedAt, now);
  });
}
