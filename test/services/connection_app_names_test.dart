import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/connection_entry.dart';
import 'package:keqdroid/services/connections_service.dart';

/// Лог tun2socks с нашим префиксом из forkexec.c. Формат самой строки у
/// tun2socks свой и от версии к версии меняется, поэтому парсер цепляется
/// только за пару адресов.
const _tun2socksLog = '''
08-10 09:12:01 time="2026-08-10T09:12:01+04:00" level=info msg="[TCP] 10.0.0.2:41234 <-> 216.58.198.162:443"
08-10 09:12:01 time="2026-08-10T09:12:01+04:00" level=info msg="[UDP] 10.0.0.2:55600 <-> 8.8.8.8:53"
08-10 09:12:02 time="2026-08-10T09:12:02+04:00" level=warning msg="[TCP] dial 1.2.3.4:443: i/o timeout"
08-10 09:12:03 time="2026-08-10T09:12:03+04:00" level=info msg="[TCP] 10.0.0.2:41500 <-> [2606:4700:4700::1111]:443"
''';

ConnectionEntry _entry({
  required String host,
  String destIp = '',
  String network = 'tcp',
  int port = 443,
  bool closed = false,
}) =>
    ConnectionEntry(
      id: '$network:$host:$port',
      network: network,
      host: host,
      destPort: port,
      destIp: destIp,
      closed: closed,
    );

ConnectionsSnapshot _snapshot(List<ConnectionEntry> entries) =>
    ConnectionsSnapshot(
      entries: entries,
      source: ConnectionsSource.coreLog,
      ruleInfoAvailable: true,
    );

void main() {
  group('Tun2SocksLogParser', () {
    test('reads the app side of each connection', () {
      final peers = Tun2SocksLogParser.parse(_tun2socksLog);

      final tcp = peers[Tun2SocksLogParser.keyFor('tcp', '216.58.198.162', 443)];
      expect(tcp?.ip, '10.0.0.2');
      expect(tcp?.port, 41234);

      final udp = peers[Tun2SocksLogParser.keyFor('udp', '8.8.8.8', 53)];
      expect(udp?.ip, '10.0.0.2');
      expect(udp?.port, 55600);
    });

    test('keeps IPv6 destinations in one piece', () {
      final peers = Tun2SocksLogParser.parse(_tun2socksLog);
      final v6 = peers[Tun2SocksLogParser.keyFor(
        'tcp',
        '[2606:4700:4700::1111]',
        443,
      )];

      expect(v6?.port, 41500);
    });

    test('lines that are not a connection are ignored', () {
      final peers = Tun2SocksLogParser.parse(_tun2socksLog);
      // `[TCP] dial …: i/o timeout` — ошибка, а не пара адресов.
      expect(peers.length, 3);
    });
  });

  group('withAppNames', () {
    test('asks about the IP, not the sniffed domain', () async {
      List<Map<String, Object?>>? asked;
      final result = await ConnectionsService.withAppNames(
        _snapshot([
          _entry(host: 'googleads.g.doubleclick.net', destIp: '216.58.198.162'),
        ]),
        peers: Tun2SocksLogParser.parse(_tun2socksLog),
        resolve: (requests) async {
          asked = requests;
          return ['Chrome'];
        },
      );

      expect(asked, [
        {
          'protocol': 'tcp',
          'srcIp': '10.0.0.2',
          'srcPort': 41234,
          'dstIp': '216.58.198.162',
          'dstPort': 443,
        }
      ]);
      expect(result.entries.single.process, 'Chrome');
    });

    test('closed connections are not asked about', () async {
      var called = false;
      final result = await ConnectionsService.withAppNames(
        _snapshot([
          _entry(host: '216.58.198.162', closed: true),
          _entry(host: '8.8.8.8', network: 'udp', port: 53),
        ]),
        peers: Tun2SocksLogParser.parse(_tun2socksLog),
        resolve: (requests) async {
          called = true;
          // Система ищет соединение в живой таблице сокетов, закрытого там нет.
          expect(requests.single['dstIp'], '8.8.8.8');
          return ['DNS Resolver'];
        },
      );

      expect(called, isTrue);
      expect(result.entries[0].process, isEmpty);
      expect(result.entries[1].process, 'DNS Resolver');
    });

    test('an unresolved name leaves the entry alone', () async {
      final result = await ConnectionsService.withAppNames(
        _snapshot([_entry(host: '216.58.198.162')]),
        peers: Tun2SocksLogParser.parse(_tun2socksLog),
        resolve: (_) async => [''],
      );

      expect(result.entries.single.process, isEmpty);
      expect(result.entries.single.host, '216.58.198.162');
    });

    test('without a tun2socks log nothing is asked, and the UI is told why',
        () async {
      var called = false;
      final snapshot = _snapshot([_entry(host: '216.58.198.162')]);
      final result = await ConnectionsService.withAppNames(
        snapshot,
        peers: const {},
        resolve: (_) async {
          called = true;
          return [''];
        },
      );

      expect(called, isFalse);
      expect(result.entries, snapshot.entries);
      // Экран покажет подсказку про переподключение вместо пустой колонки.
      expect(result.appNamesAvailable, isFalse);
    });

    test('a known name is reused without asking the system again', () async {
      final cache = <String, String>{};
      var calls = 0;
      Future<ConnectionsSnapshot> run() => ConnectionsService.withAppNames(
            _snapshot([_entry(host: '216.58.198.162')]),
            peers: Tun2SocksLogParser.parse(_tun2socksLog),
            resolve: (_) async {
              calls++;
              return ['Chrome'];
            },
            cache: cache,
          );

      expect((await run()).entries.single.process, 'Chrome');
      // Экран опрашивается по таймеру — второй проход не должен снова
      // дёргать систему по каждому соединению.
      expect((await run()).entries.single.process, 'Chrome');
      expect(calls, 1);
    });

    test('a closed connection still shows the name found earlier', () async {
      final cache = <String, String>{};
      await ConnectionsService.withAppNames(
        _snapshot([_entry(host: '216.58.198.162')]),
        peers: Tun2SocksLogParser.parse(_tun2socksLog),
        resolve: (_) async => ['Chrome'],
        cache: cache,
      );

      // То же соединение, но уже закрытое: система про него больше не знает,
      // а показать, кто это был, всё ещё есть чем.
      final result = await ConnectionsService.withAppNames(
        _snapshot([_entry(host: '216.58.198.162', closed: true)]),
        peers: Tun2SocksLogParser.parse(_tun2socksLog),
        resolve: (_) async => throw StateError('should not be asked'),
        cache: cache,
      );

      expect(result.entries.single.process, 'Chrome');
    });

    test('a log with connections means names are available', () async {
      final result = await ConnectionsService.withAppNames(
        _snapshot([_entry(host: '216.58.198.162')]),
        peers: Tun2SocksLogParser.parse(_tun2socksLog),
        resolve: (_) async => ['Chrome'],
      );

      expect(result.appNamesAvailable, isTrue);
    });

    test('destinations missing from the log keep their place', () async {
      final result = await ConnectionsService.withAppNames(
        _snapshot([
          _entry(host: '1.1.1.1'),
          _entry(host: '216.58.198.162'),
        ]),
        peers: Tun2SocksLogParser.parse(_tun2socksLog),
        resolve: (requests) async {
          expect(requests, hasLength(1));
          return ['Chrome'];
        },
      );

      expect(result.entries[0].process, isEmpty);
      expect(result.entries[1].process, 'Chrome');
    });
  });

  // Когда туннелем владеет само ядро, исходный сокет приложения приезжает в
  // ответе его API — лог tun2socks (а с ним и требование дебаг-режима) не нужен.
  group('withAppNamesFromSource', () {
    ConnectionEntry sourced({
      required String source,
      String host = '216.58.198.162',
      String destIp = '',
      bool closed = false,
    }) =>
        ConnectionEntry(
          id: 'tcp:$host:443:$source',
          network: 'tcp',
          host: host,
          destPort: 443,
          destIp: destIp,
          source: source,
          closed: closed,
        );

    test('спрашивает по сокету из самой записи', () async {
      List<Map<String, Object?>>? asked;
      final result = await ConnectionsService.withAppNamesFromSource(
        _snapshot([
          sourced(
            source: '10.0.0.2:41234',
            host: 'googleads.g.doubleclick.net',
            destIp: '216.58.198.162',
          ),
        ]),
        resolve: (requests) async {
          asked = requests;
          return ['Chrome'];
        },
      );

      expect(asked, [
        {
          'protocol': 'tcp',
          'srcIp': '10.0.0.2',
          'srcPort': 41234,
          'dstIp': '216.58.198.162',
          'dstPort': 443,
        }
      ]);
      expect(result.entries.single.process, 'Chrome');
    });

    test('закрытые не спрашиваем — их уже нет в таблице сокетов', () async {
      var called = false;
      final result = await ConnectionsService.withAppNamesFromSource(
        _snapshot([sourced(source: '10.0.0.2:41234', closed: true)]),
        resolve: (_) async {
          called = true;
          return const [];
        },
      );

      expect(called, isFalse);
      expect(result.entries.single.process, isEmpty);
    });

    // Без сокета спрашивать нечем, и это надо СКАЗАТЬ: пустая колонка иначе
    // читается как «ни у одного соединения нет владельца».
    test('без исходного сокета колонка помечается недоступной', () async {
      final result = await ConnectionsService.withAppNamesFromSource(
        _snapshot([sourced(source: '')]),
        resolve: (_) async => const [],
      );

      expect(result.appNamesAvailable, isFalse);
    });
  });
}
