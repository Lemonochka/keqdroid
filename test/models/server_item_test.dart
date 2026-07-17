import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/server_item.dart';

void main() {
  const vlessConfig =
      'vless://uuid-1@1.2.3.4:443?security=tls&sni=x.com#🇩🇪 Germany Fast';

  ServerItem makeServer({String? customName, DateTime? pinnedAt}) => ServerItem(
        id: 'id-1',
        config: vlessConfig,
        type: ServerItemType.manual,
        customName: customName,
        pinnedAt: pinnedAt,
      );

  group('customName', () {
    test('overrides displayName; derivedName keeps the config name', () {
      final s = makeServer(customName: 'Мой сервер');
      expect(s.displayName, 'Мой сервер');
      expect(s.derivedName, '🇩🇪 Germany Fast');
    });

    test('empty/whitespace customName falls back to config name', () {
      expect(makeServer(customName: '   ').displayName, '🇩🇪 Germany Fast');
      expect(makeServer().displayName, '🇩🇪 Germany Fast');
    });

    test('countryCode falls back to the config name after rename', () {
      // в новом имени страны нет — флаг должен остаться от исходного имени
      expect(makeServer(customName: 'Мой сервер').countryCode, 'DE');
      // а если в новом имени страна есть — берётся она
      expect(makeServer(customName: 'US Home').countryCode, 'US');
    });

    test('copyWith can reset customName back to null', () {
      final renamed = makeServer(customName: 'X');
      final reset = renamed.copyWith(customName: null);
      expect(reset.customName, isNull);
      expect(reset.displayName, '🇩🇪 Germany Fast');
    });
  });

  group('pinnedAt', () {
    test('isPinned reflects pinnedAt; copyWith can unpin', () {
      final pinned = makeServer(pinnedAt: DateTime(2026, 7, 17));
      expect(pinned.isPinned, isTrue);
      expect(pinned.copyWith(pinnedAt: null).isPinned, isFalse);
    });
  });

  group('json round-trip', () {
    test('new fields survive toJson/fromJson', () {
      final s = ServerItem(
        id: 'id-2',
        config: vlessConfig,
        type: ServerItemType.subscription,
        subscriptionId: 'sub-1',
        customName: 'Renamed',
        pinnedAt: DateTime(2026, 7, 17, 12, 30),
        configOverridden: true,
      );
      final restored = ServerItem.fromJson(s.toJson());
      expect(restored.customName, 'Renamed');
      expect(restored.pinnedAt, DateTime(2026, 7, 17, 12, 30));
      expect(restored.configOverridden, isTrue);
    });

    test('old json without new fields loads with defaults', () {
      final restored = ServerItem.fromJson({
        'id': 'id-3',
        'config': vlessConfig,
        'type': 'manual',
        'isFavorite': false,
      });
      expect(restored.customName, isNull);
      expect(restored.pinnedAt, isNull);
      expect(restored.configOverridden, isFalse);
      expect(restored.isPinned, isFalse);
    });
  });

  group('vmess derived name', () {
    test('uses ps from the payload', () {
      final payload = base64.encode(utf8.encode(jsonEncode({
        'v': '2',
        'ps': 'My VMess',
        'add': 'h.com',
        'port': '443',
        'id': 'uuid',
      })));
      final s = ServerItem(
        id: 'id-4',
        config: 'vmess://$payload',
        type: ServerItemType.manual,
      );
      expect(s.displayName, 'My VMess');
    });
  });
}
