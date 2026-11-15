import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/providers/providers.dart';

import '../helpers/test_storage.dart';

const _sub = Subscription(
  id: 'a',
  name: 'a',
  url: 'https://a.example/sub',
  excludedProtocols: {'ss'},
);

final _refreshed = <Set<String>>[];

class _Subs extends SubscriptionsNotifier {
  @override
  Future<List<Subscription>> build() async => const [_sub];

  @override
  Future<void> refresh(Subscription sub) async =>
      _refreshed.add(sub.excludedProtocols);
}

Future<SubscriptionsNotifier> _notifier() async {
  final storage = await buildStorageService();
  await storage.saveSubscriptions([_sub]);
  final container = ProviderContainer(
    overrides: [
      storageProvider.overrideWithValue(storage),
      subscriptionsProvider.overrideWith(_Subs.new),
    ],
  );
  addTearDown(container.dispose);
  await container.read(subscriptionsProvider.future);
  return container.read(subscriptionsProvider.notifier);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(_refreshed.clear);

  test('другой набор протоколов сразу обновляет подписку уже с ним', () async {
    final subs = await _notifier();
    await subs.editMeta('a', excludedProtocols: {'ss', 'trojan'});
    await pumpEventQueue();
    expect(_refreshed, [
      {'ss', 'trojan'},
    ]);
  });

  test('тот же набор лишний раз подписку не качает', () async {
    final subs = await _notifier();
    await subs.editMeta('a', name: 'b', excludedProtocols: {'ss'});
    await pumpEventQueue();
    expect(_refreshed, isEmpty);
  });

  test('правка без шторки протоколов фильтр не трогает', () async {
    final subs = await _notifier();
    await subs.editMeta('a', name: 'b');
    final saved = (await subs.future).single;
    expect(saved.excludedProtocols, {'ss'});
  });
}
