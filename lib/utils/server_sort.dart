import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/server_item.dart';

/// Режим сортировки серверов внутри группы (по долгому нажатию на шапку).
///
/// Живёт отдельно от экрана серверов: тем же порядком обязан пользоваться
/// выбор звена для цепочки, иначе один и тот же набор серверов выглядит в
/// приложении двумя разными списками.
enum ServerSortMode {
  defaultOrder,
  ping,
  speed,
  name;

  static ServerSortMode fromName(String? n) {
    for (final m in values) {
      if (m.name == n) return m;
    }
    return ServerSortMode.defaultOrder;
  }

  String label(AppLocalizations l10n) => switch (this) {
        ServerSortMode.defaultOrder => l10n.serversSortDefault,
        ServerSortMode.ping => l10n.serversSortPing,
        ServerSortMode.speed => l10n.serversSortSpeed,
        ServerSortMode.name => l10n.serversSortName,
      };

  IconData get icon => switch (this) {
        ServerSortMode.defaultOrder => Icons.format_list_bulleted_rounded,
        ServerSortMode.ping => Icons.network_check_rounded,
        ServerSortMode.speed => Icons.speed_rounded,
        ServerSortMode.name => Icons.sort_by_alpha_rounded,
      };
}

/// Возвращает копию [servers], отсортированную по [mode] (для defaultOrder
/// без закреплённых — исходный порядок без копии). Закреплённые серверы всегда
/// первыми (в порядке закрепления), независимо от режима сортировки; остальные
/// сортируются по [mode], серверы без нужной метрики уходят в конец.
List<ServerItem> sortServersBy(List<ServerItem> servers, ServerSortMode mode) {
  final hasPinned = servers.any((s) => s.isPinned);
  if (mode == ServerSortMode.defaultOrder && !hasPinned) return servers;

  final pinned = <ServerItem>[];
  final rest = <ServerItem>[];
  for (final s in servers) {
    (s.isPinned ? pinned : rest).add(s);
  }
  pinned.sort((a, b) => a.pinnedAt!.compareTo(b.pinnedAt!));

  switch (mode) {
    case ServerSortMode.name:
      rest.sort((a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    case ServerSortMode.ping:
      rest.sort((a, b) => _pingSortKey(a).compareTo(_pingSortKey(b)));
    case ServerSortMode.speed:
      rest.sort((a, b) => _speedSortKey(b).compareTo(_speedSortKey(a)));
    case ServerSortMode.defaultOrder:
      break;
  }
  return [...pinned, ...rest];
}

// Латентность (url/tcp/icmp), меньше — лучше. Нет данных или это speed-результат
// (pingMs хранит kbps) → максимум, чтобы уйти в конец.
int _pingSortKey(ServerItem s) {
  if (s.pingMs == null || s.lastPingType == 'speed') return 1 << 30;
  return s.pingMs!;
}

// Скорость (kbps; lastPingType=='speed'), больше — лучше. Иначе -1 → в конец
// (при сортировке по убыванию).
int _speedSortKey(ServerItem s) {
  if (s.pingMs == null || s.lastPingType != 'speed') return -1;
  return s.pingMs!;
}
