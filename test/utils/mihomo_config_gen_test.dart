import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/tunnel/app_routing_mode.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';
import 'package:keqdroid/utils/tls_fingerprint.dart';

Map<String, dynamic> _proxy(Map<String, dynamic> config) =>
    (config['proxies'] as List).cast<Map<String, dynamic>>().single;

List<String> _rules(Map<String, dynamic> config) =>
    (config['rules'] as List).cast<String>();

/// `download-settings` у xhttp-ссылки [link] с таким [extra].
Map<String, dynamic> _download(String link, String extra) =>
    (_proxy(MihomoConfigGen.build(
      '$link&extra=${Uri.encodeQueryComponent(extra)}',
      const AppSettings(),
      socksPort: 2080,
    ))['xhttp-opts'] as Map)['download-settings'] as Map<String, dynamic>;

void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  const settings = AppSettings(
    directRules: 'vk.com, geosite:category-ru, 10.8.0.0/24, geoip:ru',
    proxyRules: 'youtube.com',
    blockedRules: 'doubleclick.net',
  );

  group('инбаунд', () {
    test('слушает только петлю и требует те же креды, что ждёт приложение', () {
      final c = MihomoConfigGen.build(
        'vless://uuid@example.com:443?type=tcp&security=none',
        const AppSettings(),
        socksPort: 2080,
      );
      expect(c['socks-port'], 2080);
      expect(c['bind-address'], '127.0.0.1');
      expect(c['allow-lan'], isFalse);
      expect(c['authentication'], ['u:p']);
    });

    test('noauth-режим не пишет authentication вовсе', () {
      final c = MihomoConfigGen.build(
        'vless://uuid@example.com:443?type=tcp&security=none',
        const AppSettings(),
        socksPort: 2080,
        localInboundsNoAuth: true,
      );
      expect(c.containsKey('authentication'), isFalse);
    });

    // Ядро иначе полезет в сеть за своими копиями баз ещё до туннеля.
    test('geo берётся из вшитых баз, без автообновления', () {
      final c = MihomoConfigGen.build(
        'vless://uuid@example.com:443?type=tcp&security=none',
        const AppSettings(),
        socksPort: 2080,
      );
      expect(c['geodata-mode'], isTrue);
      expect(c['geo-auto-update'], isFalse);
    });

    test('log-level none у mihomo называется silent', () {
      final c = MihomoConfigGen.build(
        'vless://uuid@example.com:443?type=tcp&security=none',
        const AppSettings(xrayCore: XrayCoreSettings(logLevel: 'none')),
        socksPort: 2080,
      );
      expect(c['log-level'], 'silent');
    });
  });

  group('прокси', () {
    test('vcn переносится в name-cert-verify, одиночный pcs — в fingerprint', () {
      // То же, что делает xray-генератор со своими `verifyPeerCertByName` и
      // `pinnedPeerCertSha256`: у ядра эта настройка описана как «меняет только
      // цель проверки DNSName, не трогая SNI».
      final p = _proxy(MihomoConfigGen.build(
        'vless://uuid@vps1.example.org:8443?type=tcp&security=tls'
        '&sni=spotify.com&vcn=vps1.example.org'
        '&pcs=c88234050d72a3e9430ec7738636806deaf85c3708fee0fd9202ebd917e2c843',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['servername'], 'spotify.com');
      expect(p['name-cert-verify'], 'vps1.example.org');
      expect(
        p['fingerprint'],
        'c88234050d72a3e9430ec7738636806deaf85c3708fee0fd9202ebd917e2c843',
      );
    });

    test('несколько отпечатков в pcs не пиним вовсе', () {
      // `fingerprint` у ядра — одна строка, а какой из отпечатков относится к
      // листу цепочки, из ссылки не видно. Взятый наугад чужой отпечаток
      // закрыл бы соединение совсем.
      final p = _proxy(MihomoConfigGen.build(
        'vless://uuid@vps1.example.org:8443?type=tcp&security=tls'
        '&sni=spotify.com&vcn=vps1.example.org'
        '&pcs=c88234050d72a3e9430ec7738636806deaf85c3708fee0fd9202ebd917e2c843'
        '%2Ca2372d06431e9716365eeed47ec020351497d182fcc038e457e58168a03cac07',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['name-cert-verify'], 'vps1.example.org');
      expect(p.containsKey('fingerprint'), isFalse);
    });

    test('у reality пиннинга сертификата не появляется', () {
      // Сертификат там подставной, подлинность сервера проверяет сам REALITY.
      final p = _proxy(MihomoConfigGen.build(
        'vless://uuid@nl.example:443?type=tcp&security=reality&sni=decoy.example'
        '&pbk=publickey&sid=aabb&vcn=nl.example&pcs=deadbeef',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p.containsKey('name-cert-verify'), isFalse);
      expect(p.containsKey('fingerprint'), isFalse);
    });

    test('vless + reality + vision', () {
      final p = _proxy(MihomoConfigGen.build(
        'vless://uuid@nl.example:443?type=tcp&security=reality&sni=decoy.example'
        '&pbk=publickey&sid=aabb&fp=chrome&flow=xtls-rprx-vision',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['type'], 'vless');
      expect(p['server'], 'nl.example');
      expect(p['port'], 443);
      expect(p['uuid'], 'uuid');
      expect(p['tls'], isTrue);
      expect(p['servername'], 'decoy.example');
      expect(p['flow'], 'xtls-rprx-vision');
      expect(p['reality-opts'], {'public-key': 'publickey', 'short-id': 'aabb'});
      expect(p['network'], 'tcp');
      // Без UDP через SOCKS5 ядро молча отбросит UDP-сессии.
      expect(p['udp'], isTrue);
    });

    // У mihomo пустой client-fingerprint значит «без uTLS», а не chrome, как у
    // xray, — поэтому подставляем явно, и тот же, что xray-генератор
    // (`defaultTlsFingerprint`).
    test('vless без fp получает firefox', () {
      final p = _proxy(MihomoConfigGen.build(
        'vless://uuid@e.example:443?type=tcp&security=tls&sni=e.example',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['client-fingerprint'], 'firefox');
    });

    test('vmess и trojan без fp получают тот же firefox', () {
      final vmess = base64.encode(utf8.encode(jsonEncode({
        'v': '2',
        'add': 'v.example',
        'port': '443',
        'id': 'uuid',
        'aid': '0',
        'net': 'tcp',
        'tls': 'tls',
        'sni': 'v.example',
      })));
      final v = _proxy(MihomoConfigGen.build(
        'vmess://$vmess',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(v['client-fingerprint'], 'firefox');

      final t = _proxy(MihomoConfigGen.build(
        'trojan://password@t.example:443?sni=t.example&type=tcp',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(t['client-fingerprint'], 'firefox');
    });

    // Живая ссылка провайдера: mihomo постквантовое шифрование VLESS умеет
    // (`encryption` в proxies, разбор тот же, что у xray), но пока мы это поле
    // выбрасывали, ядро подключалось открытым VLESS и сервер рвал соединение.
    test('vless переносит постквантовое шифрование', () {
      const encryption =
          'mlkem768x25519plus.xorpub.0rtt.TQWG00S9SOQfvBRqDpXGzHBAagxTkExzd';
      final p = _proxy(MihomoConfigGen.build(
        'vless://uuid@e.example:443?type=tcp&security=tls&sni=e.example'
        '&encryption=$encryption',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['encryption'], encryption);
    });

    test('encryption=none в конфиг не попадает', () {
      final p = _proxy(MihomoConfigGen.build(
        'vless://uuid@e.example:443?type=tcp&security=tls&sni=e.example'
        '&encryption=none',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p.containsKey('encryption'), isFalse);
    });

    test('vless + ws переносит path и Host', () {
      final p = _proxy(MihomoConfigGen.build(
        'vless://uuid@w.example:443?type=ws&security=tls&sni=w.example'
        '&path=%2Fpath&host=w.example',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['network'], 'ws');
      expect(p['ws-opts'], {
        'path': '/path',
        'headers': {'Host': 'w.example'},
      });
    });

    test('vless + grpc', () {
      final p = _proxy(MihomoConfigGen.build(
        'vless://uuid@g.example:443?type=grpc&security=tls&serviceName=svc',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['network'], 'grpc');
      expect(p['grpc-opts'], {'grpc-service-name': 'svc'});
    });

    test('vmess из base64-json', () {
      final payload = base64.encode(utf8.encode(jsonEncode({
        'v': '2',
        'add': 'v.example',
        'port': '443',
        'id': '11111111-1111-1111-1111-111111111111',
        'aid': '0',
        'net': 'ws',
        'tls': 'tls',
        'sni': 'v.example',
        'path': '/vmess',
        'host': 'v.example',
      })));
      final p = _proxy(MihomoConfigGen.build(
        'vmess://$payload',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['type'], 'vmess');
      expect(p['server'], 'v.example');
      expect(p['port'], 443);
      expect(p['alterId'], 0);
      expect(p['cipher'], 'auto');
      expect(p['tls'], isTrue);
      expect(p['network'], 'ws');
      expect((p['ws-opts'] as Map)['path'], '/vmess');
    });

    test('trojan', () {
      final p = _proxy(MihomoConfigGen.build(
        'trojan://secret@t.example:8443?sni=t.example',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['type'], 'trojan');
      expect(p['password'], 'secret');
      expect(p['sni'], 't.example');
    });

    test('shadowsocks sip002', () {
      final userInfo = base64.encode(utf8.encode('aes-256-gcm:pass'));
      final p = _proxy(MihomoConfigGen.build(
        'ss://$userInfo@s.example:8388#node',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['type'], 'ss');
      expect(p['server'], 's.example');
      expect(p['port'], 8388);
      expect(p['cipher'], 'aes-256-gcm');
      expect(p['password'], 'pass');
    });

    test('hysteria2 с obfs', () {
      final p = _proxy(MihomoConfigGen.build(
        'hysteria2://token@hy.example:443?sni=hy.example&obfs=salamander'
        '&obfs-password=xyz&up=50&down=200',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['type'], 'hysteria2');
      expect(p['password'], 'token');
      expect(p['obfs'], 'salamander');
      expect(p['obfs-password'], 'xyz');
      expect(p['up'], '50');
      expect(p['down'], '200');
    });

    // Тот же принцип, что и у xray: доверять любому сертификату мы не даём.
    test('insecure=1 не превращается в skip-cert-verify', () {
      final p = _proxy(MihomoConfigGen.build(
        'vless://uuid@e.example:443?type=tcp&security=tls&insecure=1',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p.containsKey('skip-cert-verify'), isFalse);
    });

    test('незнакомый протокол — внятная ошибка без самой ссылки', () {
      expect(
        () => MihomoConfigGen.build(
          'wireguard://secret@w.example:51820',
          const AppSettings(),
          socksPort: 2080,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message.toString(),
          'message',
          allOf(contains('wireguard'), isNot(contains('secret'))),
        )),
      );
    });
  });

  group('транспорт', () {
    // Из-за молчаливого отката на tcp сервер на xhttp отвечал так, будто дело
    // в ключах REALITY: ядро поднималось, конфиг был «валидным», а описывал
    // другой сервер.
    test('xhttp переносится целиком, а не сводится к tcp', () {
      final p = _proxy(MihomoConfigGen.build(
        'vless://uuid@x.example:443?type=xhttp&security=reality'
        '&pbk=key&sid=ab&sni=cdn.example&mode=auto&path=%2Fpath'
        '&x_padding_bytes=92-1412',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['network'], 'xhttp');
      expect(p['xhttp-opts'], {
        'path': '/path',
        'mode': 'auto',
        'x-padding-bytes': '92-1412',
      });
    });

    test('splithttp — то же самое под старым именем', () {
      final p = _proxy(MihomoConfigGen.build(
        'vless://uuid@x.example:443?type=splithttp&security=tls&sni=x.example',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['network'], 'xhttp');
      expect((p['xhttp-opts'] as Map)['path'], '/');
    });

    test('extra отдаёт то, чего нет в query, вместе с xmux', () {
      const extra = '{"mode":"packet-up","xPaddingBytes":"100-1000",'
          '"xmux":{"maxConcurrency":"16-32","hKeepAlivePeriod":45}}';
      final p = _proxy(MihomoConfigGen.build(
        'vless://uuid@x.example:443?type=xhttp&security=tls&sni=x.example'
        '&extra=${Uri.encodeQueryComponent(extra)}',
        const AppSettings(),
        socksPort: 2080,
      ));
      final opts = p['xhttp-opts'] as Map;
      expect(opts['mode'], 'packet-up');
      expect(opts['x-padding-bytes'], '100-1000');
      // hKeepAlivePeriod у mihomo число, остальное — строки: они принимают
      // диапазоны вида `16-32`.
      expect(opts['reuse-settings'],
          {'max-concurrency': '16-32', 'h-keep-alive-period': 45});
    });

    // Живая подписка: узел «белые списки» работал на xray и не работал на
    // mihomo. Вид запроса описан в `extra` — где номер сессии, где счётчик,
    // каким методом и куда уходят данные вверх; пока мы это выбрасывали,
    // mihomo слал запрос своего вида, и сервер отвечал 400.
    test('extra переносит форму запроса целиком', () {
      const extra = '{"seqKey":"offset","seqPlacement":"query",'
          '"sessionKey":"media_sid","sessionPlacement":"cookie",'
          '"uplinkHTTPMethod":"GET","uplinkDataPlacement":"header",'
          '"uplinkDataKey":"X-Playback-Token","noGRPCHeader":true}';
      final p = _proxy(MihomoConfigGen.build(
        'vless://uuid@x.example:443?type=xhttp&security=tls&sni=x.example'
        '&path=%2Fupload%2F&mode=packet-up'
        '&extra=${Uri.encodeQueryComponent(extra)}',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['xhttp-opts'], {
        'path': '/upload/',
        'mode': 'packet-up',
        'uplink-http-method': 'GET',
        'uplink-data-placement': 'header',
        'uplink-data-key': 'X-Playback-Token',
        'session-placement': 'cookie',
        'session-key': 'media_sid',
        'seq-placement': 'query',
        'seq-key': 'offset',
        'no-grpc-header': true,
      });
    });

    // Второе написание тех же настроек: панели пишут то `sessionKey`, то
    // `sessionIDKey`, xray понимает оба.
    test('extra принимает sessionID-написание', () {
      const extra = '{"sessionIDKey":"sid","sessionIDPlacement":"query",'
          '"sessionIDTable":"Base62","sessionIDLength":"16-32"}';
      final opts = _proxy(MihomoConfigGen.build(
        'vless://uuid@x.example:443?type=xhttp&security=tls&sni=x.example'
        '&extra=${Uri.encodeQueryComponent(extra)}',
        const AppSettings(),
        socksPort: 2080,
      ))['xhttp-opts'] as Map;
      expect(opts['session-key'], 'sid');
      expect(opts['session-placement'], 'query');
      expect(opts['session-table'], 'Base62');
      expect(opts['session-length'], '16-32');
    });

    // Тот самый узел «белые списки»: ссылка включает обфускацию набивки и
    // больше ничего про неё не говорит. xray в этом режиме шлёт заголовок
    // `X-Padding`, сервер набивку проверяет и запрос без неё отвергает, а
    // mihomo без явного размещения не набивает вовсе.
    test('обфускация набивки получает дефолты xray', () {
      const extra = '{"xPaddingObfsMode":true}';
      final opts = _proxy(MihomoConfigGen.build(
        'vless://uuid@x.example:443?type=xhttp&security=tls&sni=x.example'
        '&extra=${Uri.encodeQueryComponent(extra)}',
        const AppSettings(),
        socksPort: 2080,
      ))['xhttp-opts'] as Map;
      expect(opts['x-padding-obfs-mode'], isTrue);
      expect(opts['x-padding-placement'], 'queryInHeader');
      expect(opts['x-padding-header'], 'X-Padding');
      expect(opts['x-padding-key'], 'x_padding');
    });

    test('своё размещение набивки дефолтами не перебивается', () {
      const extra = '{"xPaddingObfsMode":true,"xPaddingPlacement":"header",'
          '"xPaddingHeader":"X-Api-Key","xPaddingMethod":"tokenish",'
          '"xPaddingBytes":"50-150"}';
      final opts = _proxy(MihomoConfigGen.build(
        'vless://uuid@x.example:443?type=xhttp&security=tls&sni=x.example'
        '&extra=${Uri.encodeQueryComponent(extra)}',
        const AppSettings(),
        socksPort: 2080,
      ))['xhttp-opts'] as Map;
      expect(opts['x-padding-placement'], 'header');
      expect(opts['x-padding-header'], 'X-Api-Key');
      expect(opts['x-padding-method'], 'tokenish');
      expect(opts['x-padding-bytes'], '50-150');
      // ключ ссылка не назвала — его дописываем сами.
      expect(opts['x-padding-key'], 'x_padding');
    });

    test('без обфускации набивку размещать нечем — дефолтов не появляется', () {
      final opts = _proxy(MihomoConfigGen.build(
        'vless://uuid@x.example:443?type=xhttp&security=tls&sni=x.example'
        '&x_padding_bytes=100-1000',
        const AppSettings(),
        socksPort: 2080,
      ))['xhttp-opts'] as Map;
      expect(opts['x-padding-bytes'], '100-1000');
      expect(opts.containsKey('x-padding-placement'), isFalse);
      expect(opts.containsKey('x-padding-header'), isFalse);
    });

    // Панели кладут эти поля и внутрь `xmux`, и рядом с ним.
    test('reuse-settings собирается и из полей рядом с xmux', () {
      const extra = '{"hKeepAlivePeriod":30,"hMaxRequestTimes":"600-900",'
          '"hMaxReusableSecs":1800}';
      final opts = _proxy(MihomoConfigGen.build(
        'vless://uuid@x.example:443?type=xhttp&security=tls&sni=x.example'
        '&extra=${Uri.encodeQueryComponent(extra)}',
        const AppSettings(),
        socksPort: 2080,
      ))['xhttp-opts'] as Map;
      expect(opts['reuse-settings'], {
        'h-max-request-times': '600-900',
        'h-max-reusable-secs': '1800',
        'h-keep-alive-period': 30,
      });
    });

    test('свои заголовки запроса из extra переносятся', () {
      const extra = '{"headers":{"X-Token":"abc"}}';
      final opts = _proxy(MihomoConfigGen.build(
        'vless://uuid@x.example:443?type=xhttp&security=tls&sni=x.example'
        '&extra=${Uri.encodeQueryComponent(extra)}',
        const AppSettings(),
        socksPort: 2080,
      ))['xhttp-opts'] as Map;
      expect(opts['headers'], {'X-Token': 'abc'});
    });

    // Закачка идёт REALITY напрямую, скачивание — обычным TLS через CDN.
    // Незаданное mihomo берёт у основного подключения, так что без явных
    // полей скачивание ушло бы с его REALITY и SNI.
    test('downloadSettings: скачивание через CDN не наследует основное', () {
      const extra = '{"downloadSettings":{"address":"cdn.example","port":443,'
          '"network":"xhttp","security":"tls",'
          '"tlsSettings":{"serverName":"front.example","alpn":["h2"]},'
          '"xhttpSettings":{"path":"/down","host":"front.example"}}}';
      final ds = _download(
        'vless://uuid@x.example:443?type=xhttp&security=reality'
        '&sni=decoy.example&pbk=publickey&sid=aabb&path=%2Fup',
        extra,
      );
      expect(ds, {
        'server': 'cdn.example',
        'port': 443,
        'tls': true,
        'host': 'front.example',
        'path': '/down',
        'reality-opts': {'public-key': ''},
        'fingerprint': '',
        'name-cert-verify': '',
        'servername': 'front.example',
        'client-fingerprint': 'firefox',
        'alpn': ['h2'],
      });
    });

    test('downloadSettings: скачивание через REALITY получает свои ключи', () {
      const extra = '{"downloadSettings":{"address":"direct.example",'
          '"port":8443,"security":"reality","realitySettings":'
          '{"serverName":"decoy.example","publicKey":"pk","shortId":"cd",'
          '"fingerprint":"safari"}}}';
      final ds = _download(
        'vless://uuid@cdn.example:443?type=xhttp&security=tls'
        '&sni=cdn.example&pcs=aabb',
        extra,
      );
      expect(ds['reality-opts'], {'public-key': 'pk', 'short-id': 'cd'});
      expect(ds['servername'], 'decoy.example');
      expect(ds['client-fingerprint'], 'safari');
      // Пин основного — к его сертификату, у скачивания сертификат чужой.
      expect(ds['fingerprint'], '');
      expect(ds['path'], '/');
    });

    test('downloadSettings без serverName: SNI — адрес скачивания', () {
      const extra = '{"downloadSettings":{"address":"dl.example","port":443,'
          '"security":"tls"}}';
      final ds = _download(
        'vless://uuid@x.example:443?type=xhttp&security=tls&sni=x.example',
        extra,
      );
      expect(ds['servername'], 'dl.example');
      expect(ds['host'], '');
      expect(ds['client-fingerprint'], 'firefox');
    });

    // Без явных tls: false и пустого ключа mihomo унаследовал бы REALITY
    // основного и не поднялся бы вовсе: REALITY без TLS не бывает.
    test('downloadSettings без TLS снимает REALITY основного', () {
      const extra =
          '{"downloadSettings":{"address":"plain.example","port":80}}';
      final ds = _download(
        'vless://uuid@x.example:443?type=xhttp&security=reality'
        '&sni=decoy.example&pbk=publickey&sid=aabb',
        extra,
      );
      expect(ds['tls'], isFalse);
      expect(ds['reality-opts'], {'public-key': ''});
      expect(ds.containsKey('servername'), isFalse);
    });

    test('downloadSettings: свой пин скачивания переносится, если он один', () {
      const extra = '{"downloadSettings":{"address":"dl.example","port":443,'
          '"security":"tls","tlsSettings":{"pinnedPeerCertSha256":"ab12",'
          '"verifyPeerCertByName":"real.example"}}}';
      final ds = _download(
        'vless://uuid@x.example:443?type=xhttp&security=tls&sni=x.example',
        extra,
      );
      expect(ds['fingerprint'], 'ab12');
      expect(ds['name-cert-verify'], 'real.example');
    });

    test('downloadSettings: заголовки и xmux скачивания — из его extra', () {
      const extra = '{"downloadSettings":{"address":"dl.example","port":443,'
          '"security":"tls","xhttpSettings":{"path":"/d","extra":'
          '{"headers":{"X-Cdn":"1"},"xmux":{"maxConcurrency":"4-8"}}}}}';
      final ds = _download(
        'vless://uuid@x.example:443?type=xhttp&security=tls&sni=x.example',
        extra,
      );
      expect(ds['path'], '/d');
      expect(ds['headers'], {'X-Cdn': '1'});
      expect(ds['reuse-settings'], {'max-concurrency': '4-8'});
    });

    test('битый extra не роняет ссылку целиком', () {
      final p = _proxy(MihomoConfigGen.build(
        'vless://uuid@x.example:443?type=xhttp&security=tls&sni=x.example'
        '&extra=%7Bnot-json',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['network'], 'xhttp');
      expect(p['xhttp-opts'], {'path': '/'});
    });

    test('raw — это tcp под новым именем', () {
      final p = _proxy(MihomoConfigGen.build(
        'vless://uuid@x.example:443?type=raw&security=none',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['network'], 'tcp');
    });

    test('незнакомый транспорт — ошибка, а не тихий tcp', () {
      expect(
        () => MihomoConfigGen.build(
          'vless://uuid@x.example:443?type=kcp&security=none',
          const AppSettings(),
          socksPort: 2080,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message.toString(),
          'message',
          allOf(contains('kcp'), isNot(contains('uuid'))),
        )),
      );
    });
  });

  group('правила', () {
    test('порядок повторяет xray: блок → сервер → обход → приватные → прокси', () {
      final rules = _rules(MihomoConfigGen.build(
        'vless://uuid@nl.example:443?type=tcp&security=none',
        settings,
        socksPort: 2080,
        resolvedServerIp: '203.0.113.7',
      ));

      int at(String needle) => rules.indexWhere((r) => r.contains(needle));

      expect(at('doubleclick.net'), lessThan(at('nl.example')));
      expect(at('nl.example'), lessThan(at('vk.com')));
      expect(at('vk.com'), lessThan(at('192.168.0.0/16')));
      expect(at('192.168.0.0/16'), lessThan(at('youtube.com')));
      expect(rules.last, 'MATCH,proxy');
    });

    test('типы правил переводятся в синтаксис mihomo', () {
      final rules = _rules(MihomoConfigGen.build(
        'vless://uuid@nl.example:443?type=tcp&security=none',
        settings,
        socksPort: 2080,
        resolvedServerIp: '203.0.113.7',
      ));
      expect(rules, contains('DOMAIN-SUFFIX,doubleclick.net,REJECT'));
      expect(rules, contains('DOMAIN,nl.example,DIRECT'));
      expect(rules, contains('IP-CIDR,203.0.113.7/32,DIRECT,no-resolve'));
      expect(rules, contains('DOMAIN-SUFFIX,vk.com,DIRECT'));
      expect(rules, contains('GEOSITE,category-ru,DIRECT'));
      expect(rules, contains('GEOIP,ru,DIRECT'));
      // Без `no-resolve`: умолчание снифера — подмена адреса назначения, и
      // тогда пользовательские IP-правила обязаны резолвить домен, иначе они
      // молча промахиваются (тот же случай, что `AsIs` → `IPIfNonMatch` у
      // xray). Полный разбор — в тесте про no-resolve ниже.
      expect(rules, contains('IP-CIDR,10.8.0.0/24,DIRECT'));
      expect(rules, contains('DOMAIN-SUFFIX,youtube.com,proxy'));
    });

    test('«остальное» уважает выбор пользователя', () {
      String finalOf(String mode) => _rules(MihomoConfigGen.build(
            'vless://uuid@nl.example:443?type=tcp&security=none',
            AppSettings(finalOutbound: mode),
            socksPort: 2080,
          )).last;

      expect(finalOf(AppSettings.finalOutboundProxy), 'MATCH,proxy');
      expect(finalOf(AppSettings.finalOutboundDirect), 'MATCH,DIRECT');
      expect(finalOf(AppSettings.finalOutboundBlock), 'MATCH,REJECT');
    });

    // Зеркало `AsIs` → `IPIfNonMatch` у xray: с подменой назначения на домен
    // IP-правило с `no-resolve` промахнулось бы мимо собственного адреса.
    test('подмена назначения снимает no-resolve с пользовательских IP-правил',
        () {
      List<String> rulesFor({required bool routeOnly, required String direct}) =>
          _rules(MihomoConfigGen.build(
            'vless://uuid@nl.example:443?type=tcp&security=none',
            AppSettings(
              directRules: direct,
              xrayCore: XrayCoreSettings(sniffingRouteOnly: routeOnly),
            ),
            socksPort: 2080,
            resolvedServerIp: '203.0.113.7',
          ));

      expect(
        rulesFor(routeOnly: false, direct: '10.130.0.0/16'),
        contains('IP-CIDR,10.130.0.0/16,DIRECT'),
      );
      expect(
        rulesFor(routeOnly: true, direct: '10.130.0.0/16'),
        contains('IP-CIDR,10.130.0.0/16,DIRECT,no-resolve'),
      );

      // Без пользовательских IP-правил резолвить каждый домен незачем — как и
      // у xray, где стратегия остаётся `AsIs`.
      final domainsOnly = rulesFor(routeOnly: false, direct: 'vk.com');
      expect(
        domainsOnly,
        contains('IP-CIDR,192.168.0.0/16,DIRECT,no-resolve'),
      );
      // Адрес сервера защищён от круга при любых настройках.
      expect(
        domainsOnly,
        contains('IP-CIDR,203.0.113.7/32,DIRECT,no-resolve'),
      );
    });

    // Голый адрес mihomo у IP-CIDR не примет — нужен префикс.
    test('голому IP дописывается префикс', () {
      final rules = _rules(MihomoConfigGen.build(
        'vless://uuid@203.0.113.9:443?type=tcp&security=none',
        const AppSettings(directRules: '1.2.3.4'),
        socksPort: 2080,
      ));
      expect(rules, contains('IP-CIDR,203.0.113.9/32,DIRECT,no-resolve'));
      // no-resolve тут нет по той же причине, что и выше: умолчание — подмена
      // адреса. Проверяем префикс, а не суффикс правила.
      expect(rules, contains('IP-CIDR,1.2.3.4/32,DIRECT'));
    });
  });

  group('sniffer', () {
    // Без него доменная половина правил не срабатывает НИКОГДА: в SOCKS от
    // локальный SOCKS приезжает голый IP, сравнивать GEOSITE/DOMAIN-SUFFIX не с чем,
    // и всё уходит в MATCH.
    test('включён и нюхает чистые IP — иначе домены не матчатся вовсе', () {
      final s = MihomoConfigGen.build(
        'vless://uuid@nl.example:443?type=tcp&security=none',
        const AppSettings(),
        socksPort: 2080,
      )['sniffer'] as Map<String, dynamic>;

      expect(s['enable'], isTrue);
      expect(s['parse-pure-ip'], isTrue);
      expect((s['sniff'] as Map).keys, containsAll(['HTTP', 'TLS', 'QUIC']));
    });

    // `routeOnly` у xray и `override-destination` у mihomo описывают одно и то
    // же с разных сторон, поэтому значения инвертированы.
    test('override-destination — зеркало sniffingRouteOnly', () {
      bool overrideFor({required bool routeOnly}) =>
          (MihomoConfigGen.build(
            'vless://uuid@nl.example:443?type=tcp&security=none',
            AppSettings(
              xrayCore: XrayCoreSettings(sniffingRouteOnly: routeOnly),
            ),
            socksPort: 2080,
          )['sniffer'] as Map<String, dynamic>)['override-destination'] as bool;

      expect(overrideFor(routeOnly: true), isFalse);
      expect(overrideFor(routeOnly: false), isTrue);
    });

    test('выключенный в настройках sniffing выключен и здесь', () {
      final s = MihomoConfigGen.build(
        'vless://uuid@nl.example:443?type=tcp&security=none',
        const AppSettings(
          xrayCore: XrayCoreSettings(sniffingEnabled: false),
        ),
        socksPort: 2080,
      )['sniffer'] as Map<String, dynamic>;

      expect(s['enable'], isFalse);
    });
  });

  group('dns', () {
    // Системного резолвера на Android нет (/etc/resolv.conf отсутствует), и без
    // своего DNS домен сервера из ссылки не разрешается вовсе.
    test('ядро резолвит само, подмена адресов по умолчанию выключена', () {
      final dns = MihomoConfigGen.build(
        'vless://uuid@nl.example:443?type=tcp&security=none',
        const AppSettings(),
        socksPort: 2080,
      )['dns'] as Map<String, dynamic>;

      expect(dns['enable'], isTrue);
      expect(dns['enhanced-mode'], 'normal');
      expect(dns['nameserver'], isNotEmpty);
      // Адрес прокси-сервера резолвится мимо туннеля, иначе круг.
      expect(dns['proxy-server-nameserver'], isNotEmpty);
    });

    // Аналог `https://` вместо `https+local://` у xray: DNS прячем в туннель
    // только когда туда же уходит всё остальное.
    test('глобал-прокси гонит DNS по правилам', () {
      Map<String, dynamic> dnsFor(String finalOutbound) =>
          MihomoConfigGen.build(
            'vless://uuid@nl.example:443?type=tcp&security=none',
            AppSettings(finalOutbound: finalOutbound),
            socksPort: 2080,
          )['dns'] as Map<String, dynamic>;

      expect(dnsFor(AppSettings.finalOutboundProxy)['respect-rules'], isTrue);
      expect(
        dnsFor(AppSettings.finalOutboundDirect).containsKey('respect-rules'),
        isFalse,
      );
    });

    test('серверы из настроек xray переводятся в схемы mihomo', () {
      expect(
        MihomoConfigGen.dnsServers(
          const XrayCoreSettings(
            dnsUseCustom: true,
            dnsServers: 'https+local://1.1.1.1/dns-query\n'
                'tcp://9.9.9.9\n'
                '8.8.4.4\n'
                'localhost\n'
                'h2c://example.com/dns-query',
          ),
        ),
        // h2c mihomo не знает — такая запись роняет разбор конфига целиком,
        // поэтому её выбрасываем, а не переносим как есть.
        [
          'https://1.1.1.1/dns-query#DIRECT',
          'tcp://9.9.9.9',
          '8.8.4.4',
          'system',
        ],
      );
    });

    test('+local переживает respect-rules', () {
      // При глобал-прокси ядро подставляет `RULES` каждому серверу с пустым
      // фрагментом, и «мимо туннеля» превращалось в «через туннель». Явное имя
      // прокси во фрагменте эту подстановку перебивает.
      const core = XrayCoreSettings(
        dnsUseCustom: true,
        dnsServers: 'https+local://9.9.9.9/dns-query\nhttps://1.1.1.1/dns-query',
      );
      expect(
        MihomoConfigGen.dnsServers(core),
        ['https://9.9.9.9/dns-query#DIRECT', 'https://1.1.1.1/dns-query'],
      );
      final dns = MihomoConfigGen.buildDns(
        const AppSettings(
          finalOutbound: AppSettings.finalOutboundProxy,
          xrayCore: core,
        ),
      );
      expect(dns['respect-rules'], isTrue);
      expect(
        (dns['nameserver'] as List).first,
        'https://9.9.9.9/dns-query#DIRECT',
      );
    });

    // По default-nameserver резолвятся ИМЕНА самих DoH-серверов, и ходит туда
    // ядро всегда напрямую, мимо туннеля и мимо правил (`parseNameServer` с
    // respectRules=false в config.go ядра). Что там лежит — то и видит
    // провайдер, поэтому чужих адресов там быть не должно.
    group('bootstrap', () {
      List<String> bootstrapFor(String servers) =>
          MihomoConfigGen.buildDns(AppSettings(
            xrayCore: XrayCoreSettings(
              dnsUseCustom: true,
              dnsServers: servers,
            ),
          ))['default-nameserver'] as List<String>;

      test('свой резолвер, а не Google с Cloudflare', () {
        // Ровно та жалоба, ради которой правка: выбран Quad9, а имя его
        // DoH-сервера уходило спрашивать у чужой пары.
        expect(
          bootstrapFor('https://9.9.9.9/dns-query'),
          ['https://9.9.9.9/dns-query'],
        );
      });

      test('запись переносится со схемой, а не голым адресом', () {
        // Голый `9.9.9.9` — это UDP-53 мимо туннеля, то есть запрошенное имя
        // открытым текстом. У DoH провайдер видит только TLS к 9.9.9.9.
        expect(bootstrapFor('https://9.9.9.9/dns-query').single, startsWith('https://'));
        // Умолчание — те же два адреса, что и были, но теперь тоже DoH.
        expect(
          MihomoConfigGen.buildDns(const AppSettings())['default-nameserver'],
          ['https://1.1.1.1/dns-query', 'https://8.8.8.8/dns-query'],
        );
      });

      test('серверы по именам в bootstrap не годятся', () {
        // Им самим нужен резолв — ядро такую запись и не примет («default
        // nameserver should be pure IP»). Берём из списка только адресные.
        expect(
          bootstrapFor('https://dns.quad9.net/dns-query, '
              'https+local://9.9.9.9/dns-query'),
          ['https://9.9.9.9/dns-query#DIRECT'],
        );
      });

      test('список без единого адреса остаётся на прежней паре', () {
        // Подставить туда нечего: без bootstrap имена DoH-серверов не
        // разрешаются вовсе, и DNS умирает целиком.
        expect(
          bootstrapFor('https://dns.quad9.net/dns-query, localhost'),
          ['1.1.1.1', '8.8.8.8'],
        );
      });

      test('порт и IPv6 адрес адресом быть не перестают', () {
        expect(bootstrapFor('tls://9.9.9.9:853'), ['tls://9.9.9.9:853']);
        expect(
          bootstrapFor('https://[2620:fe::fe]/dns-query'),
          ['https://[2620:fe::fe]/dns-query'],
        );
        // Имя с портом — всё ещё имя.
        expect(bootstrapFor('tls://dns.quad9.net:853'), ['1.1.1.1', '8.8.8.8']);
      });
    });

    test('пустой список не оставляет ядро без резолвера', () {
      expect(
        MihomoConfigGen.dnsServers(
          const XrayCoreSettings(dnsUseCustom: true, dnsServers: '  \n '),
        ),
        isNotEmpty,
      );
    });

    // Семейство адресов у обоих ядер берётся из одной настройки.
    test('queryStrategy решает судьбу AAAA', () {
      Map<String, dynamic> configFor(String strategy) => MihomoConfigGen.build(
            'vless://uuid@nl.example:443?type=tcp&security=none',
            AppSettings(
              xrayCore: XrayCoreSettings(dnsQueryStrategy: strategy),
            ),
            socksPort: 2080,
          );

      final v4 = configFor('UseIPv4');
      expect(v4['ipv6'], isFalse);
      expect((v4['dns'] as Map)['ipv6'], isFalse);

      final both = configFor('UseIP');
      expect(both['ipv6'], isTrue);
      expect((both['dns'] as Map)['ipv6'], isTrue);
    });
  });

  group('api ядра', () {
    test('external-controller поднимается только с портом и всегда с токеном',
        () {
      final withApi = MihomoConfigGen.build(
        'vless://uuid@nl.example:443?type=tcp&security=none',
        const AppSettings(),
        socksPort: 2080,
        apiPort: 9971,
        apiSecret: 's3cr3t',
      );
      expect(withApi['external-controller'], '127.0.0.1:9971');
      expect(withApi['secret'], 's3cr3t');

      // Пинг и спидтест поднимают ядро без API — управлять там нечем.
      final withoutApi = MihomoConfigGen.build(
        'vless://uuid@nl.example:443?type=tcp&security=none',
        const AppSettings(),
        socksPort: 2080,
      );
      expect(withoutApi.containsKey('external-controller'), isFalse);
      expect(withoutApi.containsKey('secret'), isFalse);
    });
  });

  group('раздача в локалку', () {
    const lanOn = AppSettings(
      lanSharing: true,
      lanSocksPort: 1080,
      lanHttpPort: 8080,
    );

    test('выключенная раздача не оставляет ни листенеров, ни их правил', () {
      final c = MihomoConfigGen.build(
        'vless://uuid@nl.example:443?type=tcp&security=none',
        const AppSettings(),
        socksPort: 2080,
      );
      expect(c.containsKey('listeners'), isFalse);
      expect(c.containsKey('sub-rules'), isFalse);
      expect(c['allow-lan'], isFalse);
    });

    test('листенеры слушают сеть и ходят по своему набору правил', () {
      final listeners = (MihomoConfigGen.build(
        'vless://uuid@nl.example:443?type=tcp&security=none',
        lanOn,
        socksPort: 2080,
      )['listeners'] as List)
          .cast<Map<String, dynamic>>();

      expect(listeners.map((l) => l['type']), ['socks', 'http']);
      for (final l in listeners) {
        expect(l['listen'], '0.0.0.0');
        expect(l['rule'], MihomoConfigGen.lanRuleSet);
        // Порт у mihomo строковый (принимает и диапазоны).
        expect(l['port'], isA<String>());
      }
      expect(listeners.first['port'], '1080');
      expect(listeners.last['port'], '8080');
    });

    // Разница «пусто» и «нет ключа» здесь решает всё: без ключа mihomo
    // подставит глобальный `authentication`, то есть случайные креды
    // приложения, и в раздачу не зайдёт никто.
    test('без пароля users пустой, но присутствует', () {
      final listeners = (MihomoConfigGen.build(
        'vless://uuid@nl.example:443?type=tcp&security=none',
        lanOn,
        socksPort: 2080,
      )['listeners'] as List)
          .cast<Map<String, dynamic>>();

      for (final l in listeners) {
        expect(l.containsKey('users'), isTrue);
        expect(l['users'], isEmpty);
      }
    });

    test('пароль просят только когда заполнены оба поля', () {
      List<Map<String, String>> usersFor(String user, String pass) =>
          MihomoConfigGen.lanUsers(
            AppSettings(lanSharing: true, lanUsername: user, lanPassword: pass),
          );

      expect(usersFor('keq', 'hunter2'), [
        {'username': 'keq', 'password': 'hunter2'},
      ]);
      expect(usersFor('  ', 'hunter2'), isEmpty);
      expect(usersFor('keq', ''), isEmpty);
    });

    // Инбаунд слушает 0.0.0.0: без замыкающего REJECT не совпавшее соединение
    // ушло бы в DIRECT, и раздача стала бы открытым прокси для интернета.
    test('чужим источникам отказ, своим — туннель', () {
      final rules = MihomoConfigGen.buildLanRules();

      expect(rules.last, 'MATCH,REJECT');
      expect(rules, contains('SRC-IP-CIDR,192.168.0.0/16,proxy'));
      expect(rules, contains('SRC-IP-CIDR,10.0.0.0/8,proxy'));
      expect(rules.where((r) => r.startsWith('SRC-IP-CIDR')).length, 5);
    });
  });

  group('свой туннель', () {
    const link = 'vless://uuid@nl.example:443?type=tcp&security=none';

    MihomoTunOptions desktopTun() => const MihomoTunOptions(
          device: 'tun-keqdis',
          stack: 'gvisor',
          mtu: 9000,
        );

    test('десктоп: ядро создаёт устройство само', () {
      final tun = MihomoConfigGen.build(
        link,
        settings,
        socksPort: 2080,
        httpPort: 2081,
        tun: desktopTun(),
        windows: true,
      )['tun'] as Map<String, dynamic>;

      expect(tun['enable'], isTrue);
      // Имя своё: без него mihomo берёт `Meta`, а wintun считает GUID
      // адаптера от имени — тот же GUID у любого mihomo-клиента на машине.
      expect(tun['device'], 'tun-keqdis');
      expect(tun['stack'], 'gvisor');
      expect(tun['mtu'], 9000);
      expect(tun['auto-route'], isTrue);
      expect(tun['auto-detect-interface'], isTrue);
      // Ради этого схема и нужна: запрос системы на 53 уходит в резолвер ядра.
      expect(tun['dns-hijack'], ['any:53']);
    });

    // На Android дескриптор и MTU принадлежат сервису: он поднял интерфейс, он
    // же и дописывает оба числа в готовый конфиг. Вторая копия MTU на этой
    // стороне разъехалась бы с интерфейсом молча.
    test('android: ни устройства, ни MTU — их проставит владелец fd', () {
      final config = MihomoConfigGen.build(
        link,
        settings,
        socksPort: 2080,
        tun: const MihomoTunOptions(
          fromFileDescriptor: true,
          stack: 'gvisor',
          autoRoute: false,
        ),
      );
      final tun = config['tun'] as Map<String, dynamic>;

      expect(tun['enable'], isTrue);
      expect(tun.containsKey('device'), isFalse);
      expect(tun.containsKey('mtu'), isFalse);
      expect(tun.containsKey('file-descriptor'), isFalse);
      // Адреса и маршруты уже проставил VpnService, а netlink на Android 14+
      // ядру запрещён — с автодетектом листенер не поднялся бы вовсе.
      expect(tun['auto-route'], isFalse);
      expect(tun['auto-detect-interface'], isFalse);
      // Владельца соединения непривилегированный процесс на Android не узнает.
      expect(config['find-process-mode'], 'off');
    });

    test('HTTP-инбаунд поднимается только там, где его просят', () {
      final android =
          MihomoConfigGen.build(link, settings, socksPort: 2080);
      expect(android.containsKey('port'), isFalse);

      final desktop = MihomoConfigGen.build(
        link,
        settings,
        socksPort: 2080,
        httpPort: 2081,
      );
      expect(desktop['port'], 2081);
    });

    test('подсеть своего интерфейса — мимо туннеля', () {
      final rules = MihomoConfigGen.build(
        link,
        settings,
        socksPort: 2080,
        tun: desktopTun(),
        windows: true,
      )['rules'] as List;

      expect(rules, contains('IP-CIDR,198.18.0.0/30,DIRECT,no-resolve'));
    });
  });

  group('fake-ip', () {
    const link = 'vless://uuid@nl.example:443?type=tcp&security=none';
    final on = settings.copyWith(mihomoFakeIp: true);

    Map<String, dynamic> dnsOf(AppSettings s, {MihomoTunOptions? tun}) =>
        MihomoConfigGen.build(
          link,
          s,
          socksPort: 2080,
          httpPort: 2081,
          tun: tun,
          windows: true,
        )['dns'] as Map<String, dynamic>;

    test('включённая настройка со своим туннелем подменяет адреса', () {
      final dns = dnsOf(
        on,
        tun: const MihomoTunOptions(device: 'tun-keqdis', stack: 'gvisor'),
      );

      expect(dns['enhanced-mode'], 'fake-ip');
      expect(dns['fake-ip-range'], '198.18.0.1/16');
      // Локальные зоны и проверки связности — мимо подмены, иначе система
      // рисует «интернета нет» поверх работающего туннеля.
      expect(dns['fake-ip-filter'], contains('*.lan'));
      expect(dns['fake-ip-filter'], contains('connectivitycheck.gstatic.com'));
    });

    // Перехват DNS живёт в tun-блоке: без него подменный адрес некому вернуть
    // системе, и он же вернулся бы в правила как неизвестный IP.
    test('без своего туннеля настройка ничего не включает', () {
      final dns = dnsOf(on);
      expect(dns['enhanced-mode'], 'normal');
      expect(dns.containsKey('fake-ip-range'), isFalse);
    });

    test('выключенная настройка оставляет обычный резолв', () {
      final dns = dnsOf(
        settings,
        tun: const MihomoTunOptions(device: 'tun-keqdis', stack: 'gvisor'),
      );
      expect(dns['enhanced-mode'], 'normal');
    });

    // Ядро стирает подменный адрес перед выбором правила и восстанавливает
    // домен, поэтому IP-правилу с no-resolve сравнивать нечего — оно
    // промахивается всегда.
    test('пользовательские IP-правила теряют no-resolve', () {
      final rules = (MihomoConfigGen.build(
        link,
        on.copyWith(
          directRules: '10.8.0.0/24',
          // Снифер в режиме routeOnly — то есть прежнее условие снятия
          // no-resolve не выполнено, и решает именно fake-ip.
          xrayCore: const XrayCoreSettings(sniffingRouteOnly: true),
        ),
        socksPort: 2080,
        tun: const MihomoTunOptions(device: 'tun-keqdis', stack: 'gvisor'),
        windows: true,
      )['rules'] as List)
          .cast<String>();

      expect(rules, contains('IP-CIDR,10.8.0.0/24,DIRECT'));
      expect(rules, isNot(contains('IP-CIDR,10.8.0.0/24,DIRECT,no-resolve')));
    });

    // Правило против круга обязано решать без резолва при любых настройках:
    // резолв ради него — это тот же круг, только на шаг раньше.
    test('правило про сам сервер no-resolve не теряет', () {
      final rules = (MihomoConfigGen.build(
        link,
        on,
        socksPort: 2080,
        resolvedServerIp: '203.0.113.7',
        tun: const MihomoTunOptions(device: 'tun-keqdis', stack: 'gvisor'),
        windows: true,
      )['rules'] as List)
          .cast<String>();

      expect(rules, contains('IP-CIDR,203.0.113.7/32,DIRECT,no-resolve'));
    });
  });

  group('правила по процессам', () {
    const link = 'vless://uuid@nl.example:443?type=tcp&security=none';

    List<String> rulesFor({
      required AppRoutingMode mode,
      List<String> managed = const [],
    }) =>
        (MihomoConfigGen.build(
          link,
          settings,
          socksPort: 2080,
          httpPort: 2081,
          tun: const MihomoTunOptions(device: 'tun-keqdis', stack: 'gvisor'),
          routingMode: mode,
          managedProcessNames: managed,
          appProcessName: 'keqdroid.exe',
          windows: true,
        )['rules'] as List)
            .cast<String>();

    // Иначе tcp-пинг мерил бы локальный конец туннеля вместо сервера.
    test('свой процесс — первым правилом и мимо туннеля', () {
      final rules = rulesFor(mode: AppRoutingMode.allProxy);
      expect(rules.first, 'PROCESS-NAME,keqdroid.exe,DIRECT');
    });

    test('чужие VPN-клиенты не заворачиваются в туннель в туннеле', () {
      final rules = rulesFor(mode: AppRoutingMode.allProxy);
      expect(rules, contains('PROCESS-NAME,tailscaled.exe,DIRECT'));
      expect(rules, contains('PROCESS-NAME,openvpn.exe,DIRECT'));
    });

    // При пер-аппном сплите пользователь назвал приложения сам, и дописывать к
    // его списку свои нельзя.
    test('при сплите чужие VPN-клиенты не дописываются', () {
      final rules = rulesFor(
        mode: AppRoutingMode.allExceptSelected,
        managed: const ['Telegram.exe'],
      );
      expect(rules.any((r) => r.contains('tailscaled')), isFalse);
      expect(rules, contains('PROCESS-NAME,Telegram.exe,DIRECT'));
      // «Всё кроме выбранных» означает, что остальное идёт в туннель.
      expect(rules.last, 'MATCH,proxy');
    });

    test('«только выбранные» шлёт остальное напрямую', () {
      final rules = rulesFor(
        mode: AppRoutingMode.onlySelected,
        managed: const ['chrome.exe'],
      );
      expect(rules, contains('PROCESS-NAME,chrome.exe,proxy'));
      expect(rules.last, 'MATCH,DIRECT');
    });

    // В локальный инбаунд ходит ровно один процесс — он же был бы
    // «владельцем» всего, поэтому правил там нет вовсе.
    test('без своего туннеля правил по процессам не бывает', () {
      final config = MihomoConfigGen.build(
        link,
        settings,
        socksPort: 2080,
        managedProcessNames: const ['Telegram.exe'],
        appProcessName: 'keqdroid.exe',
      );
      expect(config['find-process-mode'], 'off');
      expect(
        (config['rules'] as List).any((r) => '$r'.startsWith('PROCESS-NAME')),
        isFalse,
      );
    });
  });

  // Смысл тот же, что у kill switch в sing-box: весь IP-трафик в прокси, а
  // финалом отказ — падение прокси не превращается в утечку мимо туннеля.
  group('kill switch', () {
    const link = 'vless://uuid@nl.example:443?type=tcp&security=none';

    test('весь трафик в прокси, финал — отказ', () {
      final rules = (MihomoConfigGen.build(
        link,
        settings.copyWith(killSwitch: true),
        socksPort: 2080,
        httpPort: 2081,
        tun: const MihomoTunOptions(device: 'tun-keqdis', stack: 'gvisor'),
        windows: true,
      )['rules'] as List)
          .cast<String>();

      expect(rules, contains('IP-CIDR,0.0.0.0/1,proxy'));
      expect(rules, contains('IP-CIDR,128.0.0.0/1,proxy'));
      expect(rules.last, 'MATCH,REJECT');
    });

    // Финал у них и так не proxy: гнать всё в туннель ради отказа бессмысленно.
    test('при обходе и блокировке не применяется', () {
      for (final finalOutbound in const [
        AppSettings.finalOutboundDirect,
        AppSettings.finalOutboundBlock,
      ]) {
        final rules = (MihomoConfigGen.build(
          link,
          settings.copyWith(killSwitch: true, finalOutbound: finalOutbound),
          socksPort: 2080,
          tun: const MihomoTunOptions(device: 'tun-keqdis', stack: 'gvisor'),
          windows: true,
        )['rules'] as List)
            .cast<String>();
        expect(rules.any((r) => r.startsWith('IP-CIDR,0.0.0.0/1')), isFalse);
      }
    });
  });

  test('generate отдаёт валидный JSON (он же YAML для ядра)', () {
    final raw = MihomoConfigGen.generate(
      'vless://uuid@nl.example:443?type=tcp&security=reality&pbk=k&sid=aa',
      settings,
      socksPort: 2080,
    );
    final parsed = jsonDecode(raw) as Map<String, dynamic>;
    expect(parsed['proxies'], isA<List>());
    expect(parsed['rules'], isA<List>());
  });

  // Маскировка под обычный HTTP-запрос поверх tcp. У ядра это отдельный
  // `network`, а не флаг: без неё сервер ждёт запрос с заголовками, получает
  // голый поток и молчит.
  group('HTTP-маскировка', () {
    test('vless: headerType=http превращается в network http', () {
      final proxy = MihomoConfigGen.buildProxy(
        'vless://uuid@198.51.100.10:443?type=tcp&security=none'
        '&headerType=http&host=masq.example&path=%2Fmasq&method=POST',
      );
      expect(proxy['network'], 'http');
      final opts = proxy['http-opts'] as Map<String, dynamic>;
      expect(opts['method'], 'POST');
      expect(opts['path'], ['/masq']);
      expect((opts['headers'] as Map)['Host'], ['masq.example']);
    });

    test('vmess: заголовок лежит в поле type, а не в net', () {
      final payload = base64.encode(utf8.encode(jsonEncode({
        'v': '2',
        'ps': 'n',
        'add': '198.51.100.10',
        'port': '443',
        'id': 'uuid',
        'net': 'tcp',
        'type': 'http',
        'host': 'masqvmess.example',
        'path': '/masqvmess',
      })));
      final proxy = MihomoConfigGen.buildProxy('vmess://$payload');
      expect(proxy['network'], 'http');
      final opts = proxy['http-opts'] as Map<String, dynamic>;
      expect(opts['path'], ['/masqvmess']);
      expect((opts['headers'] as Map)['Host'], ['masqvmess.example']);
    });

    test('без headerType транспорт остаётся обычным tcp', () {
      final proxy = MihomoConfigGen.buildProxy(
        'vless://uuid@198.51.100.10:443?type=tcp&security=none',
      );
      expect(proxy['network'], 'tcp');
      expect(proxy.containsKey('http-opts'), isFalse);
    });

    test('trojan так не умеет — генератор отказывается', () {
      expect(
        () => MihomoConfigGen.buildProxy(
          'trojan://pwd@198.51.100.10:443?type=tcp&security=tls&headerType=http',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ECH прячет настоящее имя сервера в ClientHello. У xray поле `ech`
  // двузначно, у mihomo под это два разных вида `ech-opts`.
  // Плагин оборачивает трафик shadowsocks во что-то безобидное. Ссылка несёт
  // его одной строкой, и раньше она пропадала целиком: сервер ждал обёртку,
  // получал голый shadowsocks и не отвечал.
  group('shadowsocks: плагины и UDP внутри TCP', () {
    const user = 'YWVzLTI1Ni1nY206cGFzc3dvcmQ';

    test('obfs-local разбирается в plugin-opts', () {
      final proxy = MihomoConfigGen.buildProxy(
        'ss://$user@198.51.100.10:8388'
        '?plugin=obfs-local%3Bobfs%3Dhttp%3Bobfs-host%3Dcdn.example',
      );
      expect(proxy['plugin'], 'obfs');
      final opts = proxy['plugin-opts'] as Map<String, dynamic>;
      expect(opts['mode'], 'http');
      expect(opts['host'], 'cdn.example');
    });

    test('v2ray-plugin: tls это флаг без значения', () {
      final proxy = MihomoConfigGen.buildProxy(
        'ss://$user@198.51.100.10:8388'
        '?plugin=v2ray-plugin%3Btls%3Bmode%3Dwebsocket'
        '%3Bhost%3Dv2.example%3Bpath%3D%2Fws',
      );
      expect(proxy['plugin'], 'v2ray-plugin');
      final opts = proxy['plugin-opts'] as Map<String, dynamic>;
      expect(opts['mode'], 'websocket');
      expect(opts['host'], 'v2.example');
      expect(opts['path'], '/ws');
      expect(opts['tls'], isTrue);
    });

    test('без плагина полей плагина нет', () {
      final proxy = MihomoConfigGen.buildProxy('ss://$user@198.51.100.10:8388');
      expect(proxy.containsKey('plugin'), isFalse);
      expect(proxy.containsKey('plugin-opts'), isFalse);
      expect(proxy.containsKey('udp-over-tcp'), isFalse);
    });

    test('UDP внутри TCP включается обоими написаниями', () {
      for (final query in ['uot=1', 'udp-over-tcp=true']) {
        final proxy =
            MihomoConfigGen.buildProxy('ss://$user@198.51.100.10:8388?$query');
        expect(proxy['udp-over-tcp'], isTrue, reason: query);
      }
      final versioned = MihomoConfigGen.buildProxy(
        'ss://$user@198.51.100.10:8388?uot=1&udp-over-tcp-version=2',
      );
      expect(versioned['udp-over-tcp-version'], 2);
    });
  });

  // Ранние данные: первый пакет уезжает вместе с рукопожатием WebSocket. На
  // подключение не влияет, на скорость первого запроса — да.
  // Как упаковывать UDP: `none` — как есть, `packet` — адрес в каждом пакете,
  // всё прочее — xudp. Ссылку без параметра намеренно не трогаем.
  group('packetEncoding', () {
    Map<String, dynamic> proxyFor(String value) => MihomoConfigGen.buildProxy(
          'vless://uuid@198.51.100.10:443?type=tcp&security=none'
          '${value.isEmpty ? '' : '&packetEncoding=$value'}',
        );

    test('xudp и packet-addr', () {
      expect(proxyFor('xudp')['xudp'], isTrue);
      expect(proxyFor('packet')['packet-addr'], isTrue);
      expect(proxyFor('packet').containsKey('xudp'), isFalse);
    });

    test('none не включает ничего', () {
      final proxy = proxyFor('none');
      expect(proxy.containsKey('xudp'), isFalse);
      expect(proxy.containsKey('packet-addr'), isFalse);
    });

    test('без параметра упаковка не меняется', () {
      final proxy = proxyFor('');
      expect(proxy.containsKey('xudp'), isFalse);
      expect(proxy.containsKey('packet-addr'), isFalse);
    });
  });

  // У h2 имя в заголовке запроса бывает не тем, что в сертификате: сервер за
  // общим фронтом различает узлы именно по нему.
  test('h2: host берётся из ссылки, а не из sni', () {
    final proxy = MihomoConfigGen.buildProxy(
      'vless://uuid@198.51.100.10:443?type=http&security=tls'
      '&sni=front.example&host=node.example&path=%2Fh2',
    );
    final opts = proxy['h2-opts'] as Map<String, dynamic>;
    expect(opts['host'], ['node.example']);
    expect(opts['path'], '/h2');
    expect(proxy['servername'], 'front.example');
  });

  test('h2 без host: имя берётся от sni, как и раньше', () {
    final proxy = MihomoConfigGen.buildProxy(
      'vless://uuid@198.51.100.10:443?type=http&security=tls&sni=front.example',
    );
    expect((proxy['h2-opts'] as Map)['host'], ['front.example']);
  });

  group('ранние данные WebSocket', () {
    test('ed и eh из параметров ссылки', () {
      final proxy = MihomoConfigGen.buildProxy(
        'vless://uuid@198.51.100.10:443?type=ws&security=tls&sni=w.example'
        '&path=%2Fws&ed=2048&eh=X-Early',
      );
      final opts = proxy['ws-opts'] as Map<String, dynamic>;
      expect(opts['path'], '/ws');
      expect(opts['max-early-data'], 2048);
      expect(opts['early-data-header-name'], 'X-Early');
    });

    test('без eh подставляется соглашение', () {
      final proxy = MihomoConfigGen.buildProxy(
        'vless://uuid@198.51.100.10:443?type=ws&security=tls&sni=w.example'
        '&path=%2Fws&ed=2048',
      );
      final opts = proxy['ws-opts'] as Map<String, dynamic>;
      expect(opts['early-data-header-name'], 'Sec-WebSocket-Protocol');
    });

    // v2rayN кладёт размер внутрь пути. Оставь его там — и сервер получит путь
    // с хвостом, которого не ждёт.
    test('ed внутри пути вынимается из него', () {
      final proxy = MihomoConfigGen.buildProxy(
        'vless://uuid@198.51.100.10:443?type=ws&security=tls&sni=w.example'
        '&path=%2Fws%3Fed%3D2048',
      );
      final opts = proxy['ws-opts'] as Map<String, dynamic>;
      expect(opts['path'], '/ws');
      expect(opts['max-early-data'], 2048);
    });

    test('чужие параметры пути остаются в пути', () {
      final proxy = MihomoConfigGen.buildProxy(
        'vless://uuid@198.51.100.10:443?type=ws&security=tls&sni=w.example'
        '&path=%2Fws%3Fed%3D2048%26token%3Dabc',
      );
      final opts = proxy['ws-opts'] as Map<String, dynamic>;
      expect(opts['path'], '/ws?token=abc');
      expect(opts['max-early-data'], 2048);
    });

    test('у httpupgrade размер не нужен, нужен сам флаг', () {
      final proxy = MihomoConfigGen.buildProxy(
        'vless://uuid@198.51.100.10:443?type=httpupgrade&security=tls'
        '&sni=h.example&path=%2Fhu&ed=2048',
      );
      final opts = proxy['ws-opts'] as Map<String, dynamic>;
      expect(opts['v2ray-http-upgrade-fast-open'], isTrue);
      expect(opts.containsKey('max-early-data'), isFalse);
    });

    test('без ранних данных полей о них нет', () {
      final proxy = MihomoConfigGen.buildProxy(
        'vless://uuid@198.51.100.10:443?type=ws&security=tls&sni=w.example'
        '&path=%2Fws',
      );
      final opts = proxy['ws-opts'] as Map<String, dynamic>;
      expect(opts.containsKey('max-early-data'), isFalse);
      expect(opts.containsKey('early-data-header-name'), isFalse);
    });
  });

  group('ECH', () {
    test('base64-список уезжает в config', () {
      final proxy = MihomoConfigGen.buildProxy(
        'vless://uuid@198.51.100.10:443?type=tcp&security=tls&sni=e.example'
        '&ech=AEX%2BDQBBzQAgACD0RY0ZGF9n',
      );
      final ech = proxy['ech-opts'] as Map<String, dynamic>;
      expect(ech['enable'], isTrue);
      expect(ech['config'], 'AEX+DQBBzQAgACD0RY0ZGF9n');
      expect(ech.containsKey('query-server-name'), isFalse);
    });

    // Ссылка называет DNS, у которого спросить запись. Самого адреса ядру не
    // передать, но имя для запроса — да.
    test('форма «имя+dns» включает запрос HTTPS-записи', () {
      final proxy = MihomoConfigGen.buildProxy(
        'vless://uuid@198.51.100.10:443?type=tcp&security=tls&sni=e.example'
        '&ech=real.example%2Bhttps%3A%2F%2F1.1.1.1%2Fdns-query',
      );
      final ech = proxy['ech-opts'] as Map<String, dynamic>;
      expect(ech['enable'], isTrue);
      expect(ech['query-server-name'], 'real.example');
      expect(ech.containsKey('config'), isFalse);
    });

    // Ловушка на ровном месте: разбор запроса по правилам HTML-формы читает
    // `+` как пробел, и base64 приезжает испорченным.
    test('плюс в base64 остаётся плюсом', () {
      final proxy = MihomoConfigGen.buildProxy(
        'vless://uuid@198.51.100.10:443?type=tcp&security=tls&sni=e.example'
        '&ech=AA+BB/CC=&pcs=QQ+WW/EE=',
      );
      expect((proxy['ech-opts'] as Map)['config'], 'AA+BB/CC=');
      expect(proxy['fingerprint'], 'QQ+WW/EE=');
    });

    test('без ech поля нет вовсе', () {
      final proxy = MihomoConfigGen.buildProxy(
        'vless://uuid@198.51.100.10:443?type=tcp&security=tls&sni=e.example',
      );
      expect(proxy.containsKey('ech-opts'), isFalse);
    });
  });

  // TUIC — QUIC-протокол, которого у xray нет вовсе. Версия узнаётся по форме
  // userInfo, и поля у версий в ядре разные.
  group('TUIC', () {
    test('v5: пара uuid:password', () {
      final proxy = MihomoConfigGen.buildProxy(
        'tuic://11111111-2222-3333-4444-555555555555:secret@198.51.100.30:443'
        '?sni=tuic.example&alpn=h3&congestion_control=bbr'
        '&udp_relay_mode=quic&disable_sni=1',
      );
      expect(proxy['type'], 'tuic');
      expect(proxy['uuid'], '11111111-2222-3333-4444-555555555555');
      expect(proxy['password'], 'secret');
      expect(proxy.containsKey('token'), isFalse);
      expect(proxy['sni'], 'tuic.example');
      expect(proxy['alpn'], ['h3']);
      expect(proxy['congestion-controller'], 'bbr');
      expect(proxy['udp-relay-mode'], 'quic');
      expect(proxy['disable-sni'], isTrue);
    });

    test('v4: один токен', () {
      final proxy =
          MihomoConfigGen.buildProxy('tuic://sometoken@198.51.100.30:443');
      expect(proxy['token'], 'sometoken');
      expect(proxy.containsKey('uuid'), isFalse);
      expect(proxy.containsKey('password'), isFalse);
    });

    test('без ключей — отказ, а не прокси без пароля', () {
      expect(
        () => MihomoConfigGen.buildProxy('tuic://198.51.100.30:443'),
        throwsA(isA<ArgumentError>()),
      );
    });

    // Политика та же, что у insecure везде: доверять любому сертификату не
    // соглашаемся, сколько бы ссылка ни просила.
    test('allow_insecure не превращается в skip-cert-verify', () {
      final proxy = MihomoConfigGen.buildProxy(
        'tuic://uuid:pwd@198.51.100.30:443?allow_insecure=1',
      );
      expect(proxy.containsKey('skip-cert-verify'), isFalse);
    });
  });

  // AnyTLS: поток внутри обычного TLS. Имени пользователя у протокола нет —
  // если в userInfo нет двоеточия, паролем работает всё, что там есть.
  group('AnyTLS', () {
    test('пароль из userInfo, с двоеточием и без', () {
      final pair = MihomoConfigGen.buildProxy(
        'anytls://user:secret@198.51.100.31:443?sni=a.example',
      );
      expect(pair['type'], 'anytls');
      expect(pair['password'], 'secret');

      final single =
          MihomoConfigGen.buildProxy('anytls://secret@198.51.100.31:443');
      expect(single['password'], 'secret');
    });

    test('hpkp — это пин сертификата, а не отпечаток uTLS', () {
      final proxy = MihomoConfigGen.buildProxy(
        'anytls://secret@198.51.100.31:443?sni=a.example&hpkp=QQ+WW/EE=',
      );
      expect(proxy['fingerprint'], 'QQ+WW/EE=');
      // А отпечаток uTLS — наш общий по умолчанию.
      expect(proxy['client-fingerprint'], defaultTlsFingerprint);
    });

    test('без ключей — отказ', () {
      expect(
        () => MihomoConfigGen.buildProxy('anytls://198.51.100.31:443'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('insecure не превращается в skip-cert-verify', () {
      final proxy = MihomoConfigGen.buildProxy(
        'anytls://secret@198.51.100.31:443?insecure=1',
      );
      expect(proxy.containsKey('skip-cert-verify'), isFalse);
    });
  });

  // SSR у нас принимался разбором, но не собирался ни одним генератором:
  // сервер в списке был, подключения не было.
  group('SSR', () {
    String b64(String value) =>
        base64Url.encode(utf8.encode(value)).replaceAll('=', '');

    test('собирается со всеми полями', () {
      final payload = '198.51.100.32:8388:auth_aes128_md5:aes-256-cfb:'
          'tls1.2_ticket_auth:${b64('secret')}/?'
          'obfsparam=${b64('cdn.example')}&protoparam=${b64('32')}';
      final proxy = MihomoConfigGen.buildProxy('ssr://${b64(payload)}');

      expect(proxy['type'], 'ssr');
      expect(proxy['server'], '198.51.100.32');
      expect(proxy['port'], 8388);
      expect(proxy['cipher'], 'aes-256-cfb');
      expect(proxy['password'], 'secret');
      expect(proxy['obfs'], 'tls1.2_ticket_auth');
      expect(proxy['protocol'], 'auth_aes128_md5');
      expect(proxy['obfs-param'], 'cdn.example');
      expect(proxy['protocol-param'], '32');
    });

    test('битая ссылка — отказ, а не прокси без адреса', () {
      expect(
        () => MihomoConfigGen.buildProxy('ssr://не-base64'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // У mieru порт и транспорт — пара параметров запроса, а не часть адреса.
  group('Mieru', () {
    test('собирается со всеми полями', () {
      final proxy = MihomoConfigGen.buildProxy(
        'mierus://user:secret@198.51.100.33?port=2999&protocol=TCP'
        '&multiplexing=MULTIPLEXING_HIGH&handshake-mode=standard'
        '&traffic-pattern=chatty',
      );
      expect(proxy['type'], 'mieru');
      expect(proxy['server'], '198.51.100.33');
      expect(proxy['port'], 2999);
      expect(proxy['transport'], 'TCP');
      expect(proxy['username'], 'user');
      expect(proxy['password'], 'secret');
      expect(proxy['multiplexing'], 'MULTIPLEXING_HIGH');
      expect(proxy['handshake-mode'], 'standard');
      expect(proxy['traffic-pattern'], 'chatty');
    });

    test('диапазон портов уезжает в своё поле', () {
      final proxy = MihomoConfigGen.buildProxy(
        'mierus://user:secret@198.51.100.33?port=2999-3010&protocol=TCP',
      );
      expect(proxy['port-range'], '2999-3010');
      expect(proxy.containsKey('port'), isFalse);
    });

    test('без пары порт/протокол — отказ', () {
      expect(
        () => MihomoConfigGen.buildProxy('mierus://user:secret@198.51.100.33'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('hysteria', () {
    // Схема одна на обе версии. Первую не собираем вовсе, вторую под этой же
    // схемой терять нельзя — панели со старым шаблоном выдают именно её.
    test('v1 отклоняется', () {
      expect(
        () => MihomoConfigGen.buildProxy(
          'hysteria://host:443?auth=secret&upmbps=100&downmbps=200',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    // Перебор портов: сервер слушает диапазон и ждёт, что клиент будет по нему
    // ходить. Список приходит двумя способами, и второй раньше ронял разбор
    // ссылки целиком.
    test('список портов из запроса доезжает вместе с интервалом', () {
      final proxy = MihomoConfigGen.buildProxy(
        'hysteria2://pwd@198.51.100.16:443?sni=hy2.example'
        '&mport=20000-20050&hop-interval=30',
      );
      expect(proxy['ports'], '20000-20050');
      expect(proxy['hop-interval'], '30');
    });

    test('список портов прямо в адресе тоже доезжает', () {
      final proxy = MihomoConfigGen.buildProxy(
        'hysteria2://pwd@198.51.100.16:20000-20050,443?sni=hy2.example',
      );
      expect(proxy['server'], '198.51.100.16');
      // В адресе остаётся первый порт списка — как это делает и само ядро.
      expect(proxy['port'], 20000);
      expect(proxy['ports'], '20000-20050,443');
      expect(proxy['sni'], 'hy2.example');
    });

    test('пин сертификата уезжает в fingerprint', () {
      final proxy = MihomoConfigGen.buildProxy(
        'hysteria2://pwd@198.51.100.16:443?sni=hy2.example&pinSHA256=QQ+WW/EE=',
      );
      expect(proxy['fingerprint'], 'QQ+WW/EE=');
    });

    test('без перебора портов полей о нём нет', () {
      final proxy = MihomoConfigGen.buildProxy(
        'hysteria2://pwd@198.51.100.16:443?sni=hy2.example&hop-interval=30',
      );
      expect(proxy.containsKey('ports'), isFalse);
      expect(proxy.containsKey('hop-interval'), isFalse);
    });

    test('hysteria:// с параметрами второй версии собирается как hysteria2', () {
      final proxy = MihomoConfigGen.buildProxy(
        'hysteria://password@198.51.100.16:443?sni=hy2.example'
        '&obfs=salamander&obfs-password=obfspass',
      );
      expect(proxy['type'], 'hysteria2');
      expect(proxy['sni'], 'hy2.example');
      expect(proxy['obfs'], 'salamander');
    });
  });
}
