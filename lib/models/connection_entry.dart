/// Одно соединение, показанное в дебаг-экране «Соединения».
///
/// Источников два, и они дают разный объём данных:
///  - desktop: clash_api ядра (`GET /connections`) — процесс, домен, IP, правило,
///    счётчики байт;
///  - Android: access-лог xray — процесса нет (ядро его не знает), байт нет,
///    зато есть домен/IP, инбаунд, аутбаунд и (при уровне логов Info) правило.
class ConnectionEntry {
  const ConnectionEntry({
    required this.id,
    required this.network,
    required this.host,
    required this.destPort,
    this.destIp = '',
    this.source = '',
    this.process = '',
    this.inbound = '',
    this.outbound = '',
    this.rule = '',
    this.startedAt,
    this.upload,
    this.download,
    this.rejected = false,
  });

  /// Стабильный ключ для списка: source+dest у одного соединения не меняются.
  final String id;

  /// `tcp` / `udp`.
  final String network;

  /// Домен, если ядро его знает (сниффинг/CONNECT), иначе IP.
  final String host;
  final int destPort;

  /// IP назначения — когда известен и отличается от [host].
  final String destIp;

  /// `ip:port` источника (локальный сокет приложения).
  final String source;

  /// Путь/имя процесса. Пусто, когда источник его не даёт (Android).
  final String process;

  /// Тег инбаунда ядра (`socks-in`, `tun-in`, …).
  final String inbound;

  /// Тег аутбаунда, куда ушло соединение (`proxy`, `direct`, `block`).
  final String outbound;

  /// Правило, по которому выбран аутбаунд. Пусто — правило неизвестно
  /// (на Android для этого нужен уровень логов Info).
  final String rule;

  final DateTime? startedAt;

  /// Счётчики байт. null — источник их не отдаёт.
  final int? upload;
  final int? download;

  /// Соединение отклонено ядром (`rejected` в access-логе).
  final bool rejected;

  /// Куда ушло соединение — для раскраски: прокси/напрямую/блок.
  ConnectionVerdict get verdict {
    if (rejected) return ConnectionVerdict.blocked;
    final tag = outbound.toLowerCase();
    if (tag.contains('block')) return ConnectionVerdict.blocked;
    if (tag.contains('direct')) return ConnectionVerdict.direct;
    if (tag.isEmpty) return ConnectionVerdict.unknown;
    return ConnectionVerdict.proxied;
  }

  /// `host:port`, как это привычно видеть в логах.
  String get target => '$host:$destPort';

  /// Строка для поиска по списку.
  String get searchHaystack =>
      '$host $destIp $process $rule $outbound $inbound $source'.toLowerCase();
}

enum ConnectionVerdict { proxied, direct, blocked, unknown }

/// Откуда взят снимок соединений — экран сообщает это пользователю, потому что
/// от источника зависит полнота данных.
enum ConnectionsSource {
  /// clash_api ядра: полные данные, живой снимок активных соединений.
  coreApi,

  /// Access-лог ядра: история, без байт и процессов.
  coreLog,

  /// Источник недоступен (нет активной сессии/платформа не поддерживает).
  unavailable,
}

/// Снимок списка соединений вместе с метаданными для UI.
class ConnectionsSnapshot {
  const ConnectionsSnapshot({
    required this.entries,
    required this.source,
    this.note = '',
    this.ruleInfoAvailable = true,
  });

  static const empty = ConnectionsSnapshot(
    entries: [],
    source: ConnectionsSource.unavailable,
  );

  final List<ConnectionEntry> entries;
  final ConnectionsSource source;

  /// Человекочитаемая причина, когда список пуст/неполон.
  final String note;

  /// false — источник в принципе не может сказать, какое правило сработало
  /// (access-лог при уровне логов ниже Info).
  final bool ruleInfoAvailable;
}
