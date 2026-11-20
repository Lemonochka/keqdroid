import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:keqdroid/services/subscription_service.dart';

import '../helpers/test_storage.dart';

String _vless(String name, {int n = 10}) =>
    'vless://00000000-0000-4000-8000-000000000000@198.51.100.$n:443'
    '?security=tls&sni=a.example&type=ws&path=%2Fws#$name';

String _trojan(String name, {int n = 20}) =>
    'trojan://secret@198.51.100.$n:443?security=tls&sni=a.example#$name';

String _ss(String name, {int n = 30}) =>
    'ss://YWVzLTI1Ni1nY206c2VjcmV0@198.51.100.$n:8388#$name';

String _hy2(String name, {int n = 40}) =>
    'hy2://secret@198.51.100.$n:443?sni=a.example#$name';

String _hysteria2(String name, {int n = 41}) =>
    'hysteria2://secret@198.51.100.$n:443?sni=a.example#$name';

Subscription _sub({Set<String> excluded = const {}}) => Subscription(
  id: 'a',
  name: 'a',
  url: 'https://a.example/sub',
  excludedProtocols: excluded,
);

Future<StorageService> _seed(
  Subscription sub, {
  List<ServerItem> servers = const [],
  String? activeId,
}) async {
  final storage = await buildStorageService();
  await storage.saveSubscriptions([sub]);
  await storage.saveServers(servers);
  await storage.setActiveServerId(activeId);
  return storage;
}

Future<({List<ServerItem> servers, Subscription sub})> _update(
  StorageService storage,
  Subscription sub,
  List<String> configs,
) async {
  final service = SubscriptionService(
    storage,
    dio: Dio()..httpClientAdapter = _Body(configs.join('\n')),
  );
  final result = await service.updateSubscription(sub);
  expect(result.success, isTrue, reason: result.error);
  return (
    servers: (await storage.getServers())
        .where((s) => s.subscriptionId == sub.id)
        .toList(),
    sub: (await storage.getSubscriptions()).single,
  );
}

List<String> _names(List<ServerItem> servers) => [
  for (final s in servers) s.displayName,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mixed = [
    _vless('V1'),
    _ss('S1'),
    _vless('V2', n: 11),
    _trojan('T1'),
    _ss('S2', n: 31),
  ];

  group('без фильтра всё как было', () {
    test('приходят все протоколы в порядке провайдера', () async {
      final sub = _sub();
      final storage = await _seed(sub);
      final r = await _update(storage, sub, mixed);
      expect(_names(r.servers), ['V1', 'S1', 'V2', 'T1', 'S2']);
      expect(r.sub.serverCount, 5);
    });

    test('подписка запоминает, сколько пришло каждого протокола', () async {
      final sub = _sub();
      final storage = await _seed(sub);
      final r = await _update(storage, sub, mixed);
      expect(r.sub.protocolCounts, {'vless': 2, 'ss': 2, 'trojan': 1});
    });
  });

  group('выключенные протоколы', () {
    test('не попадают в список, счёт серверов без них', () async {
      final sub = _sub(excluded: {'ss'});
      final storage = await _seed(sub);
      final r = await _update(storage, sub, mixed);
      expect(_names(r.servers), ['V1', 'V2', 'T1']);
      expect(r.sub.serverCount, 3);
    });

    test('в счёте протоколов остаются: по нему строится шторка', () async {
      final sub = _sub(excluded: {'ss'});
      final storage = await _seed(sub);
      final r = await _update(storage, sub, mixed);
      expect(r.sub.protocolCounts, {'vless': 2, 'ss': 2, 'trojan': 1});
      expect(r.sub.excludedProtocols, {'ss'});
    });

    test('уже лежавшие серверы выключенного протокола уходят', () async {
      final sub = _sub();
      final storage = await _seed(sub);
      await _update(storage, sub, mixed);
      final filtered = sub.copyWith(excludedProtocols: {'ss', 'trojan'});
      await storage.saveSubscriptions([filtered]);
      final r = await _update(storage, filtered, mixed);
      expect(_names(r.servers), ['V1', 'V2']);
    });

    test('включённый обратно возвращается при следующем обновлении', () async {
      final sub = _sub(excluded: {'ss'});
      final storage = await _seed(sub);
      await _update(storage, sub, mixed);
      final all = sub.copyWith(excludedProtocols: const {});
      await storage.saveSubscriptions([all]);
      final r = await _update(storage, all, mixed);
      expect(_names(r.servers), ['V1', 'S1', 'V2', 'T1', 'S2']);
    });

    test(
      'новый протокол от провайдера приходит, а не пропадает молча',
      () async {
        final sub = _sub(excluded: {'ss'});
        final storage = await _seed(sub);
        final r = await _update(storage, sub, [...mixed, _hy2('H1')]);
        expect(_names(r.servers), ['V1', 'V2', 'T1', 'H1']);
      },
    );

    test('hy2 и hysteria2 это один протокол', () async {
      final sub = _sub();
      final storage = await _seed(sub);
      final r = await _update(storage, sub, [
        _vless('V1'),
        _hy2('H1'),
        _hysteria2('H2'),
      ]);
      expect(r.sub.protocolCounts, {'vless': 1, 'hysteria2': 2});

      final filtered = sub.copyWith(excludedProtocols: {'hysteria2'});
      await storage.saveSubscriptions([filtered]);
      final again = await _update(storage, filtered, [
        _vless('V1'),
        _hy2('H1'),
        _hysteria2('H2'),
      ]);
      expect(_names(again.servers), ['V1']);
    });

    test(
      'если провайдер прислал одни выключенные, фильтр не опустошает подписку',
      () async {
        final sub = _sub(excluded: {'ss'});
        final storage = await _seed(sub);
        final r = await _update(storage, sub, [_ss('S1'), _ss('S2', n: 31)]);
        expect(_names(r.servers), ['S1', 'S2']);
      },
    );

    test(
      'выбранный сервер выключенного протокола в ручном режиме снимается',
      () async {
        final sub = _sub();
        final storage = await _seed(sub);
        final first = await _update(storage, sub, mixed);
        final picked = first.servers.firstWhere((s) => s.displayName == 'S1');
        await storage.setActiveServerId(picked.id);

        final filtered = sub.copyWith(excludedProtocols: {'ss'});
        await storage.saveSubscriptions([filtered]);
        await _update(storage, filtered, mixed);
        expect(storage.getActiveServerId(), isNull);
      },
    );

    test(
      'правленный руками сервер выключенного протокола тоже уходит',
      () async {
        final edited = ServerItem.fromRaw(
          _ss('Mine', n: 99),
          subscriptionId: 'a',
        ).copyWith(configOverridden: true);
        final sub = _sub(excluded: {'ss'});
        final storage = await _seed(sub, servers: [edited]);
        final r = await _update(storage, sub, mixed);
        expect(_names(r.servers), ['V1', 'V2', 'T1']);
      },
    );
  });

  group('модель', () {
    test('фильтр и счёт переживают сохранение', () {
      final sub = _sub(
        excluded: {'ss'},
      ).copyWith(protocolCounts: {'vless': 2, 'ss': 1});
      final back = Subscription.fromJson(sub.toJson());
      expect(back.excludedProtocols, {'ss'});
      expect(back.protocolCounts, {'vless': 2, 'ss': 1});
    });

    test('у старой подписки фильтра нет', () {
      final old = Subscription.fromJson({
        'id': 'a',
        'name': 'a',
        'url': 'https://a.example/sub',
      });
      expect(old.excludedProtocols, isEmpty);
      expect(old.protocolCounts, isEmpty);
    });

    test('заголовки профиля фильтр не стирают', () {
      final sub = _sub(excluded: {'ss'})
          .copyWith(protocolCounts: {'vless': 2, 'ss': 1})
          .withProfileHeaders(
            title: 't',
            announce: null,
            supportUrl: null,
            webPageUrl: null,
          );
      expect(sub.excludedProtocols, {'ss'});
      expect(sub.protocolCounts, {'vless': 2, 'ss': 1});
    });
  });
}

class _Body implements HttpClientAdapter {
  _Body(this.body);

  final String body;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    body,
    200,
    headers: {
      'content-type': ['text/plain; charset=utf-8'],
    },
  );
}
