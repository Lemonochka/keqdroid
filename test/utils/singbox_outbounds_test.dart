import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/singbox_outbounds.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';
import 'package:keqdroid/utils/ssr_uri.dart';
import 'package:keqdroid/utils/vpn_core_support.dart';

/// Перевод узлов sing-box в ссылки. Поля — `option/*.go` sing-box.
///
/// Здесь проверяется ссылка, а не конфиг ядра: что ссылка доезжает до ядра,
/// стережёт перепись (generator_link_params_test.dart). Последняя группа
/// связывает одно с другим — каждую ссылку корпуса собирает то ядро, которое
/// для неё выбирает правило, иначе перевод дал бы сервер, который не
/// поднимется.

const _uuid = '00000000-0000-4000-8000-000000000000';
const _corpus = 'test/fixtures/subscription_payloads/singbox-outbounds.txt';

/// Конфиг вокруг узлов — со служебными аутбаундами, как его отдают панели.
String _config(
  List<Map<String, Object?>> outbounds, {
  List<Map<String, Object?>> endpoints = const [],
}) =>
    jsonEncode({
      'outbounds': [
        {
          'type': 'selector',
          'tag': 'proxy',
          'outbounds': [for (final o in outbounds) o['tag']],
        },
        ...outbounds,
        {'type': 'direct', 'tag': 'direct'},
      ],
      if (endpoints.isNotEmpty) 'endpoints': endpoints,
    });

Map<String, Object?> _node(String type, Map<String, Object?> fields) => {
      'type': type,
      'tag': 'node',
      'server': '198.51.100.40',
      'server_port': 443,
      ...fields,
    };

String _link(Map<String, Object?> outbound) =>
    SingboxOutbounds.translate(_config([outbound])).links.single;

Map<String, int> _skipped(Map<String, Object?> outbound) =>
    SingboxOutbounds.translate(_config([outbound])).skipped;

Map<String, String> _query(String link) => Uri.parse(link).queryParameters;

Map<String, dynamic> _vmessJson(String link) => jsonDecode(
      utf8.decode(base64.decode(link.substring('vmess://'.length))),
    ) as Map<String, dynamic>;

void main() {
  group('что считается конфигом sing-box', () {
    test('конфиг xray — нет: протокол у него в `protocol`', () {
      const xray = '{"outbounds": [{"protocol": "vless", "settings": {}}]}';
      expect(SingboxOutbounds.looksLike(xray), isFalse);
      expect(SingboxOutbounds.translate(xray).links, isEmpty);
    });

    test('ссылки, Clash и битый json — нет', () {
      expect(SingboxOutbounds.looksLike('vless://$_uuid@a.example:443'), isFalse);
      expect(SingboxOutbounds.looksLike('proxies:\n  - name: a'), isFalse);
      expect(SingboxOutbounds.looksLike('{"outbounds": [{"type"'), isFalse);
    });

    test('служебные аутбаунды — не серверы и не пропуски', () {
      final config = jsonEncode({
        'outbounds': [
          {'type': 'selector', 'tag': 'proxy', 'outbounds': ['auto']},
          {'type': 'urltest', 'tag': 'auto', 'outbounds': ['direct']},
          {'type': 'direct', 'tag': 'direct'},
          {'type': 'block', 'tag': 'block'},
          {'type': 'dns', 'tag': 'dns-out'},
        ],
      });
      final nodes = SingboxOutbounds.translate(config);
      expect(nodes.links, isEmpty);
      expect(nodes.skipped, isEmpty);
      expect(
        SingboxOutbounds.describeProblem(config),
        SingboxOutbounds.noServers,
      );
    });
  });

  group('vless', () {
    test('REALITY со всем, что делает его рабочим', () {
      final uri = Uri.parse(_link(_node('vless', {
        'uuid': _uuid,
        'flow': 'xtls-rprx-vision',
        'tls': {
          'enabled': true,
          'server_name': 'reality.example',
          'utls': {'enabled': true, 'fingerprint': 'firefox'},
          'reality': {'enabled': true, 'public_key': 'pbk', 'short_id': 'ab12'},
        },
      })));
      expect(uri.scheme, 'vless');
      expect(uri.userInfo, _uuid);
      expect(uri.host, '198.51.100.40');
      expect(uri.port, 443);
      expect(uri.fragment, 'node');
      expect(uri.queryParameters, {
        'security': 'reality',
        'sni': 'reality.example',
        'fp': 'firefox',
        'pbk': 'pbk',
        'sid': 'ab12',
        'flow': 'xtls-rprx-vision',
      });
    });

    test('websocket: путь, Host из заголовков, ранние данные', () {
      final link = _link(_node('vless', {
        'uuid': _uuid,
        'tls': {
          'enabled': true,
          'server_name': 'ws.example',
          'alpn': ['h2', 'http/1.1'],
        },
        'transport': {
          'type': 'ws',
          'path': '/ws',
          'headers': {'Host': 'cdn.example'},
          'max_early_data': 2048,
          'early_data_header_name': 'Sec-WebSocket-Protocol',
        },
      }));
      expect(_query(link), {
        'type': 'ws',
        'path': '/ws',
        'host': 'cdn.example',
        'ed': '2048',
        'security': 'tls',
        'sni': 'ws.example',
        'alpn': 'h2,http/1.1',
      });
    });

    // По умолчанию sing-box шлёт ранние данные хвостом пути. Наши ядра так не
    // умеют, а без ранних данных сервер соединение всё равно примет.
    test('ранние данные в пути или своём заголовке не переносятся', () {
      for (final header in ['', 'X-Early']) {
        final query = _query(_link(_node('vless', {
          'uuid': _uuid,
          'transport': {
            'type': 'ws',
            'path': '/ws',
            'max_early_data': 2048,
            'early_data_header_name': header,
          },
        })));
        expect(query.containsKey('ed'), isFalse, reason: header);
        expect(query.containsKey('eh'), isFalse, reason: header);
      }
    });

    test('gRPC и httpupgrade', () {
      expect(
        _query(_link(_node('vless', {
          'uuid': _uuid,
          'transport': {'type': 'grpc', 'service_name': 'svc'},
        }))),
        {'type': 'grpc', 'serviceName': 'svc'},
      );
      expect(
        _query(_link(_node('vless', {
          'uuid': _uuid,
          'transport': {
            'type': 'httpupgrade',
            'host': 'up.example',
            'path': '/up',
          },
        }))),
        {'type': 'httpupgrade', 'path': '/up', 'host': 'up.example'},
      );
    });

    // transport/v2rayhttp/client.go: HTTP/2 — только поверх TLS, без него —
    // HTTP/1.1, то есть маскировка `headerType=http`, а не транспорт h2.
    test('http: с TLS — HTTP/2, без TLS — маскировка поверх tcp', () {
      const transport = {
        'type': 'http',
        'host': ['a.example', 'b.example'],
        'path': '/p',
        'method': 'PUT',
      };
      expect(
        _query(_link(_node('vless', {
          'uuid': _uuid,
          'tls': {'enabled': true},
          'transport': transport,
        }))),
        {'type': 'http', 'path': '/p', 'host': 'a.example', 'security': 'tls'},
      );
      expect(
        _query(_link(_node('vless', {'uuid': _uuid, 'transport': transport}))),
        {
          'type': 'tcp',
          'headerType': 'http',
          'path': '/p',
          'host': 'a.example',
          'method': 'PUT',
        },
      );
    });

    test('упаковка UDP называется так, как её зовёт ссылка', () {
      String? encoding(String value) => _query(_link(_node('vless', {
            'uuid': _uuid,
            'packet_encoding': value,
          })))['packetEncoding'];
      expect(encoding('packetaddr'), 'packet');
      expect(encoding('xudp'), 'xudp');
      expect(encoding(''), isNull);
    });

    test('quic не соберёт ни одно ядро — узел в пропущенных', () {
      expect(
        _skipped(_node('vless', {
          'uuid': _uuid,
          'transport': {'type': 'quic'},
        })),
        {'vless over quic': 1},
      );
    });
  });

  group('vmess', () {
    test('base64-json со всеми полями, которые читают генераторы', () {
      final json = _vmessJson(_link(_node('vmess', {
        'uuid': _uuid,
        'security': 'aes-128-gcm',
        'alter_id': 2,
        'tls': {
          'enabled': true,
          'server_name': 'vm.example',
          'utls': {'enabled': true, 'fingerprint': 'safari'},
        },
        'transport': {
          'type': 'ws',
          'path': '/vm',
          'headers': {'Host': 'cdn.example'},
        },
      })));
      expect(json, {
        'v': '2',
        'ps': 'node',
        'add': '198.51.100.40',
        'port': '443',
        'id': _uuid,
        'aid': '2',
        'scy': 'aes-128-gcm',
        'net': 'ws',
        'type': 'none',
        'host': 'cdn.example',
        'path': '/vm',
        'tls': 'tls',
        'sni': 'vm.example',
        'fp': 'safari',
      });
    });

    test('имя gRPC-сервиса и ранние данные — в path, как у v2rayN', () {
      expect(
        _vmessJson(_link(_node('vmess', {
          'uuid': _uuid,
          'transport': {'type': 'grpc', 'service_name': 'svc'},
        })))['path'],
        'svc',
      );
      expect(
        _vmessJson(_link(_node('vmess', {
          'uuid': _uuid,
          'transport': {
            'type': 'ws',
            'path': '/vm',
            'max_early_data': 2048,
            'early_data_header_name': 'Sec-WebSocket-Protocol',
          },
        })))['path'],
        '/vm?ed=2048',
      );
    });

    test('HTTP/2 в json зовётся h2', () {
      expect(
        _vmessJson(_link(_node('vmess', {
          'uuid': _uuid,
          'tls': {'enabled': true},
          'transport': {'type': 'http'},
        })))['net'],
        'h2',
      );
    });

    test('REALITY у vmess не соберёт никто', () {
      expect(
        _skipped(_node('vmess', {
          'uuid': _uuid,
          'tls': {
            'enabled': true,
            'reality': {'enabled': true, 'public_key': 'pbk'},
          },
        })),
        {'vmess over reality': 1},
      );
    });
  });

  group('trojan', () {
    test('TLS и транспорт', () {
      final link = _link(_node('trojan', {
        'password': 'password',
        'tls': {'enabled': true, 'server_name': 't.example'},
        'transport': {'type': 'grpc', 'service_name': 'svc'},
      }));
      expect(Uri.parse(link).userInfo, 'password');
      expect(_query(link), {
        'type': 'grpc',
        'serviceName': 'svc',
        'security': 'tls',
        'sni': 't.example',
      });
    });

    test('REALITY', () {
      final query = _query(_link(_node('trojan', {
        'password': 'password',
        'tls': {
          'enabled': true,
          'reality': {'enabled': true, 'public_key': 'pbk', 'short_id': 'ab'},
        },
      })));
      expect(query['security'], 'reality');
      expect(query['pbk'], 'pbk');
      expect(query['sid'], 'ab');
    });

    // Генераторы собирают trojan всегда с TLS — в ссылках это чинит опечатку,
    // а здесь дало бы не тот сервер.
    test('без TLS — в пропущенных, а не сервером с чужим TLS', () {
      expect(
        _skipped(_node('trojan', {'password': 'password'})),
        {'trojan without tls': 1},
      );
    });
  });

  group('shadowsocks', () {
    test('метод и пароль в userInfo, плагин одной строкой SIP002', () {
      final uri = Uri.parse(_link(_node('shadowsocks', {
        'method': 'chacha20-ietf-poly1305',
        'password': 'password',
        'plugin': 'obfs-local',
        'plugin_opts': 'obfs=http;obfs-host=obfs.example',
      })));
      expect(
        utf8.decode(base64Url.decode(base64Url.normalize(uri.userInfo))),
        'chacha20-ietf-poly1305:password',
      );
      expect(
        uri.queryParameters['plugin'],
        'obfs-local;obfs=http;obfs-host=obfs.example',
      );
    });

    // sing-box без номера берёт вторую версию, mihomo — первую: номер обязан
    // ехать явно.
    test('UDP-over-TCP всегда с номером версии', () {
      Map<String, String> uot(Object value) => _query(_link(_node(
            'shadowsocks',
            {
              'method': 'aes-128-gcm',
              'password': 'password',
              'udp_over_tcp': value,
            },
          )));
      expect(uot(true), {'uot': '1', 'udp-over-tcp-version': '2'});
      expect(uot({'enabled': true}), {'uot': '1', 'udp-over-tcp-version': '2'});
      expect(
        uot({'enabled': true, 'version': 1}),
        {'uot': '1', 'udp-over-tcp-version': '1'},
      );
      expect(uot(false), isEmpty);
    });
  });

  test('shadowsocksr: все шесть частей и оба параметра', () {
    final ssr = SsrLink.tryParse(_link(_node('shadowsocksr', {
      'method': 'aes-256-cfb',
      'password': 'password',
      'obfs': 'http_simple',
      'obfs_param': 'o.example',
      'protocol': 'auth_aes128_md5',
      'protocol_param': '1:abc',
    })))!;
    expect(ssr.host, '198.51.100.40');
    expect(ssr.port, 443);
    expect(ssr.method, 'aes-256-cfb');
    expect(ssr.password, 'password');
    expect(ssr.obfs, 'http_simple');
    expect(ssr.obfsParam, 'o.example');
    expect(ssr.protocol, 'auth_aes128_md5');
    expect(ssr.protocolParam, '1:abc');
    expect(ssr.remarks, 'node');
  });

  group('hysteria2', () {
    test('перебор портов: диапазон через дефис, в адресе — первый порт', () {
      final uri = Uri.parse(_link(_node('hysteria2', {
        'password': 'password',
        'server_ports': ['20000:20050', '443'],
        'hop_interval': '1m',
        'up_mbps': 50,
        'down_mbps': 200,
        'obfs': {'type': 'salamander', 'password': 'obfs-pass'},
        'tls': {
          'enabled': true,
          'server_name': 'hy2.example',
          'alpn': ['h3'],
        },
      })));
      expect(uri.scheme, 'hysteria2');
      expect(uri.userInfo, 'password');
      expect(uri.port, 20000);
      expect(uri.queryParameters, {
        'sni': 'hy2.example',
        'alpn': 'h3',
        'obfs': 'salamander',
        'obfs-password': 'obfs-pass',
        'up': '50',
        'down': '200',
        'mport': '20000-20050,443',
        'hop-interval': '60',
      });
    });

    test('интервал — в целых секундах, как его ждут оба ядра', () {
      String? hop(String value) => _query(_link(_node('hysteria2', {
            'password': 'password',
            'server_ports': ['20000:20050'],
            'hop_interval': value,
          })))['hop-interval'];
      expect(hop('30s'), '30');
      expect(hop('1m30s'), '90');
      expect(hop('30'), '30');
      expect(hop('полминуты'), isNull);
    });

    test('без списка портов порт — свой', () {
      expect(
        Uri.parse(_link(_node('hysteria2', {'password': 'password'}))).port,
        443,
      );
    });
  });

  test('tuic: пара uuid:password и параметры QUIC', () {
    final uri = Uri.parse(_link(_node('tuic', {
      'uuid': _uuid,
      'password': 'pa@ss',
      'congestion_control': 'bbr',
      'udp_relay_mode': 'quic',
      'tls': {
        'enabled': true,
        'server_name': 'tuic.example',
        'alpn': ['h3'],
        'disable_sni': true,
      },
    })));
    expect(uri.userInfo, '$_uuid:pa%40ss');
    expect(uri.queryParameters, {
      'sni': 'tuic.example',
      'alpn': 'h3',
      'congestion_control': 'bbr',
      'udp_relay_mode': 'quic',
      'disable_sni': '1',
    });
  });

  test('anytls: пароль, имя сертификата и отпечаток', () {
    final link = _link(_node('anytls', {
      'password': 'password',
      'tls': {
        'enabled': true,
        'server_name': 'a.example',
        'utls': {'enabled': true, 'fingerprint': 'firefox'},
      },
    }));
    expect(Uri.parse(link).userInfo, 'password');
    expect(_query(link), {'sni': 'a.example', 'fp': 'firefox'});
  });

  group('чего в ссылке не бывает и почему', () {
    test('insecure не переносится никогда', () {
      final query = _query(_link(_node('trojan', {
        'password': 'password',
        'tls': {'enabled': true, 'insecure': true},
      })));
      for (final key in ['insecure', 'allowInsecure', 'allow_insecure']) {
        expect(query.containsKey(key), isFalse, reason: key);
      }
    });

    // Пин sing-box — хэш открытого ключа, а наши ядра сверяют хэш сертификата
    // целиком (GenerateCertHash у xray): переложить одно в другое нельзя.
    test('пин открытого ключа не выдаётся за пин сертификата', () {
      const tls = {
        'enabled': true,
        'certificate_public_key_sha256': ['YWFh'],
      };
      expect(
        _query(_link(_node('vless', {'uuid': _uuid, 'tls': tls}))),
        {'security': 'tls'},
      );
      expect(
        _query(_link(_node('hysteria2', {'password': 'p', 'tls': tls}))),
        isEmpty,
      );
      expect(
        _query(_link(_node('anytls', {'password': 'p', 'tls': tls}))),
        isEmpty,
      );
    });

    // Пустой отпечаток sing-box читает как chrome, но это его умолчание, а не
    // выбор автора: остаётся наше (tls_fingerprint.dart).
    test('uTLS без отпечатка не превращается в chrome', () {
      final query = _query(_link(_node('vless', {
        'uuid': _uuid,
        'tls': {
          'enabled': true,
          'utls': {'enabled': true},
        },
      })));
      expect(query.containsKey('fp'), isFalse);
    });

    test('ECH из PEM — тот же список голым base64', () {
      const body =
          'AEX+DQBBzQAgACD0RY0ZGF9nQqPMhTPT8xzDLoyPTgUYNGyLGUqPXGEXCg==';
      final link = _link(_node('vless', {
        'uuid': _uuid,
        'tls': {
          'enabled': true,
          'ech': {
            'enabled': true,
            'config': [
              '-----BEGIN ECH CONFIGS-----',
              body.substring(0, 30),
              body.substring(30),
              '-----END ECH CONFIGS-----',
            ],
          },
        },
      }));
      // `+` в значении читается по RFC 3986, а не как поле формы: разбор
      // формы сделал бы из него пробел.
      final raw = Uri.parse(link)
          .query
          .split('&')
          .firstWhere((pair) => pair.startsWith('ech='));
      expect(Uri.decodeComponent(raw.substring('ech='.length)), body);
    });

    test('ECH без списка (спроси у DNS) не переносится: резолвера у узла нет',
        () {
      final query = _query(_link(_node('vless', {
        'uuid': _uuid,
        'tls': {
          'enabled': true,
          'ech': {'enabled': true},
        },
      })));
      expect(query.containsKey('ech'), isFalse);
    });
  });

  group('пропущенные', () {
    test('чего не умеем — по типам, включая endpoints', () {
      final nodes = SingboxOutbounds.translate(_config(
        [
          _node('ssh', {'user': 'root'}),
          _node('hysteria', {'auth_str': 'password'}),
          _node('socks', {}),
          // Без uuid это не сервер.
          _node('vless', {}),
        ],
        endpoints: [
          {'type': 'wireguard', 'tag': 'wg'},
        ],
      ));
      expect(nodes.links, isEmpty);
      expect(nodes.skipped, {
        'ssh': 1,
        'hysteria': 1,
        'socks': 1,
        'vless': 1,
        'wireguard': 1,
      });
    });

    test('узел за другим узлом — цепочка, в пропущенных', () {
      final nodes = SingboxOutbounds.translate(_config([
        {
          'type': 'shadowtls',
          'tag': 'stls',
          'server': '198.51.100.40',
          'server_port': 443,
        },
        {
          ..._node('shadowsocks', {'method': 'aes-128-gcm', 'password': 'p'}),
          'detour': 'stls',
        },
      ]));
      expect(nodes.links, isEmpty);
      expect(nodes.skipped, {'shadowtls': 1, 'shadowsocks via detour': 1});
    });

    test('detour на direct — не цепочка', () {
      final nodes = SingboxOutbounds.translate(_config([
        {
          ..._node('shadowsocks', {'method': 'aes-128-gcm', 'password': 'p'}),
          'detour': 'direct',
        },
      ]));
      expect(nodes.links, hasLength(1));
    });

    test('ни одного нашего — причина называет типы', () {
      expect(
        SingboxOutbounds.describeProblem(_config([_node('ssh', {})])),
        allOf(contains('sing-box'), contains('1 of type ssh')),
      );
      expect(
        SingboxOutbounds.describeProblem(_config([
          _node('vless', {'uuid': _uuid}),
        ])),
        isNull,
      );
    });
  });

  group('корпус: каждую ссылку собирает ядро, выбранное для неё правилом', () {
    setUp(() => Socks5Credentials().init('u', 'p'));

    final nodes = SingboxOutbounds.translate(File(_corpus).readAsStringSync());

    test('взято двенадцать узлов, пропущено четыре', () {
      expect(nodes.links, hasLength(12));
      expect(nodes.skipped, {
        'ssh': 1,
        'hysteria': 1,
        'vless over quic': 1,
        'wireguard': 1,
      });
    });

    for (final (i, link) in nodes.links.indexed) {
      test('узел ${i + 1}: ${link.substring(0, link.indexOf('://'))}', () {
        final backends = backendsForLink(link);
        expect(backends, isNotEmpty);
        for (final backend in backends) {
          switch (backend.name) {
            case 'xray':
              expect(
                () => ConfigGeneratorV2.generateConfig(link, const AppSettings()),
                returnsNormally,
              );
            case 'mihomo':
              expect(
                () => MihomoConfigGen.build(
                  link,
                  const AppSettings(),
                  socksPort: 2080,
                ),
                returnsNormally,
              );
            default:
              fail('ссылка ушла не к прокси-ядру: $link');
          }
        }
      });
    }

    // То, что sing-box пишет не так, как ссылка, обязано доехать до ядра в
    // его собственном виде.
    test('диапазон портов и версия UoT доезжают до mihomo как надо', () {
      Map<String, dynamic> proxy(String prefix) {
        final config = MihomoConfigGen.build(
          nodes.links.firstWhere((l) => l.startsWith(prefix)),
          const AppSettings(),
          socksPort: 2080,
        );
        return (config['proxies'] as List).first as Map<String, dynamic>;
      }

      expect(proxy('hysteria2://')['ports'], '20000-20050');
      expect(proxy('hysteria2://')['hop-interval'], '30');
      final ss = proxy('ss://');
      expect(ss['udp-over-tcp'], isTrue);
      expect(ss['udp-over-tcp-version'], 2);
    });
  });
}
