import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/connection_entry.dart';
import 'package:keqdroid/services/connections_service.dart';

ConnectionsSnapshot _snapshot(List<ConnectionEntry> entries) =>
    ConnectionsSnapshot(
      entries: entries,
      source: ConnectionsSource.coreLog,
      ruleInfoAvailable: true,
    );

void main() {
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
    // Домен в записи появляется от снифера, а система знает соединение по
    // адресу: спросить по домену — значит не найти владельца никогда.
    test('спрашивает по адресу, а не по подсмотренному домену', () async {
      List<Map<String, Object?>>? asked;
      await ConnectionsService.withAppNamesFromSource(
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

      expect(asked!.single['dstIp'], '216.58.198.162');
    });

    // Экран опрашивается по таймеру, а соединение живёт дольше: без кэша
    // система получала бы один и тот же вопрос каждые две секунды.
    test('найденное имя больше у системы не спрашивается', () async {
      final cache = <String, String>{};
      final entry = sourced(source: '10.0.0.2:41234');
      var calls = 0;
      Future<List<String>> resolve(List<Map<String, Object?>> r) async {
        calls++;
        return ['Chrome'];
      }

      await ConnectionsService.withAppNamesFromSource(
        _snapshot([entry]), resolve: resolve, cache: cache);
      final again = await ConnectionsService.withAppNamesFromSource(
        _snapshot([entry]), resolve: resolve, cache: cache);

      expect(calls, 1);
      expect(again.entries.single.process, 'Chrome');
    });
  });
}
