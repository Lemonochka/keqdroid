import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/connection_entry.dart';
import 'package:keqdroid/services/connections_tracker.dart';

ConnectionEntry _entry({
  required String source,
  String host = 'www.youtube.com',
  int port = 443,
  String network = 'tcp',
  String outbound = 'proxy',
  String rule = 'proxy-geosite',
  String process = '',
  bool closed = false,
  DateTime? startedAt,
}) =>
    ConnectionEntry(
      id: '$source>$network:$host:$port',
      network: network,
      host: host,
      destPort: port,
      source: source,
      process: process,
      inbound: 'socks-in',
      outbound: outbound,
      rule: rule,
      closed: closed,
      startedAt: startedAt,
    );

ConnectionsSnapshot _log(
  List<ConnectionEntry> entries, {
  bool ruleInfoAvailable = true,
}) =>
    ConnectionsSnapshot(
      entries: entries,
      source: ConnectionsSource.coreLog,
      ruleInfoAvailable: ruleInfoAvailable,
    );

void main() {
  final t0 = DateTime(2026, 8, 11, 6, 14);

  group('ConnectionsTracker grouping', () {
    test('collapses connections to the same target into one row', () {
      final tracker = ConnectionsTracker();
      final snapshot = tracker.merge(
        _log([
          _entry(source: '127.0.0.1:53182', startedAt: t0),
          _entry(source: '127.0.0.1:53183', startedAt: t0.add(const Duration(seconds: 1))),
          _entry(source: '127.0.0.1:53184', startedAt: t0.add(const Duration(seconds: 2))),
          _entry(source: '127.0.0.1:53190', host: 'vk.com', outbound: 'direct'),
        ]),
        sessionToken: 'log:',
        now: t0.add(const Duration(seconds: 3)),
      );

      expect(snapshot.entries.length, 2);
      final youtube =
          snapshot.entries.firstWhere((e) => e.host == 'www.youtube.com');
      expect(youtube.count, 3);
      // Время начала — самое раннее из свёрнутых, а не последнее увиденное.
      expect(youtube.startedAt, t0);
      expect(youtube.rule, 'proxy-geosite');
      // Локальный сокет у группы не один — показывать чей-то один нельзя.
      expect(youtube.source, isEmpty);
      expect(snapshot.entries.firstWhere((e) => e.host == 'vk.com').count, 1);
    });

    test('keeps different verdicts and owners apart', () {
      final tracker = ConnectionsTracker();
      final snapshot = tracker.merge(
        _log([
          _entry(source: 'a:1'),
          _entry(source: 'a:2', outbound: 'direct'),
          _entry(source: 'a:3', process: 'org.telegram.messenger'),
        ]),
        sessionToken: 'log:',
        now: t0,
      );
      expect(snapshot.entries.length, 3);
      expect(snapshot.entries.every((e) => e.count == 1), isTrue);
    });

    test('sums byte counters of a group', () {
      final tracker = ConnectionsTracker();
      final snapshot = tracker.merge(
        ConnectionsSnapshot(
          entries: [
            ConnectionEntry(
              id: 'a',
              network: 'tcp',
              host: 'example.com',
              destPort: 443,
              outbound: 'proxy',
              upload: 100,
              download: 900,
            ),
            ConnectionEntry(
              id: 'b',
              network: 'tcp',
              host: 'example.com',
              destPort: 443,
              outbound: 'proxy',
              upload: 20,
              download: 80,
            ),
          ],
          source: ConnectionsSource.coreApi,
        ),
        sessionToken: 'api:9090',
        now: t0,
      );
      expect(snapshot.entries.single.count, 2);
      expect(snapshot.entries.single.upload, 120);
      expect(snapshot.entries.single.download, 980);
    });
  });

  group('ConnectionsTracker holding live connections', () {
    test('keeps a connection whose log lines scrolled out of the tail', () {
      final tracker = ConnectionsTracker();
      tracker.merge(
        _log([_entry(source: '127.0.0.1:53182', startedAt: t0)]),
        sessionToken: 'log:',
        now: t0,
      );

      // Следующий опрос: в хвосте лога соединения уже нет, но ядро не сообщало
      // о его закрытии — значит оно живо, и строка обязана остаться.
      final later = tracker.merge(
        _log(const []),
        sessionToken: 'log:',
        now: t0.add(const Duration(minutes: 2)),
      );
      expect(later.entries.length, 1);
      expect(later.entries.single.closed, isFalse);
      expect(later.entries.single.host, 'www.youtube.com');
    });

    test('drops it once the core reported the closure and the linger passed', () {
      final tracker = ConnectionsTracker(
        closedLinger: const Duration(seconds: 45),
      );
      tracker.merge(
        _log([_entry(source: 'a:1')]),
        sessionToken: 'log:',
        now: t0,
      );
      final closed = tracker.merge(
        _log([_entry(source: 'a:1', closed: true)]),
        sessionToken: 'log:',
        now: t0.add(const Duration(seconds: 5)),
      );
      expect(closed.entries.single.closed, isTrue);

      final gone = tracker.merge(
        // Строка о закрытии всё ещё в хвосте лога — это не повод показывать её
        // вечно: отсчёт идёт от момента закрытия.
        _log([_entry(source: 'a:1', closed: true)]),
        sessionToken: 'log:',
        now: t0.add(const Duration(seconds: 55)),
      );
      expect(gone.entries, isEmpty);
    });

    test('first poll shows live connections, not the whole log history', () {
      final tracker = ConnectionsTracker(
        closedLinger: const Duration(seconds: 45),
      );
      // Так выглядит только что открытый экран: в хвосте лога и живое, и то,
      // что закрылось час назад.
      final snapshot = tracker.merge(
        _log([
          _entry(
            source: 'a:1',
            host: 'ancient.example.com',
            closed: true,
            startedAt: t0.subtract(const Duration(hours: 1)),
          ),
          _entry(
            source: 'a:2',
            host: 'just.example.com',
            closed: true,
            startedAt: t0.subtract(const Duration(seconds: 5)),
          ),
          _entry(source: 'a:3', host: 'live.example.com', startedAt: t0),
        ]),
        sessionToken: 'log:',
        now: t0,
      );

      final hosts = snapshot.entries.map((e) => e.host).toList();
      expect(hosts, containsAll(<String>['live.example.com', 'just.example.com']));
      expect(hosts, isNot(contains('ancient.example.com')));
    });

    test('a connection that closes later is shown even if it lived long', () {
      final tracker = ConnectionsTracker(
        closedLinger: const Duration(seconds: 45),
      );
      // Долгая закачка: началась час назад, живая.
      final started = t0.subtract(const Duration(hours: 1));
      tracker.merge(
        _log([_entry(source: 'a:1', startedAt: started)]),
        sessionToken: 'log:',
        now: t0,
      );
      // Закрылась только сейчас — «давняя» отсечка первого опроса тут не при
      // делах, строка обязана мелькнуть.
      final closed = tracker.merge(
        _log([_entry(source: 'a:1', startedAt: started, closed: true)]),
        sessionToken: 'log:',
        now: t0.add(const Duration(seconds: 2)),
      );
      expect(closed.entries.length, 1);
      expect(closed.entries.single.closed, isTrue);
    });

    test('a group stays alive while at least one of its connections is', () {
      final tracker = ConnectionsTracker();
      final snapshot = tracker.merge(
        _log([
          _entry(source: 'a:1', closed: true),
          _entry(source: 'a:2'),
        ]),
        sessionToken: 'log:',
        now: t0,
      );
      expect(snapshot.entries.single.count, 2);
      expect(snapshot.entries.single.closed, isFalse);
    });

    test('does not pretend to know liveness without Info-level logs', () {
      final tracker = ConnectionsTracker(
        unreportedTtl: const Duration(seconds: 30),
      );
      // Без строк роутинга (уровень логов ниже info) ядро не пишет и
      // «connection ends» — держать соединение «живым» тут нечем.
      tracker.merge(
        _log([_entry(source: 'a:1')], ruleInfoAvailable: false),
        sessionToken: 'log:',
        now: t0,
      );
      final held = tracker.merge(
        _log(const [], ruleInfoAvailable: false),
        sessionToken: 'log:',
        now: t0.add(const Duration(seconds: 20)),
      );
      expect(held.entries.length, 1);

      final gone = tracker.merge(
        _log(const [], ruleInfoAvailable: false),
        sessionToken: 'log:',
        now: t0.add(const Duration(seconds: 31)),
      );
      expect(gone.entries, isEmpty);
    });

    test('drops a connection the log stopped mentioning long ago', () {
      final tracker = ConnectionsTracker(silentTtl: const Duration(minutes: 10));
      tracker.merge(
        _log([_entry(source: 'a:1')]),
        sessionToken: 'log:',
        now: t0,
      );
      final gone = tracker.merge(
        _log(const []),
        sessionToken: 'log:',
        now: t0.add(const Duration(minutes: 11)),
      );
      expect(gone.entries, isEmpty);
    });

    test('carries over the sniffed domain and the resolved app name', () {
      final tracker = ConnectionsTracker();
      tracker.merge(
        _log([
          _entry(
            source: 'a:1',
            host: 'www.youtube.com',
            process: 'com.google.android.youtube',
          ),
        ]),
        sessionToken: 'log:',
        now: t0,
      );
      // Свежий разбор потерял имя владельца (система отдаёт его только для
      // живых сокетов) — однажды выясненное не должно пропадать из строки.
      final next = tracker.merge(
        _log([_entry(source: 'a:1', host: 'www.youtube.com')]),
        sessionToken: 'log:',
        now: t0.add(const Duration(seconds: 2)),
      );
      expect(next.entries.single.process, 'com.google.android.youtube');
    });

    test('holds nothing across sessions', () {
      final tracker = ConnectionsTracker();
      tracker.merge(
        _log([_entry(source: 'a:1')]),
        sessionToken: 'log:',
        now: t0,
      );
      final other = tracker.merge(
        _log(const []),
        sessionToken: 'api:9090',
        now: t0.add(const Duration(seconds: 2)),
      );
      expect(other.entries, isEmpty);
      expect(tracker.trackedCount, 0);
    });

    test('forgets everything when the source goes away', () {
      final tracker = ConnectionsTracker();
      tracker.merge(
        _log([_entry(source: 'a:1')]),
        sessionToken: 'log:',
        now: t0,
      );
      final gone = tracker.merge(
        const ConnectionsSnapshot(
          entries: [],
          source: ConnectionsSource.unavailable,
          note: 'No active core session.',
        ),
        sessionToken: 'unavailable:',
        now: t0.add(const Duration(seconds: 2)),
      );
      expect(gone.entries, isEmpty);
      expect(gone.note, 'No active core session.');
      expect(tracker.trackedCount, 0);
    });

    test('live rows come first and keep their place', () {
      final tracker = ConnectionsTracker();
      tracker.merge(
        _log([
          _entry(source: 'a:1', host: 'old.example.com', startedAt: t0),
          _entry(
            source: 'a:2',
            host: 'new.example.com',
            startedAt: t0.add(const Duration(seconds: 10)),
          ),
        ]),
        sessionToken: 'log:',
        now: t0.add(const Duration(seconds: 10)),
      );
      final snapshot = tracker.merge(
        _log([
          _entry(source: 'a:1', host: 'old.example.com', startedAt: t0),
          _entry(
            source: 'a:2',
            host: 'new.example.com',
            startedAt: t0.add(const Duration(seconds: 10)),
            closed: true,
          ),
        ]),
        sessionToken: 'log:',
        now: t0.add(const Duration(seconds: 12)),
      );
      // Закрытое ушло вниз, живое наверх — при том, что начиналось раньше.
      expect(snapshot.entries.first.host, 'old.example.com');
      expect(snapshot.entries.last.host, 'new.example.com');
      expect(snapshot.entries.last.closed, isTrue);
    });

    test('keeps memory bounded', () {
      final tracker = ConnectionsTracker(maxTracked: 10);
      for (var i = 0; i < 25; i++) {
        tracker.merge(
          _log([_entry(source: 'a:$i', host: 'h$i.example.com')]),
          sessionToken: 'log:',
          now: t0.add(Duration(seconds: i)),
        );
      }
      expect(tracker.trackedCount, lessThanOrEqualTo(10));
    });
  });
}
