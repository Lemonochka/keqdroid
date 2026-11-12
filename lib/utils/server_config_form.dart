import 'dart:convert';

import 'custom_clash_config.dart';
import 'raw_share_uri.dart';
import 'server_field_rules.dart';

// ссылка в поля редактора и обратно. чужие параметры остаются в RawShareUri, порядок и кодирование не трогаем
class ServerConfigForm {
  String _protocol = 'unknown';

  RawShareUri? _uri;
  Map<String, dynamic>? _vmess;
  bool _vmessPortWasInt = false;
  String _vmessSecurityKey = 'scy';
  bool _vmessExtraIsObject = false;

  Map<String, dynamic>? _clashConfig;

  bool _ssBase64 = false;
  bool _hyAuthInQuery = false;

  final Map<String, String> parsedText = {};
  final Map<String, String> _drop = {};
  final Map<String, bool> _toggle = {};

  String Function(String id) _v = (_) => '';

  String get protocol => _protocol;
  Map<String, String> get drop => _drop;
  Map<String, bool> get toggle => _toggle;

  // протокол и признаки формата ссылки не сбрасываем: при сбое разбора редактор держит прежние
  void reset() {
    parsedText.clear();
    _drop.clear();
    _toggle.clear();
    _uri = null;
    _vmess = null;
    _clashConfig = null;
  }

  void _ctrl(String id, [String initial = '']) =>
      parsedText.putIfAbsent(id, () => initial);

  String? parse(String rawConfig) => _initFromConfig(rawConfig);

  String build(String Function(String id) text) {
    _v = text;
    if (_protocol == 'vmess') return _buildVmess();
    if (_protocol == 'clash') {
      return jsonEncode({
        ..._clashConfig!,
        'proxies': [jsonDecode(_v('clashNode'))],
      });
    }
    return _buildUri();
  }

  String? _initFromConfig(String rawConfig) {
    final config = rawConfig.trim();
    final lower = config.toLowerCase();

    String protocol = 'unknown';
    if (lower.startsWith('vless://')) {
      protocol = 'vless';
    } else if (lower.startsWith('vmess://')) {
      protocol = 'vmess';
    } else if (lower.startsWith('trojan://')) {
      protocol = 'trojan';
    } else if (lower.startsWith('ss://')) {
      protocol = 'ss';
    } else if (lower.startsWith('hysteria2://') ||
        lower.startsWith('hy2://') ||
        lower.startsWith('hysteria://')) {
      protocol = 'hysteria';
    }

    // одиночный узел Clash полями; профиль с группами остаётся текстом
    if (protocol == 'unknown' && CustomClashConfig.looksLikeClash(config)) {
      final clash = CustomClashConfig.tryParse(config);
      if (clash != null &&
          clash.proxies.length == 1 &&
          clash.map['proxy-groups'] == null) {
        _protocol = 'clash';
        _clashConfig = clash.map;
        _ctrl('clashNode', jsonEncode(clash.proxies.single));
        return null;
      }
    }

    if (protocol == 'unknown') return 'raw-only protocol';

    if (protocol == 'vmess') {
      return _initVmess(config);
    }

    final uri = RawShareUri.parse(config);
    if (uri == null) return 'unparsable uri';

    _protocol = protocol;
    _uri = uri;
    _ctrl('address', uri.host);
    _ctrl('port', uri.port);

    switch (protocol) {
      case 'vless':
        _ctrl('userInfo', uri.userInfo);
        _ctrl('encryption', uri.takeParam('encryption'));
        _drop['flow'] = uri.takeParam('flow');
        final security = uri.takeParam('security');
        _drop['security'] = security.isEmpty ? 'none' : security;
        break;
      case 'trojan':
        _ctrl('userInfo', uri.userInfo);
        // у trojan пустой security значит tls, ссылки его обычно не пишут
        final trojanSecurity = uri.takeParam('security');
        _drop['security'] =
            trojanSecurity.isEmpty ? 'tls' : trojanSecurity;
        break;
      case 'ss':
        final userInfo = uri.userInfo;
        if (userInfo.isEmpty) return 'ss without userinfo';
        if (userInfo.contains(':')) {
          _ssBase64 = false;
          final idx = userInfo.indexOf(':');
          _ctrl('method', userInfo.substring(0, idx));
          _ctrl('password', userInfo.substring(idx + 1));
        } else {
          _ssBase64 = true;
          try {
            var normalized =
                userInfo.replaceAll('-', '+').replaceAll('_', '/');
            while (normalized.length % 4 != 0) {
              normalized += '=';
            }
            final decoded = utf8.decode(base64.decode(normalized));
            final idx = decoded.indexOf(':');
            if (idx <= 0) return 'bad ss userinfo';
            _ctrl('method', decoded.substring(0, idx));
            _ctrl('password', decoded.substring(idx + 1));
          } catch (_) {
            return 'bad ss base64';
          }
        }
        break;
      case 'hysteria':
        var auth = uri.takeParam('auth');
        if (auth.isEmpty) auth = uri.takeParam('password');
        _hyAuthInQuery = auth.isNotEmpty;
        if (auth.isEmpty && uri.userInfo.isNotEmpty) {
          try {
            auth = Uri.decodeComponent(uri.userInfo);
          } catch (_) {
            auth = uri.userInfo;
          }
        }
        _ctrl('auth', auth);
        break;
    }

    if (protocol == 'vless' || protocol == 'trojan') {
      _ctrl('sni', uri.takeParam('sni'));
      _drop['fp'] = uri.takeParam('fp');
      _ctrl('alpn', uri.takeParam('alpn'));
      _ctrl('ech', uri.takeParam('ech'));
      _toggle['insecure'] = _takeInsecure(uri);
      _ctrl('pcs', uri.takeParam('pcs'));
      _ctrl('vcn', uri.takeParam('vcn'));
      _ctrl('pbk', uri.takeParam('pbk'));
      _ctrl('sid', uri.takeParam('sid'));
      _ctrl('spx', uri.takeParam('spx'));
      _ctrl('pqv', uri.takeParam('pqv'));
      final type = uri.takeParam('type');
      _drop['type'] = type.isEmpty ? 'tcp' : type;
      _ctrl('path', uri.takeParam('path'));
      _ctrl('host', uri.takeParam('host'));
      _ctrl('serviceName', uri.takeParam('serviceName'));
      _drop['mode'] = uri.takeParam('mode');
      _ctrl('authority', uri.takeParam('authority'));
      _ctrl('ed', uri.takeParam('ed'));
      _ctrl('extra', uri.takeParam('extra'));
      _ctrl('x_padding_bytes', uri.takeParam('x_padding_bytes'));
      _paddingIntoExtra();
      _ctrl('seed', uri.takeParam('seed'));
      _ctrl('mtu', uri.takeParam('mtu'));
      _ctrl('tti', uri.takeParam('tti'));
      _ctrl('method', uri.takeParam('method'));
      _drop['headerType'] = uri.takeParam('headerType');
    }

    if (protocol == 'hysteria') {
      _ctrl('sni', uri.takeParam('sni'));
      _drop['fp'] = uri.takeParam('fp');
      _ctrl('alpn', uri.takeParam('alpn'));
      _ctrl('ech', uri.takeParam('ech'));
      _toggle['insecure'] = _takeInsecure(uri);
      _drop['obfs'] = uri.takeParam('obfs');
      _ctrl('obfs-password', uri.takeParam('obfs-password'));
      _ctrl('up', uri.takeParam('up'));
      _ctrl('down', uri.takeParam('down'));
      _ctrl('mport', uri.takeParam('mport'));
      _ctrl('hop-interval', uri.takeParam('hop-interval'));
      _ctrl('pinSHA256', uri.takeParam('pinSHA256'));
    }

    return null;
  }

  // ссылки несут набивку и плоским x_padding_bytes, и в extra. в редакторе поле у неё одно, в extra: оттуда
  // её читают оба генератора, а если заданы обе, config_gen берёт значение из extra
  void _paddingIntoExtra() {
    final flat = parsedText['x_padding_bytes']!.trim();
    if (flat.isEmpty) return;
    final raw = parsedText['extra']!.trim();
    final Map<String, dynamic> extra;
    try {
      final decoded = raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw);
      if (decoded is! Map) return;
      extra = decoded.cast<String, dynamic>();
    } on FormatException {
      return;
    }
    extra.putIfAbsent('xPaddingBytes', () => flat);
    parsedText['extra'] = jsonEncode(extra);
    parsedText['x_padding_bytes'] = '';
  }

  bool _takeInsecure(RawShareUri uri) {
    var on = false;
    for (final key in ['insecure', 'allowInsecure', 'skip-cert-verify']) {
      final v = uri.takeParam(key).toLowerCase();
      if (v == '1' || v == 'true' || v == 'yes') on = true;
    }
    return on;
  }

  String? _initVmess(String config) {
    try {
      var payload = config.substring('vmess://'.length).trim();
      payload = payload.replaceAll(RegExp(r'\s+'), '')
          .replaceAll('-', '+')
          .replaceAll('_', '/');
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final decoded = utf8.decode(base64.decode(payload));
      final json = jsonDecode(decoded);
      if (json is! Map<String, dynamic>) return 'vmess payload is not a map';
      _protocol = 'vmess';
      _vmess = json;
      _vmessPortWasInt = json['port'] is int;
      _vmessSecurityKey = json.containsKey('security') ? 'security' : 'scy';

      String s(String key) => (json[key] ?? '').toString();
      _ctrl('address', s('add'));
      _ctrl('port', s('port'));
      _ctrl('userInfo', s('id'));
      _drop['scy'] = (json[_vmessSecurityKey] ?? '').toString();
      _drop['type'] = s('net').isEmpty ? 'tcp' : s('net');
      _drop['security'] = s('tls') == 'tls' ? 'tls' : 'none';
      _ctrl('sni', s('sni'));
      _ctrl('host', s('host'));
      _ctrl('path', s('path'));
      // ключи как в _vmessStreamParams config_gen: имя сервиса gRPC и seed mKCP лежат в path, заголовок в type.
      // serviceName писал прежний редактор, генераторы его не читают
      final net = normalizeTransport(_drop['type']!);
      _ctrl('serviceName', net == 'grpc' && s('path').isNotEmpty ? s('path') : s('serviceName'));
      _ctrl('seed', net == 'kcp' ? s('path') : '');
      _drop['headerType'] = s('type');
      _drop['mode'] = s('mode');
      _ctrl('authority', s('authority'));
      _ctrl('ed', s('ed'));
      _ctrl('mtu', s('mtu'));
      _ctrl('tti', s('tti'));
      _ctrl('method', s('method'));
      final extra = json['extra'];
      _vmessExtraIsObject = extra is Map;
      _ctrl('extra', extra is Map || extra is List ? jsonEncode(extra) : s('extra'));
      _ctrl('x_padding_bytes', s('x_padding_bytes'));
      _paddingIntoExtra();
      _drop['fp'] = s('fp');
      _ctrl('alpn', s('alpn'));
      _ctrl('ech', s('ech'));
      _ctrl('pcs', s('pcs'));
      _ctrl('vcn', s('vcn'));
      var insecure = false;
      for (final k in ['insecure', 'allowInsecure', 'skip-cert-verify']) {
        final v = s(k).trim().toLowerCase();
        if (v == '1' || v == 'true' || v == 'yes') insecure = true;
      }
      _toggle['insecure'] = insecure;
      return null;
    } catch (_) {
      return 'bad vmess payload';
    }
  }

  String _buildUri() {
    final uri = _uri!;
    uri.host = _v('address');
    uri.port = _v('port');

    final managed = <MapEntry<String, String>>[];
    void add(String key, String value) =>
        managed.add(MapEntry(key, value.trim()));

    switch (_protocol) {
      case 'vless':
        uri.userInfo = _v('userInfo');
        add('encryption', _v('encryption'));
        add('flow', _drop['flow'] ?? '');
        final security = _drop['security'] ?? 'none';
        add('security', security == 'none' ? 'none' : security);
        if (security == 'tls' || security == 'reality') {
          add('sni', _v('sni'));
          add('fp', _drop['fp'] ?? '');
        }
        if (security == 'tls') {
          add('alpn', _v('alpn'));
          add('ech', _v('ech'));
          if (_toggle['insecure'] ?? false) add('insecure', '1');
        }
        if (security == 'tls' || security == 'reality') {
          add('pcs', _v('pcs'));
          add('vcn', _v('vcn'));
        }
        if (security == 'reality') {
          add('pbk', _v('pbk'));
          add('sid', _v('sid'));
          add('spx', _v('spx'));
          add('pqv', _v('pqv'));
        }
        _addTransportParams(add);
        break;
      case 'trojan':
        uri.userInfo = _v('userInfo');
        final trojanSecurity = _drop['security'] ?? 'tls';
        add('security', trojanSecurity == 'tls' ? '' : trojanSecurity);
        add('sni', _v('sni'));
        add('fp', _drop['fp'] ?? '');
        if (trojanSecurity == 'tls') {
          add('alpn', _v('alpn'));
          add('ech', _v('ech'));
          add('pcs', _v('pcs'));
          add('vcn', _v('vcn'));
          if (_toggle['insecure'] ?? false) add('insecure', '1');
        }
        if (trojanSecurity == 'reality') {
          add('pbk', _v('pbk'));
          add('sid', _v('sid'));
          add('spx', _v('spx'));
          add('pqv', _v('pqv'));
        }
        _addTransportParams(add);
        break;
      case 'ss':
        final method = _v('method');
        final password = _v('password');
        if (_ssBase64) {
          uri.userInfo = base64Url
              .encode(utf8.encode('$method:$password'))
              .replaceAll('=', '');
        } else {
          uri.userInfo = '$method:$password';
        }
        break;
      case 'hysteria':
        final auth = _v('auth');
        if (_hyAuthInQuery) {
          add('auth', auth);
          uri.userInfo = '';
        } else {
          uri.userInfo = Uri.encodeComponent(auth);
        }
        add('sni', _v('sni'));
        add('fp', _drop['fp'] ?? '');
        add('alpn', _v('alpn'));
        add('ech', _v('ech'));
        if (_toggle['insecure'] ?? false) add('insecure', '1');
        add('obfs', _drop['obfs'] ?? '');
        if ((_drop['obfs'] ?? '').isNotEmpty) {
          add('obfs-password', _v('obfs-password'));
        }
        add('up', _v('up'));
        add('down', _v('down'));
        add('mport', _v('mport'));
        if (_v('mport').isNotEmpty) {
          add('hop-interval', _v('hop-interval'));
        }
        add('pinSHA256', _v('pinSHA256'));
        break;
    }

    return uri.build(managedParams: managed);
  }

  void _addTransportParams(void Function(String, String) add) {
    final type = _drop['type'] ?? 'tcp';
    add('type', type);
    switch (normalizeTransport(type)) {
      case 'ws':
      case 'httpupgrade':
        add('path', _v('path'));
        add('host', _v('host'));
        add('ed', _v('ed'));
      case 'xhttp':
        add('path', _v('path'));
        add('host', _v('host'));
        add('mode', _drop['mode'] ?? '');
        add('extra', _v('extra'));
        add('x_padding_bytes', _v('x_padding_bytes'));
      case 'grpc':
        add('serviceName', _v('serviceName'));
        add('mode', _drop['mode'] ?? '');
        add('authority', _v('authority'));
      case 'kcp':
        add('headerType', _drop['headerType'] ?? '');
        add('seed', _v('seed'));
        add('mtu', _v('mtu'));
        add('tti', _v('tti'));
      case 'tcp':
        final headerType = _drop['headerType'] ?? '';
        add('headerType', headerType);
        if (headerType == 'http') {
          add('host', _v('host'));
          add('path', _v('path'));
          add('method', _v('method'));
        }
    }
  }

  String _buildVmess() {
    final payload = Map<String, dynamic>.from(_vmess!);

    void put(String key, String value) {
      if (value.isEmpty) {
        payload.remove(key);
      } else if (payload[key] is int && int.tryParse(value) != null) {
        payload[key] = int.parse(value);
      } else {
        payload[key] = value;
      }
    }

    payload['add'] = _v('address');
    payload['port'] = _vmessPortWasInt
        ? (int.tryParse(_v('port')) ?? _v('port'))
        : _v('port');
    payload['id'] = _v('userInfo');
    put(_vmessSecurityKey, _drop['scy'] ?? '');
    final net = _drop['type'] ?? 'tcp';
    payload['net'] = net;
    final tls = _drop['security'] == 'tls';
    put('tls', tls ? 'tls' : '');
    put('sni', _v('sni'));
    put('host', _v('host'));
    switch (normalizeTransport(net)) {
      case 'grpc':
        put('path', _v('serviceName'));
        if (payload.containsKey('serviceName')) {
          put('serviceName', _v('serviceName'));
        }
        put('mode', _drop['mode'] ?? '');
        put('authority', _v('authority'));
      case 'kcp':
        put('path', _v('seed'));
        put('type', _drop['headerType'] ?? '');
        put('mtu', _v('mtu'));
        put('tti', _v('tti'));
      case 'xhttp':
        put('path', _v('path'));
        put('mode', _drop['mode'] ?? '');
        _putVmessExtra(payload);
        put('x_padding_bytes', _v('x_padding_bytes'));
      case 'ws' || 'httpupgrade':
        put('path', _v('path'));
        put('ed', _v('ed'));
      case 'tcp':
        put('type', _drop['headerType'] ?? '');
        put('path', _v('path'));
        put('method', _v('method'));
      default:
        put('path', _v('path'));
    }
    put('fp', _drop['fp'] ?? '');
    put('alpn', _v('alpn'));
    put('ech', _v('ech'));
    put('pcs', _v('pcs'));
    put('vcn', _v('vcn'));
    payload.remove('allowInsecure');
    payload.remove('skip-cert-verify');
    if (_toggle['insecure'] ?? false) {
      payload['insecure'] = '1';
    } else {
      payload.remove('insecure');
    }

    final json = jsonEncode(payload);
    return 'vmess://${base64.encode(utf8.encode(json))}';
  }

  // extra в vmess бывает и объектом, и строкой; генератор понимает оба, пишем как пришло
  void _putVmessExtra(Map<String, dynamic> payload) {
    final text = _v('extra');
    if (text.isEmpty) {
      payload.remove('extra');
      return;
    }
    if (_vmessExtraIsObject || !_vmess!.containsKey('extra')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          payload['extra'] = decoded;
          return;
        }
      } on FormatException {
        // битый остаётся строкой, его видно в поле extra
      }
    }
    payload['extra'] = text;
  }
}
