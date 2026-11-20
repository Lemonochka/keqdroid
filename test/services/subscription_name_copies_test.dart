import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:keqdroid/services/subscription_service.dart';

import '../helpers/test_storage.dart';

String _vless(
  String name, {
  String host = '198.51.100.10',
  String sni = 'a.example',
}) =>
    'vless://00000000-0000-4000-8000-000000000000@$host:443'
    '?security=tls&sni=$sni&type=ws&path=%2Fws#$name';

String _vmess(String name, {String path = '/ws'}) =>
    'vmess://${base64.encode(utf8.encode(jsonEncode({'v': '2', 'ps': name, 'add': '198.51.100.20', 'port': '443', 'id': '00000000-0000-4000-8000-000000000001', 'net': 'ws', 'path': path, 'tls': 'tls'})))}';

final _sub = Subscription(id: 'a', name: 'a', url: 'https://a.example/sub');

Future<StorageService> _seed(
  List<ServerItem> servers, {
  String? activeId,
}) async {
  final storage = await buildStorageService();
  await storage.saveSubscriptions([_sub]);
  await storage.saveServers(servers);
  await storage.setActiveServerId(activeId);
  return storage;
}

Future<List<ServerItem>> _update(
  StorageService storage,
  List<String> configs,
) async {
  final service = SubscriptionService(
    storage,
    dio: Dio()..httpClientAdapter = _Body(configs.join('\n')),
  );
  final result = await service.updateSubscription(_sub);
  expect(result.success, isTrue, reason: result.error);
  return (await storage.getServers())
      .where((s) => s.subscriptionId == 'a')
      .toList();
}

List<String> _names(List<ServerItem> servers) => [
  for (final s in servers) s.displayName,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('как было до склейки копий', () {
    test('одинаковые строки дают один сервер', () async {
      final storage = await _seed([]);
      final servers = await _update(storage, [
        _vless('A'),
        _vless('A'),
        _vless('B', host: '198.51.100.11'),
      ]);
      expect(_names(servers), ['A', 'B']);
    });

    test(
      'другой SNI при том же адресе, порте и UUID это другой сервер',
      () async {
        final storage = await _seed([]);
        final servers = await _update(storage, [
          _vless('A'),
          _vless('B', sni: 'b.example'),
        ]);
        expect(_names(servers), ['A', 'B']);
      },
    );

    test('vmess с другим путём это другой сервер', () async {
      final storage = await _seed([]);
      final servers = await _update(storage, [
        _vmess('A'),
        _vmess('B', path: '/other'),
      ]);
      expect(_names(servers), ['A', 'B']);
    });

    test('сервер, переименованный провайдером, сохраняет id и пинг', () async {
      final old = ServerItem.fromRaw(
        _vless('Old'),
        subscriptionId: 'a',
      ).copyWith(pingMs: 90, lastPingType: 'url', lastTestedAt: DateTime.now());
      final storage = await _seed([old], activeId: old.id);
      final servers = await _update(storage, [_vless('New')]);
      expect(servers.single.id, old.id);
      expect(servers.single.pingMs, 90);
      expect(servers.single.displayName, 'New');
      expect(storage.getActiveServerId(), old.id);
    });
  });

  group('копии одного сервера под разными именами', () {
    test('остаётся одна, первая, на её месте', () async {
      final storage = await _seed([]);
      final servers = await _update(storage, [
        _vless('@chan1'),
        _vless('Other', host: '198.51.100.11'),
        _vless('@chan2'),
        _vmess('@chan3'),
        _vmess('@chan4'),
      ]);
      expect(_names(servers), ['@chan1', 'Other', '@chan3']);
    });

    test('выбранная копия остаётся, даже если она не первая', () async {
      final first = ServerItem.fromRaw(_vless('@chan1'), subscriptionId: 'a');
      final picked = ServerItem.fromRaw(
        _vless('@chan2'),
        subscriptionId: 'a',
      ).copyWith(pingMs: 70, lastPingType: 'url', lastTestedAt: DateTime.now());
      final storage = await _seed([first, picked], activeId: picked.id);
      final servers = await _update(storage, [
        _vless('@chan1'),
        _vless('@chan2'),
      ]);
      expect(servers.single.id, picked.id);
      expect(servers.single.pingMs, 70);
      expect(storage.getActiveServerId(), picked.id);
    });

    test(
      'закреплённая, переименованная или отмеченная мимо Авто копия остаётся',
      () async {
        for (final mark in <ServerItem Function(ServerItem)>[
          (s) => s.copyWith(pinnedAt: DateTime(2026, 11, 1)),
          (s) => s.copyWith(customName: 'Мой'),
          (s) => s.copyWith(autoSkip: true),
        ]) {
          final first = ServerItem.fromRaw(
            _vless('@chan1'),
            subscriptionId: 'a',
          );
          final kept = mark(
            ServerItem.fromRaw(_vless('@chan2'), subscriptionId: 'a'),
          );
          final storage = await _seed([first, kept]);
          final servers = await _update(storage, [
            _vless('@chan1'),
            _vless('@chan2'),
          ]);
          expect(servers.single.id, kept.id);
        }
      },
    );
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
