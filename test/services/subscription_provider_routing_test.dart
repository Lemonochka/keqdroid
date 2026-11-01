import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/routing_profile.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/models/traffic_route.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:keqdroid/services/subscription_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockStorageService extends Mock implements StorageService {}

const _servers = 'vless://00000000-0000-4000-8000-000000000000@198.51.100.10:443'
    '?security=reality&type=tcp#Alpha';

final _happLink = 'happ://routing/onadd/${base64.encode(utf8.encode(jsonEncode({
      'Name': 'RU напрямую',
      'GlobalProxy': 'true',
      'DirectSites': ['geosite:category-ru'],
      'DirectIp': ['geoip:ru'],
    })))}';

void main() {
  late _MockStorageService storage;
  late List<RoutingProfile> profiles;
  late AppSettings settings;

  setUpAll(() {
    registerFallbackValue(const Subscription(id: '', name: '', url: ''));
    registerFallbackValue(<ServerItem>[]);
    registerFallbackValue(<RoutingProfile>[]);
  });

  setUp(() {
    profiles = const [];
    settings = const AppSettings();
    storage = _MockStorageService();
    when(() => storage.getSettings()).thenAnswer((_) async => settings);
    when(() => storage.getHwid()).thenReturn(null);
    when(() => storage.setHwid(any())).thenAnswer((_) async {});
    when(() => storage.getServers()).thenAnswer((_) async => const []);
    when(() => storage.getActiveServerId()).thenReturn(null);
    when(() => storage.replaceServersBySubscription(any(), any()))
        .thenAnswer((_) async {});
    when(() => storage.upsertSubscription(any())).thenAnswer((_) async {});
    when(() => storage.getRoutingProfiles()).thenAnswer((_) async => profiles);
    when(() => storage.saveRoutingProfiles(any())).thenAnswer((inv) async {
      profiles = inv.positionalArguments.first as List<RoutingProfile>;
    });
  });

  const sub = Subscription(id: 's1', name: 'Моя подписка', url: 'https://example.com/sub');

  Future<UpdateResult> update(String body, {Map<String, String> headers = const {}}) =>
      SubscriptionService(
        storage,
        dio: Dio()..httpClientAdapter = _Adapter(body, headers),
      ).updateSubscription(sub);

  test('заголовок routing заводит профиль, привязанный к подписке', () async {
    final result = await update(_servers, headers: {'routing': _happLink});
    expect(result.success, isTrue);
    expect(result.routingChanged, isTrue);
    final p = profiles.single;
    expect(p.name, 'RU напрямую');
    expect(p.subscriptionIds, ['s1']);
    expect(p.providerSubscriptionId, 's1');
    expect(p.routes.single.target, RouteTarget.direct);
    expect(p.routes.single.sites, 'geosite:category-ru\ngeoip:ru');
  });

  test('ссылка в теле работает так же, серверы при этом на месте', () async {
    final result = await update('$_happLink\n$_servers\n');
    expect(result.serverCount, 1);
    expect(profiles.single.providerSubscriptionId, 's1');
  });

  test('те же правила второй раз ничего не пишут', () async {
    await update(_servers, headers: {'routing': _happLink});
    final again = await update(_servers, headers: {'routing': _happLink});
    expect(again.routingChanged, isFalse);
    verify(() => storage.saveRoutingProfiles(any())).called(1);
  });

  test('с «Игнорировать правила провайдера» профиль не заводится', () async {
    settings = const AppSettings(ignoreProviderRules: true);
    final result = await update(_servers, headers: {'routing': _happLink});
    expect(result.routingChanged, isFalse);
    verifyNever(() => storage.saveRoutingProfiles(any()));
  });

  test('свой профиль у подписки остаётся, провайдерский не появляется', () async {
    const own = RoutingProfile(id: 'mine', name: 'Моё', subscriptionIds: ['s1']);
    profiles = const [own];
    final result = await update(_servers, headers: {'routing': _happLink});
    expect(result.routingChanged, isFalse);
    expect(profiles.single.id, 'mine');
  });

  test('routing/off убирает профиль провайдера', () async {
    await update(_servers, headers: {'routing': _happLink});
    expect(profiles, hasLength(1));
    final result = await update(_servers, headers: {'routing': 'happ://routing/off'});
    expect(result.routingChanged, isTrue);
    expect(profiles, isEmpty);
  });

  test('подписка без правил профили не трогает', () async {
    final result = await update(_servers);
    expect(result.routingChanged, isFalse);
    verifyNever(() => storage.getRoutingProfiles());
  });
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.body, this.headers);

  final String body;
  final Map<String, String> headers;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(
        body,
        200,
        headers: {
          'content-type': ['text/plain; charset=utf-8'],
          for (final e in headers.entries) e.key: [e.value],
        },
      );
}
