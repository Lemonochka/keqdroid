import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/xray_session_log.dart';

/// xray сессии на десктопе работает не тише info: отказы дозвона до своего
/// сервера xray 26.x пишет только там. Лог при этом должен остаться ровно
/// таким, какой заказан в настройках.
String _config(String? level) => jsonEncode({
      if (level != null) 'log': {'loglevel': level, 'access': 'none'},
      'outbounds': [
        {'protocol': 'vless', 'tag': 'proxy'},
      ],
    });

String? _levelOf(String config) =>
    ((jsonDecode(config) as Map)['log'] as Map?)?['loglevel'] as String?;

void main() {
  group('подъём уровня', () {
    test('warning, error, none поднимаются до info, порог — выбранный', () {
      for (final (level, threshold) in [
        ('warning', 2),
        ('error', 3),
        ('none', 4),
      ]) {
        final raised = XraySessionLog.raise(_config(level));
        expect(_levelOf(raised.config), 'info', reason: level);
        expect(raised.threshold, threshold, reason: level);
      }
    });

    test('без поля log — это warning, и он тоже поднимается', () {
      final raised = XraySessionLog.raise(_config(null));
      expect(_levelOf(raised.config), 'info');
      expect(raised.threshold, 2);
    });

    test('info и debug не трогаются', () {
      for (final level in ['info', 'debug']) {
        final config = _config(level);
        final raised = XraySessionLog.raise(config);
        expect(raised.config, config, reason: level);
        expect(raised.threshold, 0, reason: level);
      }
    });

    test('остальной конфиг и соседние поля log не меняются', () {
      final raised = XraySessionLog.raise(_config('warning'));
      final json = jsonDecode(raised.config) as Map;
      expect((json['log'] as Map)['access'], 'none');
      expect(json['outbounds'], [
        {'protocol': 'vless', 'tag': 'proxy'},
      ]);
    });

    test('неразборчивый конфиг уходит ядру как есть', () {
      const broken = '{"log": {"loglevel": "warning"} // комментарий\n}';
      final raised = XraySessionLog.raise(broken);
      expect(raised.config, broken);
      expect(raised.threshold, 0);
    });
  });

  group('фильтр строк', () {
    const info = '2026/09/23 02:09:14.123456 [Info] [1] app/dispatcher: '
        'taking detour [proxy] for [tcp:x:443]';
    const warning = '2026/09/23 02:09:14.123456 [Warning] core: Xray started';
    const error = '2026/09/23 02:09:14.123456 [Error] app/dns: failed';

    test('при warning уходят только info и debug', () {
      expect(XraySessionLog.keep(info, 2), isFalse);
      expect(XraySessionLog.keep(warning, 2), isTrue);
      expect(XraySessionLog.keep(error, 2), isTrue);
    });

    test('при error уходит и warning', () {
      expect(XraySessionLog.keep(warning, 3), isFalse);
      expect(XraySessionLog.keep(error, 3), isTrue);
    });

    test('порог 0 пропускает всё', () {
      expect(XraySessionLog.keep(info, 0), isTrue);
    });

    test('строки без метки xray не режутся никогда', () {
      // sing-box, mihomo и баннер: первая скобка у них — не уровень xray.
      for (final line in [
        'INFO[0012] inbound/tun[tun-in]: started',
        'time="2026-09-23T10:00:00Z" level=info msg="[TCP] 1.2.3.4 --> x"',
        'Xray 26.9.9 (Xray, Penetrates Everything.)',
      ]) {
        expect(XraySessionLog.keep(line, 4), isTrue, reason: line);
      }
    });
  });
}
