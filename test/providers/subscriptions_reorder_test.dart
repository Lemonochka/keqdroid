import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/storage_service.dart';

import '../helpers/test_storage.dart';

Subscription _sub(String id) =>
    Subscription(id: id, name: id, url: 'https://example.com/$id');

/// Builds a container whose subscriptionsProvider is seeded with [ids] in order.
Future<(ProviderContainer, StorageService)> _seed(List<String> ids) async {
  final storage = await buildStorageService();
  await storage.saveSubscriptions(ids.map(_sub).toList());
  final container = ProviderContainer(
    overrides: [storageProvider.overrideWithValue(storage)],
  );
  addTearDown(container.dispose);
  await container.read(subscriptionsProvider.future); // build state from storage
  return (container, storage);
}

List<String> _stateIds(ProviderContainer c) =>
    (c.read(subscriptionsProvider).value ?? []).map((s) => s.id).toList();

Future<List<String>> _storedIds(StorageService s) async =>
    (await s.getSubscriptions()).map((e) => e.id).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SubscriptionsNotifier.reorder', () {
    test('button reorder (fromReorderableList: false) inserts at given index',
        () async {
      final (c, _) = await _seed(['a', 'b', 'c', 'd']);
      await c
          .read(subscriptionsProvider.notifier)
          .reorder(0, 2, fromReorderableList: false);
      expect(_stateIds(c), ['b', 'c', 'a', 'd']);
    });

    test('ReorderableListView downward (fromReorderableList: true) subtracts 1',
        () async {
      // moving "a" below "c": the legacy onReorder reports the pre-removal
      // newIndex (3); the -1 adjustment lands it at the same place as above.
      final (c, _) = await _seed(['a', 'b', 'c', 'd']);
      await c
          .read(subscriptionsProvider.notifier)
          .reorder(0, 3, fromReorderableList: true);
      expect(_stateIds(c), ['b', 'c', 'a', 'd']);
    });

    test(
        'onReorderItem downward (fromReorderableList: false) matches the migrated call site',
        () async {
      // onReorderItem already adjusts the index, so the migrated call passes
      // fromReorderableList: false with the adjusted newIndex (2). Must match
      // the legacy true/3 outcome above — guards the onReorderItem migration.
      final (c, _) = await _seed(['a', 'b', 'c', 'd']);
      await c
          .read(subscriptionsProvider.notifier)
          .reorder(0, 2, fromReorderableList: false);
      expect(_stateIds(c), ['b', 'c', 'a', 'd']);
    });

    test('upward move keeps newIndex (no -1 for either API)', () async {
      final (c, _) = await _seed(['a', 'b', 'c', 'd']);
      await c
          .read(subscriptionsProvider.notifier)
          .reorder(3, 0, fromReorderableList: true);
      expect(_stateIds(c), ['d', 'a', 'b', 'c']);
    });

    test('out-of-range oldIndex is a no-op (state and storage untouched)',
        () async {
      final (c, storage) = await _seed(['a', 'b', 'c']);
      await c
          .read(subscriptionsProvider.notifier)
          .reorder(9, 0, fromReorderableList: false);
      expect(_stateIds(c), ['a', 'b', 'c']);
      expect(await _storedIds(storage), ['a', 'b', 'c']);
    });

    test('new order is persisted to storage', () async {
      final (c, storage) = await _seed(['a', 'b', 'c', 'd']);
      await c
          .read(subscriptionsProvider.notifier)
          .reorder(0, 2, fromReorderableList: false);
      expect(await _storedIds(storage), _stateIds(c));
      expect(await _storedIds(storage), ['b', 'c', 'a', 'd']);
    });
  });
}
