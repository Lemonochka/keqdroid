import 'dart:convert';
import '../models/app_settings.dart';
import '../models/xray_core_settings.dart';
import '../utils/hysteria_uri.dart';
import '../utils/socks5_credentials.dart';

/// builds client outbound json for xray 26.x. a few quirks: no empty fingerprint
/// (core rejects ""), emit allowInsecure only when true, echConfigList is a
/// string not an array, and hysteria2 uses network "hysteria" not "quic".
class ConfigGeneratorV2 {
  static String generateConfig(
    String input,
    AppSettings settings, {
    String? resolvedServerIp,
    /// windows system proxy can't pass socks5 creds — use noauth on localhost.
    bool localInboundsNoAuth = false,
  }) {
    return const JsonEncoder.withIndent('  ').convert(
      _buildXrayConfig(
        input,
        settings,
        resolvedServerIp: resolvedServerIp,
        localInboundsNoAuth: localInboundsNoAuth,
      ),
    );
  }

  /// minimal xray config for ephemeral url ping (local socks5, no auth).
  static String generatePingConfig(
    String input,
    AppSettings settings, {
    required int socksPort,
    String? resolvedServerIp,
  }) {
    return jsonEncode(
      _buildXrayConfig(
        input,
        settings,
        resolvedServerIp: resolvedServerIp,
        pingSocksPort: socksPort,
      ),
    );
  }

  /// shared localhost port for ephemeral ping (sequential batch tests).
  static const int ephemeralPingPort = 28150;

  /// ephemeral socks port for url ping (fixed, one xray at a time).
  static int ephemeralPingPortFor(String serverId) => ephemeralPingPort;

  static bool _truthyQueryFlag(String Function(String, [String]) getParam, List<String> keys) {
    for (final k in keys) {
      final v = getParam(k, '').trim().toLowerCase();
      if (v == '1' || v == 'true' || v == 'yes') return true;
    }
    return false;
  }

  static List<String>? _splitAlpn(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final list = raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return list.isEmpty ? null : list;
  }

  /// tls client profile — keep fields compatible with infra/conf json tags.
  static Map<String, dynamic> _tlsClientSettings({
    required String serverName,
    bool allowInsecure = false,
    String fingerprint = '',
    String? alpnQuery,
    String? echConfigList,
    String? pinnedPeerCertSha256,
  }) {
    final tls = <String, dynamic>{
      'serverName': serverName,
    };
    if (allowInsecure) tls['allowInsecure'] = true;
    final fp = fingerprint.trim();
    if (fp.isNotEmpty) tls['fingerprint'] = fp;
    final alpn = _splitAlpn(alpnQuery);
    if (alpn != null) tls['alpn'] = alpn;
    final ech = echConfigList?.trim() ?? '';
    if (ech.isNotEmpty) tls['echConfigList'] = ech;
    final pin = pinnedPeerCertSha256?.trim() ?? '';
    if (pin.isNotEmpty) tls['pinnedPeerCertSha256'] = pin;
    return tls;
  }

  static String _decodeBase64UrlCompat(String input) {
    var normalized = input.trim().replaceAll('-', '+').replaceAll('_', '/');
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    return utf8.decode(base64.decode(normalized));
  }

  static Map<String, dynamic> _parseVmessPayload(String input) {
    final payload = input.substring('vmess://'.length).trim();
    if (payload.isEmpty) {
      throw ArgumentError('VMess payload is empty');
    }
    final decoded = _decodeBase64UrlCompat(payload);
    final parsed = jsonDecode(decoded);
    if (parsed is! Map<String, dynamic>) {
      throw ArgumentError('Invalid VMess payload format');
    }
    return parsed;
  }

  static Map<String, dynamic> _buildXrayConfig(
    String input,
    AppSettings settings, {
    String? resolvedServerIp,
    int? pingSocksPort,
    bool localInboundsNoAuth = false,
  }) {
    final trimmed = input.trim();
    final bool isVmess = trimmed.toLowerCase().startsWith('vmess://');
    final lowerTrimmed = trimmed.toLowerCase();
    final bool isHysteria = lowerTrimmed.startsWith('hysteria://') ||
        lowerTrimmed.startsWith('hysteria2://') ||
        lowerTrimmed.startsWith('hy2://');

    Uri uri;
    Map<String, dynamic>? vmessConfig;

    try {
      if (isVmess) {
        vmessConfig = _parseVmessPayload(trimmed);
        uri = Uri.parse('vmess://proxy');
      } else {
        uri = Uri.parse(trimmed);
      }
    } catch (e) {
      throw ArgumentError('Invalid URI format: $trimmed');
    }

    final scheme = isVmess ? 'vmess' : uri.scheme.toLowerCase();
    final address = isVmess ? (vmessConfig?['add']?.toString() ?? '') : uri.host;
    final port = isVmess
        ? int.tryParse(vmessConfig?['port']?.toString() ?? '') ?? 0
        : uri.port;

    String getParam(String key, [String def = '']) {
      if (vmessConfig != null) {
        if (key == 'type' && vmessConfig.containsKey('net')) {
          final value = vmessConfig['net'];
          return value == null ? def : value.toString();
        }
        final value = vmessConfig[key];
        if (value != null) return value.toString();
      }
      final val = uri.queryParametersAll[key];
      return (val != null && val.isNotEmpty) ? val.first : def;
    }

    final networkType = getParam('type', isHysteria ? 'hysteria' : 'tcp');
    final security = isVmess
        ? (vmessConfig?['tls']?.toString().toLowerCase() == 'tls' ? 'tls' : 'none')
        : getParam('security', scheme == 'trojan' ? 'tls' : (isHysteria ? 'none' : 'none'));

    final Map<String, dynamic> outbound;
    Map<String, dynamic> streamSettings = {'network': networkType};

    if (scheme == 'vless') {
      outbound = _buildVlessOutbound(uri, getParam, address, port, streamSettings);
    } else if (scheme == 'trojan') {
      outbound = _buildTrojanOutbound(uri, getParam, vmessConfig, address, port, streamSettings);
    } else if (scheme == 'ss') {
      outbound = _buildShadowsocksOutbound(uri, getParam, address, port);
    } else if (scheme == 'vmess') {
      outbound = _buildVmessOutbound(vmessConfig, getParam, address, port, streamSettings);
    } else if (isHysteria) {
      outbound = _buildHysteriaOutbound(uri, getParam, address, port, streamSettings);
    } else {
      throw ArgumentError('Unsupported protocol: $scheme');
    }

    _applyXrayStreamExtras(outbound, settings.xrayCore);

    return _wrapConfig(
      outbound,
      settings,
      resolvedServerIp ?? address,
      port,
      originalServerAddress: address,
      pingSocksPort: pingSocksPort,
      localInboundsNoAuth: localInboundsNoAuth,
    );
  }

  /// client-side xhttp extras (xmux) and similar stream options.
  static void _applyXrayStreamExtras(
    Map<String, dynamic> outbound,
    XrayCoreSettings core,
  ) {
    final stream = outbound['streamSettings'];
    if (stream is! Map<String, dynamic>) return;
    final network = stream['network']?.toString() ?? '';
    if (network != 'xhttp' && network != 'splithttp') return;

    final xmux = core.buildXmuxMap();
    if (xmux == null) return;

    final xhttp = Map<String, dynamic>.from(
      (stream['xhttpSettings'] as Map<String, dynamic>?) ?? {},
    );
    final extra = Map<String, dynamic>.from(
      (xhttp['extra'] as Map<String, dynamic>?) ?? {},
    );
    extra['xmux'] = xmux;
    xhttp['extra'] = extra;
    stream['xhttpSettings'] = xhttp;
  }

  // vless
  static Map<String, dynamic> _buildVlessOutbound(
      Uri uri, String Function(String, [String]) getParam, String address, int port, Map<String, dynamic> streamSettings) {
    final uuid = uri.userInfo;
    if (uuid.isEmpty) {
      throw ArgumentError('VLESS requires UUID in userInfo');
    }

    final flow = getParam('flow');
    final encryption = getParam('encryption', 'none').trim().isEmpty
        ? 'none'
        : getParam('encryption', 'none').trim();

    return {
      'tag': 'proxy',
      'protocol': 'vless',
      'settings': {
        'address': address,
        'port': port,
        'id': uuid,
        'encryption': encryption,
        if (flow.isNotEmpty) 'flow': flow,
        'level': 0,
      },
      'streamSettings': _buildStreamSettings(uri, getParam, address, streamSettings),
    };
  }

  // vmess
  static Map<String, dynamic> _buildVmessOutbound(
      Map<String, dynamic>? vmessConfig, String Function(String, [String]) getParam,
      String address, int port, Map<String, dynamic> streamSettings) {
    final uuid = vmessConfig?['id']?.toString() ?? '';
    if (uuid.isEmpty) {
      throw ArgumentError('VMess requires id in payload');
    }

    final vmessSecurity = vmessConfig?['security']?.toString() ?? vmessConfig?['scy']?.toString() ?? 'auto';
    final flow = vmessConfig?['flow']?.toString() ?? '';

    return {
      'tag': 'proxy',
      'protocol': 'vmess',
      'settings': {
        'address': address,
        'port': port,
        'id': uuid,
        'security': vmessSecurity,
        'level': 0,
        if (flow.isNotEmpty) 'flow': flow,
      },
      'streamSettings': _buildVmessStreamSettings(vmessConfig, streamSettings),
    };
  }

  static Map<String, dynamic> _buildVmessStreamSettings(
      Map<String, dynamic>? vmessConfig, Map<String, dynamic> streamSettings) {
    final network = vmessConfig?['net']?.toString() ?? 'tcp';
    final security = vmessConfig?['tls']?.toString() ?? 'none';
    final sni = vmessConfig?['sni']?.toString() ?? vmessConfig?['host']?.toString() ?? '';

    if (security == 'tls') {
      streamSettings['security'] = 'tls';
      final fp = vmessConfig?['fp']?.toString() ?? '';
      var insecure = false;
      if (vmessConfig != null) {
        for (final k in ['insecure', 'allowInsecure', 'skip-cert-verify']) {
          final v = (vmessConfig[k] ?? '').toString().trim().toLowerCase();
          if (v == '1' || v == 'true' || v == 'yes') {
            insecure = true;
            break;
          }
        }
      }
      final alpn = vmessConfig?['alpn']?.toString();
      final ech = vmessConfig?['ech']?.toString();
      streamSettings['tlsSettings'] = _tlsClientSettings(
        serverName: sni.isNotEmpty ? sni : (vmessConfig?['add']?.toString() ?? ''),
        allowInsecure: insecure,
        fingerprint: fp,
        alpnQuery: alpn,
        echConfigList: ech,
      );
    }

    if (network == 'ws') {
      streamSettings['wsSettings'] = {
        'path': vmessConfig?['path']?.toString() ?? '/',
        'headers': {'Host': vmessConfig?['host']?.toString() ?? sni},
      };
    } else if (network == 'grpc') {
      streamSettings['grpcSettings'] = {
        'serviceName': vmessConfig?['serviceName']?.toString() ?? '',
      };
    }

    return streamSettings;
  }

  // trojan
  static Map<String, dynamic> _buildTrojanOutbound(
      Uri uri, String Function(String, [String]) getParam, Map<String, dynamic>? vmessConfig,
      String address, int port, Map<String, dynamic> streamSettings) {
    final password = vmessConfig != null
        ? (vmessConfig['id']?.toString() ?? '')
        : uri.userInfo;
    if (password.isEmpty) {
      throw ArgumentError('Trojan requires password in userInfo');
    }

    final email = getParam('email');

    final type = getParam('type', 'tcp');
    final sni = getParam('sni', address);
    final fingerprint = getParam('fp', '');
    final insecure = _truthyQueryFlag(getParam, ['insecure', 'allowInsecure', 'skip-cert-verify']);

    streamSettings['network'] = type;
    streamSettings['security'] = 'tls';
    streamSettings['tlsSettings'] = _tlsClientSettings(
      serverName: sni,
      allowInsecure: insecure,
      fingerprint: fingerprint,
      alpnQuery: getParam('alpn'),
      echConfigList: getParam('ech'),
    );

    if (type == 'ws') {
      streamSettings['wsSettings'] = {
        'path': getParam('path', '/'),
        'headers': {'Host': getParam('host', sni)},
      };
    } else if (type == 'grpc') {
      streamSettings['grpcSettings'] = {
        'serviceName': getParam('serviceName'),
      };
    }

    return {
      'tag': 'proxy',
      'protocol': 'trojan',
      'settings': {
        'address': address,
        'port': port,
        'password': password,
        if (email.isNotEmpty) 'email': email,
        'level': 0,
      },
      'streamSettings': streamSettings,
    };
  }

  // shadowsocks
  static Map<String, dynamic> _buildShadowsocksOutbound(
      Uri uri, String Function(String, [String]) getParam, String address, int port) {
    // sip002: ss://base64(method:password@host:port) или ss://method:password@host:port
    // также бывает ss://base64(method:password)@host:port
    final withoutScheme = uri.toString().replaceFirst('ss://', '').trim();
    final hashIdx = withoutScheme.indexOf('#');
    final beforeHash = hashIdx >= 0 ? withoutScheme.substring(0, hashIdx) : withoutScheme;
    final atIdx = beforeHash.lastIndexOf('@');

    String method;
    String password;

    if (atIdx < 0) {
      throw ArgumentError('Shadowsocks requires userInfo with method:password');
    }

    final userInfo = beforeHash.substring(0, atIdx);

    if (userInfo.contains(':')) {
      // plain text method:password
      final splitIdx = userInfo.indexOf(':');
      method = userInfo.substring(0, splitIdx);
      password = userInfo.substring(splitIdx + 1);
    } else {
      // base64 method:password (sip002)
      final decoded = _decodeBase64UrlCompat(userInfo);
      final splitIdx = decoded.indexOf(':');
      if (splitIdx <= 0 || splitIdx >= decoded.length - 1) {
        throw ArgumentError('Invalid Shadowsocks userInfo format');
      }
      method = decoded.substring(0, splitIdx);
      password = decoded.substring(splitIdx + 1);
    }

    final email = getParam('email');
    final uot = getParam('uot');
    final uotVersion = getParam('UoTVersion');

    return {
      'tag': 'proxy',
      'protocol': 'shadowsocks',
      'settings': {
        'address': address,
        'port': port,
        'method': method,
        'password': password,
        if (email.isNotEmpty) 'email': email,
        if (uot.isNotEmpty) 'uot': uot.toLowerCase() == 'true',
        if (uotVersion.isNotEmpty) 'UoTVersion': int.tryParse(uotVersion) ?? 0,
        'level': 0,
      },
      'streamSettings': {'network': 'tcp'},
    };
  }

  // hysteria / hy2
  static Map<String, dynamic> _buildHysteriaOutbound(
      Uri uri,
      String Function(String, [String]) getParam,
      String address,
      int port,
      Map<String, dynamic> streamSettings,
  ) {
    var auth = getParam('auth', getParam('password', '')).trim();
    if (auth.isEmpty && uri.userInfo.isNotEmpty) {
      auth = Uri.decodeComponent(uri.userInfo).trim();
    }
    if (auth.isEmpty) {
      throw ArgumentError('Hysteria requires auth/password in URI (query or userInfo)');
    }

    final udpIdleTimeout = int.tryParse(getParam('udpIdleTimeout', '60')) ?? 60;

    Map<String, dynamic>? buildMasquerade() {
      final type = getParam('masqueradeType', getParam('masqType', ''));
      final dir = getParam('masqueradeDir', getParam('masqDir', ''));
      final url = getParam('masqueradeUrl', getParam('masqUrl', ''));
      final content = getParam('masqueradeContent', getParam('masqContent', ''));
      final statusCode = int.tryParse(getParam('masqueradeStatusCode', getParam('masqStatusCode', '')));

      if (type.isEmpty && dir.isEmpty && url.isEmpty && content.isEmpty && statusCode == null) {
        return null;
      }

      final map = <String, dynamic>{
        if (type.isNotEmpty) 'type': type,
        if (dir.isNotEmpty) 'dir': dir,
        if (url.isNotEmpty) 'url': url,
        if (content.isNotEmpty) 'content': content,
        if (statusCode != null) 'statusCode': statusCode,
      };
      return map;
    }

    final hyParams = HysteriaLinkParams.fromConfig(uri.toString());
    final sni = getParam('sni', hyParams.sni.isNotEmpty ? hyParams.sni : address);
    final insecure = _truthyQueryFlag(getParam, ['insecure', 'allowInsecure']);
    final version = int.tryParse(getParam('version', '2')) ?? 2;
    if (version != 2) {
      throw ArgumentError(
        'Hysteria v1 is not supported by Xray 26+. Use hysteria2:// or hy2:// links.',
      );
    }

    final alpnRaw = getParam('alpn', hyParams.alpn);
    final alpnForTls = alpnRaw.isNotEmpty ? alpnRaw : 'h3';

    // xray 26+ removed standalone "quic"; use the dedicated "hysteria" network
    streamSettings['network'] = 'hysteria';
    streamSettings['security'] = 'tls';
    streamSettings['tlsSettings'] = _tlsClientSettings(
      serverName: sni,
      allowInsecure: insecure,
      fingerprint: getParam('fp', ''),
      alpnQuery: alpnForTls,
      echConfigList: getParam('ech'),
      pinnedPeerCertSha256: getParam('pinSHA256', hyParams.pinSha256),
    );

    final hysteriaSettings = <String, dynamic>{
      'version': version,
      'auth': auth,
      'udpIdleTimeout': udpIdleTimeout,
      if (buildMasquerade() != null) 'masquerade': buildMasquerade(),
    };

    final up = HysteriaLinkParams.formatBandwidth(
      getParam('up', hyParams.up),
    );
    final down = HysteriaLinkParams.formatBandwidth(
      getParam('down', hyParams.down),
    );
    if (up != null) hysteriaSettings['up'] = up;
    if (down != null) hysteriaSettings['down'] = down;

    final mport = getParam('mport', hyParams.mport);
    if (mport.isNotEmpty) {
      final hop = <String, dynamic>{'ports': mport};
      final interval = getParam('hop-interval', hyParams.hopInterval);
      if (interval.isNotEmpty) hop['interval'] = interval;
      hysteriaSettings['udphop'] = hop;
    }

    streamSettings['hysteriaSettings'] = hysteriaSettings;

    final finalmask = hyParams.buildFinalmask();
    if (finalmask != null) {
      streamSettings['finalmask'] = finalmask;
    }

    return {
      'tag': 'proxy',
      'protocol': 'hysteria',
      'settings': {
        'address': address,
        'port': port,
        'version': hysteriaSettings['version'],
      },
      'streamSettings': streamSettings,
    };
  }

  // stream settings
  static Map<String, dynamic> _buildStreamSettings(
      Uri uri, String Function(String, [String]) getParam, String address, Map<String, dynamic> existing) {
    final type = getParam('type', 'tcp');
    final security = getParam('security', 'none');
    final sni = getParam('sni', getParam('host', address));

    final stream = existing;
    stream['network'] = type;
    stream['security'] = security;

    if (security == 'tls') {
      final insecure = _truthyQueryFlag(getParam, ['insecure', 'allowInsecure', 'skip-cert-verify']);
      stream['tlsSettings'] = _tlsClientSettings(
        serverName: sni,
        allowInsecure: insecure,
        fingerprint: getParam('fp', ''),
        alpnQuery: getParam('alpn'),
        echConfigList: getParam('ech'),
      );
    } else if (security == 'reality') {
      final rfp = getParam('fp', '').trim();
      stream['realitySettings'] = {
        'show': false,
        // reality needs a known utls fingerprint; empty is invalid on xray 26+.
        'fingerprint': rfp.isNotEmpty ? rfp : 'chrome',
        'serverName': sni,
        'publicKey': getParam('pbk'),
        'shortId': getParam('sid'),
        'spiderX': getParam('spx'),
      };
    }

    switch (type) {
      case 'ws':
        stream['wsSettings'] = {'path': getParam('path', '/'), 'headers': {'Host': getParam('host', sni)}};
      case 'grpc':
        stream['grpcSettings'] = {'serviceName': getParam('serviceName'), 'multiMode': getParam('mode') == 'multi'};
      case 'xhttp': case 'splithttp':
        final host = getParam('host');
        stream['xhttpSettings'] = {
          'path': getParam('path', '/'),
          'host': host.isNotEmpty ? host : sni,
          if (getParam('mode').isNotEmpty) 'mode': getParam('mode'),
        };
      case 'httpupgrade':
        stream['httpupgradeSettings'] = {'path': getParam('path', '/'), 'host': getParam('host', sni)};
      case 'tcp':
        if (getParam('headerType') == 'http') {
          stream['tcpSettings'] = {'header': {'type': 'http', 'request': {'headers': {'Host': [getParam('host', address)]}}}};
        }
    }
    return stream;
  }

  // обёртка конфига
  static Map<String, dynamic> _wrapConfig(
      Map<String, dynamic> outbound, AppSettings settings, String serverAddress, int serverPort,
      {String? originalServerAddress, int? pingSocksPort, bool localInboundsNoAuth = false}) {

    originalServerAddress ??= serverAddress;
    final isPingMode = pingSocksPort != null;

    List<String> parseList(String s) => s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    List<String> normalizeDomains(List<String> domains) => domains.map((d) {
      final c = d.trim().toLowerCase();
      if (c.startsWith('domain:') || c.startsWith('full:') || c.startsWith('regexp:') || c.startsWith('geosite:')) return c;
      if (!c.contains('.')) return 'regexp:.*\\.$c\$';
      if (c.startsWith('.')) return 'domain:${c.substring(1)}';
      return 'domain:$c';
    }).toList();

    final directDomains  = normalizeDomains(parseList(settings.directDomains));
    final blockedDomains = normalizeDomains(parseList(settings.blockedDomains));
    final proxyDomains   = normalizeDomains(parseList(settings.proxyDomains));
    final directIps      = parseList(settings.directIps);

    final core = settings.xrayCore;
    final dns = isPingMode
        ? {
            'servers': ['8.8.8.8', '1.1.1.1'],
            'queryStrategy': 'UseIPv4',
          }
        : core.buildDnsBlock(directDomains: directDomains);

    final rules = <Map<String, dynamic>>[];
    rules.add({'type': 'field', 'ip': ['169.254.0.0/16', '224.0.0.0/4', '255.255.255.255/32'], 'outboundTag': 'block'});

    if (isPingMode) {
      final isServerIp = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(serverAddress);
      if (isServerIp) {
        rules.add({'type': 'field', 'ip': [serverAddress], 'outboundTag': 'direct'});
      }
      if (!RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(originalServerAddress)) {
        rules.add({'type': 'field', 'domain': ['full:$originalServerAddress'], 'outboundTag': 'direct'});
      } else if (!isServerIp) {
        rules.add({'type': 'field', 'ip': [originalServerAddress], 'outboundTag': 'direct'});
      }
      rules.add({
        'type': 'field',
        'ip': [
          '0.0.0.0/8', '10.0.0.0/8', '127.0.0.0/8', '172.16.0.0/12',
          '192.168.0.0/16', '::1/128', 'fc00::/7', 'fe80::/10',
        ],
        'outboundTag': 'direct',
      });
    } else {
    if (!isPingMode && settings.lanSharing) {
      rules.add({
        'type': 'field',
        'inboundTag': ['socks-lan', 'http-lan'],
        'source': [
          '10.0.0.0/8',
          '172.16.0.0/12',
          '192.168.0.0/16',
          '169.254.0.0/16',
          '127.0.0.0/8',
        ],
        'outboundTag': 'proxy',
      });
      rules.add({
        'type': 'field',
        'inboundTag': ['socks-lan', 'http-lan'],
        'outboundTag': 'block',
      });
    }
    if (blockedDomains.isNotEmpty) {
      rules.add({'type': 'field', 'domain': blockedDomains, 'outboundTag': 'block'});
    }
    final isServerIp = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(serverAddress);
    if (isServerIp) {
      rules.add({'type': 'field', 'ip': [serverAddress], 'outboundTag': 'direct'});
    }
    if (!RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(originalServerAddress)) {
      rules.add({'type': 'field', 'domain': ['full:$originalServerAddress'], 'outboundTag': 'direct'});
    } else if (!isServerIp) {
      rules.add({'type': 'field', 'ip': [originalServerAddress], 'outboundTag': 'direct'});
    }
    if (directDomains.isNotEmpty) {
      rules.add({'type': 'field', 'domain': directDomains, 'outboundTag': 'direct'});
    }
    const basePrivateIps = {
      '0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8',
      '169.254.0.0/16', '172.16.0.0/12', '172.19.0.0/30',
      '192.0.0.0/24', '192.168.0.0/16',
      '198.51.100.0/24', '203.0.113.0/24',
      '::1/128', 'fc00::/7', 'fe80::/10',
    };
    final extraDirectIps = directIps.where((ip) => !basePrivateIps.contains(ip)).toList();

    rules.add({'type': 'field', 'ip': [
      ...extraDirectIps,
      '0.0.0.0/8',
      '10.0.0.0/8',
      '100.64.0.0/10',
      '127.0.0.0/8',
      '169.254.0.0/16',
      '172.16.0.0/12',
      '172.19.0.0/30',
      '192.0.0.0/24',
      '192.168.0.0/16',
      '198.51.100.0/24',
      '203.0.113.0/24',
      '::1/128', 'fc00::/7', 'fe80::/10',
    ], 'outboundTag': 'direct'});
    if (proxyDomains.isNotEmpty) {
      rules.add({'type': 'field', 'domain': proxyDomains, 'outboundTag': 'proxy'});
    }

    // kill switch: 0.0.0.0/1 + 128.0.0.0/1 ловят весь трафик в обход default route
    if (!isPingMode && settings.killSwitch) {
      rules.add({
        'type': 'field',
        'ip': ['0.0.0.0/1', '128.0.0.0/1'],
        'outboundTag': 'proxy',
      });
    }
    } // end full routing (non-ping)

    rules.add({'type': 'field', 'outboundTag': 'proxy', 'network': 'tcp,udp'});

    final socksPort = pingSocksPort ?? settings.localPort;
    final useNoAuthInbound = isPingMode || localInboundsNoAuth;
    final inbounds = <Map<String, dynamic>>[
      {
        'tag': 'socks-in',
        'port': socksPort,
        'listen': '127.0.0.1',
        'protocol': 'socks',
        'settings': useNoAuthInbound
            ? {'auth': 'noauth', 'udp': true}
            : {
                'auth': 'password',
                'udp': true,
                'accounts': [
                  {
                    'user': Socks5Credentials().username,
                    'pass': Socks5Credentials().password,
                  }
                ],
              },
        if (!isPingMode) 'sniffing': core.buildSniffing(),
      },
      if (!isPingMode) ...[
      {
        'tag': 'http-in',
        'port': settings.httpPort,
        'listen': '127.0.0.1',
        'protocol': 'http',
        'settings': useNoAuthInbound
            ? {'allowTransparent': false}
            : {
                'allowTransparent': false,
                'accounts': [
                  {
                    'user': Socks5Credentials().username,
                    'pass': Socks5Credentials().password,
                  }
                ],
              },
      },
      if (settings.lanSharing) ...[
        {
          'tag': 'socks-lan',
          'port': settings.lanSocksPort,
          'listen': '0.0.0.0',
          'protocol': 'socks',
          'settings': {
            'auth': 'noauth',
            'udp': true,
          },
          'sniffing': core.buildSniffing(),
        },
        {
          'tag': 'http-lan',
          'port': settings.lanHttpPort,
          'listen': '0.0.0.0',
          'protocol': 'http',
          'settings': {'allowTransparent': false},
        },
      ],
      ],
    ];

    return {
      'log': {'loglevel': isPingMode ? 'none' : core.logLevel},
      'dns': dns,
      'inbounds': inbounds,
      'outbounds': [
        outbound,
        {'protocol': 'freedom', 'tag': 'direct'},
        {'protocol': 'blackhole', 'tag': 'block'},
      ],
      'routing': {
        'domainStrategy': isPingMode ? 'AsIs' : core.routingDomainStrategy,
        'rules': rules,
      },
    };
  }
}
