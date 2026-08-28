import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/singbox_tun_config.dart';

/// Три способа получить «туннель поднялся, ошибок нет, трафика нет».
///
/// Все три жили в одном конфиге и по отдельности незаметны: ядро стартует,
/// логи выглядят здоровыми, а пользователь видит мёртвый интернет.
///
///  1. Перехват DNS держался ТОЛЬКО на снифере. Не опознал — запрос падал в
///     правило «подсеть TUN → direct», а адрес системного резолвера лежит
///     ровно в этой подсети: sing-tun отдаёт системе следующий адрес после
///     адреса интерфейса (172.19.0.1 → 172.19.0.2).
///  2. Правило «ядро ходит мимо туннеля» перечисляло `xray` и `sing-box` —
///     процессов с такими именами на десктопе нет с тех пор, как оба уехали
///     внутрь keqrnel. Круг ловило только правило по IP сервера.
///  3. А правило по IP сервера исчезает, стоит резолву не удаться: туда
///     приезжает исходная строка, то есть домен, и `домен/32` — невалидный
///     префикс, на котором sing-box не разбирает конфиг вовсе.
Map<String, dynamic> _build({
  required bool windows,
  String serverIpToExclude = '203.0.113.9',
}) =>
    jsonDecode(
      SingBoxTunConfigGen.generate(
        localSocksPort: 2080,
        socksUsername: 'u',
        socksPassword: 'p',
        serverIpToExclude: serverIpToExclude,
        settings: const AppSettings(),
        windows: windows,
        appProcessName: windows ? 'keqdroid.exe' : 'keqdroid',
      ),
    ) as Map<String, dynamic>;

List<Map<String, dynamic>> _rules(Map<String, dynamic> config) => [
      for (final r in ((config['route'] as Map)['rules'] as List))
        (r as Map).cast<String, dynamic>(),
    ];

/// Индекс первого правила, удовлетворяющего условию; -1 — нет такого.
int _indexWhere(
  Map<String, dynamic> config,
  bool Function(Map<String, dynamic>) test,
) =>
    _rules(config).indexWhere(test);

/// Разбирается ли строка как префикс, который примет `ip_cidr` sing-box.
bool _validCidr(String raw) {
  final slash = raw.lastIndexOf('/');
  if (slash < 0) return InternetAddress.tryParse(raw) != null;
  final address = InternetAddress.tryParse(raw.substring(0, slash));
  if (address == null) return false;
  final bits = int.tryParse(raw.substring(slash + 1));
  if (bits == null) return false;
  final max = address.type == InternetAddressType.IPv6 ? 128 : 32;
  return bits >= 0 && bits <= max;
}

void main() {
  group('перехват DNS не зависит от снифера', () {
    for (final windows in const [false, true]) {
      final label = windows ? 'windows' : 'linux';

      test('правило по порту 53 есть ($label)', () {
        final config = _build(windows: windows);
        final byPort = _indexWhere(
          config,
          (r) => r['port'] == 53 && r['action'] == 'hijack-dns',
        );

        expect(byPort, isNonNegative);
      });

      test('перехват стоит РАНЬШЕ правила о подсети TUN ($label)', () {
        // Иначе запрос к системному резолверу (он же адрес из этой подсети)
        // уходит в `direct`, то есть в никуда, и резолва нет вовсе.
        final config = _build(windows: windows);
        final byPort = _indexWhere(
          config,
          (r) => r['port'] == 53 && r['action'] == 'hijack-dns',
        );
        final tunSubnet = _indexWhere(
          config,
          (r) => ((r['ip_cidr'] as List?) ?? const [])
              .any((c) => '$c'.startsWith('172.19.0.')),
        );

        expect(tunSubnet, isNonNegative, reason: 'правило о подсети пропало');
        expect(byPort, lessThan(tunSubnet));
      });
    }
  });

  group('ядро ходит мимо собственного туннеля', () {
    test('в списке имена РЕАЛЬНЫХ бинарей (linux)', () {
      final config = _build(windows: false);
      final bypass = _rules(config).firstWhere(
        (r) => r['process_name'] != null && r['outbound'] == 'direct',
      )['process_name'] as List;

      // keqrnel исполняет и sing-box, и xray: именно его сокет идёт к серверу.
      expect(bypass, contains('keqrnel'));
      expect(bypass, contains('mihomo'));
      expect(bypass, contains('wireproxy'));
      // Без суффикса: на Linux find_process сравнивает с comm-именем.
      expect(bypass, isNot(contains('keqrnel.exe')));
    });

    test('на windows те же имена с .exe', () {
      final config = _build(windows: true);
      final bypass = _rules(config).firstWhere(
        (r) => r['process_name'] != null && r['outbound'] == 'direct',
      )['process_name'] as List;

      expect(bypass, contains('keqrnel.exe'));
      expect(bypass, contains('mihomo.exe'));
      expect(bypass, isNot(contains('keqrnel')));
    });

    test('правило по имени процесса идёт раньше правила по IP сервера', () {
      // Оно и есть страховка на случай, когда IP сервера неизвестен.
      final config = _build(windows: false);
      final byProcess = _indexWhere(
        config,
        (r) => ((r['process_name'] as List?) ?? const []).contains('keqrnel'),
      );
      final byIp = _indexWhere(
        config,
        (r) =>
            ((r['ip_cidr'] as List?) ?? const []).contains('203.0.113.9/32'),
      );

      expect(byProcess, isNonNegative);
      expect(byIp, isNonNegative);
      expect(byProcess, lessThan(byIp));
    });
  });

  group('нерезолвленный адрес сервера не роняет конфиг', () {
    test('домен вместо IP не превращается в `домен/32`', () {
      // Резолв при неудаче откатывается на исходную строку сервера, и она
      // приезжает сюда как есть. `vpn.example.com/32` — невалидный префикс:
      // sing-box не разбирает такой конфиг и выходит, то есть TUN не
      // поднимается совсем.
      final config = _build(
        windows: false,
        serverIpToExclude: 'vpn.example.com',
      );

      expect(
        jsonEncode(config).contains('vpn.example.com'),
        isFalse,
        reason: 'домен уехал в конфиг',
      );
    });

    test('круг при этом всё равно разорван — правилом по процессу', () {
      final config = _build(
        windows: false,
        serverIpToExclude: 'vpn.example.com',
      );
      final byProcess = _indexWhere(
        config,
        (r) => ((r['process_name'] as List?) ?? const []).contains('keqrnel'),
      );

      expect(byProcess, isNonNegative);
    });

    test('любой ip_cidr в конфиге разбирается как префикс', () {
      for (final target in const [
        '203.0.113.9',
        '203.0.113.0/24',
        '2a03:1234::1',
        'vpn.example.com',
        'не адрес вовсе',
        '',
      ]) {
        for (final windows in const [false, true]) {
          final config = _build(windows: windows, serverIpToExclude: target);
          for (final rule in _rules(config)) {
            for (final cidr in (rule['ip_cidr'] as List?) ?? const []) {
              expect(
                _validCidr('$cidr'),
                isTrue,
                reason: 'ip_cidr "$cidr" из serverIpToExclude="$target"',
              );
            }
          }
        }
      }
    });

    test('IPv6-адрес сервера получает /128, а не /32', () {
      final config = _build(windows: false, serverIpToExclude: '2a03:1234::1');
      expect(jsonEncode(config), contains('2a03:1234::1/128'));
    });
  });
}
