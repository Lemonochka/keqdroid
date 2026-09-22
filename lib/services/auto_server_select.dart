import '../models/server_item.dart';

/// Выбор сервера за человека — та самая «Авто» в шапке подписки.
///
/// Правило одно: из живых берём лучший по последнему замеру. Живой тут значит
/// «замер удался»: [ServerItem.pingMs] у неудачного замера обнуляется
/// (см. servers_provider), поэтому красный сервер и сервер, которого никогда
/// не мерили, в списке выглядят одинаково — и это не одно и то же. Ни разу не
/// меренный не мёртв, он неизвестен, поэтому идёт следом за померенными, а не
/// выбрасывается: подписка, которую ещё не пинговали, иначе не дала бы
/// подключиться вовсе.
abstract final class AutoServerSelect {
  /// Кого включать автовыбором в подписке [subscriptionId].
  ///
  /// [exclude] — сервер, с которого только что съехали: он только что не
  /// работал, и возвращаться на него в ту же секунду незачем. Когда кроме
  /// него никого нет, возвращаем его же — «совсем ничего» и «единственный
  /// сервер» разные вещи, и во втором случае честнее попробовать ещё раз.
  ///
  /// [excludeHost] — адрес умершего сервера. Протоколы на одной машине
  /// умирают вместе (на живом тесте погасили VPS, и в списке остался его же
  /// Vless со старым хорошим пингом), так что соседей по адресу обходим
  /// тоже — пока есть кто-то ещё.
  static ServerItem? pick(
    List<ServerItem> servers, {
    required String subscriptionId,
    String? exclude,
    String? excludeHost,
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

    final measured = [
      for (final server in pool)
        if (server.pingMs != null) server,
    ]..sort((a, b) => a.pingMs!.compareTo(b.pingMs!));
    if (measured.isNotEmpty) return measured.first;

    final untested = [
      for (final server in pool)
        if (server.lastTestedAt == null) server,
    ];
    if (untested.isNotEmpty) return untested.first;

    // Остались только те, чей замер не удался. Брать всё равно кого-то надо:
    // замер мог не удаться и по своей причине (пинг шёл до подключения, сеть
    // сменилась), а «автовыбор ничего не выбрал» — худший из возможных
    // ответов на нажатую кнопку.
    return pool.first;
  }

  /// Кого мерить, когда текущий сервер под подозрением: он сам и лучшие из
  /// соседей по подписке — всего не больше [limit].
  ///
  /// Сам текущий — обязательно: решение «уходить» принимается по его же
  /// свежему замеру, а не по тому, что показалось сторожу. Соседей — по
  /// порядку старых замеров, потому что мерить всю подписку ради одного
  /// переезда незачем, а десяток на Android — это ровно одно ядро замера.
  static List<ServerItem> candidatesToMeasure(
    List<ServerItem> servers, {
    required String subscriptionId,
    required ServerItem current,
    int limit = 10,
  }) {
    final others = [
      for (final server in servers)
        if (server.subscriptionId == subscriptionId && server.id != current.id)
          server,
    ];
    int rank(ServerItem s) => s.pingMs != null
        ? 0
        : s.lastTestedAt == null
            ? 1
            : 2;
    others.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      return (a.pingMs ?? 0).compareTo(b.pingMs ?? 0);
    });
    return [current, ...others.take(limit - 1)];
  }

  /// Что делать по свежему замеру.
  ///
  /// Правила, и все по результатам, а не по догадкам:
  ///
  /// текущий ответил — остаёмся, тревога была ложной, что бы её ни вызвало;
  /// текущий не ответил, а кто-то из соседей ответил — переезжаем на самого
  /// быстрого из ответивших, то есть на сервер, живой прямо сейчас, а не
  /// когда-то в прошлом замере;
  /// не ответил никто — остаёмся: это либо сеть, либо всё мёртвое сразу, и
  /// переезд ничего бы не дал.
  ///
  /// [currentPresumedDead] — три секунды через туннель не пришло ни байта.
  /// Тогда не ждём, пока замер текущего упрётся в таймаут: если соседи уже
  /// ответили, а он нет, этого достаточно. Для слабых сигналов ждём вердикта
  /// по нему самому — [undecided], пока замер не закончен.
  static AutoSelectVerdict judge({
    required String currentId,
    required Iterable<({String id, bool success, int? latencyMs})> results,
    required bool batchComplete,
    bool currentPresumedDead = false,
  }) {
    ({String id, bool success, int? latencyMs})? current;
    ({String id, bool success, int? latencyMs})? best;
    for (final r in results) {
      if (r.id == currentId) {
        current = r;
        continue;
      }
      if (!r.success) continue;
      if (best == null || (r.latencyMs ?? 1 << 30) < (best.latencyMs ?? 1 << 30)) {
        best = r;
      }
    }
    if (current != null && current.success) return const AutoSelectVerdict.stay();

    final currentFailed = current != null && !current.success;
    if (currentFailed || currentPresumedDead || batchComplete) {
      if (best != null) return AutoSelectVerdict.switchTo(best.id);
      if (batchComplete) return const AutoSelectVerdict.stay();
    }
    return const AutoSelectVerdict.undecided();
  }
}

/// Итог [AutoServerSelect.judge].
final class AutoSelectVerdict {
  const AutoSelectVerdict.stay() : nextId = null, decided = true;
  const AutoSelectVerdict.switchTo(String this.nextId) : decided = true;
  const AutoSelectVerdict.undecided() : nextId = null, decided = false;

  /// Куда переезжать; null — оставаться (или ещё не решено).
  final String? nextId;

  /// false — замер ещё идёт, и по уже пришедшему решать рано.
  final bool decided;
}
