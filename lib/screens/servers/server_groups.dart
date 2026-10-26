part of '../servers_tab.dart';

class _ServersListPanel extends ConsumerWidget {
  final double topPadding;
  final Future<void> Function(ServerItem) onSelectServer;
  final Widget emptyState;

  const _ServersListPanel({
    super.key,
    this.topPadding = 0,
    required this.onSelectServer,
    required this.emptyState,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serversState = ref.watch(serversProvider);
    final subs = ref.watch(subscriptionsProvider).value ?? [];

    if (serversState.isLoading) {
      return const Center(child: ShapeLoadingIndicator());
    }
    if (subs.isEmpty && serversState.servers.isEmpty) {
      return emptyState;
    }

    final groups = [
      for (final group in buildServerGroups(
        servers: serversState.servers,
        subscriptions: subs,
      ))
        switch (group.kind) {
          ServerGroupKind.chains => _ServerGroupEntry(
              key: const ValueKey('server-group-chains'),
              subscription: null,
              servers: group.servers,
              groupKey: group.key,
              groupTitle: context.l10n.chainGroupTitle,
              onRefresh: null,
              onPingAll: () => ref.read(serversProvider.notifier).pingChains(),
            ),
          ServerGroupKind.subscription => _ServerGroupEntry(
              key: ValueKey('server-group-${group.key}'),
              subscription: group.subscription,
              servers: group.servers,
              onRefresh: () => ref
                  .read(subscriptionsProvider.notifier)
                  .refreshTracked(group.subscription!),
              onPingAll: () => ref
                  .read(serversProvider.notifier)
                  .pingSubscription(group.key),
            ),
          ServerGroupKind.manual => _ServerGroupEntry(
              key: const ValueKey('server-group-manual'),
              subscription: null,
              servers: group.servers,
              onRefresh: null,
              onPingAll: () =>
                  ref.read(serversProvider.notifier).pingSubscription(null),
            ),
        },
    ];


    // параметром сверху: вотч внутри карточки перестроил бы уходящий при кросс-фейде список
    final wantedColumns = ref.watch(
      settingsNotifierProvider.select(
        (a) => a.value == null ? 1 : ServerRow.wantedColumns(a.value!),
      ),
    );
    final textScaler = MediaQuery.textScalerOf(context);
    final cardHeight = ServerRow.cardHeight(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _ServerListLayout.resolve(
          wantedColumns: wantedColumns,
          width: constraints.maxWidth,
          textScaler: textScaler,
        );
        final rowExtent = layout.isCards ? cardHeight : ServerRow.height;

        final list = ServerGroupAnchorScope(
          leadingInset: topPadding + 12,
          child: SmoothScroll(
            builder: (context, controller) => CustomScrollView(
              controller: controller,
              physics: const ClampingScrollPhysics(),
              slivers: [
                for (var index = 0; index < groups.length; index++)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      _listSideInset,
                      index == 0 ? topPadding : 0,
                      _listSideInset,
                      index < groups.length - 1 ? 20 : 80,
                    ),
                    sliver: _SubCard(
                      key: groups[index].key,
                      subscription: groups[index].subscription,
                      servers: groups[index].servers,
                      groupKey: groups[index].groupKey,
                      groupTitle: groups[index].groupTitle,
                      layout: layout,
                      rowExtent: rowExtent,
                      onSelectServer: onSelectServer,
                      onRefresh: groups[index].onRefresh,
                      onPingAll: groups[index].onPingAll,
                    ),
                  ),
              ],
            ),
          ),
        );

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.98, end: 1.0).animate(animation),
              child: child,
            ),
          ),
          child: KeyedSubtree(
            key: ValueKey(layout),
            child: list,
          ),
        );
      },
    );
  }
}

class _GroupHeaderBackground extends StatelessWidget {
  const _GroupHeaderBackground({
    required this.subscription,
    required this.surface,
    required this.open,
    required this.child,
  });

  final Subscription? subscription;

  final Color surface;

  // 0 свёрнута, 1 раскрыта: шапка идёт по той же пружине, что и список под ней
  final double open;
  final Widget child;

  static const fadeHeight = 26.0;

  static double heightFor(Subscription? subscription, {required bool collapsed}) =>
      heightAt(subscription, collapsed ? 0 : 1);

  static double heightAt(Subscription? subscription, double open) {
    final below = [
      if (_showsImage(subscription)) fadeHeight,
      if (subscription?.autoSelectVisible == true) autoRowHeight,
      0.0,
    ].reduce((a, b) => a > b ? a : b);
    return _subCardRowHeight + below * open;
  }

  static const autoRowHeight = 40.0;

  static bool _showsImage(Subscription? sub) =>
      sub != null &&
      sub.cardThemeInServers &&
      sub.cardThemeId.isNotEmpty &&
      resolveCardTheme(sub.cardThemeId).hasImage;

  @override
  Widget build(BuildContext context) {
    final sub = subscription;
    if (!_showsImage(sub)) return child;
    final theme = resolveCardTheme(sub!.cardThemeId);

    const outer = ExpressiveShape.extraLarge;
    final headerFraction =
        _subCardRowHeight / (_subCardRowHeight + fadeHeight * open);
    final fadeStart = headerFraction * 0.72;
    // в полную силу, когда шапка подросла на 1 dp: на возврате из перелёта оно вспыхивало целиком
    final fadeStrength = (fadeHeight * open).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.vertical(
        top: const Radius.circular(outer),
        bottom: Radius.circular(outer * (1 - open)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          theme.background(
            context,
            veil: CardVeil.none,
            overlay: Stack(
              fit: StackFit.expand,
              children: [
                CardVeilOverlay(color: surface, veil: sub.cardVeil),
                if (open > 0)
                  // плавный вход и выход: на изломе линейного градиента глаз видел светлую полосу
                  SmoothFadeBox(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    color: surface,
                    curve: FadeCurve.eased(0, fadeStrength, start: fadeStart),
                  ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            // высота вместе со строкой Авто: иначе кнопку видно, но нажатия до неё не доходят
            child: SizedBox(
              height: heightAt(sub, open),
              child: child,
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

  final String? groupKey;

  final String? groupTitle;
  final Future<void> Function()? onRefresh;
  final Future<void> Function() onPingAll;

  const _ServerGroupEntry({
    required this.key,
    required this.subscription,
    required this.servers,
    this.groupKey,
    this.groupTitle,
    this.onRefresh,
    required this.onPingAll,
  });
}

const _listTopPadding = 22.0;

class _ListEdgeFade extends StatefulWidget {
  const _ListEdgeFade({this.underPanel = false, required this.child});

  // над списком панель «Модерна»: верх тает по её контуру со скруглёнными углами
  final bool underPanel;
  final Widget child;

  @override
  State<_ListEdgeFade> createState() => _ListEdgeFadeState();
}

class _ListEdgeFadeState extends State<_ListEdgeFade> {
  double _progress = 0;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final next = (n.metrics.extentBefore / 32).clamp(0.0, 1.0);
    if ((next - _progress).abs() > 0.01 || (next == 0) != (_progress == 0)) {
      setState(() => _progress = next);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: EdgeFadeMask(
        // сверху в покое под краем пусто, затухание растёт с прокруткой
        top: _progress == 0
            ? 0
            : _listTopPadding + (35 - _listTopPadding) * _progress,
        // без излома хватает короткого: полностью скрыт только системный отступ
        bottom: 28,
        bottomHidden: MediaQuery.paddingOf(context).bottom,
        topOutline: widget.underPanel
            ? const EdgeFadeOutline(
                inset: _ModernConnectPanel._margin,
                radius: ExpressiveShape.extraLarge,
                gap: _ModernConnectPanel._gapBelow,
              )
            : null,
        child: widget.child,
      ),
    );
  }
}

const _subCardRowHeight = ServerRow.height;

const _listSideInset = ServerRow.listSideInset;

enum _RowKind { list, grid, cards }

class _ServerListLayout {
  const _ServerListLayout._(this.kind, this.columns);

  static const list = _ServerListLayout._(_RowKind.list, 1);

  final _RowKind kind;
  final int columns;

  bool get isCards => kind == _RowKind.cards;

  double get gap => ExpressiveListSegment.gap;

  ServerRowLayout get rowLayout =>
      isCards ? ServerRowLayout.card : ServerRowLayout.inline;

  static _ServerListLayout resolve({
    required int wantedColumns,
    required double width,
    required TextScaler textScaler,
  }) {
    final columns = ServerRow.fittingColumns(width, textScaler, wantedColumns);
    if (columns == 1) return list;
    final cell = ServerRow.columnCell(width, columns);
    final kind =
        ServerRow.fitsInline(cell, textScaler) ? _RowKind.grid : _RowKind.cards;
    return _ServerListLayout._(kind, columns);
  }

  @override
  bool operator ==(Object other) =>
      other is _ServerListLayout &&
      other.kind == kind &&
      other.columns == columns;

  @override
  int get hashCode => Object.hash(kind, columns);
}

const _subCardHeaderIconSize = 32.0;
const _subCardHeaderActionGap = ExpressiveSpacing.small;
const _subCardHeaderIntervalGap = ExpressiveSpacing.small;

Widget _subCardHeaderIconButton(
  BuildContext context, {
  required String tooltip,
  required VoidCallback? onPressed,
  required Widget icon,
  Color? color,
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
    style: TvFocus.iconButtonStyle(
      context,
      color: color,
      base: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size(_subCardHeaderIconSize, _subCardHeaderIconSize),
        fixedSize: const Size(_subCardHeaderIconSize, _subCardHeaderIconSize),
        padding: EdgeInsets.zero,
      ),
    ),
  );
}

void _serverGroupSortMenu(
  WidgetRef ref,
  BuildContext context,
  String collapseKey,
  ServerSortMode current,
) {
  final l10n = context.l10n;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    // без этого шторка не выше 9/16 экрана, и на телевизоре список обрывался
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExpressiveSectionHeader(l10n.serversSortTitle),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ExpressiveGroup(
                  children: [
                    for (final mode in ServerSortMode.values)
                      ExpressiveActionTile(
                        icon: mode.icon,
                        title: mode.label(l10n),
                        selected: mode == current,
                        onTap: () {
                          ref.read(serverSortModesProvider.notifier).update(
                                (m) => {...m, collapseKey: mode.name},
                              );
                          Navigator.of(ctx).pop();
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );
    },
  );
}


class _ServerGroupHeader extends ConsumerWidget {
  const _ServerGroupHeader({
    required this.subscription,
    required this.servers,
    required this.groupKey,
    required this.groupTitle,
    required this.onRefresh,
    required this.onPingAll,
    required this.accent,
    required this.openness,
  });

  final Subscription? subscription;
  final List<ServerItem> servers;
  final String? groupKey;
  final String? groupTitle;
  final Future<void> Function()? onRefresh;
  final Future<void> Function() onPingAll;

  final SubscriptionAccent? accent;

  final Animation<double> openness;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = subscription;
    final collapseKey = groupKey ?? sub?.id ?? ServersNotifier.manualGroupKey;
    final collapsed = ref.watch(
      collapsedServerGroupsProvider.select((m) => m[collapseKey] ?? false),
    );
    final sortMode = ServerSortMode.fromName(
      ref.watch(serverSortModesProvider.select((m) => m[collapseKey])),
    );
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
    final scheme = Theme.of(context).colorScheme;
    final groupColor =
        accent?.surface(scheme.surfaceContainerLow) ??
        scheme.surfaceContainerLow;
    final accentColor = accent?.seed ?? AppTheme.accent(context);
    final textLightColor = AppTheme.textLight(context);
    final pingScope = collapseKey;
    final isPingingAll = ref.watch(
      pingingScopesProvider.select((scopes) => scopes.contains(pingScope)),
    );
    final title =
        groupTitle ??
        (sub != null
            ? '${sub.name}  |  ${ltrIsolate(sub.usageLabel)}'
            : context.l10n.serversManualGroup);
    return ServerGroupAnchor(
        groupKey: collapseKey,
        child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: openness,
          builder: (context, row) {
            final open = openness.value.clamp(0.0, 1.0);
            return SizedBox(
              height: _GroupHeaderBackground.heightAt(sub, open),
              child: _GroupHeaderBackground(
                subscription: sub,
                surface: groupColor,
                open: open,
                // строка Авто уезжает под край вместе со сворачиванием
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        row!,
                        if (sub != null && sub.autoSelectVisible && open > 0)
                          _AutoSelectRow(subscription: sub),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
          child: SizedBox(
                  height: _subCardRowHeight,
                  child: Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 14, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
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
                        _serverGroupSortMenu(ref, context, collapseKey, sortMode);
                      },
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: _subCardHeaderIconSize,
                            height: _subCardHeaderIconSize,
                            child: Center(
                              child: AnimatedRotation(
                                turns: collapsed ? -0.25 : 0,
                                duration: ExpressiveMotion.durationFast,
                                curve: ExpressiveMotion.emphasized,
                                child: Icon(
                                  Icons.expand_more_rounded,
                                  size: ExpressiveIconSize.medium,
                                  color: textLightColor,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: ExpressiveSpacing.small),
                          Expanded(
                            child: Text(
                              title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(color: textLightColor),
                              textDirection: contentDirection(
                                title,
                                fallback: Directionality.of(context),
                              ),
                              textAlign: uiStartAlign(context),
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
                  padding: const EdgeInsetsDirectional.only(
                    start: ExpressiveSpacing.small,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (sub != null && sub.autoUpdate) ...[
                        TvFocusHighlight(
                          radius: BorderRadius.circular(ExpressiveShape.full),
                          child: Builder(builder: (context) {
                            final focusFill =
                                TvFocusHighlight.containerOf(context);
                            return Material(
                              color: focusFill ??
                                  accentColor.withValues(alpha: 0.18),
                              shape: ExpressiveShape.border(
                                ExpressiveShape.full,
                              ),
                              child: InkWell(
                                onTap: () => showUpdateIntervalSheet(
                                  context,
                                  ref,
                                  sub,
                                ),
                                customBorder: ExpressiveShape.border(
                                  ExpressiveShape.full,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: ExpressiveSpacing.small,
                                    vertical: ExpressiveSpacing.extraSmall,
                                  ),
                                  child: Text(
                                    context.l10n.subscriptionsIntervalShort(
                                      sub.updateIntervalHours,
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: focusFill != null
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                              : accentColor,
                                        ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(
                          width: _subCardHeaderIntervalGap,
                        ),
                      ],
                      _subCardHeaderIconButton(
                        context,
                        tooltip:
                            AppLocalizations.of(context)!.serversSortTitle,
                        onPressed: () => _serverGroupSortMenu(ref,
                          context,
                          collapseKey,
                          sortMode,
                        ),
                        color: sortMode == ServerSortMode.defaultOrder
                            ? textLightColor
                            : accentColor,
                        icon: SeasonalIcon(
                          sortMode == ServerSortMode.defaultOrder
                              ? Icons.sort_rounded
                              : sortMode.icon,
                          size: ExpressiveIconSize.medium,
                        ),
                      ),
                      const SizedBox(width: _subCardHeaderActionGap),
                      if (onRefresh != null) ...[
                        _subCardHeaderIconButton(
                          context,
                          tooltip: AppLocalizations.of(
                            context,
                          )!.serversRefreshSubscription,
                          color: hasRefreshError
                              ? AppTheme.red(context)
                              : textLightColor,
                          onPressed: isRefreshing
                              ? null
                              : () async {
                                  try {
                                    await onRefresh!.call();
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(
                                      context,
                                    ).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          _shortError(e),
                                        ),
                                        backgroundColor: AppTheme.red(
                                          context,
                                        ),
                                      ),
                                    );
                                  }
                                },
                          icon: isRefreshing
                              ? ShapeLoadingIndicator(
                                  size: ExpressiveIconSize.medium,
                                  color: accentColor,
                                )
                              : const SeasonalIcon(
                                  Icons.refresh_rounded,
                                  size: ExpressiveIconSize.medium,
                                ),
                        ),
                        const SizedBox(width: _subCardHeaderActionGap),
                      ],
                      _subCardHeaderIconButton(
                        context,
                        tooltip: AppLocalizations.of(
                          context,
                        )!.serversPingAll,
                        color: textLightColor,
                        onPressed: isPingingAll
                            ? null
                            : () async {
                                try {
                                  await onPingAll();
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(
                                    context,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(_shortError(e)),
                                      backgroundColor: AppTheme.red(
                                        context,
                                      ),
                                    ),
                                  );
                                }
                              },
                        icon: isPingingAll
                            ? ShapeLoadingIndicator(
                                size: ExpressiveIconSize.medium,
                                color: accentColor,
                              )
                            : const SeasonalIcon(
                                Icons.network_ping_rounded,
                                size: ExpressiveIconSize.medium,
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
      );
  }
}

class _AutoSelectRow extends ConsumerWidget {
  const _AutoSelectRow({required this.subscription});

  final Subscription subscription;

  Future<void> _toggle(WidgetRef ref, BuildContext context) async {
    final on = subscription.autoSelect;
    final subs = ref.read(subscriptionsProvider.notifier);
    if (on) {
      await subs.editMeta(subscription.id, autoSelect: false);
      return;
    }
    await subs.handAutoSelectTo(subscription.id);

    final servers = ref.read(serversProvider).servers;
    final pick = AutoServerSelect.pick(
      servers,
      subscriptionId: subscription.id,
    );
    if (pick == null) return;
    final active = ref.read(serversProvider).activeServer;
    if (pick.id == active?.id) return;
    await ref.read(serversProvider.notifier).setActive(pick);

    final status = ref.read(vpnStateProvider).value?.status;
    if (status != VpnStatus.connected && status != VpnStatus.connecting) return;
    try {
      await ref.read(vpnStateProvider.notifier).reconnectToActiveServer();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return SizedBox(
      height: _GroupHeaderBackground.autoRowHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 14, 0),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Tooltip(
            message: l10n.serversAutoSelectTooltip,
            child: ExpressiveToggleButton(
              selected: subscription.autoSelect,
              label: l10n.serversAutoSelect,
              onPressed: () => unawaited(_toggle(ref, context)),
            ),
          ),
        ),
      ),
    );
  }
}

class _SubCard extends ConsumerStatefulWidget {
  final Subscription? subscription;
  final List<ServerItem> servers;
  final String? groupKey;
  final String? groupTitle;
  final _ServerListLayout layout;
  final double rowExtent;
  final void Function(ServerItem) onSelectServer;
  final Future<void> Function()? onRefresh;
  final Future<void> Function() onPingAll;

  const _SubCard({
    super.key,
    required this.subscription,
    required this.servers,
    this.groupKey,
    this.groupTitle,
    required this.layout,
    required this.rowExtent,
    required this.onSelectServer,
    required this.onRefresh,
    required this.onPingAll,
  });

  @override
  ConsumerState<_SubCard> createState() => _SubCardState();
}

class _SubCardState extends ConsumerState<_SubCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _open = AnimationController.unbounded(
    vsync: this,
    value: (ref.read(collapsedServerGroupsProvider)[_collapseKey] ?? false)
        ? 0
        : 1,
  );

  String get _collapseKey =>
      widget.groupKey ??
      widget.subscription?.id ??
      ServersNotifier.manualGroupKey;

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  List<ServerItem>? _sortedCache;
  List<ServerItem>? _sortedSource;
  ServerSortMode? _sortedMode;

  SubscriptionAccent? _accent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAccent();
  }

  @override
  void didUpdateWidget(_SubCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subscription?.cardThemeId !=
        widget.subscription?.cardThemeId) {
      _syncAccent();
    }
  }

  void _syncAccent() {
    final themeId = widget.subscription?.cardThemeId ?? '';
    final scheme = Theme.of(context).colorScheme;
    if (themeId.isEmpty) {
      if (_accent != null) setState(() => _accent = null);
      return;
    }

    final cached = SubscriptionAccentService.cached(
      themeId: themeId,
      scheme: scheme,
    );
    if (cached != null) {
      if (cached != _accent) setState(() => _accent = cached);
      return;
    }

    unawaited(() async {
      final accent = await SubscriptionAccentService.resolve(
        themeId: themeId,
        scheme: scheme,
      );
      if (!mounted) return;
      if ((widget.subscription?.cardThemeId ?? '') != themeId) return;
      if (accent != _accent) setState(() => _accent = accent);
    }());
  }

  List<ServerItem> _sortedFor(List<ServerItem> source, ServerSortMode mode) {
    if (identical(source, _sortedSource) && mode == _sortedMode) {
      return _sortedCache!;
    }
    _sortedSource = source;
    _sortedMode = mode;
    return _sortedCache = sortServersBy(source, mode);
  }

  @override
  Widget build(BuildContext context) {
    final sub = widget.subscription;
    final collapseKey = _collapseKey;
    final collapsed = ref.watch(
      collapsedServerGroupsProvider.select((m) => m[collapseKey] ?? false),
    );
    ref.listen(
      collapsedServerGroupsProvider.select((m) => m[collapseKey] ?? false),
      (_, next) {
        final target = next ? 0.0 : 1.0;
        if (MediaQuery.disableAnimationsOf(context)) {
          _open.value = target;
        } else {
          // сама пружина после перелёта встаёт на 0,0002, и шапка считала группу приоткрытой
          ExpressiveMotion.springTo(_open, target, snapToEnd: true);
        }
      },
    );
    final sortMode = ServerSortMode.fromName(
      ref.watch(serverSortModesProvider.select((m) => m[collapseKey])),
    );
    final sortedServers = _sortedFor(widget.servers, sortMode);
    final activeServerId = ref.watch(
      serversProvider.select((s) => s.activeServerId),
    );

    final activeIndex = activeServerId == null
        ? -1
        : sortedServers.indexWhere((s) => s.id == activeServerId);
    if (activeIndex >= 0) {
      final row = activeIndex ~/ widget.layout.columns;
      ServerGroupAnchors.instance.registerActiveServer(
        serverId: activeServerId!,
        groupKey: collapseKey,
        offsetInGroup: collapsed
            ? null
            : _GroupHeaderBackground.heightFor(sub, collapsed: false) +
                widget.layout.gap / 2 +
                row * widget.rowExtent,
      );
    } else {
      ServerGroupAnchors.instance.unregisterActiveServer(collapseKey);
    }

    final accent = _accent;
    final scheme = Theme.of(context).colorScheme;
    final groupColor = accent?.surface(scheme.surfaceContainerLow) ??
        scheme.surfaceContainerLow;
    final textLightColor = AppTheme.textLight(context);

    return DecoratedSliver(
      decoration: BoxDecoration(
        color: groupColor,
        borderRadius: ExpressiveShape.radius(ExpressiveShape.extraLarge),
      ),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            // якорь на шапке: SliverToBoxAdapter раскладывает её всегда, даже за экраном
            child: _ServerGroupHeader(
              subscription: widget.subscription,
              servers: widget.servers,
              groupKey: widget.groupKey,
              groupTitle: widget.groupTitle,
              onRefresh: widget.onRefresh,
              onPingAll: widget.onPingAll,
              accent: _accent,
              openness: _open,
            ),
          ),
          AnimatedBuilder(
            animation: _open,
            // список собирается один раз за обычную сборку, кадры пружины его не пересобирают
            child: SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: SizedBox(height: widget.layout.gap / 2),
                ),
                _buildExpandedServerList(
                  servers: sortedServers,
                  activeServerId: activeServerId,
                  textLightColor: textLightColor,
                  accent: accent,
                ),
                SliverToBoxAdapter(
                  child: SizedBox(height: widget.layout.gap / 2),
                ),
              ],
            ),
            builder: (context, list) {
              // свёрнутая и успокоившаяся группа плиток не строит вовсе
              if (collapsed && !_open.isAnimating) {
                return const SliverToBoxAdapter();
              }
              return SliverReveal(factor: _open.value, sliver: list!);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedServerList({
    required List<ServerItem> servers,
    required String? activeServerId,
    required Color textLightColor,
    required SubscriptionAccent? accent,
  }) {
    if (servers.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            context.l10n.serversEmptyGroupHint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: textLightColor),
          ),
        ),
      );
    }

    final layout = widget.layout;
    final columns = layout.columns;
    final direction = Directionality.of(context);
    Widget tileAt(int index) {
      final server = servers[index];
      return _ServerTile(
        key: ValueKey(server.id),
        server: server,
        isActive: server.id == activeServerId,
        layout: layout.rowLayout,
        height: widget.rowExtent,
        accent: accent,
        radius: ExpressiveListSegment.segmentRadius(
                index: index,
                count: servers.length,
                columns: columns,
                // радиус концентричный углу группы, со спековыми 16dp последний сервер выпирал за край
                endCorner:
                    ExpressiveShape.extraLarge - ExpressiveListSegment.gap,
              ).resolve(direction),
        margin: ExpressiveListSegment.segmentMargin(
          index: index,
          columns: columns,
          spacing: layout.gap,
        ).resolve(direction),
        onTap: () => widget.onSelectServer(server),
        onDelete: () => ref.read(serversProvider.notifier).delete(server.id),
        onPing: () => ref.read(serversProvider.notifier).pingSingle(server.id),
      );
    }

    if (columns > 1) {
      return SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: widget.rowExtent,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => tileAt(index),
          childCount: servers.length,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: false,
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => tileAt(index),
        childCount: servers.length,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: false,
      ),
    );
  }
}
