import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/utils/awg_profile.dart';
import 'package:keqdroid/utils/awg_uri.dart';
import 'package:keqdroid/utils/import_payload.dart';

void main() {
  // Ключи с '+' и '/' внутри — ровно те символы, на которых ломается разбор
  // query через Uri.queryParameters.
  const priv = '10YOue8MajJuVp5aQVVYv9Q7syNlHr/bTIsMkkRL/6M=';
  const pub = 'bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=';

  const warp = 'wg://engage.cloudflareclient.com:4500'
      '?private_key=10YOue8MajJuVp5aQVVYv9Q7syNlHr/bTIsMkkRL/6M%3D'
      '&local_address=172.16.0.2/32-2606:4700:110:8620:87e2:71e1:8d9d:1bc2/128'
      '&mtu=1280&enable_amnezia=true&jc=4&jmin=40&jmax=70'
      '&h1=1&h2=2&h3=3&h4=4&i1=%3Cb%200xc70000000108%3E'
      '&public_key=bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo%3D'
      '#WARP';

  test('узнаёт ссылку по схеме', () {
    expect(AwgUri.looksLikeUri(warp), isTrue);
    expect(AwgUri.looksLikeUri('wireguard://x@1.2.3.4:51820?'), isTrue);
    expect(AwgUri.looksLikeUri('vless://abc'), isFalse);
    expect(AwgUri.looksLikeUri('[Interface]'), isFalse);
  });

  test('разворачивает ссылку в .conf, который принимает наш же парсер', () {
    final conf = AwgUri.toConf(warp);
    final profile = AwgProfile.parse(conf);

    // Плюс в base64-ключе обязан пережить разбор: queryParameters превратил бы
    // его в пробел, и ключ поехал бы в ядро битым.
    expect(profile.iface.privateKey, priv);
    expect(profile.peer.publicKey, pub);
    expect(profile.peer.endpoint, 'engage.cloudflareclient.com:4500');
    expect(profile.remark, 'WARP');
    expect(profile.iface.addresses, [
      '172.16.0.2/32',
      '2606:4700:110:8620:87e2:71e1:8d9d:1bc2/128',
    ]);
    expect(profile.iface.mtu, 1280);
    expect(profile.iface.awgParams, {
      'jc': '4',
      'jmin': '40',
      'jmax': '70',
      'h1': '1',
      'h2': '2',
      'h3': '3',
      'h4': '4',
      'i1': '<b 0xc70000000108>',
    });
    // В ссылке их нет, а без них туннель поднимается и не везёт ничего
    // (AllowedIPs) или молча рвётся за NAT (keepalive).
    expect(profile.peer.allowedIps, ['0.0.0.0/0', '::/0']);
    expect(profile.peer.persistentKeepalive, '25');
  });

  test('свои AllowedIPs, DNS и keepalive из ссылки не перетираются', () {
    final conf = AwgUri.toConf(
      'wg://203.0.113.10:51820?private_key=$priv&public_key=$pub'
      '&address=10.8.0.2/32&dns=1.1.1.1,8.8.8.8'
      '&allowed_ips=10.0.0.0/8,192.168.0.0/16&persistent_keepalive=15',
    );
    final profile = AwgProfile.parse(conf);

    expect(profile.iface.dns, ['1.1.1.1', '8.8.8.8']);
    expect(profile.peer.allowedIps, ['10.0.0.0/8', '192.168.0.0/16']);
    expect(profile.peer.persistentKeepalive, '15');
  });

  test('ключ из userInfo и IPv6-endpoint в скобках', () {
    final conf = AwgUri.toConf(
      'wireguard://$priv@[2606:4700:110::1]:4500'
      '?public_key=$pub&address=10.8.0.2/32',
    );
    final profile = AwgProfile.parse(conf);

    expect(profile.iface.privateKey, priv);
    expect(profile.peer.endpoint, '[2606:4700:110::1]:4500');
    expect(profile.endpointHost, '2606:4700:110::1');
    expect(profile.endpointPort, 4500);
  });

  test('enable_amnezia=false выкидывает обфускацию', () {
    final conf = AwgUri.toConf(
      'wg://203.0.113.10:51820?private_key=$priv&public_key=$pub'
      '&address=10.8.0.2/32&enable_amnezia=false&jc=4&jmin=40&jmax=70',
    );

    expect(AwgProfile.parse(conf).iface.awgParams, isEmpty);
  });

  group('импорт', () {
    test('ссылка проходит валидацию и хранится уже как .conf', () {
      expect(ServersNotifier.validateServerConfig(warp), isNull);

      final stored = ServersNotifier.normalizeImportedConfig(warp);
      expect(AwgProfile.isAwgConfig(stored), isTrue);

      // Имя из #фрагмента и протокол — то же, что у импорта файлом.
      final item = ServerItem.fromRaw(stored);
      expect(item.protocol, 'awg');
      expect(item.derivedName, 'WARP');
      expect(item.address, 'engage.cloudflareclient.com');
      expect(item.port, 4500);
    });

    test('битую ссылку объясняем ею самой, а не «Unsupported format»', () {
      final error = ServersNotifier.validateServerConfig(
        'wg://203.0.113.10:51820?public_key=$pub',
      );
      expect(error, contains('AmneziaWG link'));
      expect(error, contains('private_key'));
      // Нормализация битую ссылку не трогает — сообщение остаётся одно.
      expect(
        ServersNotifier.normalizeImportedConfig(
          'wg://203.0.113.10:51820?public_key=$pub',
        ),
        startsWith('wg://'),
      );
    });

    test('несколько ссылок в буфере — это несколько серверов', () {
      final configs = splitServerImportPayload(
        '$warp\nwg://203.0.113.10:51820?private_key=$priv&public_key=$pub'
        '&address=10.8.0.2/32#Second',
      );

      expect(configs.length, 2);
      for (final c in configs) {
        expect(ServersNotifier.validateServerConfig(c), isNull);
      }
    });
  });

  test('чего не хватает — то и в ошибке', () {
    expect(
      () => AwgUri.toConf('wg://203.0.113.10:51820?public_key=$pub'),
      throwsA(
        isA<ArgumentError>().having(
          (e) => '${e.message}',
          'message',
          contains('private_key'),
        ),
      ),
    );
    expect(
      () => AwgUri.toConf('wg://203.0.113.10:51820?private_key=$priv'),
      throwsA(
        isA<ArgumentError>().having(
          (e) => '${e.message}',
          'message',
          contains('public_key'),
        ),
      ),
    );
    expect(
      () => AwgUri.toConf('wg://203.0.113.10?private_key=$priv&public_key=$pub'
          '&address=10.8.0.2/32'),
      throwsA(
        isA<ArgumentError>().having(
          (e) => '${e.message}',
          'message',
          contains('port'),
        ),
      ),
    );
    expect(
      () => AwgUri.toConf(
        'wg://203.0.113.10:51820?private_key=$priv&public_key=$pub',
      ),
      throwsA(
        isA<ArgumentError>().having(
          (e) => '${e.message}',
          'message',
          contains('local_address'),
        ),
      ),
    );
  });
}
