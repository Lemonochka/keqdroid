import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/subscription.dart';

import '../helpers/test_storage.dart';

void main() {
  group('StorageService', () {
    test('upsertSubscription inserts and updates by id', () async {
      final storage = await buildStorageService();
      final sub = Subscription.create(name: 'A', url: 'https://example.com/sub');

      await storage.upsertSubscription(sub);
      await storage.upsertSubscription(sub.copyWith(name: 'B'));
      final all = await storage.getSubscriptions();

      expect(all.length, 1);
      expect(all.first.name, 'B');
    });

    test('replaceServersBySubscription keeps other subscriptions', () async {
      final storage = await buildStorageService();
      final s1 = ServerItem.fromRaw('vless://id@one.com:443', subscriptionId: 'sub-a');
      final s2 = ServerItem.fromRaw('vless://id@two.com:443', subscriptionId: 'sub-b');
      await storage.saveServers([s1, s2]);

      final replacement =
          ServerItem.fromRaw('vless://id@new.com:443', subscriptionId: 'sub-a');
      await storage.replaceServersBySubscription('sub-a', [replacement]);
      final all = await storage.getServers();

      expect(all.any((s) => s.subscriptionId == 'sub-b'), isTrue);
      expect(
        all.where((s) => s.subscriptionId == 'sub-a').single.config.contains('new.com'),
        isTrue,
      );
    });

    test('deleteSubscription cascades to servers', () async {
      final storage = await buildStorageService();
      final sub = Subscription(id: 'sub-x', name: 'X', url: 'https://x');
      await storage.saveSubscriptions([sub]);
      await storage.saveServers([
        ServerItem.fromRaw('vless://id@one.com:443', subscriptionId: 'sub-x'),
      ]);

      await storage.deleteSubscription('sub-x');

      expect(await storage.getSubscriptions(), isEmpty);
      expect(await storage.getServers(), isEmpty);
    });

    test('getSettings returns defaults on invalid payload', () async {
      final storage = await buildStorageService(
        initialValues: {'keqdis_settings': '{bad json'},
      );
      final settings = await storage.getSettings();
      expect(settings, const AppSettings());
    });

    test('setActiveServerId(null) clears active id', () async {
      final storage = await buildStorageService();
      await storage.setActiveServerId('abc');
      await storage.setActiveServerId(null);
      expect(storage.getActiveServerId(), isNull);
    });
  });
}


