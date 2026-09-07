import 'dart:convert';

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
      final snapshot = TrafficSplitSource.parseSnapshot('''
{"downloadTotal":1,"uploadTotal":2,"connections":[
  {"id":"a","chains":["proxy"],"download":100,"upload":10},
  {"id":"b","chains":["DIRECT"],"download":50,"upload":5}
]}
''');
      final rows = snapshot!.connections;
      expect(rows, hasLength(2));
      expect(rows[0].id, 'a');
      expect(rows[0].chains, ['proxy']);
      expect(rows[0].download, 100);
      expect(rows[1].chains, ['DIRECT']);
      expect(rows[1].upload, 5);
      // Общие суммы ядра: по ним видно, что ядро с прошлой записи не
      // перезапускалось.
      expect(snapshot.coreDownload, 1);
      expect(snapshot.coreUpload, 2);
    });

    test('соединение без идентификатора пропускаем: свести его не с чем', () {
      final snapshot = TrafficSplitSource.parseSnapshot(
        '{"connections":[{"chains":["proxy"],"download":1}]}',
      );
      expect(snapshot!.connections, isEmpty);
    });

    test('ответ не того вида — null, а не пустая разбивка', () {
      expect(TrafficSplitSource.parseSnapshot('{"foo":1}'), isNull);
      expect(TrafficSplitSource.parseSnapshot('[]'), isNull);
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

      expect(split.vpn.downloadSpeed, 300);
      expect(split.vpn.uploadSpeed, 20);
      expect(split.direct.downloadSpeed, 20);
      expect(split.direct.uploadSpeed, 4);
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
      expect(split.direct.downloadSpeed, 42);
      expect(split.direct.uploadSpeed, 7);
    });

    test('закрывшееся соединение больше не капает', () {
      final tracker = TrafficSplitTracker();
      tracker.add([_c('a', chains: ['proxy'], download: 100)], session: 's1');
      tracker.add([_c('a', chains: ['proxy'], download: 300)], session: 's1');
      final split = tracker.add([], session: 's1');
      expect(split.vpn.downloadSpeed, 0);
      // Объём при этом остаётся: соединение закрылось, а принятое по нему за
      // сессию никуда не делось.
      expect(split.vpn.totalDownload, 200);
    });

    test('счётчик, поехавший назад, не даёт отрицательной скорости', () {
      final tracker = TrafficSplitTracker();
      tracker.add([_c('a', chains: ['proxy'], download: 500)], session: 's1');
      final split = tracker.add(
        [_c('a', chains: ['proxy'], download: 100)],
        session: 's1',
      );
      expect(split.vpn.downloadSpeed, 0);
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

    test('объём копится по каналам за сессию', () {
      final tracker = TrafficSplitTracker();
      tracker.add([
        _c('a', chains: ['proxy'], download: 0),
        _c('b', chains: ['DIRECT'], download: 0),
      ], session: 's1');
      tracker.add([
        _c('a', chains: ['proxy'], download: 300),
        _c('b', chains: ['DIRECT'], download: 40),
      ], session: 's1');
      final split = tracker.add([
        _c('a', chains: ['proxy'], download: 500),
        _c('b', chains: ['DIRECT'], download: 100),
      ], session: 's1');

      expect(split.vpn.totalDownload, 500);
      expect(split.direct.totalDownload, 100);
      // Скорость при этом — только за последний такт.
      expect(split.vpn.downloadSpeed, 200);
      expect(split.direct.downloadSpeed, 60);
    });

    test('пауза опроса не обнуляет накопленный объём', () {
      // Полоса показывает объём за сессию, а не за отрезок между сворачиваниями
      // окна: обнуляясь на каждом возврате из трея, она врала бы куда сильнее,
      // чем недосчитывая скрытый период.
      final tracker = TrafficSplitTracker();
      tracker.add([_c('a', chains: ['proxy'], download: 0)], session: 's1');
      tracker.add([_c('a', chains: ['proxy'], download: 700)], session: 's1');
      tracker.reset();
      final split = tracker.add(
        [_c('a', chains: ['proxy'], download: 900)],
        session: 's1',
      );
      expect(split.vpn.totalDownload, 700);
    });

    test('новая сессия начинает объём заново', () {
      final tracker = TrafficSplitTracker();
      tracker.add([_c('a', chains: ['proxy'], download: 0)], session: 's1');
      tracker.add([_c('a', chains: ['proxy'], download: 700)], session: 's1');
      final split = tracker.add(
        [_c('a', chains: ['proxy'], download: 700)],
        session: 's2',
      );
      expect(split.vpn.totalDownload, 0);
    });

    test('объём копится в обе стороны', () {
      // Прогон отдачи (спидтест) идёт почти целиком вверх: счётчик одного
      // приёма стоял бы на месте при живом трафике, и маршрут выглядел бы
      // мёртвым.
      final tracker = TrafficSplitTracker();
      tracker.add(
        [_c('a', chains: ['DIRECT'], download: 0, upload: 0)],
        session: 's1',
      );
      final split = tracker.add(
        [_c('a', chains: ['DIRECT'], download: 1000, upload: 20000000)],
        session: 's1',
      );
      expect(split.direct.totalDownload, 1000);
      expect(split.direct.totalUpload, 20000000);
      expect(split.direct.total, 20001000);
    });

    test('соединение без маршрута не теряет свой трафик', () {
      // Пока ядро не назначило цепочку, относить трафик некуда. Но и
      // запоминать счётчик нельзя: иначе унесённое за это время потом сойдёт
      // за уже учтённое и не попадёт ни в одну сторону.
      final tracker = TrafficSplitTracker();
      tracker.add([_c('a', chains: [], download: 0)], session: 's1');
      tracker.add([_c('a', chains: [], download: 500)], session: 's1');
      final split = tracker.add(
        [_c('a', chains: ['proxy'], download: 800)],
        session: 's1',
      );
      expect(split.vpn.downloadSpeed, 800);
    });
  });

  group('счёт переживает закрытие приложения', () {
    // Трекер, у которого по туннелю уже прошло 600 байт, а живое соединение
    // «a» стоит на счётчике 700.
    TrafficSplitTracker counted() {
      final tracker = TrafficSplitTracker();
      tracker.add([_c('a', chains: ['proxy'], download: 100)], session: 's1');
      tracker.add([_c('a', chains: ['proxy'], download: 700)], session: 's1');
      return tracker;
    }

    test('объём продолжается с того, на чём закрылись', () {
      final saved = counted().stateFor(coreDownload: 700, coreUpload: 0)!;
      expect(saved.vpnDownload, 600);
      expect(saved.connections['a'], (700, 0));

      final restarted = TrafficSplitTracker()..restore(saved);
      final split = restarted.add(
        [_c('a', chains: ['proxy'], download: 700)],
        session: 's1',
      );
      expect(split.vpn.totalDownload, 600);
    });

    test('унесённое при закрытом приложении попадает в объём', () {
      // Соединение пережило закрытие, и ядро всё это время считало по нему
      // само: 5000 байт между 700 и 5700 прошли, пока смотреть было некому.
      final saved = counted().stateFor(coreDownload: 700, coreUpload: 0)!;
      final restarted = TrafficSplitTracker()..restore(saved);
      final split = restarted.add(
        [_c('a', chains: ['proxy'], download: 5700)],
        session: 's1',
      );
      expect(split.vpn.totalDownload, 5600);
    });

    test('но не в скорость: это часы, а не один такт', () {
      final saved = counted().stateFor(coreDownload: 700, coreUpload: 0)!;
      final restarted = TrafficSplitTracker()..restore(saved);
      final first = restarted.add(
        [_c('a', chains: ['proxy'], download: 5700)],
        session: 's1',
      );
      expect(first.vpn.downloadSpeed, 0);
      // А следующий такт — уже настоящая секунда.
      final second = restarted.add(
        [_c('a', chains: ['proxy'], download: 5900)],
        session: 's1',
      );
      expect(second.vpn.downloadSpeed, 200);
    });

    test('появившееся при закрытом приложении считается целиком', () {
      final saved = counted().stateFor(coreDownload: 700, coreUpload: 0)!;
      final restarted = TrafficSplitTracker()..restore(saved);
      final split = restarted.add([
        _c('a', chains: ['proxy'], download: 700),
        _c('b', chains: ['DIRECT'], download: 42, upload: 7),
      ], session: 's1');
      expect(split.direct.total, 49);
    });

    test('до первой сессии писать нечего', () {
      final tracker = TrafficSplitTracker();
      expect(tracker.stateFor(coreDownload: 0, coreUpload: 0), isNull);
    });

    test('чужая сессия не подхватывается', () {
      final saved = counted().stateFor(coreDownload: 700, coreUpload: 30)!;
      expect(
        saved.belongsTo(session: 's1', coreDownload: 900, coreUpload: 40),
        isTrue,
      );
      expect(
        saved.belongsTo(session: 's2', coreDownload: 900, coreUpload: 40),
        isFalse,
      );
    });

    test('перезапущенное ядро видно по его собственным суммам', () {
      // Реконнект из плитки поднимает ядро на том же конфиге: порт и токен те
      // же, метка сессии совпадает. Но свои общие суммы новое ядро начинает с
      // нуля, и цифра меньше записанной означает, что счёт остался от прошлой
      // жизни ядра.
      final saved = counted().stateFor(coreDownload: 700, coreUpload: 30)!;
      expect(
        saved.belongsTo(session: 's1', coreDownload: 12, coreUpload: 0),
        isFalse,
      );
    });

    test('запись читается обратно ровно такой же', () {
      final saved = counted().stateFor(coreDownload: 700, coreUpload: 30)!;
      final back = TrafficSplitState.fromJson(
        jsonDecode(jsonEncode(saved.toJson())),
      );
      expect(back, isNotNull);
      expect(back!.session, 's1');
      expect(back.coreDownload, 700);
      expect(back.coreUpload, 30);
      expect(back.vpnDownload, 600);
      expect(back.connections, {'a': (700, 0)});
    });

    test('порванная запись — как будто её нет', () {
      // Файл пишется на живом туннеле, и процесс убивают в любой момент:
      // обрезанная или чужая запись не должна ронять разбор.
      expect(TrafficSplitState.fromJson('не json вовсе'), isNull);
      expect(TrafficSplitState.fromJson(jsonDecode('{"v":1}')), isNull);
      expect(
        TrafficSplitState.fromJson(jsonDecode('{"v":1,"session":"s1"}')),
        isNull,
      );
      expect(
        TrafficSplitState.fromJson(jsonDecode(
          '{"v":1,"session":"s1","core":[1,2],"vpn":[1,2],"direct":[1,2],'
          '"conns":{"a":[1]}}',
        )),
        isNull,
      );
      // Формат сменится — старую запись читать нечем, счёт начнётся заново.
      expect(
        TrafficSplitState.fromJson(jsonDecode(
          '{"v":2,"session":"s1","core":[1,2],"vpn":[1,2],"direct":[1,2],'
          '"conns":{}}',
        )),
        isNull,
      );
    });
  });
}
