import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/proxy_chain.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// Кто резолвит адрес самого сервера.
///
/// Без `sockopt.domainStrategy` ядро отдаёт домен сервера резолверу своего
/// процесса, а на Android он почти не отвечает: в логе бесконечное
/// «dial tcp: lookup <сервер>: operation was canceled», трафика нет, хотя
/// сервер живой. Голден-фикстуры это не ловят — в них у всех серверов адрес
/// IP-литералом, а на IP правило и не должно срабатывать.
const _domainServer =
    'vless://uuid@nl.example.com:443?security=tls&sni=nl.example.com&type=tcp#NL';
const _ipServer =
    'vless://uuid@198.51.100.10:443?security=tls&sni=nl.example.com&type=tcp#IP';
const _secondHop = 'trojan://pass@de.example.com:8443?sni=de.example.com#DE';

Map<String, dynamic> _outboundByTag(Map<String, dynamic> config, String tag) =>
    (config['outbounds'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((o) => o['tag'] == tag);

Map<String, dynamic>? _sockoptOf(Map<String, dynamic> outbound) {
  final stream = outbound['streamSettings'] as Map<String, dynamic>?;
  return stream?['sockopt'] as Map<String, dynamic>?;
}

Map<String, dynamic> _generate(String link, [AppSettings? settings]) =>
    jsonDecode(
      ConfigGeneratorV2.generateConfig(link, settings ?? const AppSettings()),
    ) as Map<String, dynamic>;

void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  test('домен сервера резолвится встроенным DNS', () {
    final config = _generate(_domainServer);
    expect(_sockoptOf(_outboundByTag(config, 'proxy'))?['domainStrategy'],
        'UseIPv4');
  });

  test('IP-адрес сервера остаётся без стратегии — резолвить нечего', () {
    final config = _generate(_ipServer);
    final sockopt = _sockoptOf(_outboundByTag(config, 'proxy'));
    expect(sockopt?.containsKey('domainStrategy') ?? false, isFalse);
  });

  test('семейство адресов совпадает с queryStrategy', () {
    final config = _generate(
      _domainServer,
      const AppSettings(
        xrayCore: XrayCoreSettings(dnsQueryStrategy: 'UseIP'),
      ),
    );
    expect(
      _sockoptOf(_outboundByTag(config, 'proxy'))?['domainStrategy'],
      'UseIP',
    );
  });

  test('в цепочке стратегия только у входного узла', () {
    final link = ProxyChainConfig(
      name: 'chain',
      hops: const [
        ProxyChainHop(config: _domainServer),
        ProxyChainHop(config: _secondHop),
      ],
    ).encode();
    final config = _generate(link);

    // Входной узел дозванивается сам — ему резолв нужен.
    expect(
      _sockoptOf(_outboundByTag(config, 'chain-0'))?['domainStrategy'],
      'UseIPv4',
    );
    // Выходной идёт уже через предыдущий (dialerProxy), его адрес резолвит
    // удалённый узел: локальная стратегия там только заставляет ждать.
    final exit = _sockoptOf(_outboundByTag(config, 'proxy'));
    expect(exit?['dialerProxy'], 'chain-0');
    expect(exit?.containsKey('domainStrategy') ?? false, isFalse);
  });

  test('DoH идёт первым, системный резолвер — запасным', () {
    final all = ((_generate(_domainServer)['dns'] as Map<String, dynamic>)
        ['servers'] as List).cast<Map<String, dynamic>>();
    final servers = all
        // Записи со своим списком доменов общего резолва не касаются: это
        // bootstrap на адрес сервера и сплит-DNS для Direct-доменов.
        .where((s) => !s.containsKey('domains'))
        .map((s) => s['address'])
        .toList();
    // Через туннель: так все DNS-запросы устройства идут одним постоянным
    // HTTP/2-соединением, а не отдельным TCP до сервера на каждый запрос.
    expect(servers.first, startsWith('https://'));
    // Сеть, где DoH не пускают, иначе осталась бы вообще без резолва.
    expect(servers.last, 'localhost');
  });

  // Адрес сервера — единственное, что НЕЛЬЗЯ резолвить через туннель: чтобы до
  // сервера дозвониться, его адрес уже нужен. Отсюда отдельная запись на
  // системный резолвер со `skipFallback`, иначе NXDOMAIN увёл бы запрос в DoH,
  // а тот — в ещё не поднятый туннель.
  test('адрес сервера резолвится в обход туннеля', () {
    final servers = ((_generate(_domainServer)['dns'] as Map<String, dynamic>)
        ['servers'] as List).cast<Map<String, dynamic>>();
    final bootstrap = servers.first;
    expect(bootstrap['address'], 'localhost');
    expect(bootstrap['skipFallback'], isTrue);
    expect(
      (bootstrap['domains'] as List).single.toString(),
      startsWith('full:'),
    );
  });

  test('пинг резолвит сервер тем же путём, что и подключение', () {
    final ping = jsonDecode(
      ConfigGeneratorV2.generatePingConfig(
        _domainServer,
        const AppSettings(),
        socksPort: 10800,
      ),
    ) as Map<String, dynamic>;

    expect(
      _sockoptOf(_outboundByTag(ping, 'proxy'))?['domainStrategy'],
      'UseIPv4',
    );
    final servers = ((ping['dns'] as Map<String, dynamic>)['servers'] as List)
        .map((s) => s is Map ? s['address'] : s)
        .toList();
    expect(servers.first, startsWith('https+local://'));
  });
}
