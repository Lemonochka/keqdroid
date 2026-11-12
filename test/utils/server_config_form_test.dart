import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/server_config_form.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

import '../helpers/server_config_form_corpus.dart';

String _fieldsOf(ServerConfigForm form, String id) =>
    form.parsedText[id]?.trim() ?? '';

void main() {
  final golden = jsonDecode(File(serverConfigFormGolden).readAsStringSync())
      as Map<String, dynamic>;

  serverConfigFormCorpus.forEach((name, link) {
    test('$name: rebuilds as the editor did', () {
      final form = ServerConfigForm();
      expect(form.parse(link), isNull);
      final built = form.build(
        (id) => id == 'address' ? 'edited.example.com' : _fieldsOf(form, id),
      );
      expect(built, golden[name]);
    });
  });

  test('building twice gives the same link', () {
    final form = ServerConfigForm();
    form.parse(serverConfigFormCorpus['vless reality tcp vision']!);
    String text(String id) => _fieldsOf(form, id);
    expect(form.build(text), form.build(text));
  });

  group('links the form cannot show', () {
    final cases = <String, String>{
      'socks://198.51.100.1:1080': 'raw-only protocol',
      'ss://198.51.100.1:8388': 'ss without userinfo',
      'ss://%%%@198.51.100.1:8388': 'bad ss base64',
      // base64 от строки без двоеточия
      'ss://${base64.encode(utf8.encode('nocolon'))}@198.51.100.1:8388':
          'bad ss userinfo',
      'vmess://not-base64!': 'bad vmess payload',
      'vmess://${base64.encode(utf8.encode('[1]'))}':
          'vmess payload is not a map',
    };
    cases.forEach((link, error) {
      test(error, () => expect(ServerConfigForm().parse(link), error));
    });
  });

  group('Clash', () {
    final node = {'name': 'n', 'type': 'ss', 'server': 'a.example', 'port': 1};

    test('a single node becomes fields and is rebuilt with its config', () {
      final config = jsonEncode({
        'mode': 'rule',
        'proxies': [node],
      });
      final form = ServerConfigForm();
      expect(form.parse(config), isNull);
      expect(form.protocol, 'clash');

      final edited = {...node, 'port': 2};
      final built = jsonDecode(form.build((_) => jsonEncode(edited)));
      expect(built['mode'], 'rule');
      expect(built['proxies'], [edited]);
    });

    test('a profile with groups stays text', () {
      final config = jsonEncode({
        'proxies': [node],
        'proxy-groups': [
          {'name': 'g', 'type': 'select', 'proxies': ['n']},
        ],
      });
      expect(ServerConfigForm().parse(config), 'raw-only protocol');
    });
  });

  test('reset clears fields and keeps the protocol for a failed reparse', () {
    final form = ServerConfigForm();
    form.parse(serverConfigFormCorpus['trojan plain']!);
    expect(form.protocol, 'trojan');
    form.reset();
    expect(form.parsedText, isEmpty);
    expect(form.drop, isEmpty);
    expect(form.toggle, isEmpty);
    expect(form.parse('socks://198.51.100.1:1080'), 'raw-only protocol');
    expect(form.protocol, 'trojan');
  });

  // 12.11.2026: в «Остальных параметрах» висел "mode": "auto", а режим уже стоял в «Транспорте»
  group('host, path и mode из extra', () {
    String xhttp(String query, Map<String, Object?> extra) =>
        'vless://716e3485-d4f9-4471-9660-fb4b0b838100@example.com:443'
        '?type=xhttp&security=tls&sni=example.com$query'
        '&extra=${Uri.encodeQueryComponent(jsonEncode(extra))}#n';

    ServerConfigForm parsed(String link) {
      final form = ServerConfigForm();
      expect(form.parse(link), isNull);
      return form;
    }

    Map<String, dynamic> core(ServerConfigForm form) {
      Socks5Credentials().init('u', 'p');
      final link = form.build(
        (id) => id == 'address' ? 'edited.example.com' : _fieldsOf(form, id),
      );
      final config = jsonDecode(
        ConfigGeneratorV2.generateConfig(link, const AppSettings()),
      ) as Map<String, dynamic>;
      final proxy = (config['outbounds'] as List).first as Map;
      return (proxy['streamSettings'] as Map)['xhttpSettings'] as Map<String, dynamic>;
    }

    test('повтор режима уходит из extra, остальное в нём остаётся', () {
      final form = parsed(
        xhttp('&mode=auto', {'mode': 'auto', 'xPaddingBytes': '100-1342'}),
      );
      expect(form.drop['mode'], 'auto');
      expect(jsonDecode(form.parsedText['extra']!), {'xPaddingBytes': '100-1342'});
    });

    test('режим только в extra встаёт в Транспорт, и xray его видит', () {
      final form = parsed(xhttp('', {'mode': 'packet-up'}));
      expect(form.drop['mode'], 'packet-up');
      expect(form.parsedText['extra'], '');

      final settings = core(form);
      expect(settings['mode'], 'packet-up');
      expect(settings.containsKey('extra'), isFalse);
    });

    test('host и path так же, а заданные снаружи не перебиваются', () {
      final form = parsed(
        xhttp('&path=%2Fouter', {'host': 'h.example', 'path': '/inner'}),
      );
      expect(form.parsedText['host'], 'h.example');
      expect(form.parsedText['path'], '/outer');
      expect(form.parsedText['extra'], '');

      final settings = core(form);
      expect(settings['host'], 'h.example');
      expect(settings['path'], '/outer');
    });

    test('extra без повторов не переписывается', () {
      final form = parsed(xhttp('&mode=auto', {'xPaddingBytes': '1-2', 'b': 1}));
      expect(form.parsedText['extra'], '{"xPaddingBytes":"1-2","b":1}');
    });
  });
}
