import '../models/ping_sample.dart';
import '../models/server_item.dart';

abstract final class AutoServerSelect {
  static const historyWindow = Duration(hours: 24);

  static const failurePenalty = 1000;

  static int? latencyScore(ServerItem server, DateTime now) {
    final last = server.pingMs;
    final type = server.lastPingType;
    if (last == null) return null;
    if (type != null && !PingSample.latencyTypes.contains(type)) return null;
    final recent = [
      for (final s in server.pingSamples)
        if (s.type == type && now.difference(s.at).abs() <= historyWindow) s,
    ];
    final answered = [
      for (final s in recent)
        if (s.ms != null) s.ms!,
    ]..sort();
    final failures = recent.length - answered.length;
    if (answered.length < 2) return last + failures * failurePenalty;
    final median = answered[answered.length ~/ 2];
    final spread = answered.last - answered.first;
    return median + spread + failures * failurePenalty;
  }

  static int? _speedKbps(ServerItem server) =>
      server.lastPingType == 'speed' ? server.pingMs : null;

  static List<ServerItem> _ranked(Iterable<ServerItem> servers, DateTime now) {
    int tier(ServerItem s) {
      if (latencyScore(s, now) != null) return 0;
      if (_speedKbps(s) != null) return 1;
      if (s.lastTestedAt == null) return 2;
      return 3;
    }

    // сортировка в Dart неустойчивая, поэтому порядок в списке последним ключом
    final indexed = servers.indexed.toList();
    indexed.sort((x, y) {
      final (ia, a) = x;
      final (ib, b) = y;
      final byTier = tier(a).compareTo(tier(b));
      if (byTier != 0) return byTier;
      final byValue = switch (tier(a)) {
        0 => latencyScore(a, now)!.compareTo(latencyScore(b, now)!),
        1 => _speedKbps(b)!.compareTo(_speedKbps(a)!),
        _ => 0,
      };
      return byValue != 0 ? byValue : ia.compareTo(ib);
    });
    return [for (final (_, s) in indexed) s];
  }

  static ServerItem? pick(
    List<ServerItem> servers, {
    required String subscriptionId,
    String? exclude,
    String? excludeHost,
    DateTime? now,
  }) {
    final group = [
      for (final server in servers)
        if (server.subscriptionId == subscriptionId) server,
    ];
    if (group.isEmpty) return null;

    final host = excludeHost?.trim().toLowerCase();
    final elsewhere = [
      for (final server in group)
        if (server.id != exclude &&
            (host == null ||
                host.isEmpty ||
                server.address.trim().toLowerCase() != host))
          server,
    ];
    final candidates = elsewhere.isNotEmpty
        ? elsewhere
        : [
            for (final server in group)
              if (server.id != exclude) server,
          ];
    final pool = candidates.isEmpty ? group : candidates;

    return _ranked(pool, now ?? DateTime.now()).first;
  }

  static List<ServerItem> candidatesToMeasure(
    List<ServerItem> servers, {
    required String subscriptionId,
    required ServerItem current,
    int limit = 10,
    Set<String> include = const {},
    DateTime? now,
  }) {
    final group = [
      for (final server in servers)
        if (server.subscriptionId == subscriptionId && server.id != current.id)
          server,
    ];
    final forced = [
      for (final server in group)
        if (include.contains(server.id)) server,
    ];
    final others = _ranked(
      group.where((s) => !include.contains(s.id)),
      now ?? DateTime.now(),
    );
    return [current, ...forced, ...others].take(limit).toList();
  }

  // не ответил никто: это сеть (лифт, метро, переезд с Wi-Fi), а не серверы.
  // такой провал сутки штрафовал бы лучших и уводил их в конец очереди замеров
  static bool worthRecording(
    Iterable<({String id, bool success, int? latencyMs})> results,
  ) =>
      results.any((r) => r.success);

  // на переезде решает не один удачный ответ: ровный сервер обходит того, кто сегодня скакал и падал
  static int switchScore(ServerItem? server, int latencyMs, DateTime now) {
    if (server == null) return latencyMs;
    final recent = [
      for (final s in server.pingSamples)
        if (s.type == 'url' && now.difference(s.at).abs() <= historyWindow) s,
    ];
    final answered = [
      latencyMs,
      for (final s in recent)
        if (s.ms != null) s.ms!,
    ]..sort();
    final failures = recent.length - (answered.length - 1);
    return latencyMs +
        (answered.last - answered.first) +
        failures * failurePenalty;
  }

  // пока текущий не ответил, соседи ничего не решают: дальний сервер иначе проигрывал бы гонку живым
  static AutoSelectVerdict judge({
    required String currentId,
    required Iterable<({String id, bool success, int? latencyMs})> results,
    required bool batchComplete,
    int Function(String id, int latencyMs)? score,
  }) {
    int rank(({String id, bool success, int? latencyMs}) r) {
      final ms = r.latencyMs ?? 1 << 30;
      return score == null ? ms : score(r.id, ms);
    }

    ({String id, bool success, int? latencyMs})? current;
    ({String id, bool success, int? latencyMs})? best;
    for (final r in results) {
      if (r.id == currentId) {
        current = r;
        continue;
      }
      if (!r.success) continue;
      if (best == null || rank(r) < rank(best)) {
        best = r;
      }
    }
    if (current != null && current.success) return const AutoSelectVerdict.stay();
    if (current != null && best != null) return AutoSelectVerdict.switchTo(best.id);
    return batchComplete
        ? const AutoSelectVerdict.stay()
        : const AutoSelectVerdict.undecided();
  }
}

final class AutoSelectVerdict {
  const AutoSelectVerdict.stay() : nextId = null, decided = true;
  const AutoSelectVerdict.switchTo(String this.nextId) : decided = true;
  const AutoSelectVerdict.undecided() : nextId = null, decided = false;

  final String? nextId;

  final bool decided;
}
