import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/server_item.dart';

import '../helpers/test_storage.dart';

/// История замеров копится там же, куда пишется каждый пинг, — по кнопке, от
/// судьи автовыбора и плановой проверки.
void main() {
  ServerItem server(String id) => ServerItem(
    id: id,
    config: 'vless://uuid@$id.example.com:443?type=tcp&security=none#$id',
    type: ServerItemType.manual,
    addedAt: DateTime(2026),
  );

  test('каждый замер ложится в историю, провал — тоже', () async {
    final storage = await buildStorageService();
    await storage.saveServers([server('a')]);

    await storage.applyPingUpdates({
      'a': (pingMs: 80, lastPingType: 'url'),
    }, DateTime(2026, 10, 6, 12));
    final out = await storage.applyPingUpdates({
      'a': (pingMs: null, lastPingType: 'url'),
    }, DateTime(2026, 10, 6, 12, 5));

    final samples = out.single.pingSamples;
    expect(samples.map((s) => s.ms), [80, null]);
    expect(samples.every((s) => s.type == 'url'), isTrue);
  });

  test('помнит только последние пять', () async {
    final storage = await buildStorageService();
    await storage.saveServers([server('a')]);

    var out = <ServerItem>[];
    for (var i = 0; i < 7; i++) {
      out = await storage.applyPingUpdates({
        'a': (pingMs: 100 + i, lastPingType: 'url'),
      }, DateTime(2026, 10, 6, 12, i));
    }

    expect(out.single.pingSamples.map((s) => s.ms), [102, 103, 104, 105, 106]);
  });

  test('тест скорости в историю задержек не пишется', () async {
    final storage = await buildStorageService();
    await storage.saveServers([server('a')]);

    final out = await storage.applyPingUpdates({
      'a': (pingMs: 90000, lastPingType: 'speed'),
    }, DateTime(2026, 10, 6, 12));

    expect(out.single.pingSamples, isEmpty);
  });

  test('история переживает запись и чтение', () async {
    final storage = await buildStorageService();
    await storage.saveServers([server('a')]);
    await storage.applyPingUpdates({
      'a': (pingMs: 42, lastPingType: 'tcp'),
    }, DateTime(2026, 10, 6, 12));

    final read = (await storage.getServers()).single.pingSamples.single;
    expect(read.ms, 42);
    expect(read.type, 'tcp');
    expect(read.at, DateTime(2026, 10, 6, 12));
  });
}
