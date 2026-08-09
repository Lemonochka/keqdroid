import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/connection_entry.dart';
import 'package:keqdroid/services/connections_service.dart';

/// Как ядро печатает решения, когда работает встроенным движком за sing-box:
/// своих инбаундов у него нет, access-строк («from … accepted …») тоже, но
/// маршрут оно всё равно выбирает и логирует — и это единственный источник
/// настоящего вердикта, потому что clash_api видит только «отдал движку».
const _engineLog = '''
2026/08/05 22:09:06.100000 [Info] app/dispatcher: Hit route rule: [direct-domains] so taking detour [direct] for [tcp:cloudcdn-m9-5.cdn.yandex.net:443]
2026/08/05 22:09:23.200000 [Info] app/dispatcher: Hit route rule: [proxy-geoip] so taking detour [proxy] for [tcp:149.154.167.41:443]
2026/08/05 22:09:30.300000 [Info] app/dispatcher: taking detour [proxy] for [tcp:music.youtube.com:443]
2026/08/05 22:09:31.400000 [Info] app/dispatcher: default route for tcp:example.org:443
''';

ConnectionEntry _entry(String host, {String network = 'tcp', int port = 443}) =>
    ConnectionEntry(
      id: '$host:$port',
      network: network,
      host: host,
      destPort: port,
      outbound: 'proxy',
    );

void main() {
  group('parseRouteDecisions', () {
    final decisions = XrayAccessLogParser.parseRouteDecisions(_engineLog);

    String key(String host) =>
        XrayAccessLogParser.targetKeyFor('tcp', host, 443);

    test('a tagged rule carries both the tag and the real outbound', () {
      final direct = decisions[key('cloudcdn-m9-5.cdn.yandex.net')]!;
      expect(direct.rule, 'direct-domains');
      expect(direct.outbound, 'direct');

      final proxied = decisions[key('149.154.167.41')]!;
      expect(proxied.rule, 'proxy-geoip');
      expect(proxied.outbound, 'proxy');
    });

    test('an untagged rule still yields the outbound', () {
      final d = decisions[key('music.youtube.com')]!;
      expect(d.rule, isEmpty);
      expect(d.outbound, 'proxy');
    });

    test('catch-all is marked as such', () {
      expect(
        XrayAccessLogParser.isDefaultRoute(decisions[key('example.org')]!.rule),
        isTrue,
      );
    });

    test('no Info lines means no decisions at all', () {
      expect(
        XrayAccessLogParser.parseRouteDecisions(
          '2026/08/05 22:09:06 [Warning] core: something else entirely',
        ),
        isEmpty,
      );
    });
  });

  group('verdict', () {
    test('a connection handed to the engine is not reported as proxied', () {
      // Ровно баг из отчёта: ru-домен уходил в direct внутри ядра, а экран
      // показывал PROXY, потому что sing-box отдал соединение движку.
      final handed = _entry('yandex.ru').withRouting(
        rule: '',
        outbound: 'proxy',
        decidedByCore: true,
      );
      expect(handed.verdict, ConnectionVerdict.viaCore);
      expect(handed.rule, isEmpty);
    });

    test('once the core log is read, the real verdict wins', () {
      final resolved = _entry('yandex.ru').withRouting(
        rule: 'direct-domains',
        outbound: 'direct',
        decidedByCore: false,
      );
      expect(resolved.verdict, ConnectionVerdict.direct);
      expect(resolved.rule, 'direct-domains');
    });

    test('sing-box decisions of its own stay untouched', () {
      expect(_entry('vk.com').verdict, ConnectionVerdict.proxied);
      expect(
        _entry('ads.example').withRouting(
          rule: 'block-domains',
          outbound: 'block',
          decidedByCore: false,
        ).verdict,
        ConnectionVerdict.blocked,
      );
    });

    test('withRouting keeps everything else', () {
      final base = ConnectionEntry(
        id: 'x',
        network: 'tcp',
        host: 'yandex.ru',
        destPort: 443,
        destIp: '5.255.255.70',
        source: '127.0.0.1:50656',
        process: 'firefox.exe',
        inbound: 'http/http-in',
        outbound: 'proxy',
        upload: 10,
        download: 20,
      );
      final next = base.withRouting(
        rule: 'direct-domains',
        outbound: 'direct',
        decidedByCore: false,
      );
      expect(next.process, 'firefox.exe');
      expect(next.source, '127.0.0.1:50656');
      expect(next.destIp, '5.255.255.70');
      expect(next.inbound, 'http/http-in');
      expect(next.upload, 10);
      expect(next.download, 20);
    });
  });
}
