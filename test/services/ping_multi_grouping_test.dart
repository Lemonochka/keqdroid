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

// ядро с плохим сервером в пачке не поднимается: натив отдаёт пустой список, бэкенд null
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
  }) async =>
      [
        for (final item in items)
          _answer(item.$1, alive: !_isBad(item.$2)),
      ];
}

/// Кого можно измерить общим конфигом, а кого нельзя.
///
/// Общий конфиг складывает серверы в один документ: у каждого свой инбаунд,
/// свой аутбаунд и свои правила. Сервер, который сам себе конфиг — готовый
/// Clash или Xray от провайдера, цепочка, AmneziaWG — туда не вкладывается:
/// он несёт собственные инбаунды, роутинг и DNS, и попытка его «вложить»
/// молча измерила бы не то. Такие остаются на поштучном пути.
void main() {
  const vless =
      'vless://bfd62637-6d18-49ea-b726-82274f5dda83@a.example.com:443?encryption=none&type=tcp&security=reality&sni=www.nvidia.com&pbk=KlybaLW0-grtjEATyTVFIYoWIaoW-Duxi4lcM54_t2U#a';
  const hysteria = 'hy2://secret@b.example.com:443?sni=b.example.com#b';
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
  const xrayJson = '{"outbounds":[{"protocol":"vless","tag":"proxy"}]}';

  test('обычные ссылки складываются', () {
    expect(PingService.mergeableForMultiPing(vless), isTrue);
    expect(PingService.mergeableForMultiPing(hysteria), isTrue);
  });

  test('сервер, который сам себе конфиг, — нет', () {
    expect(PingService.mergeableForMultiPing(clashYaml), isFalse);
    expect(PingService.mergeableForMultiPing(xrayJson), isFalse);
    expect(PingService.mergeableForMultiPing(awg), isFalse);
  });

  test('мусор не складывается тоже', () {
    // Иначе первая же непонятная строка уронила бы весь общий конфиг, а с ним
    // и замеры двадцати здоровых серверов рядом.
    expect(PingService.mergeableForMultiPing('какая-то строка'), isFalse);
    expect(PingService.mergeableForMultiPing(''), isFalse);
  });

  test('групповой путь включается только там, где его умеют', () {
    // На десктопе процессов не жалко, и общий конфиг там пришлось бы
    // заворачивать в keqrnel, чьи инбаунды принадлежат sing-box.
    expect(PingService.multiPingSupported, isFalse, reason: 'тесты идут на Windows');

    PingService.debugMultiPingSupported = true;
    addTearDown(() => PingService.debugMultiPingSupported = null);
    expect(PingService.multiPingSupported, isTrue);
  });

  test('на десктопе замеров идёт больше, чем на телефоне', () {
    // Цена замера — процесс ядра: 28 МБ у keqrnel, 19 у mihomo (замерено).
    // На ПК шестнадцать таких стоят 450 МБ на несколько секунд, на телефоне
    // столько не удержать — там подписку меряет общий конфиг.
    PlatformBootstrap.debugIsDesktopOverride = true;
    addTearDown(() => PlatformBootstrap.debugIsDesktopOverride = null);
    expect(PingService.urlPingConcurrency, 16);

    PlatformBootstrap.debugIsDesktopOverride = false;
    expect(PingService.urlPingConcurrency, 6);
  });

  test('конфигов в полёте несколько, но немного', () {
    // Ядро с десятком проб стоит 20 МБ против 19 у ядра с одним сервером
    // (замерено): цена — Go-рантайм, а не содержимое конфига, поэтому держать
    // их по очереди незачем. Потолок ставит не память, а экран: результаты
    // батча приезжают разом.
    expect(PingService.multiPingBatches, greaterThan(1));
    expect(
      PingService.multiPingBatches * PingService.multiPingChunk,
      lessThanOrEqualTo(40),
    );
  });

  test('ядро не поднялось — пачку делим, живые соседи плохого сервера живы', () async {
    // Раньше натив отдавал на такой случай список отказов той же длины,
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
    final servers = [for (final id in ['a', 'b', 'bad', 'c']) server(id)];

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
    expect(backend.multiSizes.first, 4, reason: 'сначала пачкой, а не поштучно');
  });

  test('размер чанка не «все разом»', () {
    // Батч падает целиком из-за одного негодного сервера: чем он больше, тем
    // дороже деление пополам, которым мы ищем виноватого.
    expect(PingService.multiPingChunk, lessThanOrEqualTo(25));
    expect(PingService.multiPingChunk, greaterThan(1));
  });
}
