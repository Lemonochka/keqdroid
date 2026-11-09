import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/connection_entry.dart';
import 'package:keqdroid/services/xray_access_log_parser.dart';
import 'package:keqdroid/services/xray_connection_lines.dart';
import 'package:keqdroid/services/xray_route_decisions.dart';
import 'package:keqdroid/utils/xray_session_log.dart';

// вывод xray 26 на ПК: системный прокси через http-in, socks и TUN
const _coreOutput = '''
2026/11/04 12:00:00.000000 [Warning] core: Xray 26.7.11 started
2026/11/04 12:00:01.000000 [Info] [101] proxy/http: request to Method [CONNECT] Host [www.youtube.com:443] with URL [//www.youtube.com:443]
2026/11/04 12:00:01.001000 [Info] [101] app/dispatcher: sniffed domain: www.youtube.com
2026/11/04 12:00:01.002000 [Info] [101] app/dispatcher: Hit route rule: [proxy-geosite] so taking detour [proxy] for [tcp:www.youtube.com:443]
2026/11/04 12:00:01.002500 [Info] [101] proxy/vless/outbound: tunneling request to tcp:www.youtube.com:443 via 203.0.113.7:443
2026/11/04 12:00:01.003000 from 127.0.0.1:54321 accepted //www.youtube.com:443 [http-in -> proxy]
2026/11/04 12:00:02.000000 [Info] [102] proxy/socks: TCP Connect request to tcp:vk.com:443
2026/11/04 12:00:02.002000 [Info] [102] app/dispatcher: Hit route rule: [direct-domains] so taking detour [direct] for [tcp:vk.com:443]
2026/11/04 12:00:02.003000 from tcp:127.0.0.1:54322 accepted tcp:vk.com:443 [socks-in -> direct]
2026/11/04 12:00:03.000000 [Info] [103] proxy/tun: processing from tcp:172.19.0.1:50123 to tcp:142.250.74.46:443
2026/11/04 12:00:03.001000 [Info] [103] app/dispatcher: sniffed domain: www.google.com
2026/11/04 12:00:03.002000 [Info] [103] app/dispatcher: Hit route rule: [proxy-geosite] so taking detour [proxy] for [tcp:www.google.com:443]
2026/11/04 12:00:03.003000 from tcp:172.19.0.1:50123 accepted tcp:142.250.74.46:443 [tun-in -> proxy]
2026/11/04 12:00:04.000000 [Info] [104] proxy/tun: processing from udp:172.19.0.1:50200 to udp:1.1.1.1:53
2026/11/04 12:00:04.001000 [Info] [104] app/dispatcher: default route for udp:1.1.1.1:53
2026/11/04 12:00:04.002000 from udp:172.19.0.1:50200 accepted udp:1.1.1.1:53 [tun-in >> proxy]
2026/11/04 12:00:05.000000 [Warning] [105] app/dispatcher: non existing outTag: gone
2026/11/04 12:00:09.000000 [Info] [102] app/proxyman/inbound: connection ends > io: read/write on closed pipe
''';

final class _Session {
  final journal = StringBuffer();
  final connectionLines = XrayConnectionLines();
}

// как _appendCoreLine в бэкендах Windows и Linux
_Session _run(String level, [String output = _coreOutput]) {
  final threshold =
      XraySessionLog.raise('{"log":{"loglevel":"$level"}}').threshold;
  final session = _Session();
  for (final line in output.split('\n')) {
    XrayRouteDecisions.observe(line);
    session.connectionLines.add(line);
    if (!XraySessionLog.keep(line, threshold)) continue;
    session.journal.writeln(line);
  }
  return session;
}

List<String> _seen(ConnectionsSnapshot s) => [
      for (final e in s.entries)
        '${e.host} ${e.destIp} ${e.rule} ${e.outbound} ${e.closed}',
    ];

void main() {
  setUp(XrayRouteDecisions.reset);

  group('Соединения на ПК при Warning', () {
    test('видны правило, домен в TUN и закрытие', () {
      final snapshot =
          XrayAccessLogParser.parse(_run('warning').connectionLines.text);

      expect(snapshot.ruleInfoAvailable, isTrue);
      final byHost = {for (final e in snapshot.entries) e.host: e};
      expect(byHost.keys, {
        'www.youtube.com',
        'vk.com',
        'www.google.com',
        '1.1.1.1',
      });
      expect(byHost['www.youtube.com']!.rule, 'proxy-geosite');
      expect(byHost['vk.com']!.rule, 'direct-domains');
      expect(byHost['vk.com']!.closed, isTrue);
      expect(byHost['www.google.com']!.destIp, '142.250.74.46');
      expect(byHost['www.google.com']!.rule, 'proxy-geosite');
      expect(byHost['www.google.com']!.verdict, ConnectionVerdict.proxied);
      expect(XrayAccessLogParser.isDefaultRoute(byHost['1.1.1.1']!.rule),
          isTrue);
    });

    test('экран получает то же, что раньше давал журнал при Info', () {
      final atInfo = XrayAccessLogParser.parse(_run('info').journal.toString());
      final atWarning =
          XrayAccessLogParser.parse(_run('warning').connectionLines.text);
      expect(_seen(atWarning), _seen(atInfo));
    });

    test('видимый журнал остаётся на выбранном уровне', () {
      final journal = _run('warning').journal.toString();
      expect(journal, isNot(contains('[Info]')));
      expect(journal, contains('accepted //www.youtube.com:443'));
      expect(journal, contains('non existing outTag'));
    });

    test('в буфер не попадает лишнее', () {
      final text = _run('warning').connectionLines.text;
      expect(text, isNot(contains('tunneling request')));
      expect(text, isNot(contains('Xray 26.7.11 started')));
      expect(text, isNot(contains('non existing outTag')));
      expect(text, isNot(contains('request to Method')));
    });

    test('шум ядра не вытесняет строки соединений', () {
      final noise = [
        for (var i = 0; i < 5000; i++)
          '2026/11/04 12:00:10.000000 [Debug] transport/internet: noise $i',
        'time="2026-11-04T12:00:11Z" level=info msg="[TCP] 127.0.0.1:1 --> a.b:443 match Match using Proxy"',
      ].join('\n');
      final snapshot = XrayAccessLogParser.parse(
        _run('warning', '$_coreOutput\n$noise').connectionLines.text,
      );
      expect(snapshot.entries.length, 4);
    });

    test('буфер ограничен и держит свежие строки', () {
      final output = [
        for (var i = 0; i < 3000; i++)
          '2026/11/04 12:00:00.000000 from tcp:127.0.0.1:${10000 + i} '
              'accepted tcp:h$i.example:443 [socks-in -> proxy]',
      ].join('\n');
      final text = _run('warning', output).connectionLines.text;
      expect(text.length, lessThanOrEqualTo(64 * 1024));
      expect(text, contains('h2999.example'));
      expect(text, isNot(contains('h0.example')));
    });

    test('новая сессия начинается с пустого буфера', () {
      final lines = _run('warning').connectionLines..clear();
      expect(lines.text, isEmpty);
      lines.add('2026/11/04 12:00:00.000000 from tcp:127.0.0.1:1 accepted '
          'tcp:a.example:443 [socks-in -> proxy]');
      expect(lines.text, contains('a.example'));
    });
  });
}
