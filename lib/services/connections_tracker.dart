import '../models/connection_entry.dart';

class ConnectionsTracker {
  ConnectionsTracker({
    this.closedLinger = const Duration(seconds: 45),
    this.unreportedTtl = const Duration(seconds: 30),
    this.silentTtl = const Duration(minutes: 10),
    this.maxTracked = 600,
  });

  final Duration closedLinger;

  final Duration unreportedTtl;

  final Duration silentTtl;

  final int maxTracked;

  final Map<String, _Tracked> _tracked = {};
  String? _token;

  bool _mergedOnce = false;

  void reset() {
    _tracked.clear();
    _token = null;
    _mergedOnce = false;
  }

  int get trackedCount => _tracked.length;

  ConnectionsSnapshot merge(
    ConnectionsSnapshot fresh, {
    required String sessionToken,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();

    if (fresh.source == ConnectionsSource.unavailable) {
      reset();
      return fresh;
    }
    if (_token != sessionToken) {
      reset();
      _token = sessionToken;
    }

    if (fresh.source == ConnectionsSource.coreApi) {
      return _snapshotFrom(fresh, _group(fresh.entries));
    }

    // первый опрос: в хвосте лога история, давнее закрытое отсеется по времени самого соединения
    final catchingUp = !_mergedOnce;
    _mergedOnce = true;

    for (final entry in fresh.entries) {
      final known = _tracked[entry.id];
      if (known == null) {
        _tracked[entry.id] = _Tracked(
          entry: entry,
          firstSeen: entry.startedAt ?? at,
          lastSeen: at,
          closedAt: !entry.closed
              ? null
              : catchingUp
                  ? (entry.startedAt ?? at)
                  : at,
        );
        continue;
      }
      known.absorb(entry, at);
    }

    _evict(at, closureReported: fresh.ruleInfoAvailable);

    final entries = _tracked.values.toList()
      ..sort((a, b) {
        if (a.entry.closed != b.entry.closed) return a.entry.closed ? 1 : -1;
        return b.firstSeen.compareTo(a.firstSeen);
      });

    return _snapshotFrom(
      fresh,
      _group([for (final tracked in entries) tracked.entry]),
    );
  }

  void _evict(DateTime at, {required bool closureReported}) {
    _tracked.removeWhere((_, tracked) {
      final closedAt = tracked.closedAt;
      if (closedAt != null) return at.difference(closedAt) > closedLinger;
      if (!closureReported) {
        return at.difference(tracked.lastSeen) > unreportedTtl;
      }
      return at.difference(tracked.lastSeen) > silentTtl;
    });

    if (_tracked.length <= maxTracked) return;
    final byAge = _tracked.entries.toList()
      ..sort((a, b) => a.value.lastSeen.compareTo(b.value.lastSeen));
    for (final entry in byAge.take(_tracked.length - maxTracked)) {
      _tracked.remove(entry.key);
    }
  }

  static ConnectionsSnapshot _snapshotFrom(
    ConnectionsSnapshot source,
    List<ConnectionEntry> entries,
  ) =>
      ConnectionsSnapshot(
        entries: entries,
        source: source.source,
        note: source.note,
        ruleInfoAvailable: source.ruleInfoAvailable,
        appNamesAvailable: source.appNamesAvailable,
      );

  static List<ConnectionEntry> _group(List<ConnectionEntry> entries) {
    final groups = <String, List<ConnectionEntry>>{};
    for (final entry in entries) {
      groups.putIfAbsent(entry.groupKey, () => []).add(entry);
    }
    return [
      for (final members in groups.values) _mergeGroup(members),
    ];
  }

  static ConnectionEntry _mergeGroup(List<ConnectionEntry> members) {
    if (members.length == 1) return members.first;

    var upload = 0;
    var download = 0;
    var hasBytes = false;
    DateTime? startedAt;
    var rule = '';
    var inbound = '';
    var closed = true;
    for (final member in members) {
      if (member.upload != null || member.download != null) {
        hasBytes = true;
        upload += member.upload ?? 0;
        download += member.download ?? 0;
      }
      final start = member.startedAt;
      if (start != null && (startedAt == null || start.isBefore(startedAt))) {
        startedAt = start;
      }
      if (rule.isEmpty) rule = member.rule;
      if (inbound.isEmpty) inbound = member.inbound;
      if (!member.closed) closed = false;
    }

    final newestFirst = [...members]..sort((a, b) {
        final at = a.startedAt, bt = b.startedAt;
        if (at == null || bt == null) return 0;
        return bt.compareTo(at);
      });
    final first = members.first;
    return first.copyWith(
      id: 'group:${first.groupKey}',
      source: '',
      rule: rule,
      inbound: inbound,
      startedAt: startedAt,
      upload: hasBytes ? upload : null,
      download: hasBytes ? download : null,
      closed: closed,
      count: members.length,
      members: newestFirst,
    );
  }
}

class _Tracked {
  _Tracked({
    required this.entry,
    required this.firstSeen,
    required this.lastSeen,
    this.closedAt,
  });

  ConnectionEntry entry;

  final DateTime firstSeen;

  DateTime lastSeen;

  DateTime? closedAt;

  void absorb(ConnectionEntry fresh, DateTime at) {
    lastSeen = at;
    if (fresh.closed) closedAt ??= at;
    entry = fresh.copyWith(
      // домен приходит позже сниффингом, имя приложения только у живых сокетов, выясненное не теряем
      host: fresh.host.isEmpty ? entry.host : fresh.host,
      destIp: fresh.destIp.isEmpty ? entry.destIp : fresh.destIp,
      process: fresh.process.isEmpty ? entry.process : fresh.process,
      rule: fresh.rule.isEmpty ? entry.rule : fresh.rule,
      outbound: fresh.outbound.isEmpty ? entry.outbound : fresh.outbound,
      startedAt: entry.startedAt ?? fresh.startedAt,
      closed: entry.closed || fresh.closed,
    );
  }
}
