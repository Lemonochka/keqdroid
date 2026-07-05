part of '../servers_tab.dart';

class _ServersListPanel extends ConsumerWidget {
  final double topPadding;
  final Future<void> Function(ServerItem) onSelectServer;
  final Widget emptyState;

  const _ServersListPanel({
    this.topPadding = 0,
    required this.onSelectServer,
    required this.emptyState,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serversState = ref.watch(serversProvider);
    final subs = ref.watch(subscriptionsProvider).value ?? [];

    if (serversState.isLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppTheme.accent(context)),
      );
    }
    if (subs.isEmpty && serversState.servers.isEmpty) {
      return emptyState;
    }

    final manual = serversState.servers
        .where((s) => s.subscriptionId == null)
        .toList();
    final bySubId = <String, List<ServerItem>>{};
    for (final s in serversState.servers.where(
      (s) => s.subscriptionId != null,
    )) {
      bySubId.putIfAbsent(s.subscriptionId!, () => []).add(s);
    }

    final groups = <_ServerGroupEntry>[];
    for (final sub in subs) {
      final servers = bySubId[sub.id] ?? [];
      if (servers.isEmpty) continue;
      groups.add(
        _ServerGroupEntry(
          key: ValueKey('server-group-${sub.id}'),
          subscription: sub,
          servers: servers,
          onRefresh: () =>
              ref.read(subscriptionsProvider.notifier).refreshTracked(sub),
          onPingAll: () =>
              ref.read(serversProvider.notifier).pingSubscription(sub.id),
        ),
      );
    }
    if (manual.isNotEmpty) {
      groups.add(
        _ServerGroupEntry(
          key: const ValueKey('server-group-manual'),
          subscription: null,
          servers: manual,
          onRefresh: null,
          onPingAll: () =>
              ref.read(serversProvider.notifier).pingSubscription(null),
        ),
      );
    }

    // CustomScrollView + sliver-группы: тайлы серверов строятся лениво по мере
    // прокрутки (SliverList.builder в _SubCard), а не все разом Column'ом.
    // Раньше раскрытая группа на сотни серверов строила все _ServerTile сразу —
    // основной источник джанка свайпа (build + семантика на каждый кадр).
    return SmoothScroll(
      builder: (context, controller) => CustomScrollView(
        controller: controller,
        physics: const ClampingScrollPhysics(),
        slivers: [
          for (var index = 0; index < groups.length; index++)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                16,
                index == 0 ? topPadding : 0,
                16,
                index < groups.length - 1 ? 20 : 80,
              ),
              sliver: _SubCard(
                key: groups[index].key,
                subscription: groups[index].subscription,
                servers: groups[index].servers,
                onSelectServer: onSelectServer,
                onRefresh: groups[index].onRefresh,
                onPingAll: groups[index].onPingAll,
              ),
            ),
        ],
      ),
    );
  }
}

class _ServerGroupEntry {
  final Key key;
  final Subscription? subscription;
  final List<ServerItem> servers;
  final Future<void> Function()? onRefresh;
  final Future<void> Function() onPingAll;

  const _ServerGroupEntry({
    required this.key,
    required this.subscription,
    required this.servers,
    this.onRefresh,
    required this.onPingAll,
  });
}

/// Режим сортировки серверов внутри группы (по долгому нажатию на шапку).
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
        ServerSortMode.defaultOrder => Icons.format_list_bulleted,
        ServerSortMode.ping => Icons.network_check,
        ServerSortMode.speed => Icons.speed,
        ServerSortMode.name => Icons.sort_by_alpha,
      };
}

/// Возвращает копию [servers], отсортированную по [mode] (для defaultOrder —
/// исходный порядок без копии). Серверы без нужной метрики уходят в конец.
List<ServerItem> _sortServersBy(List<ServerItem> servers, ServerSortMode mode) {
  if (mode == ServerSortMode.defaultOrder) return servers;
  final list = [...servers];
  switch (mode) {
    case ServerSortMode.name:
      list.sort((a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    case ServerSortMode.ping:
      list.sort((a, b) => _pingSortKey(a).compareTo(_pingSortKey(b)));
    case ServerSortMode.speed:
      list.sort((a, b) => _speedSortKey(b).compareTo(_speedSortKey(a)));
    case ServerSortMode.defaultOrder:
      break;
  }
  return list;
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

/// высота градиента-затухания над списком серверов
const _listTopFadeHeight = 56.0;

/// насколько верхний тайл заезжает под фейд (виден из-под хедера)
const _listTopFadeTileOverlap = 34.0;

// фейд продлён вверх за нижний padding хедера, чтобы не было видимого шва
const _listTopFadeUpExtension = 8.0;
const _listTopFadeOverlayHeight = _listTopFadeHeight + _listTopFadeUpExtension;
// доля непрозрачной части градиента с учётом extension, чтобы фейд начинался у хедера
const _listTopFadeSolidStop =
    (_listTopFadeUpExtension + 0.45 * _listTopFadeHeight) /
    _listTopFadeOverlayHeight;

/// высота строки группы совпадает с высотой [_ServerTile]
const _subCardRowHeight = 76.0;

/// флаг в круге: масштабируем asset через BoxFit.cover, без искажения пропорций
Widget _countryFlagCircle({
  required String? countryCode,
  required Color protocolColor,
  required String protocol,
  double size = 40,
}) {
  return SizedBox(
    width: size,
    height: size,
    child: ClipOval(
      clipBehavior: Clip.antiAlias,
      child: countryCode != null
          ? FittedBox(
              fit: BoxFit.cover,
              alignment: Alignment.center,
              child: CountryFlag.fromCountryCode(
                countryCode,
                theme: const ImageTheme(width: 60, height: 40),
              ),
            )
          : ColoredBox(
              color: protocolColor,
              child: Center(
                child: Text(
                  protocol.isNotEmpty ? protocol[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
    ),
  );
}

const _subCardHeaderIconSize = 32.0;
const _subCardHeaderActionGap = 8.0;
const _subCardHeaderIntervalGap = 10.0;

Widget _subCardHeaderIconButton({
  required String tooltip,
  required VoidCallback? onPressed,
  required Widget icon,
}) {
  return IconButton(
    onPressed: onPressed,
    tooltip: tooltip,
    icon: icon,
    padding: EdgeInsets.zero,
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints(
      minWidth: _subCardHeaderIconSize,
      maxWidth: _subCardHeaderIconSize,
      minHeight: _subCardHeaderIconSize,
      maxHeight: _subCardHeaderIconSize,
    ),
    style: IconButton.styleFrom(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: const Size(_subCardHeaderIconSize, _subCardHeaderIconSize),
      fixedSize: const Size(_subCardHeaderIconSize, _subCardHeaderIconSize),
      padding: EdgeInsets.zero,
    ),
  );
}

class _SubCard extends ConsumerStatefulWidget {
  final Subscription? subscription;
  final List<ServerItem> servers;
  final void Function(ServerItem) onSelectServer;
  final Future<void> Function()? onRefresh;
  final Future<void> Function() onPingAll;

  const _SubCard({
    super.key,
    required this.subscription,
    required this.servers,
    required this.onSelectServer,
    required this.onRefresh,
    required this.onPingAll,
  });

  @override
  ConsumerState<_SubCard> createState() => _SubCardState();
}

class _SubCardState extends ConsumerState<_SubCard> {
  // Мемоизация сортировки: карточка перестраивается и от «своих» вотчей
  // (спиннеры refresh/ping, collapse, activeServerId), когда список серверов
  // не менялся — в этих случаях не пересортировываем O(N·logN) заново.
  List<ServerItem>? _sortedCache;
  List<ServerItem>? _sortedSource;
  ServerSortMode? _sortedMode;

  List<ServerItem> _sortedFor(List<ServerItem> source, ServerSortMode mode) {
    if (identical(source, _sortedSource) && mode == _sortedMode) {
      return _sortedCache!;
    }
    _sortedSource = source;
    _sortedMode = mode;
    return _sortedCache = _sortServersBy(source, mode);
  }

  @override
  Widget build(BuildContext context) {
    final sub = widget.subscription;
    final collapseKey = sub?.id ?? '__manual__';
    final collapsed = ref.watch(
      collapsedServerGroupsProvider.select((m) => m[collapseKey] ?? false),
    );
    final sortMode = ServerSortMode.fromName(
      ref.watch(serverSortModesProvider.select((m) => m[collapseKey])),
    );
    final sortedServers = _sortedFor(widget.servers, sortMode);
    final isRefreshing =
        sub != null &&
        ref.watch(
          subscriptionRefreshingIdsProvider.select(
            (ids) => ids.contains(sub.id),
          ),
        );
    final hasRefreshError =
        sub != null &&
        ref.watch(
          subscriptionRefreshErrorsProvider.select(
            (m) => m.containsKey(sub.id),
          ),
        );
    final pingScope = sub?.id ?? '__manual__';
    final isPingingAll = ref.watch(
      pingingScopesProvider.select((scopes) => scopes.contains(pingScope)),
    );
    final activeServerId = ref.watch(
      serversProvider.select((s) => s.activeServerId),
    );
    final title = sub != null
        ? '${sub.name}  |  ${sub.usageLabel}'
        : context.l10n.serversManualGroup;

    // кэшируем цвета, чтобы не дёргать Theme.of() на каждый вложенный виджет
    final cardColor = AppTheme.card(context);
    final dividerColor = AppTheme.divider(context);
    final accentColor = AppTheme.accent(context);
    final textLightColor = AppTheme.textLight(context);

    // Sliver-карточка: DecoratedSliver рисует фон/рамку/тень на всю длину
    // группы (включая невидимую часть), а тайлы строятся лениво SliverList'ом.
    return DecoratedSliver(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: dividerColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      sliver: SliverPadding(
        // 1px со всех сторон — чтобы контент не перекрывал рамку декорации
        // (в отличие от Container, DecoratedSliver не вставляет отступ рамки).
        padding: const EdgeInsets.all(1),
        sliver: SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: RepaintBoundary(
                child: SizedBox(
                  height: _subCardRowHeight,
                  child: Center(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 14, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Шеврон и заголовок в общем Expanded: при узкой ширине
                        // (напр. кадр во время сворачивания окна в трей) они
                        // сжимаются вместе, а ряд иконок справа не вызывает overflow.
                        Expanded(
                          // Шеврон + заголовок + tap — один семантический узел
                          // (см. комментарий в _ServerTile).
                          child: MergeSemantics(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => ref
                                  .read(collapsedServerGroupsProvider.notifier)
                                  .update(
                                    (m) => {...m, collapseKey: !collapsed},
                                  ),
                              onLongPress: () {
                                HapticFeedback.mediumImpact();
                                _showSortMenu(context, collapseKey, sortMode);
                              },
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 32,
                                    height: _subCardHeaderIconSize,
                                    child: Center(
                                      child: AnimatedRotation(
                                        turns: collapsed ? -0.25 : 0,
                                        duration: const Duration(
                                          milliseconds: 200,
                                        ),
                                        child: Icon(
                                          Icons.expand_more,
                                          size: 22,
                                          color: textLightColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: textLightColor,
                                        letterSpacing: 0.2,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (sub != null && sub.autoUpdate) ...[
                                GestureDetector(
                                  onTap: () =>
                                      _showIntervalPicker(context, sub),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: accentColor.withValues(
                                        alpha: 0.18,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${sub.updateIntervalHours}h',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: accentColor,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(
                                  width: _subCardHeaderIntervalGap,
                                ),
                              ],
                              // Явная кнопка сортировки: long-press по шапке
                              // остаётся, но на десктопе он неоткрываем мышью
                              // интуитивно — иконка делает функцию видимой.
                              _subCardHeaderIconButton(
                                tooltip:
                                    AppLocalizations.of(context)!.serversSortTitle,
                                onPressed: () => _showSortMenu(
                                  context,
                                  collapseKey,
                                  sortMode,
                                ),
                                icon: Icon(
                                  sortMode == ServerSortMode.defaultOrder
                                      ? Icons.sort
                                      : sortMode.icon,
                                  size: 18,
                                  color: sortMode == ServerSortMode.defaultOrder
                                      ? textLightColor
                                      : accentColor,
                                ),
                              ),
                              const SizedBox(width: _subCardHeaderActionGap),
                              if (widget.onRefresh != null) ...[
                                _subCardHeaderIconButton(
                                  tooltip: AppLocalizations.of(
                                    context,
                                  )!.serversRefreshSubscription,
                                  onPressed: isRefreshing
                                      ? null
                                      : () async {
                                          try {
                                            await widget.onRefresh!.call();
                                          } catch (e) {
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  _friendlyError(e),
                                                ),
                                                backgroundColor: AppTheme.red(
                                                  context,
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                  icon: isRefreshing
                                      ? SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: accentColor,
                                          ),
                                        )
                                      : Icon(
                                          Icons.refresh,
                                          size: 18,
                                          color: hasRefreshError
                                              ? AppTheme.red(context)
                                              : textLightColor,
                                        ),
                                ),
                                const SizedBox(width: _subCardHeaderActionGap),
                              ],
                              _subCardHeaderIconButton(
                                tooltip: AppLocalizations.of(
                                  context,
                                )!.serversPingAll,
                                onPressed: isPingingAll
                                    ? null
                                    : () async {
                                        try {
                                          await widget.onPingAll();
                                        } catch (e) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(_friendlyError(e)),
                                              backgroundColor: AppTheme.red(
                                                context,
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                icon: isPingingAll
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: accentColor,
                                        ),
                                      )
                                    : Icon(
                                        Icons.network_ping,
                                        size: 18,
                                        color: textLightColor,
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ),
              ),
            ),

            // Свёрнутая группа — просто без sliver'а тайлов. AnimatedSize с
            // Column всех тайлов ушёл: он строил их разом и несовместим с
            // ленивым sliver-построением (шеврон по-прежнему анимируется).
            if (!collapsed)
              _buildExpandedServerList(
                servers: sortedServers,
                activeServerId: activeServerId,
                textLightColor: textLightColor,
              ),
          ],
        ),
      ),
    );
  }

  /// Sliver с тайлами: SliverList.builder строит только видимые в viewport —
  /// раскрытая группа на сотни серверов больше не собирает все тайлы разом.
  Widget _buildExpandedServerList({
    required List<ServerItem> servers,
    required String? activeServerId,
    required Color textLightColor,
  }) {
    if (servers.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            context.l10n.serversEmptyGroupHint,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: textLightColor),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => _ServerTile(
          key: ValueKey(servers[index].id),
          server: servers[index],
          isActive: servers[index].id == activeServerId,
          isFirst: index == 0,
          isLast: index == servers.length - 1,
          onTap: () => widget.onSelectServer(servers[index]),
          onDelete: () =>
              ref.read(serversProvider.notifier).delete(servers[index].id),
          onPing: () =>
              ref.read(serversProvider.notifier).pingSingle(servers[index].id),
        ),
        childCount: servers.length,
        addAutomaticKeepAlives: false,
        // _ServerTile сам оборачивается в RepaintBoundary — не дублируем.
        addRepaintBoundaries: false,
      ),
    );
  }

  /// Долгое нажатие на шапку группы → выбор сортировки серверов.
  void _showSortMenu(
    BuildContext context,
    String collapseKey,
    ServerSortMode current,
  ) {
    final accent = AppTheme.accent(context);
    final textColor = AppTheme.text(context);
    final textLight = AppTheme.textLight(context);
    final l10n = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: textLight.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.serversSortTitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textLight,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
              for (final mode in ServerSortMode.values)
                ListTile(
                  leading: Icon(
                    mode.icon,
                    color: mode == current ? accent : textLight,
                  ),
                  title: Text(
                    mode.label(l10n),
                    style: TextStyle(
                      fontSize: 15,
                      color: textColor,
                      fontWeight:
                          mode == current ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  trailing: mode == current
                      ? Icon(Icons.check, color: accent, size: 20)
                      : null,
                  onTap: () {
                    ref.read(serverSortModesProvider.notifier).update(
                          (m) => {...m, collapseKey: mode.name},
                        );
                    Navigator.of(ctx).pop();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showIntervalPicker(BuildContext context, Subscription sub) {
    const options = [1, 3, 6, 12, 24, 48, 72];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final maxHeight = MediaQuery.sizeOf(ctx).height * 0.85;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.textLight(context).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  context.l10n.subscriptionsAutoUpdateInterval,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.text(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10n.subscriptionsCurrentInterval(
                    sub.updateIntervalHours,
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textLight(context),
                  ),
                ),
                const SizedBox(height: 8),
                ...options.map(
                  (h) => ListTile(
                    title: Text(
                      h == 1
                          ? context.l10n.subscriptionsEveryHour
                          : h < 24
                          ? context.l10n.subscriptionsEveryHours(h)
                          : h == 24
                          ? context.l10n.subscriptionsEveryDay
                          : context.l10n.subscriptionsEveryDays(h ~/ 24),
                      style: TextStyle(
                        color: AppTheme.text(context),
                        fontWeight: h == sub.updateIntervalHours
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: h == sub.updateIntervalHours
                        ? Icon(Icons.check, color: AppTheme.accent(context))
                        : null,
                    onTap: () {
                      ref
                          .read(subscriptionsProvider.notifier)
                          .updateInterval(sub.id, h);
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
