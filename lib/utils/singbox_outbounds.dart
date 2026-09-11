import 'dart:convert';

import 'ssr_uri.dart';

/// Узлы конфига sing-box — каждый своей ссылкой.
///
/// Такой конфиг панели отдают sing-box-клиентам. Целиком его исполнить нечем:
/// sing-box у нас только держит TUN на десктопе. Но его аутбаунды — те же
/// серверы, а ссылку понимают оба ядра и всё приложение: список, пинг, выбор
/// ядра. Имена полей — из `option/*.go` sing-box.
class SingboxOutbounds {
  SingboxOutbounds._();

  /// Группы и выходы мимо прокси: серверами не бывают, в пропущенные не идут.
  static const _service = {'selector', 'urltest', 'direct', 'block', 'dns'};

  /// Конфиг без единого сервера. С подписки это обычно заглушка панели.
  static const noServers = 'The sing-box config has no servers in it. From a '
      'subscription this is usually a provider stub: check subscription status '
      'and HWID binding in the provider panel.';

  /// Конфиг ли это sing-box. От xray его отличает одно, но надёжно: протокол
  /// аутбаунда sing-box зовёт `type`, xray — `protocol`. Отсутствием
  /// `protocol` не проверить: у SSR-узла sing-box это поле тоже есть, там в нём
  /// протокол обфускации SSR.
  static bool looksLike(String raw) => _config(raw) != null;

  /// Ссылки на узлы, которые умеем, и счёт остальных по типу. Не sing-box —
  /// оба пусты.
  static ({List<String> links, Map<String, int> skipped}) translate(
    String raw,
  ) {
    final config = _config(raw);
    if (config == null) return (links: const [], skipped: const {});
    final outbounds = _maps(config['outbounds']);
    final typeByTag = {
      for (final o in outbounds) _str(o['tag']): _str(o['type']).toLowerCase(),
    };
    final links = <String>[];
    final skipped = <String, int>{};
    void skip(String kind) => skipped[kind] = (skipped[kind] ?? 0) + 1;

    for (final o in outbounds) {
      final type = _str(o['type']).toLowerCase();
      if (_service.contains(type)) continue;
      // Узел за другим узлом — цепочка, одной ссылкой её не выразить: ссылка
      // пошла бы к серверу напрямую, мимо первого звена.
      final detour = _str(o['detour']);
      if (detour.isNotEmpty && typeByTag[detour] != 'direct') {
        skip('$type via detour');
        continue;
      }
      final node = _node(type, o);
      final link = node.link;
      if (link != null) {
        links.add(link);
      } else {
        skip(node.kind);
      }
    }
    // WireGuard и Tailscale с 1.11 лежат не среди аутбаундов, а здесь.
    for (final e in _maps(config['endpoints'])) {
      final type = _str(e['type']).toLowerCase();
      skip(type.isEmpty ? 'unknown' : type);
    }
    return (links: links, skipped: skipped);
  }

  /// Почему из конфига не взято ни одного сервера. null — взят хоть один или
  /// это вовсе не sing-box.
  static String? describeProblem(String raw) {
    if (_config(raw) == null) return null;
    final nodes = translate(raw);
    if (nodes.links.isNotEmpty) return null;
    if (nodes.skipped.isEmpty) return noServers;
    final kinds = nodes.skipped.entries
        .map((e) => '${e.value} of type ${e.key}')
        .join(', ');
    return 'sing-box config: none of its servers can run in this client '
        '($kinds)';
  }

  /// Ссылка на узел, а если её нет — как назвать узел в пропущенных: типом,
  /// иногда с уточнением, чтобы по логу было видно, что именно не взято.
  static ({String? link, String kind}) _node(
    String type,
    Map<String, dynamic> o,
  ) {
    final security = _security(o);
    // REALITY наши ядра собирают только у VLESS и Trojan.
    if (security['security'] == 'reality' &&
        type != 'vless' &&
        type != 'trojan') {
      return (link: null, kind: '$type over reality');
    }
    if (type == 'vless' || type == 'vmess' || type == 'trojan') {
      final transport = _transport(o);
      if (transport == null) {
        final name = _str(_map(o['transport'])?['type']);
        return (link: null, kind: '$type over $name');
      }
      // Trojan без TLS генераторы соберут с TLS: в ссылках `security=none` у
      // trojan — опечатка, и они её чинят. Здесь это был бы чужой сервер.
      if (type == 'trojan' && security.isEmpty) {
        return (link: null, kind: 'trojan without tls');
      }
      final link = switch (type) {
        'vless' => _vless(o, transport, security),
        'vmess' => _vmess(o, transport, security),
        _ => _trojan(o, transport, security),
      };
      return (link: link, kind: type);
    }
    final link = switch (type) {
      'shadowsocks' => _shadowsocks(o),
      'shadowsocksr' => _shadowsocksR(o),
      'hysteria2' => _hysteria2(o, security),
      'tuic' => _tuic(o, security),
      'anytls' => _anytls(o, security),
      _ => null,
    };
    return (link: link, kind: type.isEmpty ? 'unknown' : type);
  }

  static String? _vless(
    Map<String, dynamic> o,
    Map<String, String> transport,
    Map<String, String> security,
  ) {
    final uuid = _str(o['uuid']);
    final server = _str(o['server']);
    final port = _int(o['server_port']);
    if (uuid.isEmpty || server.isEmpty || port <= 0) return null;
    final flow = _str(o['flow']);
    // packetaddr у ссылки зовётся `packet` (handleVShareLink в
    // common/convert/v.go mihomo).
    final packet = switch (_str(o['packet_encoding']).toLowerCase()) {
      'xudp' => 'xudp',
      'packetaddr' => 'packet',
      _ => '',
    };
    return _uri('vless', uuid, server, port, _str(o['tag']), {
      ...transport,
      ...security,
      if (flow.isNotEmpty) 'flow': flow,
      if (packet.isNotEmpty) 'packetEncoding': packet,
    });
  }

  static String? _trojan(
    Map<String, dynamic> o,
    Map<String, String> transport,
    Map<String, String> security,
  ) {
    final password = _str(o['password']);
    final server = _str(o['server']);
    final port = _int(o['server_port']);
    if (password.isEmpty || server.isEmpty || port <= 0) return null;
    return _uri('trojan', password, server, port, _str(o['tag']), {
      ...transport,
      ...security,
    });
  }

  /// VMess — base64-json v2rayN, как и у перевода Clash: у этой формы есть
  /// `aid`, которого нет у ссылки AEAD.
  static String? _vmess(
    Map<String, dynamic> o,
    Map<String, String> transport,
    Map<String, String> security,
  ) {
    final uuid = _str(o['uuid']);
    final server = _str(o['server']);
    final port = _int(o['server_port']);
    if (uuid.isEmpty || server.isEmpty || port <= 0) return null;
    // HTTP/2 json v2rayN зовёт `h2`, ссылка — `http`.
    final net = switch (transport['type']) {
      null => 'tcp',
      'http' => 'h2',
      final String type => type,
    };
    // Своих полей для имени gRPC-сервиса и ранних данных у json нет: v2rayN
    // кладёт то и другое в `path`, так их и читают генераторы.
    var path = transport['path'] ?? '';
    final ed = transport['ed'];
    if (net == 'grpc') {
      path = transport['serviceName'] ?? '';
    } else if (ed != null) {
      if (path.isEmpty) path = '/';
      path = '$path${path.contains('?') ? '&' : '?'}ed=$ed';
    }
    final cipher = _str(o['security']);
    final json = <String, String>{
      'v': '2',
      'ps': _str(o['tag']),
      'add': server,
      'port': '$port',
      'id': uuid,
      'aid': '${_int(o['alter_id'])}',
      'scy': cipher.isEmpty ? 'auto' : cipher,
      'net': net,
      'type': transport['headerType'] ?? 'none',
      'host': transport['host'] ?? '',
      'path': path,
      'tls': security.isEmpty ? '' : 'tls',
      for (final key in const ['sni', 'alpn', 'fp', 'ech'])
        if (security[key] != null) key: security[key]!,
    };
    return 'vmess://${base64.encode(utf8.encode(jsonEncode(json)))}';
  }

  static String? _shadowsocks(Map<String, dynamic> o) {
    final method = _str(o['method']);
    final password = _str(o['password']);
    final server = _str(o['server']);
    final port = _int(o['server_port']);
    if (method.isEmpty || password.isEmpty || server.isEmpty || port <= 0) {
      return null;
    }
    final plugin = _str(o['plugin']);
    final opts = _str(o['plugin_opts']);
    final uot = _uotVersion(o['udp_over_tcp']);
    final userInfo =
        base64Url.encode(utf8.encode('$method:$password')).replaceAll('=', '');
    return _uri('ss', userInfo, server, port, _str(o['tag']), {
      // В ссылке SIP002 плагин с настройками — одна строка через `;`.
      if (plugin.isNotEmpty) 'plugin': opts.isEmpty ? plugin : '$plugin;$opts',
      if (uot != null) 'uot': '1',
      if (uot != null) 'udp-over-tcp-version': '$uot',
    });
  }

  /// Версия UDP-over-TCP; null — выключен. Номер пишем всегда: sing-box без
  /// номера берёт вторую, а mihomo — первую (adapter/outbound/shadowsocks.go),
  /// и с сервером они бы разошлись.
  static int? _uotVersion(Object? raw) {
    if (raw == true) return 2;
    final options = _map(raw);
    if (options?['enabled'] != true) return null;
    final version = _int(options!['version']);
    return version == 0 ? 2 : version;
  }

  static String? _shadowsocksR(Map<String, dynamic> o) {
    final method = _str(o['method']);
    final password = _str(o['password']);
    final server = _str(o['server']);
    final port = _int(o['server_port']);
    if (method.isEmpty || password.isEmpty || server.isEmpty || port <= 0) {
      return null;
    }
    final protocol = _str(o['protocol']);
    final obfs = _str(o['obfs']);
    // Сам sing-box SSR не исполняет с 1.6 (include/registry.go), но старые
    // конфиги такие узлы несут, а mihomo их собирает.
    return SsrLink(
      host: server,
      port: port,
      // Пустое поле ссылке не годится — без всех шести частей она не
      // разбирается, — поэтому простейшие варианты.
      protocol: protocol.isEmpty ? 'origin' : protocol,
      method: method,
      obfs: obfs.isEmpty ? 'plain' : obfs,
      password: password,
      obfsParam: _str(o['obfs_param']),
      protocolParam: _str(o['protocol_param']),
      remarks: _str(o['tag']),
    ).encode();
  }

  static String? _hysteria2(
    Map<String, dynamic> o,
    Map<String, String> security,
  ) {
    final password = _str(o['password']);
    final server = _str(o['server']);
    // Диапазон sing-box пишет через двоеточие (`20000:20050`), ссылка — через
    // дефис. При списке портов `server_port` ядро не читает вовсе
    // (option/hysteria2.go), а ссылке порт в адресе нужен — первый из списка.
    final ports = [
      for (final range in _list(o['server_ports'])) range.replaceAll(':', '-'),
    ];
    final port = ports.isEmpty
        ? _int(o['server_port'])
        : int.tryParse(ports.first.split('-').first) ?? 0;
    if (password.isEmpty || server.isEmpty || port <= 0) return null;
    final obfs = _map(o['obfs']);
    final obfsType = _str(obfs?['type']);
    final up = _int(o['up_mbps']);
    final down = _int(o['down_mbps']);
    final hop = _seconds(_str(o['hop_interval']));
    return _uri('hysteria2', password, server, port, _str(o['tag']), {
      if (security['sni'] != null) 'sni': security['sni']!,
      if (security['alpn'] != null) 'alpn': security['alpn']!,
      if (obfsType.isNotEmpty) 'obfs': obfsType,
      if (obfsType.isNotEmpty) 'obfs-password': _str(obfs?['password']),
      if (up > 0) 'up': '$up',
      if (down > 0) 'down': '$down',
      if (ports.isNotEmpty) 'mport': ports.join(','),
      if (ports.isNotEmpty && hop.isNotEmpty) 'hop-interval': hop,
    });
  }

  static String? _tuic(Map<String, dynamic> o, Map<String, String> security) {
    final uuid = _str(o['uuid']);
    final server = _str(o['server']);
    final port = _int(o['server_port']);
    if (uuid.isEmpty || server.isEmpty || port <= 0) return null;
    final congestion = _str(o['congestion_control']);
    final relay = _str(o['udp_relay_mode']);
    final disableSni = _map(o['tls'])?['disable_sni'] == true;
    // Части пары кодируем сами: генератор их раскодирует, и `%` в пароле
    // иначе приехал бы чужим символом.
    final userInfo = '${Uri.encodeComponent(uuid)}:'
        '${Uri.encodeComponent(_str(o['password']))}';
    return _uri('tuic', userInfo, server, port, _str(o['tag']), {
      if (security['sni'] != null) 'sni': security['sni']!,
      if (security['alpn'] != null) 'alpn': security['alpn']!,
      if (congestion.isNotEmpty) 'congestion_control': congestion,
      if (relay.isNotEmpty) 'udp_relay_mode': relay,
      if (disableSni) 'disable_sni': '1',
    });
  }

  static String? _anytls(
    Map<String, dynamic> o,
    Map<String, String> security,
  ) {
    final password = _str(o['password']);
    final server = _str(o['server']);
    final port = _int(o['server_port']);
    if (password.isEmpty || server.isEmpty || port <= 0) return null;
    return _uri(
      'anytls',
      Uri.encodeComponent(password),
      server,
      port,
      _str(o['tag']),
      {
        for (final key in const ['sni', 'alpn', 'fp', 'ech'])
          if (security[key] != null) key: security[key]!,
      },
    );
  }

  /// Транспорт узла параметрами ссылки; пусто — голый tcp. null — такого
  /// транспорта нет ни у одного нашего ядра: `quic` xray снёс, у mihomo его
  /// не было.
  static Map<String, String>? _transport(Map<String, dynamic> o) {
    final t = _map(o['transport']);
    if (t == null) return const {};
    final path = _str(t['path']);
    switch (_str(t['type']).toLowerCase()) {
      case 'ws':
        final host = _header(t['headers'], 'host');
        final ed = _int(t['max_early_data']);
        final edHeader = _str(t['early_data_header_name']).toLowerCase();
        return {
          'type': 'ws',
          if (path.isNotEmpty) 'path': path,
          if (host.isNotEmpty) 'host': host,
          // Наши ядра шлют ранние данные только в Sec-WebSocket-Protocol.
          // Сервер, который ждёт их в пути или другом заголовке, первый пакет
          // оттуда не достанет, а без ранних данных примет соединение и так
          // (transport/v2raywebsocket/server.go).
          if (ed > 0 && edHeader == 'sec-websocket-protocol') 'ed': '$ed',
        };
      case 'httpupgrade':
        final host = _str(t['host']);
        return {
          'type': 'httpupgrade',
          if (path.isNotEmpty) 'path': path,
          if (host.isNotEmpty) 'host': host,
        };
      case 'grpc':
        final service = _str(t['service_name']);
        return {'type': 'grpc', if (service.isNotEmpty) 'serviceName': service};
      case 'http':
        // Хостов sing-box даёт список и выбирает случайный, ссылка несёт
        // один — первый.
        final hosts = _list(t['host']);
        final method = _str(t['method']);
        // Под этим именем у sing-box два транспорта (transport/v2rayhttp):
        // с TLS — HTTP/2, без него — HTTP/1.1 поверх tcp, то есть маскировка
        // `headerType=http` ссылки.
        if (_map(o['tls'])?['enabled'] == true) {
          return {
            'type': 'http',
            if (path.isNotEmpty) 'path': path,
            if (hosts.isNotEmpty) 'host': hosts.first,
          };
        }
        return {
          'type': 'tcp',
          'headerType': 'http',
          if (path.isNotEmpty) 'path': path,
          if (hosts.isNotEmpty) 'host': hosts.first,
          if (method.isNotEmpty) 'method': method,
        };
      default:
        return null;
    }
  }

  /// TLS и REALITY узла параметрами ссылки.
  ///
  /// Чего здесь нет и почему. `insecure` — политика: доверять любому
  /// сертификату не соглашаемся (removed_tls_fields.dart). Пин
  /// `certificate_public_key_sha256` — хэш открытого ключа, а оба наших ядра
  /// сверяют хэш сертификата целиком (GenerateCertHash у xray): переложить
  /// одно в другое нельзя. Пустой отпечаток uTLS sing-box читает как chrome,
  /// но это его умолчание, а не выбор автора — остаётся наше.
  static Map<String, String> _security(Map<String, dynamic> o) {
    final tls = _map(o['tls']);
    if (tls == null || tls['enabled'] != true) return const {};
    final reality = _map(tls['reality']);
    final isReality = reality?['enabled'] == true;
    final utls = _map(tls['utls']);
    final fp = utls?['enabled'] == true ? _str(utls!['fingerprint']) : '';
    final sni = _str(tls['server_name']);
    final alpn = _list(tls['alpn']);
    final pbk = isReality ? _str(reality!['public_key']) : '';
    final sid = isReality ? _str(reality!['short_id']) : '';
    final ech = _ech(tls['ech']);
    return {
      'security': isReality ? 'reality' : 'tls',
      if (sni.isNotEmpty) 'sni': sni,
      if (alpn.isNotEmpty) 'alpn': alpn.join(','),
      if (fp.isNotEmpty) 'fp': fp,
      if (pbk.isNotEmpty) 'pbk': pbk,
      if (sid.isNotEmpty) 'sid': sid,
      if (ech.isNotEmpty) 'ech': ech,
    };
  }

  /// ECH у sing-box — PEM-блок `ECH CONFIGS` (common/tls/ech.go), у ссылки —
  /// тот же ECHConfigList голым base64: снимаем броню, байты те же. Включённый
  /// ECH без списка значит «спроси у DNS», а резолвер ссылка называет явно —
  /// у узла sing-box его нет, поэтому такой ECH не переносится.
  static String _ech(Object? raw) {
    final ech = _map(raw);
    if (ech == null || ech['enabled'] != true) return '';
    final pem = _list(ech['config']).join('\n');
    final body = RegExp(
      r'-----BEGIN ECH CONFIGS-----([\s\S]*?)-----END ECH CONFIGS-----',
    ).firstMatch(pem)?.group(1);
    return body?.replaceAll(RegExp(r'\s'), '') ?? '';
  }

  /// Длительность Go (`30s`, `1m30s`) в целых секундах — так интервал ждут
  /// оба ядра. Пусто — не разобралась.
  static String _seconds(String raw) {
    final text = raw.trim();
    if (RegExp(r'^\d+$').hasMatch(text)) return text;
    const units = {
      'h': 3600.0,
      'm': 60.0,
      's': 1.0,
      'ms': 1e-3,
      'us': 1e-6,
      'µs': 1e-6,
      'ns': 1e-9,
    };
    final parts = RegExp(r'(\d+(?:\.\d+)?)(ms|us|µs|ns|h|m|s)')
        .allMatches(text)
        .toList();
    if (parts.isEmpty || parts.map((m) => m.group(0)).join() != text) {
      return '';
    }
    final total = parts.fold<double>(
      0,
      (sum, m) => sum + double.parse(m.group(1)!) * units[m.group(2)]!,
    );
    final seconds = total.round();
    return seconds > 0 ? '$seconds' : '';
  }

  static String _uri(
    String scheme,
    String userInfo,
    String host,
    int port,
    String name,
    Map<String, String> query,
  ) =>
      Uri(
        scheme: scheme,
        userInfo: userInfo,
        host: host,
        port: port,
        queryParameters: query.isEmpty ? null : query,
        fragment: name.isEmpty ? null : name,
      ).toString();

  static Map<String, dynamic>? _config(String raw) {
    final text = raw.trim();
    if (!text.startsWith('{')) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final config = decoded.cast<String, dynamic>();
    final outbounds = _maps(config['outbounds']);
    if (outbounds.isEmpty || !outbounds.every((o) => o['type'] is String)) {
      return null;
    }
    return config;
  }

  /// Значение заголовка из `headers` sing-box, без оглядки на регистр имени.
  static String _header(Object? headers, String name) {
    final map = _map(headers);
    if (map == null) return '';
    for (final entry in map.entries) {
      if (entry.key.toLowerCase() != name) continue;
      final values = _list(entry.value);
      if (values.isNotEmpty) return values.first;
    }
    return '';
  }

  static String _str(Object? value) => switch (value) {
        null => '',
        final String s => s,
        _ => '$value',
      };

  static int _int(Object? value) => switch (value) {
        final int n => n,
        _ => int.tryParse(_str(value)) ?? 0,
      };

  static Map<String, dynamic>? _map(Object? value) =>
      value is Map ? value.cast<String, dynamic>() : null;

  static List<Map<String, dynamic>> _maps(Object? value) => [
        if (value is List)
          for (final item in value)
            if (item is Map) item.cast<String, dynamic>(),
      ];

  /// `Listable` sing-box: одна строка или список строк.
  static List<String> _list(Object? value) {
    if (value is List) {
      return [
        for (final item in value)
          if (_str(item).isNotEmpty) _str(item),
      ];
    }
    final single = _str(value);
    return single.isEmpty ? const [] : [single];
  }
}
