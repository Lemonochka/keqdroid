import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/connection_entry.dart';
import 'package:keqdroid/services/connections_service.dart';

/// Живой лог xray 26.7.11 с Android (сокращён, домены настоящие).
///
/// Главное, что из него видно: домен НИКОГДА не попадает в access-строку. Её
/// назначение инбаунд записывает в момент приёма соединения, а сниффер читает
/// SNI позже — поэтому `accepted tcp:216.58.198.162:443`, хотя строкой выше
/// ядро уже назвало `googleads.g.doubleclick.net`. Связать их можно только
/// через идентификатор сессии в квадратных скобках.
const _log = '''
08-09 22:43:37 2026/08/09 18:43:37.228543 [Warning] core: Xray 26.7.11 started
08-09 22:43:40 2026/08/09 18:43:40.300259 [Info] [2637336328] proxy/socks: TCP Connect request to tcp:8.8.8.8:853
08-09 22:43:40 2026/08/09 18:43:40.300968 [Info] [2637336328] app/dispatcher: Hit route rule: [final] so taking detour [proxy] for [tcp:8.8.8.8:853]
08-09 22:43:40 2026/08/09 18:43:40.301092 from tcp:127.0.0.1:37678 accepted tcp:8.8.8.8:853 [socks-in -> proxy]
08-09 22:43:40 2026/08/09 18:43:40.568948 [Info] [1375174631] proxy/socks: TCP Connect request to tcp:216.58.198.162:443
08-09 22:43:40 2026/08/09 18:43:40.570500 [Info] [1375174631] app/dispatcher: sniffed domain: googleads.g.doubleclick.net
08-09 22:43:40 2026/08/09 18:43:40.570631 [Info] [1375174631] app/dispatcher: Hit route rule: [final] so taking detour [proxy] for [tcp:googleads.g.doubleclick.net:443]
08-09 22:43:40 2026/08/09 18:43:40.570701 from tcp:127.0.0.1:37726 accepted tcp:216.58.198.162:443 [socks-in -> proxy]
08-09 22:43:40 2026/08/09 18:43:40.568675 [Info] [3159036192] proxy/socks: TCP Connect request to tcp:209.85.233.188:5228
08-09 22:43:40 2026/08/09 18:43:40.582661 [Info] [3159036192] app/dispatcher: sniffed domain: mtalk.google.com
08-09 22:43:40 2026/08/09 18:43:40.582817 from tcp:127.0.0.1:37720 accepted tcp:209.85.233.188:5228 [socks-in -> proxy]
08-09 22:43:40 2026/08/09 18:43:40.821747 [Info] [2625866746] proxy/socks: TCP Connect request to tcp:64.233.162.188:5228
08-09 22:43:40 2026/08/09 18:43:40.883573 [Info] [2625866746] app/dispatcher: sniffed domain: mtalk.google.com
08-09 22:43:40 2026/08/09 18:43:40.883733 from tcp:127.0.0.1:37736 accepted tcp:64.233.162.188:5228 [socks-in -> proxy]
08-09 22:43:55 2026/08/09 18:43:55.922023 [Info] [3537878845] proxy/socks: client UDP connection from udp:127.0.0.1:38603
08-09 22:43:55 2026/08/09 18:43:55.922443 [Info] [3537878845] transport/internet/udp: establishing new connection for udp:142.251.154.6:443
08-09 22:43:55 2026/08/09 18:43:55.923503 [Info] [3537878845] app/dispatcher: sniffed domain: s.youtube.com
08-09 22:43:55 2026/08/09 18:43:55.923531 [Info] [3537878845] app/dispatcher: Hit route rule: [final] so taking detour [proxy] for [udp:s.youtube.com:443]
08-09 22:43:55 2026/08/09 18:43:55.923663 from udp:127.0.0.1:38603 accepted udp:142.251.154.6:443 [socks-in -> proxy]
08-09 22:43:55 2026/08/09 18:43:55.785765 from udp:127.0.0.1:37560 accepted udp:172.217.119.4:443 [socks-in -> proxy]
08-09 22:43:55 2026/08/09 18:43:55.785356 [Info] [4191171849] proxy/socks: client UDP connection from udp:127.0.0.1:37560
08-09 22:43:55 2026/08/09 18:43:55.788673 [Info] [4191171849] transport/internet/udp: establishing new connection for udp:172.217.119.4:443
08-09 22:43:55 2026/08/09 18:43:55.788692 [Info] [4191171849] app/dispatcher: sniffed domain: notifications-pa.googleapis.com
08-09 22:45:44 2026/08/09 18:45:44.659648 [Info] [947926533] proxy/socks: client UDP connection from udp:127.0.0.1:55933
08-09 22:45:44 2026/08/09 18:45:44.659734 [Info] [947926533] transport/internet/udp: establishing new connection for udp:216.58.198.182:443
08-09 22:45:44 2026/08/09 18:45:44.659902 [Info] [947926533] app/dispatcher: Hit route rule: [final] so taking detour [proxy] for [udp:216.58.198.182:443]
08-09 22:45:44 2026/08/09 18:45:44.660038 from udp:127.0.0.1:55933 accepted udp:216.58.198.182:443 [socks-in -> proxy]
''';

ConnectionEntry _find(ConnectionsSnapshot snapshot, String target) =>
    snapshot.entries.firstWhere(
      (e) => e.target == target,
      orElse: () => throw StateError(
        'no entry $target in ${snapshot.entries.map((e) => e.target).toList()}',
      ),
    );

void main() {
  group('domains from the core log', () {
    test('TCP: sniffed domain becomes the title, IP moves below', () {
      final snapshot = XrayAccessLogParser.parse(_log);
      final entry = _find(snapshot, 'googleads.g.doubleclick.net:443');

      expect(entry.host, 'googleads.g.doubleclick.net');
      expect(entry.destIp, '216.58.198.162');
      expect(entry.network, 'tcp');
      expect(entry.outbound, 'proxy');
    });

    test('UDP: session is matched by the client address', () {
      final snapshot = XrayAccessLogParser.parse(_log);
      final entry = _find(snapshot, 's.youtube.com:443');

      expect(entry.destIp, '142.251.154.6');
      expect(entry.source, 'udp:127.0.0.1:38603');
    });

    test('order inside the log does not matter', () {
      // Эта access-строка стоит РАНЬШЕ строк своей сессии — в живом логе
      // ядро пишет их из разных горутин и порядок не гарантирован.
      final snapshot = XrayAccessLogParser.parse(_log);
      final entry = _find(snapshot, 'notifications-pa.googleapis.com:443');

      expect(entry.destIp, '172.217.119.4');
    });

    test('same domain on two different IPs resolves both times', () {
      final snapshot = XrayAccessLogParser.parse(_log);
      final ips = snapshot.entries
          .where((e) => e.host == 'mtalk.google.com')
          .map((e) => e.destIp)
          .toSet();

      expect(ips, {'209.85.233.188', '64.233.162.188'});
    });

    test('without a sniffed domain the IP stays the title', () {
      final snapshot = XrayAccessLogParser.parse(_log);
      final dns = _find(snapshot, '8.8.8.8:853');
      final quic = _find(snapshot, '216.58.198.182:443');

      // IP не дублируется второй строкой под самим собой.
      expect(dns.destIp, isEmpty);
      expect(quic.destIp, isEmpty);
    });

    test('catch-all rule tag reads as the default action', () {
      final snapshot = XrayAccessLogParser.parse(_log);
      final entry = _find(snapshot, 'googleads.g.doubleclick.net:443');

      expect(entry.rule, 'final');
      expect(XrayAccessLogParser.isDefaultRoute(entry.rule), isTrue);
      expect(snapshot.ruleInfoAvailable, isTrue);
    });

    test('time comes from the device prefix, not from UTC of the core', () {
      final snapshot = XrayAccessLogParser.parse(_log);
      final entry = _find(snapshot, 'googleads.g.doubleclick.net:443');

      // В строке два времени: 22:43:40 местное (наш forkexec) и 18:43:40 UTC
      // (сам xray, у Go на Android нет базы часовых поясов).
      expect(entry.startedAt, DateTime(2026, 8, 9, 22, 43, 40));
    });

    test('a log without the device prefix still parses', () {
      final withoutPrefix = _log
          .split('\n')
          .map((l) => l.replaceFirst(RegExp(r'^\d{2}-\d{2} \d{2}:\d{2}:\d{2} '), ''))
          .join('\n');
      final snapshot = XrayAccessLogParser.parse(withoutPrefix);
      final entry = _find(snapshot, 'googleads.g.doubleclick.net:443');

      expect(entry.destIp, '216.58.198.162');
      expect(entry.startedAt, DateTime(2026, 8, 9, 18, 43, 40));
    });
  });

  group('parseSessions', () {
    test('collects destination, client, domain and verdict per session', () {
      final sessions = XrayAccessLogParser.parseSessions(_log);
      final trace = sessions['3537878845']!;

      expect(trace.clientKey, 'udp:127.0.0.1:38603');
      expect(trace.destKey, 'udp:142.251.154.6:443');
      expect(trace.domain, 's.youtube.com');
      expect(trace.rule, 'final');
      expect(trace.outbound, 'proxy');
    });

    test('lines without a session id are ignored', () {
      final sessions = XrayAccessLogParser.parseSessions(
        '2026/08/09 18:43:37.212541 [Info] app/dns: DNS: created localhost client\n'
        '2026/08/09 18:43:37.228543 [Warning] core: Xray 26.7.11 started\n',
      );

      expect(sessions, isEmpty);
    });
  });
}
