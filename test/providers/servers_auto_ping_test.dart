import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/providers/providers.dart';

import '../helpers/test_storage.dart';

class _SpyServers extends ServersNotifier {
  final calls = <String>[];

  @override
  Future<void> pingAll() async => calls.add('all');

  @override
  Future<void> pingSubscription(String? subscriptionId) async =>
      calls.add('sub:$subscriptionId');
}

Future<_SpyServers> _seed({required bool autoPing}) async {
  final storage = await buildStorageService();
  await storage.saveSettings(const AppSettings().copyWith(autoPing: autoPing));
  await storage.saveServers([
    ServerItem.fromRaw(
      'vless://11111111-1111-1111-1111-111111111111@1.1.1.1:443'
      '?security=reality&type=tcp#A',
      subscriptionId: 's1',
    ),
  ]);
  final spy = _SpyServers();
  final container = ProviderContainer(
    overrides: [
      storageProvider.overrideWithValue(storage),
      serversProvider.overrideWith(() => spy),
    ],
  );
  addTearDown(container.dispose);
  container.read(serversProvider);
  return spy;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('выключенный автопинг ничего не пингует сам', () async {
    final spy = await _seed(autoPing: false);
    await spy.autoPingAll();
    await spy.autoPingSubscription('s1');
    expect(spy.calls, isEmpty);
  });

  test('включённый пингует всё при открытии и подписку после обновления',
      () async {
    final spy = await _seed(autoPing: true);
    await spy.autoPingAll();
    await spy.autoPingSubscription('s1');
    expect(spy.calls, ['all', 'sub:s1']);
  });

  test('возврат в приложение пингует не чаще раза в 15 минут', () async {
    final spy = await _seed(autoPing: true);
    await spy.autoPingAll();
    await spy.autoPingAll();
    expect(spy.calls, ['all']);
  });

  test('настройка переживает сохранение и по умолчанию выключена', () {
    final saved = const AppSettings().copyWith(autoPing: true).toJsonString();
    expect(AppSettings.fromJsonString(saved).autoPing, isTrue);
    expect(const AppSettings().autoPing, isFalse);
  });
}
