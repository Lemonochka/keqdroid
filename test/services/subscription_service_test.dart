import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:keqdroid/services/subscription_service.dart';
import 'package:keqdroid/utils/mieru_uri.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';
import 'package:keqdroid/utils/ssr_uri.dart';
import 'package:mocktail/mocktail.dart';

class _MockStorageService extends Mock implements StorageService {}

void main() {
  late _MockStorageService storage;
  late SubscriptionService service;

  setUpAll(() {
    registerFallbackValue(const Subscription(id: '', name: '', url: ''));
    registerFallbackValue(<ServerItem>[]);
  });

  setUp(() {
    storage = _MockStorageService();
    service = SubscriptionService(storage);
  });

  group('SubscriptionService.isSafeUrl', () {
    test('allows public https url', () {
      expect(SubscriptionService.isSafeUrl('https://example.com/sub'), isTrue);
    });

    test('blocks localhost and metadata urls', () {
      expect(SubscriptionService.isSafeUrl('http://localhost:8080/test'), isFalse);
      expect(SubscriptionService.isSafeUrl('http://169.254.169.254/latest'), isFalse);
    });

    test('blocks private and loopback literal ips', () {
      expect(SubscriptionService.isSafeUrl('http://10.0.0.1/sub'), isFalse);
      expect(SubscriptionService.isSafeUrl('http://172.16.5.4/sub'), isFalse);
      expect(SubscriptionService.isSafeUrl('http://192.168.1.1/sub'), isFalse);
      expect(SubscriptionService.isSafeUrl('http://127.0.0.1/sub'), isFalse);
      expect(SubscriptionService.isSafeUrl('http://[::1]/sub'), isFalse);
    });

    test('blocks numeric-shorthand loopback that bypasses dotted-quad checks', () {
      // 2130706433 == 0x7f000001 == 127.0.0.1
      expect(SubscriptionService.isSafeUrl('http://2130706433/sub'), isFalse);
      expect(SubscriptionService.isSafeUrl('http://0x7f000001/sub'), isFalse);
    });

    test('still allows a public literal ip', () {
      expect(SubscriptionService.isSafeUrl('https://1.1.1.1/sub'), isTrue);
    });

    test('blocks plain http (subscription payload carries server secrets)', () {
      expect(SubscriptionService.isSafeUrl('http://example.com/sub'), isFalse);
      expect(SubscriptionService.isSafeUrl('http://1.1.1.1/sub'), isFalse);
    });
  });

  group('SubscriptionService.getDueForUpdate', () {
    test('uses default interval when updateIntervalHours is 0', () async {
      final now = DateTime.now();
      when(() => storage.getSubscriptions()).thenAnswer((_) async => [
            Subscription(
              id: '1',
              name: 'A',
              url: 'https://a',
              autoUpdate: true,
              updateIntervalHours: 0,
              lastUpdatedAt: now.subtract(const Duration(hours: 2)),
            ),
          ]);

      final due =
          await service.getDueForUpdate(defaultInterval: const Duration(hours: 1));
      expect(due.length, 1);
    });

    test('skips autoUpdate=false and fresh updates', () async {
      final now = DateTime.now();
      when(() => storage.getSubscriptions()).thenAnswer((_) async => [
            Subscription(
              id: '1',
              name: 'A',
              url: 'https://a',
              autoUpdate: false,
              lastUpdatedAt: now.subtract(const Duration(hours: 5)),
            ),
            Subscription(
              id: '2',
              name: 'B',
              url: 'https://b',
              autoUpdate: true,
              updateIntervalHours: 12,
              lastUpdatedAt: now.subtract(const Duration(hours: 1)),
            ),
          ]);

      final due = await service.getDueForUpdate();
      expect(due, isEmpty);
    });
  });

  group('SubscriptionService.updateAll', () {
    test('returns results only for autoUpdate subscriptions', () async {
      when(() => storage.getSubscriptions()).thenAnswer((_) async => [
            Subscription(id: '1', name: 'A', url: 'http://localhost/a', autoUpdate: true),
            Subscription(id: '2', name: 'B', url: 'http://localhost/b', autoUpdate: false),
          ]);
      when(() => storage.getSettings()).thenAnswer((_) async => const AppSettings());
      when(() => storage.getHwid()).thenReturn(null);
      when(() => storage.getServers()).thenAnswer((_) async => <ServerItem>[]);
      when(() => storage.getActiveServerId()).thenReturn(null);

      final results = await service.updateAll();
      expect(results.length, 1);
    });
  });

  group('SubscriptionService provider-gate handling', () {
    test('returns traffic-limit message for metadata-only payload', () async {
      final dio = Dio();
      final payload = base64.encode(
        utf8.encode(
          'vless://11111111-1111-1111-1111-111111111111@0.0.0.0:1?security=&type=tcp#Traffic%20limit%20reached',
        ),
      );
      dio.httpClientAdapter = _FakeAdapter(
        statusCode: 200,
        body: payload,
        headers: {'content-type': ['text/plain; charset=utf-8']},
      );
      service = SubscriptionService(storage, dio: dio);

      when(() => storage.getSettings()).thenAnswer((_) async => const AppSettings());
      when(() => storage.getHwid()).thenReturn(null);
      when(() => storage.setHwid(any())).thenAnswer((_) async {});
      when(() => storage.getServers()).thenAnswer((_) async => <ServerItem>[]);
      when(() => storage.getActiveServerId()).thenReturn(null);

      expect(
        service.updateSubscription(
          const Subscription(id: 's1', name: 'S', url: 'https://example.com/sub'),
        ),
        completion(
          isA<UpdateResult>().having(
            (r) => r.error ?? '',
            'error',
            contains('traffic limit reached'),
          ),
        ),
      );
    });
  });

  group('SubscriptionService User-Agent handling', () {
    // в тестах PackageInfo недоступен → appUserAgent() падает в 'keqdroid'
    const appUaPrefix = 'keqdroid';

    late _UaGateAdapter adapter;

    // сервис с UA-зависимым фейк-адаптером; базовый браузерный UA как в
    // проде (_buildDio) — per-request UA обязан его переопределять
    SubscriptionService buildService(bool Function(String ua) isAllowed) {
      final dio = Dio(BaseOptions(headers: {
        'User-Agent': SubscriptionService.browserUserAgent,
      }));
      adapter = _UaGateAdapter(isAllowed: isAllowed);
      dio.httpClientAdapter = adapter;
      return SubscriptionService(storage, dio: dio);
    }

    setUp(() {
      when(() => storage.getSettings()).thenAnswer((_) async => const AppSettings());
      when(() => storage.getHwid()).thenReturn(null);
      when(() => storage.setHwid(any())).thenAnswer((_) async {});
      when(() => storage.getServers()).thenAnswer((_) async => <ServerItem>[]);
      when(() => storage.getActiveServerId()).thenReturn(null);
      when(() => storage.replaceServersBySubscription(any(), any()))
          .thenAnswer((_) async {});
      when(() => storage.upsertSubscription(any())).thenAnswer((_) async {});
    });

    test('first request goes with app UA and it is persisted on success',
        () async {
      service = buildService((ua) => ua.startsWith(appUaPrefix));

      final result = await service.updateSubscription(
        const Subscription(id: 's1', name: 'S', url: 'https://example.com/sub'),
      );

      expect(result.error, isNull);
      expect(result.success, isTrue);
      expect(result.serverCount, 1);
      // ровно один запрос, ушёл с UA приложения (не с базовым браузерным)
      expect(adapter.requestedUserAgents, hasLength(1));
      expect(adapter.requestedUserAgents.single, startsWith(appUaPrefix));
      expect(result.subscription.userAgent, startsWith(appUaPrefix));
    });

    test('falls back to client UA list when panel rejects app UA with 502',
        () async {
      // Regression: панели, маршрутизирующие по UA, отдают неизвестным UA
      // html-страницу подписки (её бэкенд может лежать → 502), а известным
      // клиентским — payload. UA-ретрай обязан жить и в error-ветке: dio
      // кидает на 502 до того, как успешная ветка (200+html) до него дойдёт.
      service = buildService((ua) => ua == 'v2rayNG/1.9.28');

      final result = await service.updateSubscription(
        const Subscription(id: 's1', name: 'S', url: 'https://example.com/sub'),
      );

      expect(result.error, isNull);
      expect(result.success, isTrue);
      expect(result.serverCount, 1);
      // userinfo берётся из ответа под сработавшим UA
      expect(result.subscription.usedBytes, 300);
      expect(result.subscription.totalBytes, 1024);
      // первым шёл UA приложения, повторно в переборе он не участвует
      expect(adapter.requestedUserAgents.first, startsWith(appUaPrefix));
      expect(
        adapter.requestedUserAgents
            .where((ua) => ua.startsWith(appUaPrefix))
            .length,
        1,
      );
      // сработавший UA сохранился в подписке
      expect(result.subscription.userAgent, 'v2rayNG/1.9.28');
    });

    test('saved UA is used for the first request without iteration', () async {
      service = buildService((ua) => ua == 'NekoBox/1.3.9');

      final result = await service.updateSubscription(
        const Subscription(
          id: 's1',
          name: 'S',
          url: 'https://example.com/sub',
          userAgent: 'NekoBox/1.3.9',
        ),
      );

      expect(result.error, isNull);
      expect(result.success, isTrue);
      expect(adapter.requestedUserAgents, ['NekoBox/1.3.9']);
      expect(result.subscription.userAgent, 'NekoBox/1.3.9');
    });

    test('re-iterates UA list when saved UA stopped working', () async {
      service = buildService((ua) => ua == 'v2rayNG/1.9.28');

      final result = await service.updateSubscription(
        const Subscription(
          id: 's1',
          name: 'S',
          url: 'https://example.com/sub',
          userAgent: 'NekoBox/1.3.9', // сохранённый UA, который панель перестала принимать
        ),
      );

      expect(result.error, isNull);
      expect(result.success, isTrue);
      // сломанный сохранённый UA пробуем ровно один раз, без повтора в переборе
      expect(adapter.requestedUserAgents.first, 'NekoBox/1.3.9');
      expect(
        adapter.requestedUserAgents.where((ua) => ua == 'NekoBox/1.3.9').length,
        1,
      );
      // новый рабочий UA перезаписал сохранённый
      expect(result.subscription.userAgent, 'v2rayNG/1.9.28');
    });
  });

  group('SubscriptionService._parseBody name extraction', () {
    test('keeps fragment names that contain spaces (and an inner #)', () {
      // Regression: a plain subscription where the #name has raw spaces, an emoji
      // flag and a second '#'. The old extractor regex stopped at the first space,
      // truncating the name to just the flag emoji, which cleanDisplayName then
      // stripped to an empty string. The full name must survive to displayName.
      const body =
          'vless://2289a6ad-c4b9-42b3-903e-082d77f4b0d2@176.108.245.184:25565'
          '?encryption=none&type=tcp&security=reality&sni=gp.x5.ru&fp=chrome'
          '#🇷🇺 Белый интернет #1 | Все операторы';

      final configs = SubscriptionService.parseBodyForTest(body);
      expect(configs.length, 1);

      final server = ServerItem.fromRaw(configs.first);
      expect(server.displayName, '🇷🇺 Белый интернет #1 | Все операторы');
      // cleanName drops the flag emoji but must NOT be empty.
      expect(server.cleanName, 'Белый интернет #1 | Все операторы');
      expect(server.countryCode, 'RU');
    });

    // Ключ сопоставления серверов при обновлении подписки. Ошибка здесь не
    // видна сразу: сервер просто теряет пинг, избранное и «активный».
    test('vmess-ссылка AEAD опознаётся по uuid, а не по одному адресу', () {
      const first = 'vmess://aaaaaaaa-1111-2222-3333-444444444444'
          '@1.2.3.4:443?type=tcp#one';
      const second = 'vmess://bbbbbbbb-1111-2222-3333-444444444444'
          '@1.2.3.4:443?type=tcp#two';

      final keyOne = SubscriptionService.stableKeyForTest(first);
      expect(keyOne, contains('aaaaaaaa-1111-2222-3333-444444444444'));
      expect(keyOne, isNot(SubscriptionService.stableKeyForTest(second)));
      // Имя и параметры меняются у провайдера постоянно — ключ не должен.
      expect(
        SubscriptionService.stableKeyForTest(
          'vmess://aaaaaaaa-1111-2222-3333-444444444444'
          '@1.2.3.4:443?type=ws&path=%2Fx#renamed',
        ),
        keyOne,
      );
    });

    // Решение хозяйки: первую версию Hysteria не поддерживаем. В списке она
    // выглядела рабочим сервером и молчала после подключения.
    test('Hysteria v1 в список не попадает, вторая под той же схемой попадает',
        () {
      const body = 'hysteria://1.2.3.4:443?auth=x&upmbps=100&downmbps=200#v1\n'
          'hysteria://pwd@5.6.7.8:443?sni=node.example&obfs=salamander'
          '&obfs-password=abc#v2';

      final configs = SubscriptionService.parseBodyForTest(body);
      expect(configs.length, 1);
      expect(configs.single, contains('obfs=salamander'));
    });

    test('splits two URIs that share one line instead of merging them', () {
      const body =
          'vless://aaaaaaaa-1111-2222-3333-444444444444@1.2.3.4:443?type=tcp#name one '
          'vmess://bbbbbbbb-1111-2222-3333-444444444444@5.6.7.8:80#name two';

      final configs = SubscriptionService.parseBodyForTest(body);
      expect(configs.length, 2);
      final names = configs.map((c) => ServerItem.fromRaw(c).displayName).toSet();
      expect(names, containsAll(<String>['name one', 'name two']));
    });
  });

  group('SubscriptionService._parseBody with Clash payloads', () {
    // Панель отдаёт такое, когда у подписки выставлена идентичность
    // clash-клиента. Узлы важнее профиля: их видно списком, между ними
    // переключаются, каждый пингуется — и они работают на любом ядре.
    const reality = '''
proxies:
  - name: "NL Reality"
    type: vless
    server: nl.example
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    network: tcp
    tls: true
    servername: www.example.org
    client-fingerprint: chrome
    flow: xtls-rprx-vision
    reality-opts:
      public-key: aGVsbG8gd29ybGQgaGVsbG8gd29ybGQgaGVsbG8gd28
      short-id: 0123abcd
proxy-groups:
  - name: Proxy
    type: select
    proxies: ["NL Reality"]
rules:
  - MATCH,Proxy
''';

    test('узел REALITY переживает перевод в ссылку целиком', () {
      // Ключ REALITY и отпечаток лежат ВЛОЖЕННЫМИ картами. Построчный сканер
      // их не видел, и ссылка собиралась «успешно» — без pbk, то есть
      // молча неподключаемая.
      final configs = SubscriptionService.parseBodyForTest(reality);
      expect(configs, hasLength(1));

      final uri = Uri.parse(configs.single);
      expect(uri.scheme, 'vless');
      expect(uri.host, 'nl.example');
      expect(uri.queryParameters['security'], 'reality');
      expect(uri.queryParameters['pbk'], isNotEmpty);
      expect(uri.queryParameters['sid'], '0123abcd');
      expect(uri.queryParameters['fp'], 'chrome');
      expect(uri.queryParameters['flow'], 'xtls-rprx-vision');
      expect(uri.queryParameters['sni'], 'www.example.org');
      // `type` у Clash — это протокол, а не транспорт: подставленный в
      // транспорт, он давал ссылку с несуществующим `type=vless`.
      expect(uri.queryParameters['type'], 'tcp');
    });

    test('узел type: hysteria пропускается, hysteria2 рядом переводится', () {
      // `type: hysteria` у Clash — всегда первая версия. Раньше ему
      // приписывался `version=2`, и он уезжал в ядро как hysteria2: конфиг не
      // того протокола и сервер, который не отвечает.
      const mixed = '''
proxies:
  - name: "old"
    type: hysteria
    server: v1.example
    port: 443
    auth_str: secret
    up: 100
    down: 200
  - name: "new"
    type: hysteria2
    server: v2.example
    port: 443
    password: secret
    sni: v2.example
proxy-groups:
  - name: Proxy
    type: select
    proxies: ["old", "new"]
rules:
  - MATCH,Proxy
''';
      final configs = SubscriptionService.parseBodyForTest(mixed);
      expect(configs, hasLength(1));
      expect(Uri.parse(configs.single).host, 'v2.example');
    });

    // Стадия 2: узлы этих типов у Clash молча выпадали — `_proxyMapToUri`
    // отвечал на них null, и в списке их просто не было.
    test('узлы tuic, anytls, ssr и mieru переводятся в ссылки', () {
      const profile = '''
proxies:
  - name: "T"
    type: tuic
    server: tuic.example
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    password: secret
    sni: tuic.example
    congestion-controller: bbr
    udp-relay-mode: quic
  - name: "A"
    type: anytls
    server: anytls.example
    port: 443
    password: anysecret
    sni: anytls.example
  - name: "R"
    type: ssr
    server: ssr.example
    port: 8388
    cipher: aes-256-cfb
    password: ssrsecret
    obfs: tls1.2_ticket_auth
    protocol: auth_aes128_md5
    obfs-param: cdn.example
  - name: "M"
    type: mieru
    server: mieru.example
    port: 2999
    transport: TCP
    username: mieruser
    password: mierupass
proxy-groups:
  - name: Proxy
    type: select
    proxies: ["T", "A", "R", "M"]
rules:
  - MATCH,Proxy
''';
      final configs = SubscriptionService.parseBodyForTest(profile);
      expect(configs, hasLength(4));

      final tuic = Uri.parse(configs[0]);
      expect(tuic.scheme, 'tuic');
      expect(tuic.userInfo, '11111111-2222-3333-4444-555555555555:secret');
      expect(tuic.queryParameters['congestion_control'], 'bbr');
      expect(tuic.queryParameters['udp_relay_mode'], 'quic');

      final anytls = Uri.parse(configs[1]);
      expect(anytls.scheme, 'anytls');
      expect(anytls.userInfo, 'anysecret');
      expect(anytls.queryParameters['sni'], 'anytls.example');

      final ssr = SsrLink.tryParse(configs[2])!;
      expect(ssr.host, 'ssr.example');
      expect(ssr.method, 'aes-256-cfb');
      expect(ssr.obfs, 'tls1.2_ticket_auth');
      expect(ssr.protocol, 'auth_aes128_md5');
      expect(ssr.obfsParam, 'cdn.example');
      expect(ssr.remarks, 'R');

      final mieru = MieruLink.tryParse(configs[3])!;
      expect(mieru.host, 'mieru.example');
      expect(mieru.port, 2999);
      expect(mieru.transport, 'TCP');
      expect(mieru.username, 'mieruser');
      expect(mieru.password, 'mierupass');
    });

    // То, что этап 1 научил понимать генераторы, обязано доезжать и через
    // перевод из Clash: иначе тот же сервер работает ссылкой и не работает
    // профилем.
    test('поля из вложенных блоков доезжают в ссылку', () {
      const profile = '''
proxies:
  - name: "WS"
    type: vless
    server: ws.example
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    tls: true
    servername: ws.example
    network: ws
    ws-opts:
      path: /ws
      max-early-data: 2048
      early-data-header-name: Sec-WebSocket-Protocol
      headers:
        Host: cdn.example
  - name: "MASQ"
    type: vmess
    server: masq.example
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    cipher: auto
    network: http
    http-opts:
      method: POST
      path:
        - /masq
      headers:
        Host:
          - masq.example
  - name: "PLUG"
    type: ss
    server: ss.example
    port: 8388
    cipher: aes-256-gcm
    password: sspass
    plugin: obfs
    plugin-opts:
      mode: http
      host: cdn.example
  - name: "HOP"
    type: hysteria2
    server: hop.example
    port: 443
    password: hoppass
    ports: 20000-20050
    hop-interval: 30
    fingerprint: QQ+WW/EE=
proxy-groups:
  - name: Proxy
    type: select
    proxies: ["WS", "MASQ", "PLUG", "HOP"]
rules:
  - MATCH,Proxy
''';
      final configs = SubscriptionService.parseBodyForTest(profile);
      expect(configs, hasLength(4));

      final ws = Uri.parse(configs[0]);
      expect(ws.queryParameters['ed'], '2048');
      expect(ws.queryParameters['eh'], 'Sec-WebSocket-Protocol');
      expect(ws.queryParameters['host'], 'cdn.example');

      // `network: http` у Clash — это маскировка поверх tcp. В vmess-json она
      // пишется `net: tcp` + `type: http`, а `net: http` оба генератора читают
      // как HTTP/2 — узел собирался не тем транспортом. Host у http-opts —
      // заголовок, а не поле.
      final masq = jsonDecode(utf8.decode(base64.decode(base64.normalize(
        configs[1].substring('vmess://'.length),
      )))) as Map<String, dynamic>;
      expect(masq['net'], 'tcp');
      expect(masq['type'], 'http');
      expect(masq['path'], '/masq');
      expect(masq['host'], 'masq.example');

      final ss = Uri.parse(configs[2]);
      expect(ss.queryParameters['plugin'],
          'obfs-local;obfs=http;obfs-host=cdn.example');

      final hop = Uri.parse(configs[3]);
      expect(hop.queryParameters['mport'], '20000-20050');
      expect(hop.queryParameters['hop-interval'], '30');
      expect(hop.queryParameters['pinSHA256'], 'QQ+WW/EE=');
    });

    // Ветка vmess собирала свой json мимо общих разборщиков и теряла то, что
    // vless и trojan переносят. Главное — имя gRPC-сервиса: без него vmess на
    // gRPC из Clash не подключался вовсе.
    test('vmess из Clash несёт то же, что vless: gRPC, sni, отпечаток, '
        'ранние данные', () {
      const profile = '''
proxies:
  - name: "GRPC"
    type: vmess
    server: grpc.example
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    alterId: 0
    cipher: aes-128-gcm
    tls: true
    servername: sni.example
    client-fingerprint: safari
    alpn: [h2]
    network: grpc
    grpc-opts:
      grpc-service-name: svc
  - name: "WS"
    type: vmess
    server: ws.example
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    cipher: auto
    tls: true
    servername: sni.example
    network: ws
    ws-opts:
      path: /ws
      max-early-data: 2048
      early-data-header-name: Sec-WebSocket-Protocol
      headers:
        Host: cdn.example
proxy-groups:
  - name: Proxy
    type: select
    proxies: ["GRPC", "WS"]
rules:
  - MATCH,Proxy
''';
      final configs = SubscriptionService.parseBodyForTest(profile);
      expect(configs, hasLength(2));
      Map<String, dynamic> json(String link) => jsonDecode(utf8.decode(
            base64.decode(base64.normalize(link.substring('vmess://'.length))),
          )) as Map<String, dynamic>;

      final grpc = json(configs[0]);
      expect(grpc['net'], 'grpc');
      expect(grpc['path'], 'svc');
      expect(grpc['scy'], 'aes-128-gcm');
      expect(grpc['sni'], 'sni.example');
      expect(grpc['fp'], 'safari');
      expect(grpc['alpn'], 'h2');

      final ws = json(configs[1]);
      expect(ws['host'], 'cdn.example');
      expect(ws['sni'], 'sni.example');
      expect(ws['path'], '/ws?ed=2048');

      // И до ядра: имя сервиса доезжает до grpc-opts mihomo.
      Socks5Credentials().init('u', 'p');
      final proxy = (MihomoConfigGen.build(
        configs[0],
        const AppSettings(),
        socksPort: 2080,
      )['proxies'] as List)
          .first as Map;
      expect((proxy['grpc-opts'] as Map)['grpc-service-name'], 'svc');
      expect(proxy['servername'], 'sni.example');
    });

    test('vmess с REALITY из Clash — в пропущенных: его не соберёт никто', () {
      const profile = '''
proxies:
  - name: "R"
    type: vmess
    server: r.example
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    cipher: auto
    tls: true
    reality-opts:
      public-key: pbk
proxy-groups:
  - name: Proxy
    type: select
    proxies: ["R"]
rules:
  - MATCH,Proxy
''';
      expect(SubscriptionService.unsupportedClashNodes(profile), {'vmess': 1});
    });

    // `spx` — это spiderX у REALITY, а у Clash такого поля нет вовсе. Туда
    // уезжал флаг постквантового ключа, то есть в ядро ехал мусор.
    test('флаг постквантового ключа не выдаётся за spiderX', () {
      const profile = '''
proxies:
  - name: "R"
    type: vless
    server: r.example
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    tls: true
    reality-opts:
      public-key: aGVsbG8gd29ybGQgaGVsbG8gd29ybGQgaGVsbG8gd28
      short-id: 0123abcd
      support-x25519mlkem768: true
proxy-groups:
  - name: Proxy
    type: select
    proxies: ["R"]
rules:
  - MATCH,Proxy
''';
      final uri = Uri.parse(SubscriptionService.parseBodyForTest(profile).single);
      expect(uri.queryParameters['pbk'], isNotEmpty);
      expect(uri.queryParameters.containsKey('spx'), isFalse);
    });

    // Узел неизвестного типа исчезал молча: подписка на 20 серверов приезжала
    // как 12, и спросить было не о чем.
    test('узлы, которых мы не умеем, считаются по типам', () {
      const profile = '''
proxies:
  - name: "ok"
    type: vless
    server: ok.example
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
  - name: "s1"
    type: snell
    server: s1.example
    port: 443
    psk: x
  - name: "s2"
    type: snell
    server: s2.example
    port: 443
    psk: y
  - name: "w"
    type: wireguard
    server: w.example
    port: 51820
    private-key: k
proxy-groups:
  - name: Proxy
    type: select
    proxies: ["ok", "s1", "s2", "w"]
rules:
  - MATCH,Proxy
''';
      expect(SubscriptionService.parseBodyForTest(profile), hasLength(1));
      expect(
        SubscriptionService.unsupportedClashNodes(profile),
        {'snell': 2, 'wireguard': 1},
      );
    });

    test('когда всё разобралось, пропущенных нет', () {
      const profile = '''
proxies:
  - name: "ok"
    type: vless
    server: ok.example
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
proxy-groups:
  - name: Proxy
    type: select
    proxies: ["ok"]
rules:
  - MATCH,Proxy
''';
      expect(SubscriptionService.unsupportedClashNodes(profile), isEmpty);
    });

    test('профиль без разбираемых узлов остаётся конфигом целиком', () {
      // Узлы приходят из `proxy-providers` (в сеть за ними мы не ходим), но
      // сам конфиг рабочий — его исполнит mihomo, как написал автор.
      const providerProfile = '''
proxies:
  - name: "direct-ish"
    type: socks5
    server: 198.51.100.9
    port: 1080
proxy-groups:
  - name: Proxy
    type: select
    use: ["provider-a"]
proxy-providers:
  provider-a:
    type: http
    url: "https://example.invalid/nodes.yaml"
    interval: 3600
rules:
  - MATCH,Proxy
''';
      final configs = SubscriptionService.parseBodyForTest(providerProfile);
      expect(configs, hasLength(1));

      final server = ServerItem.fromRaw(configs.single);
      expect(server.protocol, 'clash');
      expect(server.address, '198.51.100.9');
      // Авторские правила и провайдеры доезжают до сервера как есть.
      expect(server.config, contains('proxy-providers'));
    });

    // Ровно то, что панели отдают clash-клиентам чаще всего: ни одного
    // `proxies`, весь список узлов за ссылкой. Раньше такая подписка
    // отказывалась обновляться с «Unsupported subscription format: Clash YAML»
    // — при том, что Clash приложение как раз исполняет.
    const providersOnly = '''
mixed-port: 7890
proxy-providers:
  main:
    type: http
    url: "https://example.invalid/nodes.yaml"
    interval: 3600
    path: ./providers/main.yaml
proxy-groups:
  - name: "🚀 Proxy"
    type: select
    use: ["main"]
rules:
  - MATCH,🚀 Proxy
''';

    test('профиль целиком из proxy-providers принимается сервером', () {
      final configs = SubscriptionService.parseBodyForTest(providersOnly);
      expect(configs, hasLength(1));

      final server = ServerItem.fromRaw(configs.single);
      expect(server.protocol, 'clash');
      // Своего адреса у такого профиля нет и быть не может — список ещё не
      // скачан. Это не болванка, и отказывать по этому признаку нельзя.
      expect(server.address, isEmpty);
      expect(server.config, contains('proxy-providers'));
    });

    // Без групп правилу некуда указывать: `primaryTarget` вернул бы DIRECT, то
    // есть подключение «работает», а прокси нет. Лучше отказ с причиной.
    test('провайдеры без групп — отказ, и причина названа', () {
      const noGroups = '''
proxy-providers:
  main:
    type: http
    url: "https://example.invalid/nodes.yaml"
''';
      expect(
        () => SubscriptionService.parseBodyForTest(noGroups),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(contains('proxy-groups'), isNot(contains('Unsupported'))),
        )),
      );
    });

    test('битый YAML объясняется сообщением парсера', () {
      const broken = '''
proxies:
  - name: "a
    type: vless
''';
      expect(
        () => SubscriptionService.parseBodyForTest(broken),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(contains('Clash subscription'), contains('YAML')),
        )),
      );
    });
  });

  group('SubscriptionService._parseBody with ready-made core configs', () {
    // Провайдеры отдают не только списки ссылок, но и «сервера с готовым
    // роутингом» — конфиг xray целиком, имя в корневом `remarks` (v2rayNG).
    const custom = '{"remarks": "🇳🇱 Обход - Нидерланды", '
        '"routing": {"rules": [{"type": "field", "protocol": ["bittorrent"], '
        '"outboundTag": "direct"}]}, '
        '"outbounds": [{"tag": "proxy", "protocol": "vless", "settings": '
        '{"vnext": [{"address": "nl1.example.com", "port": 443}]}}]}';

    test('takes a whole json config as one server', () {
      final configs = SubscriptionService.parseBodyForTest(custom);
      expect(configs.length, 1);

      final server = ServerItem.fromRaw(configs.single);
      expect(server.protocol, 'custom');
      expect(server.displayName, '🇳🇱 Обход - Нидерланды');
      expect(server.address, 'nl1.example.com');
      // Авторский роутинг доезжает до сервера как есть — в нём весь смысл.
      expect(server.config, contains('bittorrent'));
    });

    test('takes a json array as several servers', () {
      final configs = SubscriptionService.parseBodyForTest('[$custom,$custom]');
      expect(configs.length, 2);
    });

    test('unwraps a base64 payload with a json config', () {
      final body = base64.encode(utf8.encode(custom));
      final configs = SubscriptionService.parseBodyForTest(body);
      expect(configs.length, 1);
      expect(ServerItem.fromRaw(configs.single).protocol, 'custom');
    });

    test('handles a mixed payload: links and per-line json configs', () {
      final body = [
        'vless://aaaaaaaa-1111-2222-3333-444444444444@1.2.3.4:443#link',
        base64.encode(utf8.encode(custom)),
      ].join('\n');

      final configs = SubscriptionService.parseBodyForTest(body);
      expect(configs.length, 2);
      final protocols =
          configs.map((c) => ServerItem.fromRaw(c).protocol).toSet();
      expect(protocols, containsAll(<String>['vless', 'custom']));
    });

    test('refuses a provider stub instead of adding a dead server', () {
      // Панель отдаёт валидный конфиг ядра без сервера (истёкшая подписка,
      // непривязанный HWID). Такой «сервер» подключался бы молча мимо туннеля,
      // поэтому обновление должно падать, и падать понятно.
      const stub = '{"remarks": "Subscription", "outbounds": '
          '[{"tag": "direct", "protocol": "freedom"}]}';
      expect(
        () => SubscriptionService.parseBodyForTest(stub),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('without a server address'), contains('stub')),
          ),
        ),
      );
    });

    test('an outbound with an empty vnext is a stub too', () {
      const stub = '{"outbounds": [{"tag": "proxy", "protocol": "vless", '
          '"settings": {"vnext": []}}]}';
      expect(
        () => SubscriptionService.parseBodyForTest(stub),
        throwsA(isA<FormatException>()),
      );
    });

    test('takes a sing-box config apart into the servers it holds', () {
      const singbox = '{"inbounds": [{"type": "tun"}], "outbounds": ['
          '{"type": "vless", "tag": "nl", "server": "nl1.example.com", '
          '"server_port": 443, "uuid": "00000000-0000-4000-8000-000000000000"}, '
          '{"type": "direct", "tag": "direct"}]}';
      expect(SubscriptionService.parseBodyForTest(singbox), [
        'vless://00000000-0000-4000-8000-000000000000@nl1.example.com:443#nl',
      ]);
    });

    // Раньше отказ был на весь формат, теперь — только когда брать нечего, и
    // тогда в тексте видно, каких узлов мы не умеем.
    test('a sing-box config with nothing to run says what it held', () {
      const singbox = '{"inbounds": [{"type": "tun"}], "outbounds": ['
          '{"type": "vless", "server": "nl1.example.com", "server_port": 443}, '
          '{"type": "ssh", "tag": "s", "server": "nl2.example.com", '
          '"server_port": 22}]}';
      expect(
        () => SubscriptionService.parseBodyForTest(singbox),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('sing-box'), contains('ssh')),
          ),
        ),
      );
    });

    test('digs a json config out of a subscription served as an HTML page',
        () async {
      // Часть панелей отдаёт подписку страницей, а payload лежит в <pre>. Из
      // html доставались только ссылки, и конфиг целиком терялся.
      const custom = '{"remarks": "NL page", "outbounds": [{"tag": "proxy", '
          '"protocol": "vless", "settings": {"vnext": [{"address": '
          '"nl1.example.com", "port": 443}]}}]}';
      final dio = Dio();
      dio.httpClientAdapter = _FakeAdapter(
        statusCode: 200,
        body: '<html><body><h1>Subscription</h1><pre>$custom</pre></body></html>',
        headers: {'content-type': ['text/html; charset=utf-8']},
      );
      service = SubscriptionService(storage, dio: dio);

      when(() => storage.getSettings()).thenAnswer((_) async => const AppSettings());
      when(() => storage.getHwid()).thenReturn(null);
      when(() => storage.setHwid(any())).thenAnswer((_) async {});

      final result = await service.fetchRaw('https://example.com/sub');
      expect(result.configs.length, 1);

      final server = ServerItem.fromRaw(result.configs.single);
      expect(server.protocol, 'custom');
      expect(server.displayName, 'NL page');
      expect(server.address, 'nl1.example.com');
    });
  });
}

/// payload — только UA, прошедшим [isAllowed]; остальным 502 (nginx-заглушка).
class _UaGateAdapter implements HttpClientAdapter {
  _UaGateAdapter({required this.isAllowed});

  final bool Function(String ua) isAllowed;
  final requestedUserAgents = <String>[];

  static final _payload = base64.encode(
    utf8.encode(
      'vless://22222222-2222-2222-2222-222222222222@1.2.3.4:443?security=reality&type=tcp#Node',
    ),
  );

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final ua = options.headers['User-Agent'] as String? ?? '';
    requestedUserAgents.add(ua);
    if (!isAllowed(ua)) {
      return ResponseBody.fromString(
        '<html><head><title>502 Bad Gateway</title></head>'
        '<body><center><h1>502 Bad Gateway</h1></center><hr><center>nginx</center></body></html>',
        502,
        headers: {
          'content-type': ['text/html'],
        },
      );
    }
    return ResponseBody.fromString(
      _payload,
      200,
      headers: {
        'content-type': ['text/plain; charset=utf-8'],
        'subscription-userinfo': ['upload=100; download=200; total=1024; expire=1788520373'],
      },
    );
  }
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({
    required this.statusCode,
    required this.body,
    this.headers = const <String, List<String>>{},
  });

  final int statusCode;
  final String body;
  final Map<String, List<String>> headers;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: headers,
    );
  }
}

