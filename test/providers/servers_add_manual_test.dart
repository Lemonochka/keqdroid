import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _vless(String name, {String sni = 'a.example'}) =>
    'vless://00000000-0000-4000-8000-000000000000@198.51.100.10:443'
    '?security=tls&sni=$sni&type=ws&path=%2Fws#$name';

Future<ProviderContainer> _seed(List<ServerItem> servers) async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService(await SharedPreferences.getInstance());
  await storage.saveServers(servers);
  final container = ProviderContainer(
    overrides: [storageProvider.overrideWithValue(storage)],
  );
  addTearDown(container.dispose);
  container.read(serversProvider);
  for (var i = 0; i < 20 && container.read(serversProvider).isLoading; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return container;
}

List<String> _names(ProviderContainer c) =>
    [for (final s in c.read(serversProvider).servers) s.displayName];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('та же строка второй раз не добавляется', () async {
    final c = await _seed([ServerItem.fromRaw(_vless('A'))]);
    await expectLater(
      c.read(serversProvider.notifier).addManual(_vless('A')),
      throwsA(isA<Exception>().having((e) => '$e', 'text', contains('already added'))),
    );
    expect(_names(c), ['A']);
  });

  test('тот же сервер под другим именем второй раз не добавляется', () async {
    final c = await _seed([ServerItem.fromRaw(_vless('A'), subscriptionId: 's1')]);
    await expectLater(
      c.read(serversProvider.notifier).addManual(_vless('@channel B')),
      throwsA(isA<Exception>().having((e) => '$e', 'text', contains('already added'))),
    );
    expect(_names(c), ['A']);
  });

  test('другой SNI добавляется вторым сервером', () async {
    final c = await _seed([ServerItem.fromRaw(_vless('A'))]);
    await c.read(serversProvider.notifier).addManual(_vless('B', sni: 'b.example'));
    expect(_names(c), ['A', 'B']);
  });
}
