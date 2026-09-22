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
}
