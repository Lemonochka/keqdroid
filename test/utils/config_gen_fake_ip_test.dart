import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/fake_ip.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

// Fake-ip на Android: TUN держит сам xray, подменный адрес отдаёт его
// fakedns, а обратно в домен его превращает снифер tun-инбаунда.
const _link =
    'vless://0e0f3003-f4d9-46ef-b0b5-79c4223caa6c@198.51.100.25:443'
    '?type=tcp&security=none#t';

Map<String, dynamic> _gen(
  String input,
  AppSettings settings, {
  bool nativeTun = true,
}) =>
    jsonDecode(
          ConfigGeneratorV2.generateConfig(
            input,
            settings,
            nativeTunInbound: nativeTun,
          ),
        )
        as Map<String, dynamic>;

List<Object?> _servers(Map<String, dynamic> c) =>
    (c['dns'] as Map)['servers'] as List;

String _address(Object? s) =>
    s is String ? s : ((s as Map)['address'] as String);

Map<String, dynamic> _tunSniffing(Map<String, dynamic> c) =>
    ((c['inbounds'] as List).cast<Map<Object?, Object?>>().firstWhere(
              (i) => i['tag'] == 'tun-in',
            )['sniffing']
            as Map)
        .cast<String, dynamic>();

void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  test('включённый: пул, подмена в DNS и снифер с fakedns', () {
    final c = _gen(_link, const AppSettings(fakeIp: true));
    expect(c['fakedns'], [
      {'ipPool': kFakeIpRange, 'poolSize': 65535},
    ]);
    expect(_servers(c).map(_address), contains('fakedns'));
    expect(_tunSniffing(c)['destOverride'], contains('fakedns'));
  });

  // Ядро опрашивает по доменам, потом всех остальных по порядку, кроме
  // skipFallback: подмена обязана быть первой в этом переборе.
  test('fakedns — первый в общем переборе, исключения только за своих', () {
    final servers = _servers(_gen(_link, const AppSettings(fakeIp: true)));
    final fakeAt = servers.indexWhere((s) => _address(s) == 'fakedns');
    for (final s in servers.take(fakeAt)) {
      expect(
        (s as Map)['skipFallback'],
        isTrue,
        reason: '$s ответил бы раньше подмены',
      );
    }
    final exclusions = servers[fakeAt - 1] as Map;
    expect(exclusions['domains'], fakeIpFilterAsRules());
    expect(
      servers.skip(fakeAt + 1),
      isNotEmpty,
      reason: 'резолверы после подмены нужны собственным запросам ядра',
    );
  });

  test('без своего туннеля и в пробе пинга подмены нет', () {
    final proxyMode = _gen(
      _link,
      const AppSettings(fakeIp: true),
      nativeTun: false,
    );
    expect(proxyMode.containsKey('fakedns'), isFalse);
    expect(jsonEncode(proxyMode), isNot(contains('fakedns')));

    final ping =
        jsonDecode(
              ConfigGeneratorV2.generatePingConfig(
                _link,
                const AppSettings(fakeIp: true),
                socksPort: 20999,
              ),
            )
            as Map<String, dynamic>;
    expect(jsonEncode(ping), isNot(contains('fakedns')));
  });

  test('выключенный снифер оживает только на fakedns', () {
    final c = _gen(
      _link,
      const AppSettings(fakeIp: true).copyWith(
        xrayCore: const AppSettings().xrayCore.copyWith(sniffingEnabled: false),
      ),
    );
    expect(_tunSniffing(c), {
      'enabled': true,
      'destOverride': ['fakedns'],
      'metadataOnly': true,
    });
  });

  group('готовый конфиг', () {
    String custom(Map<String, dynamic> dns) => jsonEncode({
      'dns': dns,
      'outbounds': [
        {
          'tag': 'proxy',
          'protocol': 'freedom',
          'settings': <String, dynamic>{},
        },
      ],
    });

    // Как у провайдера из жалобы: первым стоит голый 1.1.1.1.
    test('подмена встаёт перед первым общим сервером автора', () {
      final servers = _servers(
        _gen(
          custom({
            'servers': [
              '1.1.1.1',
              {
                'address': 'localhost',
                'domains': ['domain:corp.example'],
                'skipFallback': true,
              },
            ],
          }),
          const AppSettings(fakeIp: true),
        ),
      );
      expect(_address(servers[0]), 'tcp://1.1.1.1:53');
      expect((servers[0] as Map)['skipFallback'], isTrue);
      expect(_address(servers[1]), 'fakedns');
      expect(servers[2], 'tcp://1.1.1.1:53');
    });

    test('свой fakedns автора не трогаем', () {
      final c = _gen(
        custom({
          'servers': ['fakedns', '1.1.1.1'],
        }),
        const AppSettings(fakeIp: true),
      );
      expect(_servers(c).where((s) => _address(s) == 'fakedns'), hasLength(1));
      expect(c.containsKey('fakedns'), isFalse);
    });
  });
}
