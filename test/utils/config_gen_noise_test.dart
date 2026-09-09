import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// Шум перед UDP — единственное средство обхода, которое есть у UDP-серверов:
/// фрагментация ClientHello там не работает по устройству, резать нечего.
///
/// Ключ `finalmask` ядро пишет строчными, хотя всё вокруг camelCase. Ошибка в
/// имени не видна ничем: неизвестный ключ xray выбрасывает молча, конфиг
/// поднимается, а шума нет. Поэтому имя проверяется буквой, а не смыслом.
const _hy2 = 'hysteria2://password@host.example:443?sni=hy2.example';
const _vless = 'vless://uuid@host.example:443?type=tcp&security=tls&sni=x.example';

AppSettings _noise({
  String kind = XrayCoreSettings.noiseRandom,
  String packet = '',
  String randLength = XrayCoreSettings.defaultNoiseRandLength,
  String randBytes = '',
  String delay = '',
  String reset = '',
}) =>
    AppSettings(
      xrayCore: XrayCoreSettings(
        noiseEnabled: true,
        noiseKind: kind,
        noisePacket: packet,
        noiseRandLength: randLength,
        noiseRandBytes: randBytes,
        noiseDelay: delay,
        noiseReset: reset,
      ),
    );

Map<String, dynamic>? _stream(String uri, AppSettings settings) {
  Socks5Credentials().init('u', 'p');
  final config =
      jsonDecode(ConfigGeneratorV2.generateConfig(uri, settings)) as Map<String, dynamic>;
  final outbound = (config['outbounds'] as List).first as Map<String, dynamic>;
  return outbound['streamSettings'] as Map<String, dynamic>?;
}

List<dynamic>? _udpMask(String uri, AppSettings settings) =>
    (_stream(uri, settings)?['finalmask'] as Map<String, dynamic>?)?['udp']
        as List<dynamic>?;

Map<String, dynamic>? _noiseItem(String uri, AppSettings settings) {
  final udp = _udpMask(uri, settings);
  final entry = udp?.cast<Map<String, dynamic>>().firstWhere(
        (e) => e['type'] == 'noise',
        orElse: () => <String, dynamic>{},
      );
  final settingsMap = entry?['settings'] as Map<String, dynamic>?;
  return (settingsMap?['noise'] as List?)?.first as Map<String, dynamic>?;
}

void main() {
  group('куда шум попадает', () {
    test('ключ называется finalmask строчными, как ждёт ядро', () {
      final stream = _stream(_hy2, _noise())!;
      expect(stream.containsKey('finalmask'), isTrue);
      expect(stream.containsKey('finalMask'), isFalse);
    });

    test('случайный мусор: rand есть, packet нет — вместе ядро их не берёт', () {
      final item = _noiseItem(_hy2, _noise())!;
      expect(item['rand'], XrayCoreSettings.defaultNoiseRandLength);
      expect(item.containsKey('packet'), isFalse);
      expect(item.containsKey('type'), isFalse);
    });

    test('свой пакет: packet и его кодировка есть, rand нет', () {
      final item = _noiseItem(
        _hy2,
        _noise(kind: XrayCoreSettings.noiseHex, packet: 'deadbeef'),
      )!;
      expect(item['type'], 'hex');
      expect(item['packet'], 'deadbeef');
      expect(item.containsKey('rand'), isFalse);
    });

    test('пустой пакет — не тишина, а откат на мусор', () {
      final item = _noiseItem(
        _hy2,
        _noise(kind: XrayCoreSettings.noiseBase64, packet: '   '),
      )!;
      expect(item['rand'], XrayCoreSettings.defaultNoiseRandLength);
      expect(item.containsKey('packet'), isFalse);
    });

    test('салмандер из ссылки остаётся, шум дописывается следом', () {
      final udp = _udpMask(
        '$_hy2&obfs=salamander&obfs-password=pass',
        _noise(),
      )!;
      expect(udp.map((e) => (e as Map)['type']), ['salamander', 'noise']);
    });

    test('число и диапазон едут как есть: ядро принимает оба вида', () {
      final item = _noiseItem(
        _hy2,
        _noise(randLength: '128', delay: '5-20', randBytes: '32-126'),
      )!;
      expect(item['rand'], 128);
      expect(item['delay'], '5-20');
      expect(item['randRange'], '32-126');
    });

    test('reset лежит рядом с noise, а не внутри пакета', () {
      final udp = _udpMask(_hy2, _noise(reset: '60'))!;
      final entry = udp.single as Map<String, dynamic>;
      expect((entry['settings'] as Map)['reset'], 60);
    });
  });

  group('куда шум не попадает', () {
    test('выключен — ключа finalmask нет вовсе', () {
      expect(_stream(_hy2, const AppSettings())?['finalmask'], isNull);
    });

    test('TCP-сервер: там работает фрагментация, шуметь нечем', () {
      expect(_stream(_vless, _noise())?['finalmask'], isNull);
    });

    test('мусор нулевой длины не отправляется: пустое поле — это дефолт', () {
      // Пустой rand у ядра означает нулевую длину, то есть шума не будет вовсе.
      // Поэтому мусор без длины откатывается на умолчание, а не уезжает пустым.
      expect(
        _noiseItem(_hy2, _noise(randLength: '  '))?['rand'],
        XrayCoreSettings.defaultNoiseRandLength,
      );
    });

    test('нечисловые диапазоны выбрасываются, а не роняют конфиг', () {
      final item = _noiseItem(
        _hy2,
        _noise(delay: 'быстро', randBytes: 'много', reset: 'иногда'),
      )!;
      expect(item.containsKey('delay'), isFalse);
      expect(item.containsKey('randRange'), isFalse);
      final udp = _udpMask(_hy2, _noise(reset: 'иногда'))!;
      expect(
        ((udp.single as Map)['settings'] as Map).containsKey('reset'),
        isFalse,
      );
    });
  });
}
