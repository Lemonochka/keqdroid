import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/connection_entry.dart';
import 'package:keqdroid/services/connections_service.dart';

/// Строки — как их пишет xray: forkexec на Android дублирует вывод ядра в файл,
/// добавляя свой префикс `MM-DD HH:MM:SS`, поэтому парсер обязан искать образцы
/// в любом месте строки, а не с её начала.
const _log = '''
08-05 12:34:55 2026/08/05 12:34:55.123456 [Info] app/dispatcher: Hit route rule: [proxy-geosite] so taking detour [proxy] for [tcp:www.youtube.com:443]
08-05 12:34:55 2026/08/05 12:34:55.200000 from 127.0.0.1:53182 accepted tcp:www.youtube.com:443 [socks-in -> proxy]
08-05 12:34:56 2026/08/05 12:34:56.000000 [Info] app/dispatcher: Hit route rule: [direct-domains] so taking detour [direct] for [tcp:vk.com:443]
08-05 12:34:56 2026/08/05 12:34:56.100000 from 127.0.0.1:53190 accepted tcp:vk.com:443 [socks-in -> direct]
08-05 12:34:57 2026/08/05 12:34:57.000000 [Info] app/dispatcher: default route for udp:1.1.1.1:53
08-05 12:34:57 2026/08/05 12:34:57.100000 from 127.0.0.1:53191 accepted udp:1.1.1.1:53 [socks-in >> proxy]
08-05 12:34:58 2026/08/05 12:34:58.100000 from 127.0.0.1:53192 rejected tcp:doubleclick.net:443 [socks-in -> block]
''';

/// Тот же трафик при уровне логов warning: строк роутинга нет вовсе.
const _logWithoutRoutingLines = '''
2026/08/05 12:34:55.200000 from 127.0.0.1:53182 accepted tcp:www.youtube.com:443 [socks-in -> proxy]
2026/08/05 12:34:56.100000 from 127.0.0.1:53190 accepted tcp:vk.com:443 [socks-in -> direct]
''';

ConnectionEntry _byHost(ConnectionsSnapshot s, String host) =>
    s.entries.firstWhere((e) => e.host == host);

void main() {
  group('XrayAccessLogParser', () {
    test('pairs access lines with the routing rule of the same destination', () {
      final snapshot = XrayAccessLogParser.parse(_log);

      expect(snapshot.source, ConnectionsSource.coreLog);
      expect(snapshot.ruleInfoAvailable, isTrue);
      expect(snapshot.entries.length, 4);

      final youtube = _byHost(snapshot, 'www.youtube.com');
      expect(youtube.network, 'tcp');
      expect(youtube.destPort, 443);
      expect(youtube.source, '127.0.0.1:53182');
      expect(youtube.inbound, 'socks-in');
      expect(youtube.outbound, 'proxy');
      expect(youtube.rule, 'proxy-geosite');
      expect(youtube.verdict, ConnectionVerdict.proxied);
      expect(youtube.startedAt?.hour, 12);
      expect(youtube.startedAt?.minute, 34);

      final vk = _byHost(snapshot, 'vk.com');
      expect(vk.rule, 'direct-domains');
      expect(vk.verdict, ConnectionVerdict.direct);
    });

    test('marks catch-all routing separately from a named rule', () {
      final dns = _byHost(XrayAccessLogParser.parse(_log), '1.1.1.1');
      expect(dns.network, 'udp');
      expect(XrayAccessLogParser.isDefaultRoute(dns.rule), isTrue);
      // `>>` в detour означает «роутер правило не выбрал».
      expect(dns.outbound, 'proxy');
    });

    test('rejected connections count as blocked', () {
      final ad = _byHost(XrayAccessLogParser.parse(_log), 'doubleclick.net');
      expect(ad.rejected, isTrue);
      expect(ad.verdict, ConnectionVerdict.blocked);
    });

    test('reports that rule info is missing below log level Info', () {
      final snapshot = XrayAccessLogParser.parse(_logWithoutRoutingLines);
      expect(snapshot.entries.length, 2);
      expect(snapshot.ruleInfoAvailable, isFalse);
      expect(snapshot.entries.every((e) => e.rule.isEmpty), isTrue);
      // Аутбаунд из access-строки берётся и без строк роутинга.
      expect(_byHost(snapshot, 'vk.com').outbound, 'direct');
    });

    test('newest connection comes first', () {
      final entries = XrayAccessLogParser.parse(_log).entries;
      expect(entries.first.host, 'doubleclick.net');
    });

    test('a repeated connection from the same socket is not duplicated', () {
      final doubled = XrayAccessLogParser.parse('$_log$_log');
      expect(doubled.entries.where((e) => e.host == 'vk.com').length, 1);
    });

    test('garbage input yields no entries instead of throwing', () {
      final snapshot = XrayAccessLogParser.parse('not a log at all\n\n???');
      expect(snapshot.entries, isEmpty);
    });
  });
}
