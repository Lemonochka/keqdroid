import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/core/exceptions.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CountingStorage extends StorageService {
  _CountingStorage(super.prefs);

  final writes = <List<bool>>[];
  bool fail = false;

  @override
  Future<void> upsertServers(Iterable<ServerItem> changed) async {
    if (fail) throw const StorageException('disk full');
    writes.add([for (final s in changed) s.autoSkip]);
    await super.upsertServers(changed);
  }
}

final _server = ServerItem.fromRaw(
  'vless://11111111-1111-1111-1111-111111111111@1.1.1.1:443'
  '?security=reality&type=tcp#A',
  subscriptionId: 's1',
);

Future<(ProviderContainer, _CountingStorage)> _seed() async {
  SharedPreferences.setMockInitialValues({});
  final storage = _CountingStorage(await SharedPreferences.getInstance());
  await storage.saveServers([_server]);
  final container = ProviderContainer(
    overrides: [storageProvider.overrideWithValue(storage)],
  );
  addTearDown(container.dispose);
  container.read(serversProvider);
  for (var i = 0; i < 20 && container.read(serversProvider).isLoading; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return (container, storage);
}

bool _marked(ProviderContainer c) =>
    c.read(serversProvider).servers.single.autoSkip;

Future<bool> _markedOnDisk(StorageService s) async =>
    (await s.getServers()).single.autoSkip;

const _quiet = Duration(milliseconds: 800);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'пометка видна сразу, а на диск уходит одной записью, когда нажатия '
      'туда-обратно стихли', () async {
    final (container, storage) = await _seed();
    final notifier = container.read(serversProvider.notifier);

    notifier.toggleAutoSkip(_server.id);
    expect(_marked(container), isTrue);
    notifier.toggleAutoSkip(_server.id);
    notifier.toggleAutoSkip(_server.id);
    expect(_marked(container), isTrue);
    expect(storage.writes, isEmpty, reason: 'посреди нажатий диск не трогаем');

    await Future<void>.delayed(_quiet);

    expect(storage.writes, [
      [true],
    ]);
    expect(await _markedOnDisk(storage), isTrue);
  });

  test(
      'пометка не перестраивает весь список: shape у неё прежний, у любой '
      'другой перемены новый', () async {
    final (container, _) = await _seed();
    final notifier = container.read(serversProvider.notifier);
    final shape = container.read(serversProvider).shape;

    notifier.toggleAutoSkip(_server.id);
    expect(container.read(serversProvider).shape, shape);

    await notifier.setActive(_server);
    expect(container.read(serversProvider).shape, isNot(shape));
    await notifier.flushAutoSkip();
  });

  test('Готово пишет сразу, и отложенная запись уже не нужна', () async {
    final (container, storage) = await _seed();
    final notifier = container.read(serversProvider.notifier);

    notifier.toggleAutoSkip(_server.id);
    await notifier.flushAutoSkip();
    expect(await _markedOnDisk(storage), isTrue);

    await Future<void>.delayed(_quiet);
    expect(storage.writes, hasLength(1));
  });

  test('не записалось: пометка возвращается к той, что на диске', () async {
    final (container, storage) = await _seed();
    final notifier = container.read(serversProvider.notifier);
    storage.fail = true;

    notifier.toggleAutoSkip(_server.id);
    await expectLater(notifier.flushAutoSkip(), throwsA(isA<StorageException>()));
    expect(_marked(container), isFalse);

    notifier.toggleAutoSkip(_server.id);
    notifier.toggleAutoSkip(_server.id);
    await expectLater(notifier.flushAutoSkip(), throwsA(isA<StorageException>()));
    expect(_marked(container), isFalse,
        reason: 'туда-обратно до сбоя: на диске не отмечен, так и остаётся');
  });
}
