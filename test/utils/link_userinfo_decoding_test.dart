import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// Пароль из userInfo ссылки — раскодированным, на обоих ядрах.
///
/// Стандарт ссылки кодирует спецсимволы пароля (`p@ss:w` → `p%40ss%3Aw`), и
/// разбор самого mihomo его раскодирует. Генераторы брали userInfo как есть, и
/// в ядро уезжал `p%40ss%3Aw` — сервер такой пароль не принимал. Перепись
/// параметров этого не видит: сменить пароль значит сменить конфиг при любом
/// разборе.

Map<String, dynamic> _xrayProxy(String link) {
  final config = jsonDecode(
    ConfigGeneratorV2.generateConfig(link, const AppSettings()),
  ) as Map<String, dynamic>;
  return (config['outbounds'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((o) => o['tag'] == 'proxy');
}

Map<String, dynamic> _mihomoProxy(String link) =>
    (MihomoConfigGen.build(link, const AppSettings(), socksPort: 2080)['proxies']
            as List)
        .first as Map<String, dynamic>;

String _xrayTrojanPassword(String link) =>
    (_xrayProxy(link)['settings'] as Map)['password'] as String;

String _xrayHysteriaAuth(String link) =>
    ((_xrayProxy(link)['streamSettings'] as Map)['hysteriaSettings']
        as Map)['auth'] as String;

void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  test('trojan: закодированный пароль раскодирован на обоих ядрах', () {
    const link = 'trojan://p%40ss%3Aw@198.51.100.44:443?security=tls'
        '&sni=t.example#t';
    expect(_xrayTrojanPassword(link), 'p@ss:w');
    expect(_mihomoProxy(link)['password'], 'p@ss:w');
  });

  test('hysteria2: закодированный пароль раскодирован на обоих ядрах', () {
    const link = 'hysteria2://p%40ss@198.51.100.49:443?sni=hy2.example#h';
    expect(_xrayHysteriaAuth(link), 'p@ss');
    expect(_mihomoProxy(link)['password'], 'p@ss');
  });

  test('закодированный знак процента — это процент', () {
    const link = 'trojan://100%25@198.51.100.44:443?security=tls#t';
    expect(_xrayTrojanPassword(link), '100%');
    expect(_mihomoProxy(link)['password'], '100%');
  });

  test('обычный пароль не меняется', () {
    const link = 'trojan://password@198.51.100.44:443?security=tls#t';
    expect(_xrayTrojanPassword(link), 'password');
    expect(_mihomoProxy(link)['password'], 'password');
  });
}
