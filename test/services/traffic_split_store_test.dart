import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/traffic_split.dart';
import 'package:keqdroid/services/traffic_split_store.dart';
import 'package:path/path.dart' as p;

/// Каталог подсовывается через [TrafficSplitStore.directoryOverride] — тем же
/// приёмом, что у картинок карточек: path_provider в тестах не отвечает, а
/// проверять надо как раз работу с настоящими файлами.
void main() {
  late Directory dir;

  TrafficSplitState state({
    String session = 's1',
    int coreDownload = 700,
    int vpnDownload = 600,
  }) =>
      TrafficSplitState(
        session: session,
        coreDownload: coreDownload,
        coreUpload: 30,
        vpnDownload: vpnDownload,
        vpnUpload: 20,
        directDownload: 10,
        directUpload: 5,
        connections: const {'a': (700, 20)},
      );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('traffic_split_store_test');
    TrafficSplitStore.directoryOverride = dir.path;
  });

  tearDown(() {
    TrafficSplitStore.directoryOverride = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('записи нет — счёт начинается с нуля', () async {
    expect(await TrafficSplitStore.load(), isNull);
  });

  test('счёт возвращается с диска целиком', () async {
    await TrafficSplitStore.save(state());
    final back = await TrafficSplitStore.load();
    expect(back!.session, 's1');
    expect(back.vpnDownload, 600);
    expect(back.connections, {'a': (700, 20)});
  });

  test('следующая запись ложится поверх прежней', () async {
    await TrafficSplitStore.save(state(vpnDownload: 600));
    await TrafficSplitStore.save(state(vpnDownload: 900));
    expect((await TrafficSplitStore.load())!.vpnDownload, 900);
    // Временный файл записи после себя не оставляем.
    final left = dir.listSync().map((e) => p.basename(e.path)).toList();
    expect(left, ['traffic_split.json']);
  });

  test('порванный файл читается как отсутствующий', () async {
    File(p.join(dir.path, 'traffic_split.json'))
        .writeAsStringSync('{"v":1,"session":"s1","core":[7');
    expect(await TrafficSplitStore.load(), isNull);
  });

  test('метка сессии держится за порт и токен', () {
    const secret = 'ecd1e2c4f6a84cd0a1f3f5b7c9d1e3f5';
    final key = TrafficSplitStore.sessionKey(port: 41234, secret: secret);
    expect(key, startsWith('41234:'));
    expect(
      TrafficSplitStore.sessionKey(port: 41234, secret: secret),
      key,
      reason: 'та же сессия — та же метка, иначе счёт не подхватится',
    );
    // Токен в открытом виде на диск не уезжает: в конфиге ядра он уже есть,
    // второй копии заводить незачем.
    expect(key, isNot(contains(secret)));
    expect(
      TrafficSplitStore.sessionKey(port: 41234, secret: 'другой токен'),
      isNot(key),
    );
    expect(
      TrafficSplitStore.sessionKey(port: 41235, secret: secret),
      isNot(key),
    );
  });
}
