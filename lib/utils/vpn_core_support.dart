import 'dart:convert';
import 'dart:io';

import '../tunnel/vpn_backend.dart';
import 'awg_profile.dart';
import 'custom_clash_config.dart';
import 'custom_xray_config.dart';
import 'hysteria_uri.dart';
import 'proxy_chain.dart';

enum ServerFormat {
  link,

  xrayJson,

  clashYaml,

  chain,

  amneziaWg,

  unknown,
}

// молчаливого отката на xray больше нет: раньше в настройках стоял mihomo, а в сессии шёл libxray, и почему, узнать было неоткуда
enum VpnCoreSkip {
  customConfig,

  chainXrayOnly,

  chainMihomoOnly,

  amneziaWg,

  clashConfig,

  linkXrayOnly,

  linkMihomoOnly,

  // сейчас недостижимо, mihomo есть везде. оставлено для новой платформы: откатываться молча нельзя
  platform,
}

// одно место вместо трёх: раньше только Android было записано в трёх файлах подряд
bool get mihomoShipsHere =>
    Platform.isAndroid || Platform.isWindows || Platform.isLinux;

ServerFormat detectServerFormat(String config) {
  final trimmed = config.trim();
  if (trimmed.isEmpty) return ServerFormat.unknown;
  if (ProxyChainConfig.looksLikeChain(trimmed)) return ServerFormat.chain;
  if (AwgProfile.isAwgConfig(trimmed)) return ServerFormat.amneziaWg;
  if (_linkScheme.hasMatch(trimmed)) return ServerFormat.link;
  // clash раньше xray: json clash тоже начинается с {
  if (CustomClashConfig.looksLikeClash(trimmed) &&
      CustomClashConfig.tryParse(trimmed) != null) {
    return ServerFormat.clashYaml;
  }
  if (CustomXrayConfig.looksLikeJson(trimmed) &&
      CustomXrayConfig.tryParse(trimmed) != null) {
    return ServerFormat.xrayJson;
  }
  return ServerFormat.unknown;
}

final _linkScheme = RegExp(
  r'^(vless|vmess|trojan|ss|ssr|hysteria|hysteria2|hy2|tuic|anytls|mierus|socks|socks5|socks5h)://',
  caseSensitive: false,
);

Set<VpnBackend> backendsForFormat(ServerFormat format) => switch (format) {
      ServerFormat.link => const {VpnBackend.xray, VpnBackend.mihomo},
      ServerFormat.xrayJson || ServerFormat.chain => const {VpnBackend.xray},
      ServerFormat.clashYaml => const {VpnBackend.mihomo},
      ServerFormat.amneziaWg => const {VpnBackend.mihomo},
      ServerFormat.unknown => const {VpnBackend.xray},
    };

const _bothCores = {VpnBackend.xray, VpnBackend.mihomo};

const _mihomoOnlySchemes = {'tuic', 'anytls', 'ssr', 'mierus'};

// оба ядра молча пропускают незнакомый ключ: конфиг собирается, ядро поднимается, а трафик идёт не тем транспортом.
// непрочитанную ссылку считаем за оба, ошибку скажет генератор
Set<VpnBackend> backendsForLink(String link) {
  final trimmed = link.trim();
  final scheme = _schemeOf(trimmed);
  if (scheme == null) return _bothCores;

  if (_mihomoOnlySchemes.contains(scheme)) return const {VpnBackend.mihomo};

  if (scheme == 'vmess') return _vmessBackends(trimmed);

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return _bothCores;
  String param(String key) =>
      (uri.queryParameters[key] ?? '').trim().toLowerCase();

  // у xray в shadowsocks под плагин нет даже поля (infra/conf/shadowsocks.go)
  if (scheme == 'ss' && param('plugin').isNotEmpty) {
    return const {VpnBackend.mihomo};
  }

  if (scheme == 'ss' &&
      (param('uot') == '1' ||
          param('uot') == 'true' ||
          param('udp-over-tcp') == 'true' ||
          param('udp-over-tcp') == '1')) {
    return const {VpnBackend.mihomo};
  }

  // finalmask (fm, так отдаёт 3X-UI) у mihomo нет, сервер получил бы пакеты не той формы
  if ((scheme == 'vless' || scheme == 'trojan') && param('fm').isNotEmpty) {
    return const {VpnBackend.xray};
  }

  return _transportBackends(scheme, param('type'), param('headerType'));
}

Set<VpnBackend> _vmessBackends(String link) {
  try {
    var payload = link.substring('vmess://'.length).trim();
    payload = payload.replaceAll('-', '+').replaceAll('_', '/');
    final decoded = jsonDecode(utf8.decode(base64.decode(
      base64.normalize(payload),
    )));
    if (decoded is! Map) return _bothCores;
    if ((decoded['fm']?.toString() ?? '').trim().isNotEmpty) {
      return const {VpnBackend.xray};
    }
    return _transportBackends(
      'vmess',
      decoded['net']?.toString().trim().toLowerCase() ?? '',
      // type в json vmess это заголовок маскировки, не транспорт
      decoded['type']?.toString().trim().toLowerCase() ?? '',
    );
  } catch (_) {
    return _bothCores;
  }
}

// сверено по adapter/outbound/*.go mihomo 1.19.30 и infra/conf xray 26.7.28. нет поля под транспорт значит молчаливый голый TCP
Set<VpnBackend> _transportBackends(
  String scheme,
  String type,
  String headerType,
) {
  // http-opts у TrojanOption нет
  if (scheme == 'trojan' &&
      headerType == 'http' &&
      (type.isEmpty || type == 'tcp' || type == 'raw')) {
    return const {VpnBackend.xray};
  }
  return switch ((scheme, type)) {
      // h2 xray 26 снёс, конфиг падает целиком (снаружи SOCKS port not ready).
      // trojan с h2 не берёт никто, его не трогаем
      ('vless' || 'vmess', 'http' || 'h2') => const {VpnBackend.mihomo},
      // mkcp-opts у VlessOption и TrojanOption нет, у VmessOption есть, но генератор его не собирает
      (_, 'kcp' || 'mkcp') => const {VpnBackend.xray},
      // xhttp у mihomo только у VLESS
      ('vmess' || 'trojan', 'xhttp' || 'splithttp') => const {VpnBackend.xray},
      _ => _bothCores,
    };
}

String? _schemeOf(String link) => RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*)://')
    .firstMatch(link)
    ?.group(1)
    ?.toLowerCase();

// mihomo связывает узлы через dialer-proxy (adapter/outbound/base.go), так умеет любой его исходящий, AmneziaWG тоже.
// hysteria v1 он не берёт вовсе (buildProxy)
Set<VpnBackend> chainHopBackends(String config) {
  final trimmed = config.trim();
  switch (detectServerFormat(trimmed)) {
    case ServerFormat.amneziaWg:
      return const {VpnBackend.mihomo};
    case ServerFormat.link:
      final scheme = _schemeOf(trimmed);
      final link = backendsForLink(trimmed);
      return {
        if (link.contains(VpnBackend.xray) &&
            ProxyChainConfig.xrayHopProtocols.contains(scheme))
          VpnBackend.xray,
        if (link.contains(VpnBackend.mihomo) &&
            !(scheme == 'hysteria' && HysteriaLinkParams.isV1(trimmed)))
          VpnBackend.mihomo,
      };
    default:
      return const {};
  }
}

Set<VpnBackend> chainBackends(ProxyChainConfig chain) {
  var common = _bothCores;
  for (final hop in chain.hops) {
    common = common.intersection(chainHopBackends(hop.config));
  }
  return common;
}

// узлы без общего ядра раньше собирал xray, ошибку назовёт генератор
Set<VpnBackend> _chainConfigBackends(String config) {
  final chain = ProxyChainConfig.tryParse(config);
  if (chain == null) return const {VpnBackend.xray};
  final common = chainBackends(chain);
  return common.isEmpty ? const {VpnBackend.xray} : common;
}

VpnBackend preferredBackend(String preference) =>
    preference == 'mihomo' && mihomoShipsHere
        ? VpnBackend.mihomo
        : VpnBackend.xray;

typedef VpnBackendChoice = ({
  VpnBackend backend,
  ServerFormat format,
  VpnCoreSkip? skip,
});

VpnBackendChoice resolveVpnBackend({
  required String config,
  required String preference,
  required bool mihomoAvailable,
}) {
  final format = detectServerFormat(config);
  final capable = switch (format) {
    ServerFormat.link => backendsForLink(config),
    ServerFormat.chain => _chainConfigBackends(config),
    _ => backendsForFormat(format),
  };

  if (capable.length == 1) {
    final only = capable.single;
    if (only == VpnBackend.mihomo && !mihomoAvailable) {
      return (backend: only, format: format, skip: VpnCoreSkip.platform);
    }
    final skip = switch (preference) {
      'mihomo' when only != VpnBackend.mihomo => _skipFor(format, only),
      'xray' when only != VpnBackend.xray => _skipFor(format, only),
      _ => null,
    };
    return (backend: only, format: format, skip: skip);
  }

  // всё, кроме mihomo, это xray: он исполняет любой формат, на нём отлажен путь по умолчанию
  final wantsMihomo = preference == 'mihomo';
  if (wantsMihomo && !mihomoAvailable) {
    return (
      backend: VpnBackend.xray,
      format: format,
      skip: VpnCoreSkip.platform,
    );
  }
  return (
    backend: wantsMihomo ? VpnBackend.mihomo : VpnBackend.xray,
    format: format,
    skip: null,
  );
}

VpnCoreSkip _skipFor(ServerFormat format, VpnBackend only) => switch (format) {
      ServerFormat.link => only == VpnBackend.xray
          ? VpnCoreSkip.linkXrayOnly
          : VpnCoreSkip.linkMihomoOnly,
      ServerFormat.xrayJson => VpnCoreSkip.customConfig,
      ServerFormat.chain => only == VpnBackend.xray
          ? VpnCoreSkip.chainXrayOnly
          : VpnCoreSkip.chainMihomoOnly,
      ServerFormat.clashYaml => VpnCoreSkip.clashConfig,
      ServerFormat.amneziaWg => VpnCoreSkip.amneziaWg,
      _ => VpnCoreSkip.customConfig,
    };

// для лога, в UI локализованный текст
String vpnCoreSkipLogReason(VpnCoreSkip skip) => switch (skip) {
      VpnCoreSkip.customConfig => 'the server is a ready-made Xray JSON config',
      VpnCoreSkip.chainXrayOnly =>
        'mihomo cannot link some nodes of this proxy chain',
      VpnCoreSkip.chainMihomoOnly =>
        'this proxy chain has a node only mihomo can link',
      VpnCoreSkip.amneziaWg => 'the server is an AmneziaWG profile',
      VpnCoreSkip.clashConfig => 'the server is a ready-made Clash config',
      VpnCoreSkip.linkXrayOnly => 'mihomo has no such transport for this '
          'protocol',
      VpnCoreSkip.linkMihomoOnly => 'Xray 26 does not support this link',
      VpnCoreSkip.platform => 'that core does not ship on this platform',
    };
