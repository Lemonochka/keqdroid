// по docs/config/transport.md и infra/conf/vless.go ядра: vision на xhttp ядро отвергает, а не просто работает хуже
library;

const kServerTransports = <String>[
  'tcp',
  'ws',
  'grpc',
  'xhttp',
  'httpupgrade',
  'kcp',
];

// другие flow ядро не принимает и отвергает конфиг целиком
const kServerFlows = <String>[
  '',
  'xtls-rprx-vision',
  'xtls-rprx-vision-udp443',
];

String normalizeTransport(String raw) {
  final value = raw.trim().toLowerCase();
  return switch (value) {
    '' || 'raw' => 'tcp',
    'mkcp' => 'kcp',
    'splithttp' => 'xhttp',
    _ => value,
  };
}

// по матрице транспорт × защита: raw, xhttp и grpc несут REALITY, ws, httpupgrade и mkcp нет
bool realityWorksOver(String transport) =>
    const {'tcp', 'xhttp', 'grpc'}.contains(normalizeTransport(transport));

bool vlessEncryptionEnabled(String encryption) {
  final value = encryption.trim();
  return value.isNotEmpty && value != 'none';
}

// всё, кроме none и mlkem768x25519plus..., ядро отвергает целиком
bool vlessEncryptionLooksValid(String encryption) {
  final value = encryption.trim();
  if (value.isEmpty || value == 'none') return true;
  final parts = value.split('.');
  if (parts.length < 4 || parts[0] != 'mlkem768x25519plus') return false;
  if (!const {'native', 'xorpub', 'random'}.contains(parts[1])) return false;
  return const {'1rtt', '0rtt'}.contains(parts[2]);
}

bool visionWorksWith({
  required String transport,
  required String security,
  required String encryption,
}) {
  if (vlessEncryptionEnabled(encryption)) return true;
  final tls = security == 'tls' || security == 'reality';
  return tls && normalizeTransport(transport) == 'tcp';
}

enum ServerRuleIssue {
  visionNeedsRawTls,

  flowUnknown,

  realityNeedsOwnTransport,

  realityNeedsPublicKey,

  encryptionMalformed,

  noSecurityAtAll,
}

List<ServerRuleIssue> serverRuleIssues({
  required String protocol,
  required String transport,
  required String security,
  String flow = '',
  String encryption = '',
  String publicKey = '',
}) {
  final issues = <ServerRuleIssue>[];
  final kind = normalizeTransport(transport);

  if (flow.isNotEmpty) {
    if (!kServerFlows.contains(flow)) {
      issues.add(ServerRuleIssue.flowUnknown);
    } else if (!visionWorksWith(
      transport: kind,
      security: security,
      encryption: encryption,
    )) {
      issues.add(ServerRuleIssue.visionNeedsRawTls);
    }
  }

  if (security == 'reality') {
    if (!realityWorksOver(kind)) {
      issues.add(ServerRuleIssue.realityNeedsOwnTransport);
    }
    if (publicKey.trim().isEmpty) {
      issues.add(ServerRuleIssue.realityNeedsPublicKey);
    }
  }

  if (protocol == 'vless' && !vlessEncryptionLooksValid(encryption)) {
    issues.add(ServerRuleIssue.encryptionMalformed);
  }

  // trojan и vless без TLS и Encryption ядро пускает только в приватные адреса
  final bare = security != 'tls' && security != 'reality';
  if (bare && (protocol == 'trojan' || protocol == 'vless')) {
    if (protocol == 'trojan' || !vlessEncryptionEnabled(encryption)) {
      issues.add(ServerRuleIssue.noSecurityAtAll);
    }
  }

  return issues;
}

List<String> securityOptionsFor(String transport) => [
  'none',
  'tls',
  if (realityWorksOver(transport)) 'reality',
];

List<String> flowOptionsFor({
  required String protocol,
  required String transport,
  required String security,
  required String encryption,
}) {
  if (protocol != 'vless') return const [''];
  if (!visionWorksWith(
    transport: transport,
    security: security,
    encryption: encryption,
  )) {
    return const [''];
  }
  return kServerFlows;
}
