import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/server_item.dart';

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
      rest.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    case ServerSortMode.ping:
      rest.sort((a, b) => _pingSortKey(a).compareTo(_pingSortKey(b)));
    case ServerSortMode.speed:
      rest.sort((a, b) => _speedSortKey(b).compareTo(_speedSortKey(a)));
    case ServerSortMode.defaultOrder:
      break;
  }
  return [...pinned, ...rest];
}

int _pingSortKey(ServerItem s) {
  if (s.pingMs == null || s.lastPingType == 'speed') return 1 << 30;
  return s.pingMs!;
}

int _speedSortKey(ServerItem s) {
  if (s.pingMs == null || s.lastPingType != 'speed') return -1;
  return s.pingMs!;
}
