import 'dart:convert';

import 'package:flutter/foundation.dart' show listEquals;

import 'tunnel_session_request.dart';

const _perServerKeys = {
  'proxies',
  'proxy-groups',
  'proxy-providers',
  'rules',
  'rule-providers',
  'sub-rules',
  'hosts',
};

// серверы DNS и политики по доменам ядро меняет на ходу, а слушатель и подмена адресов принадлежат туннелю
const _tunnelDnsKeys = [
  'enable',
  'listen',
  'ipv6',
  'enhanced-mode',
  'fake-ip-range',
  'fake-ip-range6',
];

// на ходу mihomo меняет серверы и правила, а другой TUN или вход он пересоздал бы: это уже переподключение
bool sameTunnelShell(TunnelSessionRequest a, TunnelSessionRequest b) {
  if (a.mode != b.mode ||
      a.vpnBackend != b.vpnBackend ||
      a.xrayConfig != b.xrayConfig ||
      a.socksPort != b.socksPort ||
      a.httpPort != b.httpPort ||
      a.systemProxy != b.systemProxy ||
      a.coreEngine != b.coreEngine ||
      a.debugMode != b.debugMode ||
      !listEquals(a.excludePackages, b.excludePackages) ||
      !listEquals(a.includePackages, b.includePackages) ||
      !listEquals(a.excludeProcesses, b.excludeProcesses) ||
      !listEquals(a.includeProcesses, b.includeProcesses)) {
    return false;
  }
  final x = _shell(a.mihomoConfig);
  final y = _shell(b.mihomoConfig);
  return x != null && y != null && x == y;
}

// конфиг пишет один генератор, порядок ключей у двух сессий один и тот же
String? _shell(String? config) {
  if (config == null || config.isEmpty) return null;
  try {
    final json = jsonDecode(config);
    if (json is! Map<String, dynamic>) return null;
    final shell = <String, dynamic>{
      for (final e in json.entries)
        if (!_perServerKeys.contains(e.key)) e.key: e.value,
    };
    final dns = shell['dns'];
    if (dns is Map) {
      shell['dns'] = {
        for (final key in _tunnelDnsKeys)
          if (dns.containsKey(key)) key: dns[key],
      };
    }
    return jsonEncode(shell);
  } on FormatException {
    return null;
  }
}
