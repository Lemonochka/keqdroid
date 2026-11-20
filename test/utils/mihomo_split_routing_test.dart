import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/tunnel/app_routing_mode.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

import '../helpers/mihomo_rules_sim.dart';

/// Сплит по приложениям на mihomo в десктопном TUN.
///
/// Правило «это приложение — в VPN» стояло первым, и до списков сайтов
/// выбранные приложения не доходили: yandex.ru из Firefox уезжал через сервер
/// при «Напрямую: ru». А невыбранные шли по спискам и попадали в VPN по «Через
/// VPN». Теперь как у keqrnel и на Android: невыбранные — мимо туннеля целиком,
/// выбранные — по спискам и «Всё остальное».
const _link = 'ss://YWVzLTI1Ni1nY206dGVzdHBhc3M@203.0.113.10:8388#t';

Map<String, dynamic> _config({
  required AppRoutingMode mode,
  List<String> apps = const ['firefox.exe', 'Telegram.exe'],
  String finalOutbound = AppSettings.finalOutboundProxy,
  bool windows = true,
}) {
  Socks5Credentials().init('u', 'p');
  return MihomoConfigGen.build(
    _link,
    AppSettings(
      directRules: 'ru, yandex.ru',
      proxyRules: 'telegram.org',
      blockedRules: 'doubleclick.net',
      finalOutbound: finalOutbound,
    ),
    socksPort: 2080,
    httpPort: 2081,
    tun: const MihomoTunOptions(device: 'tun-keqdis', stack: 'gvisor'),
    routingMode: mode,
    managedProcessNames: apps,
    appProcessName: windows ? 'keqdroid.exe' : 'keqdroid',
    windows: windows,
  );
}

List<String> _rulesOf(Map<String, dynamic> config) =>
    (config['rules'] as List).cast<String>();

/// Правило сплита: по процессу, мимо туннеля, и не правило самого
/// приложения.
String _splitRule(Map<String, dynamic> config) => _rulesOf(config).singleWhere(
  (r) =>
      r.startsWith('AND,((IN-TYPE,TUN),(PROCESS-') && !r.contains('keqdroid'),
);

/// Куда mihomo отправит соединение [process] → [host], пришедшее из туннеля.
String _route(
  Map<String, dynamic> config,
  String process,
  String host, {
  String? path,
  String inType = 'TUN',
}) => simulateMihomo(
  config,
  SimConn(process: process, path: path, host: host, inType: inType),
);

void main() {
  group('только выбранные', () {
    test('выбранное приложение идёт по спискам сайтов', () {
      final rules = _config(mode: AppRoutingMode.onlySelected);
      expect(_route(rules, 'firefox.exe', 'yandex.ru'), 'DIRECT');
      expect(_route(rules, 'firefox.exe', 'mail.ru'), 'DIRECT');
      expect(_route(rules, 'firefox.exe', 'telegram.org'), 'proxy');
      expect(_route(rules, 'firefox.exe', 'doubleclick.net'), 'REJECT');
    });

    test('остальной трафик выбранного — куда велит «Всё остальное»', () {
      expect(
        _route(
          _config(mode: AppRoutingMode.onlySelected),
          'firefox.exe',
          'example.com',
        ),
        'proxy',
      );
      expect(
        _route(
          _config(
            mode: AppRoutingMode.onlySelected,
            finalOutbound: AppSettings.finalOutboundDirect,
          ),
          'firefox.exe',
          'example.com',
        ),
        'DIRECT',
      );
    });

    test('невыбранное приложение идёт мимо VPN целиком', () {
      final rules = _config(mode: AppRoutingMode.onlySelected);
      for (final host in ['telegram.org', 'example.com', 'yandex.ru']) {
        expect(_route(rules, 'chrome.exe', host), 'DIRECT', reason: host);
      }
      // И то, чей процесс ядро не узнало.
      expect(_route(rules, '', 'telegram.org'), 'DIRECT');
    });

    test('регистр имени не важен, подстрока не считается', () {
      final rules = _config(mode: AppRoutingMode.onlySelected);
      expect(_route(rules, 'FIREFOX.EXE', 'example.com'), 'proxy');
      expect(_route(rules, 'telegram.exe', 'example.com'), 'proxy');
      for (final other in ['firefoxXexe', 'myfirefox.exe', 'firefox.exe.bak']) {
        expect(_route(rules, other, 'example.com'), 'DIRECT', reason: other);
      }
    });

    // Скобка ломала разбор логических правил, запятая — любого: ядро не
    // запускалось вовсе («proxy [b.exe] not found»).
    test('скобки, запятые и пробелы в имени не ломают правило', () {
      const apps = ['App (x86).exe', 'a,b.exe', 'My App.exe'];
      final rules = _config(mode: AppRoutingMode.onlySelected, apps: apps);
      final split = _splitRule(rules);
      expect(split, contains('PROCESS-NAME-REGEX,'));
      // AND, два подправила и цель: ни одной запятой из имён.
      expect(split.split(','), hasLength(6));
      expect(
        split,
        isNot(contains('(x86)')),
        reason: 'скобки из имён должны быть закодированы',
      );
      for (final app in apps) {
        expect(_route(rules, app, 'example.com'), 'proxy', reason: app);
      }
      expect(_route(rules, 'App x86.exe', 'example.com'), 'DIRECT');
    });

    // Страховка: без единого имени процесса — прежний смысл, списки и финал
    // DIRECT, а не «всё через VPN».
    test('без имён процессов всё как было', () {
      final rules = _config(mode: AppRoutingMode.onlySelected, apps: const []);
      expect(_rulesOf(rules).last, 'MATCH,DIRECT');
      expect(
        _rulesOf(rules).any((r) => r.contains('PROCESS-NAME-REGEX,^(?!')),
        isFalse,
      );
      expect(_route(rules, 'firefox', 'telegram.org'), 'proxy');
    });
  });

  group('все, кроме выбранных', () {
    test('исключённое приложение идёт мимо VPN целиком', () {
      final rules = _config(mode: AppRoutingMode.allExceptSelected);
      expect(_route(rules, 'Telegram.exe', 'telegram.org'), 'DIRECT');
      expect(_route(rules, 'telegram.exe', 'example.com'), 'DIRECT');
    });

    test('остальные идут по спискам и «Всё остальное»', () {
      final rules = _config(mode: AppRoutingMode.allExceptSelected);
      expect(_route(rules, 'chrome.exe', 'yandex.ru'), 'DIRECT');
      expect(_route(rules, 'chrome.exe', 'telegram.org'), 'proxy');
      expect(_route(rules, 'chrome.exe', 'example.com'), 'proxy');
      final direct = _config(
        mode: AppRoutingMode.allExceptSelected,
        finalOutbound: AppSettings.finalOutboundDirect,
      );
      expect(_route(direct, 'chrome.exe', 'example.com'), 'DIRECT');
      expect(_route(direct, 'chrome.exe', 'telegram.org'), 'proxy');
    });

    test('запятая в имени не роняет конфиг', () {
      final rules = _config(
        mode: AppRoutingMode.allExceptSelected,
        apps: const ['a,b.exe'],
      );
      expect(_splitRule(rules).split(','), hasLength(6));
      expect(_route(rules, 'a,b.exe', 'telegram.org'), 'DIRECT');
    });
  });

  // Выбранное из списка или через «Обзор…» сохраняется путём: это «только
  // этот файл», одноимённая программа из другой папки им не считается.
  group('запись с путём', () {
    const firefox = r'C:\Program Files\Mozilla Firefox\firefox.exe';

    test('только выбранные: свой файл идёт по спискам', () {
      final rules = _config(
        mode: AppRoutingMode.onlySelected,
        apps: const [firefox, 'Telegram.exe'],
      );
      expect(
        _route(rules, 'firefox.exe', 'yandex.ru', path: firefox),
        'DIRECT',
      );
      expect(
        _route(rules, 'firefox.exe', 'example.com', path: firefox),
        'proxy',
      );
      // Регистр пути на Windows не важен.
      expect(
        _route(
          rules,
          'FIREFOX.EXE',
          'example.com',
          path: r'c:\program files\mozilla firefox\FIREFOX.EXE',
        ),
        'proxy',
      );
      // Имя из той же записи-списка по-прежнему ловит любой Telegram.exe.
      expect(
        _route(
          rules,
          'Telegram.exe',
          'example.com',
          path: r'D:\Portable\Telegram.exe',
        ),
        'proxy',
      );
    });

    test('только выбранные: одноимённый файл из другой папки — мимо VPN', () {
      final rules = _config(
        mode: AppRoutingMode.onlySelected,
        apps: const [firefox],
      );
      expect(
        _route(
          rules,
          'firefox.exe',
          'example.com',
          path: r'D:\Portable\firefox.exe',
        ),
        'DIRECT',
      );
      expect(_route(rules, 'chrome.exe', 'telegram.org'), 'DIRECT');
      expect(_route(rules, '', 'telegram.org', path: ''), 'DIRECT');
    });

    test('все, кроме выбранных: исключён только свой файл', () {
      final rules = _config(
        mode: AppRoutingMode.allExceptSelected,
        apps: const [firefox, 'Telegram.exe'],
      );
      expect(
        _route(rules, 'firefox.exe', 'telegram.org', path: firefox),
        'DIRECT',
      );
      expect(
        _route(
          rules,
          'firefox.exe',
          'telegram.org',
          path: r'D:\Portable\firefox.exe',
        ),
        'proxy',
      );
      expect(_route(rules, 'Telegram.exe', 'example.com'), 'DIRECT');
    });

    test('запятые и скобки в пути не ломают правило', () {
      const odd = r'C:\Games (old),new\run.exe';
      final rules = _config(
        mode: AppRoutingMode.onlySelected,
        apps: const [odd],
      );
      final split = _splitRule(rules);
      expect(split, contains('PROCESS-PATH-REGEX,'));
      expect(split.split(','), hasLength(6));
      expect(_route(rules, 'run.exe', 'example.com', path: odd), 'proxy');
    });
  });

  // На Linux имя процесса — имя файла без `.exe`.
  group('Linux', () {
    test('имена и пути без .exe', () {
      final rules = _config(
        mode: AppRoutingMode.onlySelected,
        apps: const ['firefox', '/usr/bin/curl'],
        windows: false,
      );
      expect(
        _route(rules, 'firefox', 'yandex.ru', path: '/usr/lib/firefox/firefox'),
        'DIRECT',
      );
      expect(
        _route(
          rules,
          'firefox',
          'example.com',
          path: '/usr/lib/firefox/firefox',
        ),
        'proxy',
      );
      expect(
        _route(rules, 'curl', 'example.com', path: '/usr/bin/curl'),
        'proxy',
      );
      expect(_route(rules, 'curl', 'example.com', path: '/tmp/curl'), 'DIRECT');
      expect(
        _route(rules, 'wget', 'telegram.org', path: '/usr/bin/wget'),
        'DIRECT',
      );
      expect(_rulesOf(rules).any((r) => r.contains('x2eexe')), isFalse);
    });
  });

  test('готовый Clash-конфиг: невыбранные мимо VPN, выбранные по правилам', () {
    const clash = '''
proxies:
  - {name: p1, type: ss, server: 203.0.113.10, port: 8388, cipher: aes-256-gcm, password: x}
proxy-groups:
  - {name: G, type: select, proxies: [p1]}
rules:
  - DOMAIN-SUFFIX,author-direct.example,DIRECT
  - MATCH,G
''';
    Socks5Credentials().init('u', 'p');
    final rules = MihomoConfigGen.build(
      clash,
      const AppSettings(),
      socksPort: 2080,
      httpPort: 2081,
      tun: const MihomoTunOptions(device: 'tun-keqdis', stack: 'gvisor'),
      routingMode: AppRoutingMode.onlySelected,
      managedProcessNames: const ['firefox.exe'],
      appProcessName: 'keqdroid.exe',
      windows: true,
    );
    expect(_route(rules, 'firefox.exe', 'author-direct.example'), 'DIRECT');
    expect(_route(rules, 'firefox.exe', 'example.com'), 'G');
    expect(_route(rules, 'chrome.exe', 'example.com'), 'DIRECT');
    expect(_route(rules, 'keqdroid.exe', 'example.com', inType: 'HTTP'), 'G');
  });

  // Сплит решает, кто идёт в туннель, а на свой HTTP-вход приложение шлёт
  // подписки, апдейтер и флаг выхода — то, что обязано ехать через VPN. Ядро
  // ищет процесс и у таких соединений, и «невыбранное — мимо» уводило их
  // напрямую при «Только выбранные».
  group('вход не из туннеля сплит не трогает', () {
    test('только выбранные: запросы самого приложения идут через VPN', () {
      final rules = _config(mode: AppRoutingMode.onlySelected);
      expect(
        _route(rules, 'keqdroid.exe', 'example.com', inType: 'HTTP'),
        'proxy',
      );
      expect(
        _route(rules, 'keqdroid.exe', 'github.com', inType: 'HTTP'),
        'proxy',
      );
      // Списки сайтов при этом действуют как обычно.
      expect(
        _route(rules, 'keqdroid.exe', 'yandex.ru', inType: 'HTTP'),
        'DIRECT',
      );
      // Из туннеля невыбранное по-прежнему идёт мимо.
      expect(_route(rules, 'keqdroid.exe', 'example.com'), 'DIRECT');
    });

    test('все, кроме выбранных: исключённое на HTTP-входе — по спискам', () {
      final rules = _config(mode: AppRoutingMode.allExceptSelected);
      expect(
        _route(rules, 'Telegram.exe', 'telegram.org', inType: 'HTTP'),
        'proxy',
      );
      expect(_route(rules, 'Telegram.exe', 'telegram.org'), 'DIRECT');
    });
  });
}
