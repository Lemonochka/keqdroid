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
    this.decidedByCore = false,
    this.closed = false,
    this.count = 1,
    this.members = const [],
  });

  final String id;

  final String network;

  final String host;
  final int destPort;

  final String destIp;

  final String source;

  final String process;

  final String inbound;

  final String outbound;

  final String rule;

  final DateTime? startedAt;

  final int? upload;
  final int? download;

  final bool rejected;

  final bool closed;

  final bool decidedByCore;

  final int count;

  final List<ConnectionEntry> members;

  ConnectionVerdict get verdict {
    if (rejected) return ConnectionVerdict.blocked;
    if (decidedByCore) return ConnectionVerdict.viaCore;
    final tag = outbound.toLowerCase();
    if (tag.contains('block')) return ConnectionVerdict.blocked;
    if (tag.contains('direct')) return ConnectionVerdict.direct;
    if (tag.isEmpty) return ConnectionVerdict.unknown;
    return ConnectionVerdict.proxied;
  }

  ConnectionEntry withRouting({
    required String rule,
    required String outbound,
    required bool decidedByCore,
  }) =>
      copyWith(
        rule: rule,
        outbound: outbound,
        decidedByCore: decidedByCore,
      );

  ConnectionEntry withProcess(String process) => copyWith(process: process);

  ConnectionEntry copyWith({
    String? id,
    String? host,
    String? destIp,
    String? source,
    String? process,
    String? inbound,
    String? outbound,
    String? rule,
    DateTime? startedAt,
    int? upload,
    int? download,
    bool? rejected,
    bool? decidedByCore,
    bool? closed,
    int? count,
    List<ConnectionEntry>? members,
  }) =>
      ConnectionEntry(
        id: id ?? this.id,
        network: network,
        host: host ?? this.host,
        destPort: destPort,
        destIp: destIp ?? this.destIp,
        source: source ?? this.source,
        process: process ?? this.process,
        inbound: inbound ?? this.inbound,
        outbound: outbound ?? this.outbound,
        rule: rule ?? this.rule,
        startedAt: startedAt ?? this.startedAt,
        upload: upload ?? this.upload,
        download: download ?? this.download,
        rejected: rejected ?? this.rejected,
        decidedByCore: decidedByCore ?? this.decidedByCore,
        closed: closed ?? this.closed,
        count: count ?? this.count,
        members: members ?? this.members,
      );

  String get groupKey => '$network|${host.toLowerCase()}|$destPort'
      '|${destIp.toLowerCase()}|${process.toLowerCase()}|${verdict.name}';

  String get target => '$host:$destPort';

  String get searchHaystack =>
      '$host $destIp $process $rule $outbound $inbound $source'.toLowerCase();
}

enum ConnectionVerdict {
  proxied,
  direct,
  blocked,

  viaCore,
  unknown,
}

enum ConnectionsSource {
  coreApi,

  coreLog,

  unavailable,
}

class ConnectionsSnapshot {
  const ConnectionsSnapshot({
    required this.entries,
    required this.source,
    this.note = '',
    this.ruleInfoAvailable = true,
    this.appNamesAvailable = true,
  });

  static const empty = ConnectionsSnapshot(
    entries: [],
    source: ConnectionsSource.unavailable,
  );

  final List<ConnectionEntry> entries;
  final ConnectionsSource source;

  final String note;

  final bool ruleInfoAvailable;

  final bool appNamesAvailable;
}
