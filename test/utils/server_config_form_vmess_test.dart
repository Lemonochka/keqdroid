import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/server_config_form.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

// 12.11.2026: у vmess редактор показывал режим, extra, seed и прочее, а при сохранении молча терял.
// проверяем не ключи ссылки, а то, что из правки получит ядро
const _id = '716e3485-d4f9-4471-9660-fb4b0b838100';

String _vmess(Map<String, Object?> json) =>
    'vmess://${base64.encode(utf8.encode(jsonEncode(json)))}';

Map<String, Object?> _base(String net, [Map<String, Object?> more = const {}]) =>
    {'v': '2', 'ps': 'n', 'add': '198.51.100.30', 'port': 443, 'id': _id, 'net': net, ...more};

Map<String, dynamic> _payload(String link) =>
    jsonDecode(utf8.decode(base64.decode(link.substring('vmess://'.length))))
        as Map<String, dynamic>;

({ServerConfigForm form, String Function(Map<String, String>, [Map<String, String>]) edit})
    _open(String link) {
  final form = ServerConfigForm();
  expect(form.parse(link), isNull);
  return (
    form: form,
    edit: (text, [drop = const {}]) {
      form.drop.addAll(drop);
      return form.build((id) => text[id] ?? form.parsedText[id]?.trim() ?? '');
    },
  );
}

Map<String, dynamic> _stream(String link) {
  Socks5Credentials().init('u', 'p');
  final config = jsonDecode(
    ConfigGeneratorV2.generateConfig(link, const AppSettings()),
  ) as Map<String, dynamic>;
  final proxy = (config['outbounds'] as List).first as Map<String, dynamic>;
  return proxy['streamSettings'] as Map<String, dynamic>;
}

void main() {
  group('xhttp', () {
    final link = _vmess(_base('xhttp', {
      'path': '/x',
      'host': 'h.example',
      'mode': 'packet-up',
      'extra': {
        'xmux': {'maxConcurrency': '16-32'},
      },
    }));

    test('режим и extra из ссылки видны полями', () {
      final form = _open(link).form;
      expect(form.drop['mode'], 'packet-up');
      expect(jsonDecode(form.parsedText['extra']!), {
        'xmux': {'maxConcurrency': '16-32'},
      });
    });

    test('правка режима и extra доезжает до ядра', () {
      final built = _open(link).edit(
        {'extra': '{"xPaddingBytes":"50-150"}'},
        {'mode': 'stream-up'},
      );
      final xhttp = _stream(built)['xhttpSettings'] as Map;
      expect(xhttp['mode'], 'stream-up');
      expect(xhttp['extra'], {'xPaddingBytes': '50-150'});
      expect(_payload(built)['extra'], {'xPaddingBytes': '50-150'},
          reason: 'extra пришёл объектом, объектом и уходит');
    });

    test('extra строкой остаётся строкой', () {
      final built = _open(_vmess(_base('xhttp', {'extra': '{"a":1}'})))
          .edit({'extra': '{"a":2}'});
      expect(_payload(built)['extra'], '{"a":2}');
      expect((_stream(built)['xhttpSettings'] as Map)['extra'], {'a': 2});
    });

    test('плоская набивка в одном поле с extra', () {
      final opened =
          _open(_vmess(_base('xhttp', {'x_padding_bytes': '100-1000'})));
      expect(opened.form.parsedText['x_padding_bytes'], '');
      expect(jsonDecode(opened.form.parsedText['extra']!),
          {'xPaddingBytes': '100-1000'});

      final built = opened.edit({'address': 'edited.example.com'});
      expect(_payload(built).containsKey('x_padding_bytes'), isFalse);
      expect((_stream(built)['xhttpSettings'] as Map)['extra'],
          {'xPaddingBytes': '100-1000'});
    });
  });

  test('grpc: имя сервиса, режим и authority там, где их читает ядро', () {
    final opened = _open(_vmess(_base('grpc', {'path': 'svc', 'tls': 'tls'})));
    expect(opened.form.parsedText['serviceName'], 'svc');

    final built = opened.edit(
      {'serviceName': 'svc2', 'authority': 'a.example'},
      {'mode': 'multi'},
    );
    final grpc = _stream(built)['grpcSettings'] as Map;
    expect(grpc['serviceName'], 'svc2');
    expect(grpc['multiMode'], isTrue);
    expect(grpc['authority'], 'a.example');
  });

  test('grpc: имя из serviceName, которое писал прежний редактор, не теряется', () {
    final opened = _open(_vmess(_base('grpc', {'serviceName': 'old'})));
    expect(opened.form.parsedText['serviceName'], 'old');
    final built = opened.edit({'address': 'edited.example.com'});
    expect((_stream(built)['grpcSettings'] as Map)['serviceName'], 'old');
  });

  test('kcp: seed, заголовок, mtu и tti', () {
    final opened = _open(_vmess(_base('kcp', {
      'type': 'srtp',
      'path': 'seed1',
      'mtu': 1350,
      'tti': 50,
    })));
    expect(opened.form.parsedText['seed'], 'seed1');
    expect(opened.form.drop['headerType'], 'srtp');
    expect(opened.form.parsedText['mtu'], '1350');

    final built = opened.edit(
      {'seed': 'seed2', 'mtu': '1400', 'tti': '20'},
      {'headerType': 'dtls'},
    );
    final stream = _stream(built);
    expect(stream['kcpSettings'], {'mtu': 1400, 'tti': 20});
    expect(jsonEncode(stream['finalmask']), contains('seed2'));
    expect(jsonEncode(stream['finalmask']), contains('dtls'));
    expect(_payload(built)['mtu'], 1400, reason: 'число было числом');
  });

  test('ws: ранние данные и проверка сертификата', () {
    final built = _open(_vmess(_base('ws', {'path': '/ws', 'tls': 'tls'}))).edit({
      'ed': '2048',
      'pcs': 'ab12',
      'vcn': 'b.example',
    });
    final stream = _stream(built);
    expect((stream['wsSettings'] as Map)['path'], contains('ed=2048'));
    final tls = stream['tlsSettings'] as Map;
    expect(tls['pinnedPeerCertSha256'], 'ab12');
    expect(tls['verifyPeerCertByName'], 'b.example');
  });

  test('tcp: http-заголовок с хостом, путём и методом', () {
    final built = _open(_vmess(_base('tcp'))).edit(
      {'host': 'h.example', 'path': '/p', 'method': 'POST'},
      {'headerType': 'http'},
    );
    final header = (_stream(built)['tcpSettings'] as Map)['header'] as Map;
    expect(header['type'], 'http');
    expect(jsonEncode(header), contains('POST'));
    expect(jsonEncode(header), contains('h.example'));
  });

  test('без правок ws-сервер собирается как был', () {
    final link = _vmess(_base('ws', {
      'type': 'none',
      'path': '/ws',
      'host': 'h.example',
      'tls': 'tls',
    }));
    expect(_payload(_open(link).edit({})), _payload(link));
  });
}
