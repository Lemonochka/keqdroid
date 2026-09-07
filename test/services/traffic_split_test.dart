import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/traffic_split.dart';
import 'package:keqdroid/services/traffic_split_service.dart';

ConnectionTraffic _c(
  String id, {
  required List<String> chains,
  int download = 0,
  int upload = 0,
}) =>
    ConnectionTraffic(
      id: id,
      chains: chains,
      download: download,
      upload: upload,
    );

void main() {
  group('куда ушло соединение', () {
    test('одиночный аутбаунд', () {
      expect(channelOfChains(['proxy']), TrafficChannel.vpn);
      expect(channelOfChains(['DIRECT']), TrafficChannel.direct);
      expect(channelOfChains(['REJECT']), TrafficChannel.blocked);
      expect(channelOfChains(['REJECT-DROP']), TrafficChannel.blocked);
    });

    test('регистр не важен: ядра пишут тег по-разному', () {
      expect(channelOfChains(['direct']), TrafficChannel.direct);
      expect(channelOfChains([' Direct ']), TrafficChannel.direct);
    });

    test('в цепочке с группой ищем по всем звеньям', () {
      // Пользовательский yaml вправе завести группы, и тогда рядом с DIRECT
      // стоит имя группы — с какой стороны, зависит от версии ядра.
      expect(channelOfChains(['MyGroup', 'DIRECT']), TrafficChannel.direct);
      expect(channelOfChains(['DIRECT', 'MyGroup']), TrafficChannel.direct);
      expect(channelOfChains(['MyGroup', 'node-1']), TrafficChannel.vpn);
    });

    test('пустая цепочка — ядро ещё не решило', () {
      expect(channelOfChains([]), TrafficChannel.unknown);
    });
  });

  group('разбор ответа /connections', () {
    test('счётчики и цепочки достаются из полей ядра', () {
      final rows = TrafficSplitSource.parseConnections('''
{"downloadTotal":1,"uploadTotal":2,"connections":[
  {"id":"a","chains":["proxy"],"download":100,"upload":10},
  {"id":"b","chains":["DIRECT"],"download":50,"upload":5}
]}
''');
      expect(rows, hasLength(2));
      expect(rows![0].id, 'a');
      expect(rows[0].chains, ['proxy']);
      expect(rows[0].download, 100);
      expect(rows[1].chains, ['DIRECT']);
      expect(rows[1].upload, 5);
    });

    test('соединение без идентификатора пропускаем: свести его не с чем', () {
      final rows = TrafficSplitSource.parseConnections(
        '{"connections":[{"chains":["proxy"],"download":1}]}',
      );
      expect(rows, isEmpty);
    });

    test('ответ не того вида — null, а не пустая разбивка', () {
      expect(TrafficSplitSource.parseConnections('{"foo":1}'), isNull);
      expect(TrafficSplitSource.parseConnections('[]'), isNull);
    });
  });

  group('счётчики соединений в скорость', () {
    test('первый снимок только отмечает базу', () {
      final tracker = TrafficSplitTracker();
      // Соединение живёт с прошлого часа: приняв его счётчик за разницу,
      // полоса показала бы весь скачанный за сессию гигабайт как скорость.
      final split = tracker.add(
        [_c('a', chains: ['proxy'], download: 1000000)],
        session: 's1',
      );
      expect(split, TrafficSplit.zero);
    });

    test('разница раскладывается по каналам', () {
      final tracker = TrafficSplitTracker();
      tracker.add([
        _c('a', chains: ['proxy'], download: 100, upload: 10),
        _c('b', chains: ['DIRECT'], download: 50, upload: 5),
      ], session: 's1');

      final split = tracker.add([
        _c('a', chains: ['proxy'], download: 400, upload: 30),
        _c('b', chains: ['DIRECT'], download: 70, upload: 9),
      ], session: 's1');

      expect(split.vpnDownload, 300);
      expect(split.vpnUpload, 20);
      expect(split.directDownload, 20);
      expect(split.directUpload, 4);
    });

    test('родившееся между опросами считается целиком', () {
      // Короткий запрос живёт меньше секунды: не засчитав его весь, разбивка
      // не увидела бы вообще ничего из мелкого трафика.
      final tracker = TrafficSplitTracker();
      tracker.add([], session: 's1');
      final split = tracker.add(
        [_c('new', chains: ['DIRECT'], download: 42, upload: 7)],
        session: 's1',
      );
      expect(split.directDownload, 42);
      expect(split.directUpload, 7);
    });

    test('закрывшееся соединение больше не капает', () {
      final tracker = TrafficSplitTracker();
      tracker.add([_c('a', chains: ['proxy'], download: 100)], session: 's1');
      tracker.add([_c('a', chains: ['proxy'], download: 300)], session: 's1');
      final split = tracker.add([], session: 's1');
      expect(split, TrafficSplit.zero);
    });

    test('счётчик, поехавший назад, не даёт отрицательной скорости', () {
      final tracker = TrafficSplitTracker();
      tracker.add([_c('a', chains: ['proxy'], download: 500)], session: 's1');
      final split = tracker.add(
        [_c('a', chains: ['proxy'], download: 100)],
        session: 's1',
      );
      expect(split.vpnDownload, 0);
    });

    test('заблокированное и нерешённое не идут ни в одну сторону', () {
      final tracker = TrafficSplitTracker();
      tracker.add([
        _c('r', chains: ['REJECT'], download: 0),
        _c('u', chains: [], download: 0),
      ], session: 's1');
      final split = tracker.add([
        _c('r', chains: ['REJECT'], download: 900),
        _c('u', chains: [], download: 900),
      ], session: 's1');
      expect(split, TrafficSplit.zero);
    });

    test('другая сессия ядра — счётчики заново', () {
      // Идентификаторы соединений у новой сессии свои, и разница со старыми
      // была бы разницей между несвязанными числами.
      final tracker = TrafficSplitTracker();
      tracker.add([_c('a', chains: ['proxy'], download: 100)], session: 's1');
      final split = tracker.add(
        [_c('a', chains: ['proxy'], download: 100000)],
        session: 's2',
      );
      expect(split, TrafficSplit.zero);
    });

    test('после паузы опроса база берётся заново', () {
      // Иначе первая разница после часа в трее схлопнула бы весь скрытый
      // период в одну секунду.
      final tracker = TrafficSplitTracker();
      tracker.add([_c('a', chains: ['proxy'], download: 100)], session: 's1');
      tracker.reset();
      final split = tracker.add(
        [_c('a', chains: ['proxy'], download: 999999)],
        session: 's1',
      );
      expect(split, TrafficSplit.zero);
    });
  });
}
