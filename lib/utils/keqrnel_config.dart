import 'dart:convert';

/// Строит единый конфиг для ядра `keqrnel` из уже сгенерированных конфигов
/// цепочки. Берёт sing-box TUN-конфиг и заменяет его socks-outbound `proxy`
/// (который шёл в локальный xray) на встроенный xray-outbound
/// `{"type":"xray","xray": <xrayConfig>}`. Один процесс keqrnel заменяет связку
/// xray + sing-box, при этом весь TUN/роутинг/DNS остаётся прежним.
class KeqrnelConfig {
  KeqrnelConfig._();

  /// [singboxConfig] — результат `SingBoxTunConfigGen.generate` (desktop TUN).
  /// [xrayConfig] — обычный xray-конфиг сервера (его `outbounds` исполнит
  /// встроенный xray). [windows] управляет именем процесса в bypass-правиле.
  static String fromChain({
    required String singboxConfig,
    required String xrayConfig,
    required bool windows,
  }) {
    final box = jsonDecode(singboxConfig) as Map<String, dynamic>;
    final xray = jsonDecode(xrayConfig) as Map<String, dynamic>;

    // 1. Подменяем socks-`proxy` на встроенный xray-движок.
    final outbounds = box['outbounds'] as List;
    var swapped = false;
    for (var i = 0; i < outbounds.length; i++) {
      final ob = outbounds[i] as Map<String, dynamic>;
      if (ob['tag'] == 'proxy') {
        outbounds[i] = <String, dynamic>{
          'type': 'xray',
          'tag': 'proxy',
          'xray': xray,
        };
        swapped = true;
        break;
      }
    }
    if (!swapped) {
      throw const FormatException(
        'singbox config has no outbound tagged "proxy" to replace',
      );
    }

    // 2. Bypass собственного трафика keqrnel, чтобы коннект встроенного xray к
    //    серверу не заворачивался обратно в TUN (петля). В цепочке так
    //    обходили xray.exe/sing-box.exe — здесь единственный процесс keqrnel.
    final route = box['route'] as Map<String, dynamic>;
    final rules = route['rules'] as List;
    rules.insert(0, <String, dynamic>{
      'process_name': [windows ? 'keqrnel.exe' : 'keqrnel'],
      'outbound': 'direct',
    });

    return const JsonEncoder.withIndent('  ').convert(box);
  }

  /// Конфиг keqrnel как чистого socks/http-провайдера: оборачиваем готовый
  /// xray-конфиг (в нём уже свои inbounds с теми же портами/кредами и outbound
  /// сервера) во встроенный xray-движок, без sing-box TUN. Используется там, где
  /// туннель/прокси держит кто-то другой:
  ///  - Android: VpnService + tun2socks (keqrnel = drop-in замена libxray.so);
  ///  - desktop proxy-режим: системный прокси Windows поверх socks/http keqrnel.
  static String wrapXray(String xrayConfig) {
    final xray = jsonDecode(xrayConfig) as Map<String, dynamic>;
    final inbounds = _singboxInboundsFromXray(xray);
    xray.remove('inbounds');
    final box = <String, dynamic>{
      'log': {'level': 'warn'},
      if (inbounds.isNotEmpty) 'inbounds': inbounds,
      'outbounds': [
        {'type': 'xray', 'tag': 'proxy', 'xray': xray},
      ],
      'route': {'final': 'proxy'},
    };
    return const JsonEncoder.withIndent('  ').convert(box);
  }

  static List<Map<String, dynamic>> _singboxInboundsFromXray(
    Map<String, dynamic> xray,
  ) {
    final rawInbounds = xray['inbounds'];
    if (rawInbounds is! List) return const [];

    final result = <Map<String, dynamic>>[];
    for (final raw in rawInbounds) {
      if (raw is! Map) continue;
      final protocol = raw['protocol']?.toString().toLowerCase();
      if (protocol != 'socks' && protocol != 'http') continue;

      final port = (raw['port'] as num?)?.toInt();
      if (port == null || port <= 0) continue;

      final inbound = <String, dynamic>{
        'type': protocol,
        'tag': raw['tag']?.toString() ?? '$protocol-in',
        'listen': raw['listen']?.toString() ?? '127.0.0.1',
        'listen_port': port,
      };

      final settings = raw['settings'];
      if (settings is Map) {
        final accounts = settings['accounts'];
        if (accounts is List && accounts.isNotEmpty) {
          final users = <Map<String, dynamic>>[];
          for (final account in accounts) {
            if (account is! Map) continue;
            final username = account['user']?.toString() ?? '';
            final password = account['pass']?.toString() ?? '';
            if (username.isEmpty || password.isEmpty) continue;
            users.add({'username': username, 'password': password});
          }
          if (users.isNotEmpty) inbound['users'] = users;
        }
      }

      result.add(inbound);
    }
    return result;
  }

  /// Desktop proxy-режим с подсчётом трафика. В отличие от [wrapXray], локальные
  /// SOCKS/HTTP слушает сам sing-box (а не встроенный xray), весь трафик идёт
  /// через него в xray-bridge — поэтому sing-box его считает и отдаёт через
  /// clash_api по HTTP. Сплит-роутинг xray (direct/proxy/block по доменам/IP)
  /// сохраняется: он применяется внутри встроенного xray в core.Dial. У xray
  /// убираем только inbounds — листенеры теперь на стороне sing-box.
  static String proxyWithStats({
    required String xrayConfig,
    required int socksPort,
    required int httpPort,
    required int clashPort,
  }) {
    final xray = jsonDecode(xrayConfig) as Map<String, dynamic>;
    xray.remove('inbounds');

    final box = <String, dynamic>{
      'log': {'level': 'warn'},
      'experimental': {
        'clash_api': {'external_controller': '127.0.0.1:$clashPort'},
      },
      'inbounds': [
        {
          'type': 'socks',
          'tag': 'socks-in',
          'listen': '127.0.0.1',
          'listen_port': socksPort,
        },
        {
          'type': 'http',
          'tag': 'http-in',
          'listen': '127.0.0.1',
          'listen_port': httpPort,
        },
      ],
      'outbounds': [
        {'type': 'xray', 'tag': 'proxy', 'xray': xray},
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {'final': 'proxy'},
    };
    return const JsonEncoder.withIndent('  ').convert(box);
  }
}
