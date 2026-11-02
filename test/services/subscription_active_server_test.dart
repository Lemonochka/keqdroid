import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/services/auto_select_home.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:keqdroid/services/subscription_service.dart';

import '../helpers/test_storage.dart';

// адрес и имя сменились разом: в новом списке такой сервер не узнать, он приходит новым
String _vless(String host, String name) =>
    'vless://00000000-0000-4000-8000-000000000000@$host:443'
    '?security=reality&type=tcp#$name';

Subscription _sub(String id, {bool auto = false}) => Subscription(
      id: id,
      name: id,
      url: 'https://$id.example/sub',
      autoSelectVisible: true,
      autoSelect: auto,
    );

ServerItem _server(String subId, String host, String name, {int? ping}) =>
    ServerItem.fromRaw(_vless(host, name), subscriptionId: subId).copyWith(
      pingMs: ping,
      lastPingType: ping == null ? null : 'url',
      lastTestedAt: ping == null ? null : DateTime.now(),
    );

Future<StorageService> _seed({
  required List<Subscription> subs,
  required List<ServerItem> servers,
  required String? activeId,
  AutoSelectHome? home,
}) async {
  final storage = await buildStorageService();
  await storage.saveSubscriptions(subs);
  await storage.saveServers(servers);
  await storage.setActiveServerId(activeId);
  await AutoSelectHomeStore.save(home);
  return storage;
}

Future<void> _update(
  StorageService storage,
  Subscription sub,
  List<String> configs,
) async {
  final service = SubscriptionService(
    storage,
    dio: Dio()..httpClientAdapter = _Body(configs.join('\n')),
  );
  final result = await service.updateSubscription(sub);
  expect(result.success, isTrue, reason: result.error);
}

Future<ServerItem?> _active(StorageService storage) async {
  final id = storage.getActiveServerId();
  final servers = await storage.getServers();
  return servers.where((s) => s.id == id).firstOrNull;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ручной выбор', () {
    test('выбранный сервер пропал из подписки: выбор пуст', () async {
      final gone = _server('a', '198.51.100.10', 'Old', ping: 300);
      final storage = await _seed(
        subs: [_sub('a')],
        servers: [gone, _server('a', '198.51.100.20', 'Fast', ping: 80)],
        activeId: gone.id,
      );

      await _update(storage, _sub('a'), [
        _vless('198.51.100.11', 'Renamed'),
        _vless('198.51.100.20', 'Fast'),
      ]);

      expect(storage.getActiveServerId(), isNull);
      expect(await AutoSelectFollowStore.take(), isNull);
    });

    test('сервер узнан в новом списке: выбор на месте', () async {
      final picked = _server('a', '198.51.100.10', 'Old', ping: 300);
      final storage = await _seed(
        subs: [_sub('a', auto: true)],
        servers: [picked, _server('a', '198.51.100.20', 'Fast', ping: 80)],
        activeId: picked.id,
      );

      await _update(storage, _sub('a', auto: true), [
        _vless('198.51.100.10', 'Old renamed'),
        _vless('198.51.100.20', 'Fast'),
      ]);

      expect(storage.getActiveServerId(), picked.id);
      expect(await AutoSelectFollowStore.take(), isNull);
    });

    test('выбран сервер другой подписки: обновление его не трогает', () async {
      final elsewhere = _server('b', '203.0.113.5', 'Other');
      final storage = await _seed(
        subs: [_sub('a', auto: true), _sub('b')],
        servers: [_server('a', '198.51.100.10', 'Old'), elsewhere],
        activeId: elsewhere.id,
      );

      await _update(storage, _sub('a', auto: true), [
        _vless('198.51.100.11', 'New'),
      ]);

      expect(storage.getActiveServerId(), elsewhere.id);
    });
  });

  // жалоба: в режиме авто после каждого обновления подписки приходилось выбирать сервер руками
  group('авто', () {
    test('выбранный пропал: берётся лучший по замерам из той же подписки',
        () async {
      final gone = _server('a', '198.51.100.10', 'Old', ping: 60);
      final storage = await _seed(
        subs: [_sub('a', auto: true)],
        servers: [
          gone,
          _server('a', '198.51.100.30', 'Slow', ping: 150),
          _server('a', '198.51.100.20', 'Fast', ping: 80),
        ],
        activeId: gone.id,
      );

      await _update(storage, _sub('a', auto: true), [
        _vless('198.51.100.11', 'Renamed'),
        _vless('198.51.100.30', 'Slow'),
        _vless('198.51.100.20', 'Fast'),
      ]);

      final active = await _active(storage);
      expect(active?.displayName, 'Fast');
      expect(await AutoSelectFollowStore.take(), active?.id,
          reason: 'туннель, поднятый на пропавшем, должен узнать, куда ехать');
    });

    test('замеров нет ни у кого: первый в списке', () async {
      final gone = _server('a', '198.51.100.10', 'Old');
      final storage = await _seed(
        subs: [_sub('a', auto: true)],
        servers: [gone],
        activeId: gone.id,
      );

      await _update(storage, _sub('a', auto: true), [
        _vless('198.51.100.11', 'First'),
        _vless('198.51.100.12', 'Second'),
      ]);

      expect((await _active(storage))?.displayName, 'First');
    });

    test('автовыбор увёз в соседнюю подписку и там сервер пропал: '
        'лучший из соседней, своя подписка ждёт по-прежнему', () async {
      final home = _server('a', '198.51.100.10', 'Home');
      final gone = _server('b', '203.0.113.10', 'Away');
      final storage = await _seed(
        subs: [_sub('a', auto: true), _sub('b')],
        servers: [home, gone],
        activeId: gone.id,
        home: AutoSelectHome(
          subscriptionId: 'a',
          homeId: home.id,
          pickedId: gone.id,
        ),
      );

      await _update(storage, _sub('b'), [_vless('203.0.113.11', 'Away new')]);

      final active = await _active(storage);
      expect(active?.displayName, 'Away new');
      final waiting = await AutoSelectHomeStore.load();
      expect(waiting?.homeId, home.id);
      expect(waiting?.pickedId, active?.id);
    });

    test('авто включено, но сервер соседней выбран не им: выбор пуст',
        () async {
      final picked = _server('b', '203.0.113.10', 'Tray pick');
      final storage = await _seed(
        subs: [_sub('a', auto: true), _sub('b')],
        servers: [_server('a', '198.51.100.10', 'Home'), picked],
        activeId: picked.id,
      );

      await _update(storage, _sub('b'), [_vless('203.0.113.11', 'New')]);

      expect(storage.getActiveServerId(), isNull);
    });

    test('выбранный пропал: отмеченный мимо Авто не подставляется, '
        'даже самый быстрый', () async {
      final gone = _server('a', '198.51.100.10', 'Old', ping: 60);
      final storage = await _seed(
        subs: [_sub('a', auto: true)],
        servers: [
          gone,
          _server('a', '198.51.100.20', 'Fast', ping: 30)
              .copyWith(autoSkip: true),
          _server('a', '198.51.100.30', 'Slow', ping: 150),
        ],
        activeId: gone.id,
      );

      await _update(storage, _sub('a', auto: true), [
        _vless('198.51.100.11', 'Renamed'),
        _vless('198.51.100.20', 'Fast'),
        _vless('198.51.100.30', 'Slow'),
      ]);

      expect((await _active(storage))?.displayName, 'Slow');
    });
  });

  test('пометка мимо Авто переживает обновление подписки', () async {
    final same = _server('a', '198.51.100.20', 'Same').copyWith(autoSkip: true);
    final renamed =
        _server('a', '198.51.100.30', 'Before').copyWith(autoSkip: true);
    final storage = await _seed(
      subs: [_sub('a')],
      servers: [same, renamed, _server('a', '198.51.100.40', 'Plain')],
      activeId: null,
    );

    await _update(storage, _sub('a'), [
      _vless('198.51.100.20', 'Same'),
      _vless('198.51.100.30', 'After'),
      _vless('198.51.100.40', 'Plain'),
    ]);

    final byName = {
      for (final s in await storage.getServers()) s.displayName: s.autoSkip,
    };
    expect(byName, {'Same': true, 'After': true, 'Plain': false});
  });
}

class _Body implements HttpClientAdapter {
  _Body(this.body);

  final String body;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(
        body,
        200,
        headers: {
          'content-type': ['text/plain; charset=utf-8'],
        },
      );
}
