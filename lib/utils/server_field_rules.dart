/// Что с чем сочетается в настройках сервера.
///
/// Источник — документация и код ядра, а не общие соображения:
/// `docs/config/transport.md` держит две матрицы (транспорт × защита и
/// протокол × защита), `docs/config/outbounds/vless.md` — условия XTLS Vision,
/// `infra/conf/vless.go` — разбор `encryption` и `flow`.
///
/// Нужно это редактору: половина полей друг друга исключает, и раньше их можно
/// было выставить вместе. Vision на xhttp — не «работает хуже», а отказ ядра
/// («XTLS only supports TLS and REALITY directly for now»), то есть сервер,
/// который просто не подключается.
library;

/// Транспорты, которые приложение умеет собирать для vless, vmess и trojan.
///
/// `tcp` и `raw` — одно и то же (ядро переименовало), в ссылках встречаются оба.
const kServerTransports = <String>[
  'tcp',
  'ws',
  'grpc',
  'xhttp',
  'httpupgrade',
  'kcp',
];

/// Значения `flow`, которые ядро вообще принимает. Всё прочее — отказ от
/// конфига целиком (`VLESS users: "flow" doesn't support ...`).
const kServerFlows = <String>['', 'xtls-rprx-vision', 'xtls-rprx-vision-udp443'];

/// Приводит имена транспорта к одному виду: в ссылках ходят и `raw`, и `tcp`,
/// и `mkcp`, и `kcp`, и `splithttp` вместо `xhttp`.
String normalizeTransport(String raw) {
  final value = raw.trim().toLowerCase();
  return switch (value) {
    '' || 'raw' => 'tcp',
    'mkcp' => 'kcp',
    'splithttp' => 'xhttp',
    _ => value,
  };
}

/// Несёт ли транспорт REALITY.
///
/// По матрице «транспорт × защита»: raw, xhttp и grpc — да; websocket,
/// httpupgrade и mkcp — нет.
bool realityWorksOver(String transport) =>
    const {'tcp', 'xhttp', 'grpc'}.contains(normalizeTransport(transport));

/// Включено ли у VLESS шифрование уровня протокола.
///
/// `none` (и пустое значение, которое ядро приравнивает к ошибке, а ссылки —
/// к `none`) означает «выключено».
bool vlessEncryptionEnabled(String encryption) {
  final value = encryption.trim();
  return value.isNotEmpty && value != 'none';
}

/// Похоже ли значение `encryption` на то, что разберёт ядро.
///
/// Формат: `mlkem768x25519plus.<native|xorpub|random>.<1rtt|0rtt>.…`.
/// Всё остальное, кроме `none`, ядро не принимает и отвергает конфиг целиком,
/// поэтому проверяем здесь, а не узнаём по молчащему туннелю.
bool vlessEncryptionLooksValid(String encryption) {
  final value = encryption.trim();
  if (value.isEmpty || value == 'none') return true;
  final parts = value.split('.');
  if (parts.length < 4 || parts[0] != 'mlkem768x25519plus') return false;
  if (!const {'native', 'xorpub', 'random'}.contains(parts[1])) return false;
  return const {'1rtt', '0rtt'}.contains(parts[2]);
}

/// Работает ли XTLS Vision при таком наборе.
///
/// Два случая по документации: «TCP + TLS/REALITY» или включённый VLESS
/// Encryption (тогда транспорт и защита не важны). В остальных ядро на первом
/// же соединении отвечает «XTLS only supports TLS and REALITY directly».
bool visionWorksWith({
  required String transport,
  required String security,
  required String encryption,
}) {
  if (vlessEncryptionEnabled(encryption)) return true;
  final tls = security == 'tls' || security == 'reality';
  return tls && normalizeTransport(transport) == 'tcp';
}

/// Что именно не сходится в наборе полей.
enum ServerRuleIssue {
  /// Vision выбран там, где ядро его не поднимет.
  visionNeedsRawTls,

  /// Значение `flow`, которого у ядра нет.
  flowUnknown,

  /// REALITY поверх транспорта, который его не несёт.
  realityNeedsOwnTransport,

  /// REALITY без публичного ключа сервера.
  realityNeedsPublicKey,

  /// `encryption` не `none` и не похож на ключ VLESS Encryption.
  encryptionMalformed,

  /// Ни TLS, ни REALITY, ни Encryption: ядро пустит только в приватную сеть.
  noSecurityAtAll,
}

/// Все несоответствия набора — по порядку важности.
///
/// Пустой список означает ровно одно: ядро такой конфиг возьмёт. Насколько он
/// разумен — вопрос другой и не этой функции.
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

  // Trojan без TLS и VLESS без TLS и Encryption ядро уводит в «только приватные
  // адреса» — сервер в интернете с таким набором просто не отвечает.
  final bare = security != 'tls' && security != 'reality';
  if (bare && (protocol == 'trojan' || protocol == 'vless')) {
    if (protocol == 'trojan' || !vlessEncryptionEnabled(encryption)) {
      issues.add(ServerRuleIssue.noSecurityAtAll);
    }
  }

  return issues;
}

/// Значения защиты, которые имеет смысл предлагать при таком транспорте.
///
/// Текущее значение сюда не подмешивается: чужое (ссылка из другого клиента)
/// показывает редактор, чтобы не терять его молча.
List<String> securityOptionsFor(String transport) => [
      'none',
      'tls',
      if (realityWorksOver(transport)) 'reality',
    ];

/// Значения `flow`, которые имеет смысл предлагать при таком наборе.
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
