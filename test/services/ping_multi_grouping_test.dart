import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/services/ping_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/tunnel/tunnel_backend.dart';
import 'package:keqdroid/tunnel/vpn_backend.dart';

import '../helpers/fake_tunnel_backend.dart';

typedef _Probe = ({
  String id,
  bool success,
  int? latencyMs,
  String error,
  int? httpStatus,
});

const _badIp = '192.0.2.66';

bool _isBad(String config) =>
    config.contains('bad.example.com') || config.contains(_badIp);

// ядро с плохим сервером в пачке не поднимается: нативная часть отдаёт пустой список, бэкенд null
class _OneBadServerBackend extends FakeTunnelBackend {
  final multiSizes = <int>[];

  static _Probe _answer(String id, {required bool alive}) => (
    id: id,
    success: alive,
    latencyMs: alive ? 120 : null,
    error: alive ? '' : 'dead',
    httpStatus: alive ? 204 : null,
  );

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
    multiSizes.add(probes.length);
    if (probes.any((p) => p.$1 == 'bad')) return null;
    return [for (final p in probes) _answer(p.$1, alive: true)];
  }

  @override
  Future<List<_Probe>> xrayUrlTestBatch({
    required List<(String id, String xrayConfig)> items,
    required int socksPort,
    VpnBackend core = VpnBackend.xray,
    String testUrl = 'https://connectivitycheck.gstatic.com/generate_204',
    int timeoutMs = 15000,
    bool keepAlive = true,
  }) async => [
    for (final item in items) _answer(item.$1, alive: !_isBad(item.$2)),
  ];
}

// Кого можно измерить общим конфигом, а кого нельзя.
//
// Генераторы замера выбрасывают входы, DNS и маршруты автора, оставляя только
// выходной узел и его цепочку или группу, поэтому в пачку ложатся и ссылки, и
// готовые конфиги. Не складывается только нераспознанный текст, чтобы одна
// мусорная строка не роняла соседние серверы.
void main() {
  const vless =
      'vless://bfd62637-6d18-49ea-b726-82274f5dda83@a.example.com:443?encryption=none&type=tcp&security=reality&sni=www.nvidia.com&pbk=KlybaLW0-grtjEATyTVFIYoWIaoW-Duxi4lcM54_t2U#a';
  const hysteria = 'hy2://secret@b.example.com:443?sni=b.example.com#b';
  const chain =
      'keqchain://?name=hop&hop=vless%3A%2F%2Fbfd62637-6d18-49ea-b726-82274f5dda83%40a.example.com%3A443%3Fencryption%3Dnone%23a&hop=hy2%3A%2F%2Fsecret%40b.example.com%3A443%23b';
  const awg = '''
[Interface]
PrivateKey = aQ==
Address = 10.0.0.2/32

[Peer]
PublicKey = bQ==
Endpoint = c.example.com:51820
''';
  const clashYaml = '''
proxies:
  - name: node
    type: vless
    server: d.example.com
    port: 443
    uuid: bfd62637-6d18-49ea-b726-82274f5dda83
''';
  const xrayJson =
      '{"outbounds":[{"protocol":"vless","tag":"proxy","settings":{"vnext":[{"address":"e.example.com","port":443,"users":[{"id":"bfd62637-6d18-49ea-b726-82274f5dda83"}]}]}}]}';

  test('ссылки и готовые конфиги складываются в пачку', () {
    expect(PingService.mergeableForMultiPing(vless), isTrue);
    expect(PingService.mergeableForMultiPing(hysteria), isTrue);
    expect(PingService.mergeableForMultiPing(chain), isTrue);
    expect(PingService.mergeableForMultiPing(clashYaml), isTrue);
    expect(PingService.mergeableForMultiPing(xrayJson), isTrue);
    expect(PingService.mergeableForMultiPing(awg), isTrue);
  });

  test('мусор не складывается тоже', () {
    // Иначе первая же непонятная строка уронила бы весь общий конфиг, а с ним
    // и замеры двадцати здоровых серверов рядом.
    expect(PingService.mergeableForMultiPing('какая-то строка'), isFalse);
    expect(PingService.mergeableForMultiPing(''), isFalse);
  });

  test('на ПК пачку тоже меряет одно ядро', () {
    // #18, 13.11.2026: на Windows пинг всех поднимал по ядру на сервер,
    // шестнадцать разом, и у пользователя не ответил ни один, а поштучно все.
    // keqrnel, из-за которого общий конфиг на ПК не годился, с 19.10.2026
    // не собирается: на ПК те же xray и mihomo, что на телефоне.
    expect(PingService.multiPingSupported, isTrue, reason: 'тесты идут на ПК');

    PingService.debugMultiPingSupported = false;
    addTearDown(() => PingService.debugMultiPingSupported = null);
    expect(PingService.multiPingSupported, isFalse);
  });

  test('на десктопе замеров идёт больше, чем на телефоне', () {
    // Цена замера в процессе ядра: 28 МБ у keqrnel, 19 у mihomo (замерено).
    // На ПК шестнадцать таких стоят 450 МБ на несколько секунд, на телефоне
    // столько не удержать: там подписку меряет общий конфиг.
    PlatformBootstrap.debugIsDesktopOverride = true;
    addTearDown(() => PlatformBootstrap.debugIsDesktopOverride = null);
    expect(PingService.urlPingConcurrency, 16);

    PlatformBootstrap.debugIsDesktopOverride = false;
    expect(PingService.urlPingConcurrency, 6);
  });

  test('конфигов в полёте несколько, но немного', () {
    // Ядро с десятком проб стоит 20 МБ против 19 у ядра с одним сервером
    // (замерено): платим за Go-рантайм, а не за содержимое конфига, поэтому держать
    // их по очереди незачем. Потолок ставит не память, а экран: результаты
    // пачки приезжают разом.
    expect(PingService.multiPingBatches, greaterThan(1));
    expect(
      PingService.multiPingBatches * PingService.multiPingChunk,
      lessThanOrEqualTo(40),
    );
  });

  test(
    'ядро не поднялось — пачку делим, живые соседи плохого сервера живы',
    () async {
      // Раньше нативная часть отдавала на такой случай список отказов той же длины,
      // и все десять серверов пачки уходили в красные из-за одного.
      final backend = _OneBadServerBackend();
      PingService.debugMultiPingSupported = true;
      PingService.debugEngine = VpnEngine.withBackend(backend);
      addTearDown(() {
        PingService.debugMultiPingSupported = null;
        PingService.debugEngine = null;
      });
      ServerItem server(String id) => ServerItem(
        id: id,
        config: vless.replaceFirst('a.example.com', '$id.example.com'),
        type: ServerItemType.subscription,
        subscriptionId: 's1',
      );
      final servers = [
        for (final id in ['a', 'b', 'bad', 'c']) server(id),
      ];

      final results = await PingService.pingUrlBatch(
        servers,
        const AppSettings(),
        resolvedIps: {
          'a': '192.0.2.1',
          'b': '192.0.2.2',
          'bad': _badIp,
          'c': '192.0.2.3',
        },
      );

      expect(
        {for (final r in results) r.serverId: r.success},
        {'a': true, 'b': true, 'bad': false, 'c': true},
      );
      expect(
        backend.multiSizes.first,
        4,
        reason: 'сначала пачкой, а не поштучно',
      );
    },
  );

  test('размер чанка не «все разом»', () {
    // Пачка падает целиком из-за одного негодного сервера: чем она больше, тем
    // дороже деление пополам, которым мы ищем виноватого.
    expect(PingService.multiPingChunk, lessThanOrEqualTo(25));
    expect(PingService.multiPingChunk, greaterThan(1));
  });

  test(
    'подписка из готовых Xray JSON пингуется пачкой и делит битый пополам',
    () async {
      final backend = _OneBadServerBackend();
      PingService.debugMultiPingSupported = true;
      PingService.debugEngine = VpnEngine.withBackend(backend);
      addTearDown(() {
        PingService.debugMultiPingSupported = null;
        PingService.debugEngine = null;
      });
      ServerItem jsonServer(String id, String host) => ServerItem(
        id: id,
        config: xrayJson.replaceFirst('e.example.com', host),
        type: ServerItemType.subscription,
        subscriptionId: 'json-sub',
      );
      final servers = [
        jsonServer('j1', 'j1.example.com'),
        jsonServer('j2', 'j2.example.com'),
        jsonServer('bad', 'bad.example.com'),
        jsonServer('j3', 'j3.example.com'),
      ];

      final results = await PingService.pingUrlBatch(
        servers,
        const AppSettings(),
        resolvedIps: {
          'j1': '192.0.2.11',
          'j2': '192.0.2.12',
          'bad': _badIp,
          'j3': '192.0.2.13',
        },
      );

      expect(
        {for (final r in results) r.serverId: r.success},
        {'j1': true, 'j2': true, 'bad': false, 'j3': true},
      );
      expect(backend.multiSizes.first, 4);
    },
  );

  test(
    'Clash с include-all-proxies идёт в одиночный замер, чтобы не затянуть чужие узлы пачки',
    () {
      const includeAllClash = '''
proxies:
  - name: n1
    type: vless
    server: d.example.com
    port: 443
    uuid: bfd62637-6d18-49ea-b726-82274f5dda83
proxy-groups:
  - name: Select
    type: select
    include-all-proxies: true
rules:
  - MATCH,Select
''';
      expect(PingService.mergeableForMultiPing(includeAllClash), isFalse);
    },
  );

  test(
    'балансировщик в готовом JSON пробует лучший выход в первой пачке и добирает запасной во второй без ложного отказа в onResult',
    () async {
      final calls = <List<String>>[];
      final backend = _BalancerProbeBackend(
        aliveOutboundPrefixes: {'proxy-3', 'auto-2'},
        onMultiCall: calls.add,
      );
      PingService.debugMultiPingSupported = true;
      PingService.debugEngine = VpnEngine.withBackend(backend);
      addTearDown(() {
        PingService.debugMultiPingSupported = null;
        PingService.debugEngine = null;
      });

      const penalizedBridgeJson = '''
{
  "routing": {
    "balancers": [
      {
        "tag": "Home_Balancer",
        "selector": ["proxy"],
        "strategy": {"type": "leastLoad", "settings": {"costs": [{"match": "^proxy(-2)?\$", "value": 1000000, "regexp": true}]}},
        "fallbackTag": "proxy"
      }
    ],
    "rules": [{"type": "field", "network": "tcp,udp", "balancerTag": "Home_Balancer"}]
  },
  "outbounds": [
    {"tag": "proxy", "protocol": "vless", "settings": {"vnext": [{"address": "198.51.100.10", "port": 443, "users": [{"id": "bfd62637-6d18-49ea-b726-82274f5dda83"}]}]}},
    {"tag": "proxy-2", "protocol": "vless", "settings": {"vnext": [{"address": "198.51.100.11", "port": 443, "users": [{"id": "bfd62637-6d18-49ea-b726-82274f5dda83"}]}]}},
    {"tag": "proxy-3", "protocol": "vless", "settings": {"vnext": [{"address": "198.51.100.12", "port": 443, "users": [{"id": "bfd62637-6d18-49ea-b726-82274f5dda83"}]}]}}
  ]
}
''';
      const unpenalizedAutoJson = '''
{
  "routing": {
    "balancers": [
      {
        "tag": "Super_Balancer",
        "selector": ["auto"],
        "strategy": {"type": "leastLoad"},
        "fallbackTag": "auto-1"
      }
    ],
    "rules": [{"type": "field", "network": "tcp,udp", "balancerTag": "Super_Balancer"}]
  },
  "outbounds": [
    {"tag": "auto-1", "protocol": "vless", "settings": {"vnext": [{"address": "198.51.100.21", "port": 443, "users": [{"id": "bfd62637-6d18-49ea-b726-82274f5dda83"}]}]}},
    {"tag": "auto-2", "protocol": "vless", "settings": {"vnext": [{"address": "198.51.100.22", "port": 443, "users": [{"id": "bfd62637-6d18-49ea-b726-82274f5dda83"}]}]}},
    {"tag": "auto-3", "protocol": "vless", "settings": {"vnext": [{"address": "198.51.100.23", "port": 443, "users": [{"id": "bfd62637-6d18-49ea-b726-82274f5dda83"}]}]}}
  ]
}
''';

      final emitted = <PingResult>[];
      final results = await PingService.pingUrlBatch(
        [
          ServerItem(
            id: 'home',
            config: penalizedBridgeJson,
            type: ServerItemType.subscription,
            subscriptionId: 's',
          ),
          ServerItem(
            id: 'super',
            config: unpenalizedAutoJson,
            type: ServerItemType.subscription,
            subscriptionId: 's',
          ),
        ],
        const AppSettings(),
        resolvedIps: const {'home': '198.51.100.10', 'super': '198.51.100.21'},
        onResult: emitted.add,
      );

      expect(
        {for (final r in results) r.serverId: r.success},
        {'home': true, 'super': true},
      );
      // onResult вызывается по разу на сервер и без промежуточного false у super
      expect(emitted.map((r) => (r.serverId, r.success)).toList(), [
        ('home', true),
        ('super', true),
      ]);
      // Первая пачка проверила оба сервера, вторая — только запасные выходы super
      expect(calls, [
        ['home', 'super'],
        ['super#1', 'super#2'],
      ]);
    },
  );
}

class _BalancerProbeBackend extends FakeTunnelBackend {
  _BalancerProbeBackend({
    required this.aliveOutboundPrefixes,
    required this.onMultiCall,
  });

  final Set<String> aliveOutboundPrefixes;
  final void Function(List<String> probeIds) onMultiCall;

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
    onMultiCall([for (final p in probes) p.$1]);
    final decoded = jsonDecode(config) as Map<String, dynamic>;
    final inbounds = (decoded['inbounds'] as List).cast<Map<String, dynamic>>();
    final rules = ((decoded['routing'] as Map)['rules'] as List)
        .cast<Map<String, dynamic>>();
    final tagByPort = <int, String>{
      for (final i in inbounds) i['port'] as int: i['tag'] as String,
    };

    final out = <_Probe>[];
    for (final (id, port) in probes) {
      final inTag = tagByPort[port];
      final catchAll = rules.lastWhere(
        (r) =>
            (r['inboundTag'] as List?)?.contains(inTag) == true &&
            r['network'] == 'tcp,udp',
      );
      final outTag = catchAll['outboundTag'] as String;
      final alive = aliveOutboundPrefixes.any(
        (prefix) => RegExp('^${RegExp.escape(prefix)}-\\d+\$').hasMatch(outTag),
      );
      final probe = (
        id: id,
        success: alive,
        latencyMs: alive ? 55 : null,
        error: alive ? '' : 'Timeout',
        httpStatus: alive ? 204 : null,
      );
      onEach?.call(probe);
      out.add(probe);
    }
    return out;
  }
}
