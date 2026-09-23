import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/storage_service.dart';

import '../helpers/test_storage.dart';

/// «Авто» может гореть только в одной подписке: подключение одно, и выбирать
/// для него сервер может только одна. Жалоба была такая: включила «Авто» во
/// второй подписке — переехала на неё, а в первой кнопка так и осталась
/// включённой.
Future<(ProviderContainer, StorageService)> _seed(
  List<Subscription> subs,
) async {
  final storage = await buildStorageService();
  await storage.saveSubscriptions(subs);
  final container = ProviderContainer(
    overrides: [storageProvider.overrideWithValue(storage)],
  );
  addTearDown(container.dispose);
  await container.read(subscriptionsProvider.future);
  return (container, storage);
}

Subscription _sub(String id, {bool visible = true, bool auto = false}) =>
    Subscription(
      id: id,
      name: id,
      url: 'https://example.com/$id',
      autoSelectVisible: visible,
      autoSelect: auto,
    );

Map<String, bool> _auto(List<Subscription> subs) => {
      for (final s in subs) s.id: s.autoSelect,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('включила во второй — в первой гаснет', () async {
    final (c, storage) = await _seed([
      _sub('a', auto: true),
      _sub('b'),
      _sub('c'),
    ]);
    await c.read(subscriptionsProvider.notifier).handAutoSelectTo('b');

    const expected = {'a': false, 'b': true, 'c': false};
    expect(_auto(c.read(subscriptionsProvider).value!), expected);
    expect(_auto(await storage.getSubscriptions()), expected);
  });

  test('ручной выбор сервера гасит «Авто» везде', () async {
    final (c, storage) = await _seed([
      _sub('a', auto: true),
      _sub('b'),
    ]);
    await c.read(subscriptionsProvider.notifier).handAutoSelectTo(null);

    const expected = {'a': false, 'b': false};
    expect(_auto(c.read(subscriptionsProvider).value!), expected);
    expect(_auto(await storage.getSubscriptions()), expected);
  });

  test('подписке со спрятанной плашкой «Авто» не отдаётся', () async {
    // Кнопки там не видно — выключить её было бы нечем.
    final (c, _) = await _seed([_sub('a', visible: false)]);
    await c.read(subscriptionsProvider.notifier).handAutoSelectTo('a');
    expect(c.read(subscriptionsProvider).value!.single.autoSelect, isFalse);
  });
}
