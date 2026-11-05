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
    // пометку «Авто» плитка ловит сама, весь список на неё не перестраивается
    ref.watch(serversProvider.select((s) => s.shape));
    final serversState = ref.read(serversProvider);
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
                      index < groups.length - 1
                          ? 20
                          : 80 + FloatingBar.clearance(context),
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
    required this.groups,
    required this.child,
  });

  final Subscription? subscription;

  final bool groups;

  final Color surface;

  // 0 свёрнута, 1 раскрыта: шапка идёт по той же пружине, что и список под ней
  final double open;
  final Widget child;

  static const fadeHeight = 26.0;

  static double heightFor(
    Subscription? subscription, {
    required bool collapsed,
    bool groups = false,
  }) =>
      heightAt(subscription, collapsed ? 0 : 1, groups: groups);

  static double heightAt(
    Subscription? subscription,
    double open, {
    bool groups = false,
  }) {
    final below = [
      if (_showsImage(subscription)) fadeHeight,
      if (subscription?.autoSelectVisible == true || groups) autoRowHeight,
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
    // гаснет по ходу всего сворачивания, а не за последний 1 dp. ниже 5% его нет: на отдаче
    // пружины группа снова приоткрывается на доли процента, и затемнение вспыхивало
    final fadeStrength = ((open - 0.05) / 0.95).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.vertical(
        top: const Radius.circular(outer),
        bottom: Radius.circular(outer * (1 - open)),
      ),
      // картинка и затемнение сглаживались по краю каждое само, и под картинкой светилась полоска
      // до серверов (ПК). сперва слой, потом скругление; картинка шире шапки на 1 dp
      clipBehavior:
          PlatformBootstrap.isDesktop ? Clip.antiAliasWithSaveLayer : Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            left: -1,
            top: -1,
            right: -1,
            bottom: -1,
            child: theme.background(
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
          ),
          Align(
            alignment: Alignment.topCenter,
            // высота вместе со строкой Авто: иначе кнопку видно, но нажатия до неё не доходят
            child: SizedBox(
              height: heightAt(sub, open, groups: groups),
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
    final floating = FloatingBar.shown(context);
    return ValueListenableBuilder<double>(
      valueListenable: FloatingBar.bottomInset,
      builder: (context, barInset, _) => NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: EdgeFadeMask(
        // сверху в покое под краем пусто, затухание растёт с прокруткой
        top: _progress == 0
            ? 0
            : _listTopPadding + (35 - _listTopPadding) * _progress,
        // без излома хватает короткого: полностью скрыт только системный отступ
        bottom: 28,
        // под плавающей полосой отступ тела включает её саму, а гасить надо только системный
        bottomHidden: floating ? barInset : MediaQuery.paddingOf(context).bottom,
        topOutline: widget.underPanel
            ? const EdgeFadeOutline(
                inset: _ModernConnectPanel._margin,
                radius: ExpressiveShape.extraLarge,
                gap: _ModernConnectPanel._gapBelow,
              )
            : null,
        child: widget.child,
      ),
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
    void toggleFold() => ref
        .read(collapsedServerGroupsProvider.notifier)
        .update((m) => {...m, collapseKey: !collapsed});
    final pingScope = collapseKey;
    final isPingingAll = ref.watch(
      pingingScopesProvider.select((scopes) => scopes.contains(pingScope)),
    );
    final title =
        groupTitle ??
        (sub != null
            ? '${sub.name}  |  ${ltrIsolate(sub.usageLabel)}'
            : context.l10n.serversManualGroup);
    final template =
        sub == null ? null : ref.watch(subscriptionTemplateProvider(sub.id));
    final picking =
        sub != null && ref.watch(autoSkipPickingProvider) == sub.id;
    return ServerGroupAnchor(
        groupKey: collapseKey,
        child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: openness,
          builder: (context, row) {
            final open = openness.value.clamp(0.0, 1.0);
            // перелёт пружины за ноль: свёрнутая шапка чуть проседает и выпрямляется
            final squash = min(0.0, openness.value) * 60;
            // Авто тает в первой половине сворачивания, а не уезжает за край
            final auto = ((open - 0.4) / 0.6).clamp(0.0, 1.0);
            return SizedBox(
              height: _GroupHeaderBackground.heightAt(
                    sub,
                    open,
                    groups: template != null,
                  ) +
                  squash,
              child: _GroupHeaderBackground(
                subscription: sub,
                surface: groupColor,
                open: open,
                groups: template != null,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        row!,
                        if (sub != null &&
                            (template != null || sub.autoSelectVisible) &&
                            auto > 0)
                          Opacity(
                            opacity: auto,
                            child: Transform.scale(
                              scale: 0.85 + 0.15 * auto,
                              alignment: AlignmentDirectional.centerStart,
                              child: _AutoRowMorph(
                                subscription: sub,
                                picking: picking,
                                groups: template?.groups.length,
                              ),
                            ),
                          ),
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
                      onTap: toggleFold,
                      onLongPress: () {
                        HapticFeedback.mediumImpact();
                        _serverGroupSortMenu(ref, context, collapseKey, sortMode);
                      },
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          TvTappable(
                            onTap: toggleFold,
                            radius: BorderRadius.circular(
                              _subCardHeaderIconSize / 2,
                            ),
                            child: SizedBox(
                              width: _subCardHeaderIconSize,
                              height: _subCardHeaderIconSize,
                              child: Center(
                                child: AnimatedRotation(
                                  turns: collapsed ? -0.25 : 0,
                                  duration: ExpressiveMotion.durationFast,
                                  curve: ExpressiveMotion.emphasized,
                                  child: Builder(
                                    builder: (context) => Icon(
                                      Icons.expand_more_rounded,
                                      size: ExpressiveIconSize.medium,
                                      color: TvFocusHighlight.containerOf(
                                                context) !=
                                              null
                                          ? Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                          : textLightColor,
                                    ),
                                  ),
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
                                    AppSnack.of(
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
                                  AppSnack.of(
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

class _AutoSelectRow extends StatelessWidget {
  const _AutoSelectRow({required this.subscription, this.buttonKey});

  final Subscription subscription;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: _GroupHeaderBackground.autoRowHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 14, 0),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: _AutoSelectButton(
              subscription: subscription,
              buttonKey: buttonKey,
            ),
          ),
        ),
      );
}

class _AutoSelectButton extends ConsumerWidget {
  const _AutoSelectButton({required this.subscription, this.buttonKey});

  final Subscription subscription;
  final Key? buttonKey;

  Future<void> _toggle(WidgetRef ref, BuildContext context) async {
    final on = subscription.autoSelect;
    final subs = ref.read(subscriptionsProvider.notifier);
    if (on) {
      await subs.editMeta(subscription.id, autoSelect: false);
      return;
    }
    await subs.handAutoSelectTo(subscription.id);
    await _autoSelectNow(ref, subscription.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Tooltip(
      message: l10n.serversAutoSelectTooltip,
      child: ExpressiveToggleButton(
        key: buttonKey,
        selected: subscription.autoSelect,
        label: l10n.serversAutoSelect,
        onPressed: () => unawaited(_toggle(ref, context)),
        onLongPress: () {
          HapticFeedback.mediumImpact();
          ref.read(autoSkipPickingProvider.notifier).set(subscription.id);
        },
      ),
    );
  }
}

Future<void> _autoSelectNow(WidgetRef ref, String subscriptionId) async {
  final pick = AutoServerSelect.pick(
    ref.read(serversProvider).servers,
    subscriptionId: subscriptionId,
  );
  if (pick == null) return;
  await ref.read(subscriptionsProvider.notifier).releaseMainGroup(pick);
  final active = ref.read(serversProvider).activeServer;
  if (pick.id == active?.id) return;
  await ref.read(serversProvider.notifier).setActive(pick);

  final status = ref.read(vpnStateProvider).value?.status;
  if (status != VpnStatus.connected && status != VpnStatus.connecting) return;
  try {
    await ref.read(vpnStateProvider.notifier).reconnectToActiveServer();
  } catch (_) {}
}

class _AutoSkipPickRow extends ConsumerWidget {
  const _AutoSkipPickRow({
    required this.subscription,
    required this.picking,
    this.doneKey,
  });

  final Subscription subscription;
  // на обратном пути строка ещё видна, но Назад уже не держит
  final bool picking;
  final Key? doneKey;

  void _done(WidgetRef ref) {
    ref.read(autoSkipPickingProvider.notifier).set(null);
    unawaited(ref.read(serversProvider.notifier).flushAutoSkip());
    final active = ref.read(serversProvider).activeServer;
    if (subscription.autoSelect &&
        active != null &&
        active.subscriptionId == subscription.id &&
        active.autoSkip) {
      unawaited(_autoSelectNow(ref, subscription.id));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return PopScope(
      canPop: !picking,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && picking) _done(ref);
      },
      child: SizedBox(
        height: _GroupHeaderBackground.autoRowHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 14, 0),
          child: Row(
            children: [
              Expanded(
                // на 320 dp с крупным шрифтом и в фарси на 360 dp многоточие съедало смысл, мельче лучше
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    l10n.serversAutoSkipHint,
                    maxLines: 1,
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: AppTheme.textLight(context)),
                  ),
                ),
              ),
              const SizedBox(width: ExpressiveSpacing.small),
              ExpressiveToggleButton(
                key: doneKey,
                selected: true,
                label: l10n.serversAutoSkipDone,
                onPressed: () => _done(ref),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AutoRowMorph extends StatefulWidget {
  const _AutoRowMorph({
    required this.subscription,
    required this.picking,
    required this.groups,
  });

  final Subscription subscription;
  final bool picking;
  final int? groups;

  @override
  State<_AutoRowMorph> createState() => _AutoRowMorphState();
}

class _AutoRowMorphState extends State<_AutoRowMorph>
    with SingleTickerProviderStateMixin {
  static const _lead = Interval(0, 0.6, curve: Curves.easeInOutCubic);
  static const _lag = Interval(0.3, 1, curve: Cubic(0.34, 1.3, 0.64, 1));
  static const _flood = Curves.easeInOutCubic;
  static const _drain = Cubic(0.34, 1.3, 0.64, 1);
  static const _tint = Interval(0.2, 0.7);
  static const _release = Interval(0, 0.15);

  // без пары кнопка просто едет через строку: 700 мс, хорошие с группами, тут тянулись
  static Duration _there(int? groups) =>
      Duration(milliseconds: groups == null ? 450 : 700);
  static Duration _back(int? groups) =>
      Duration(milliseconds: groups == null ? 400 : 600);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _there(widget.groups),
    reverseDuration: _back(widget.groups),
    value: widget.picking ? 1 : 0,
  );
  final _auto = GlobalKey();
  final _done = GlobalKey();
  bool _ltr = true;

  @override
  void didUpdateWidget(_AutoRowMorph oldWidget) {
    super.didUpdateWidget(oldWidget);
    _c
      ..duration = _there(widget.groups)
      ..reverseDuration = _back(widget.groups);
    if (oldWidget.picking == widget.picking) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = widget.picking ? 1 : 0;
    } else if (widget.picking) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Rect? _buttonRect(GlobalKey key, RenderBox self) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final r = MatrixUtils.transformRect(
      box.getTransformTo(self),
      Offset.zero & box.size,
    );
    return Rect.fromCenter(
      center: r.center,
      width: r.width,
      height: ExpressiveToggleButton.height,
    );
  }

  // от начала строки: в фарси начало справа
  _MorphPill? _pillAt(double t) {
    final self = context.findRenderObject();
    if (self is! RenderBox || !self.hasSize) return null;
    final from = _buttonRect(_auto, self);
    final to = _buttonRect(_done, self);
    if (from == null || to == null) return null;
    final width = self.size.width;
    final ltr = _ltr;
    double start(Rect r) => ltr ? r.left : width - r.right;
    double end(Rect r) => ltr ? r.right : width - r.left;

    final double s0;
    final double s1;
    if (widget.groups == null) {
      s1 = ui.lerpDouble(end(from), end(to), _lead.transform(t))!;
      s0 = ui.lerpDouble(start(from), start(to), _lag.transform(t))!;
    } else {
      final edge = ltr ? 16.0 : 14.0;
      s0 = t < 0.5
          ? ui.lerpDouble(start(from), edge, _flood.transform(t * 2))!
          : ui.lerpDouble(edge, start(to), _drain.transform(t * 2 - 1))!;
      s1 = ui.lerpDouble(end(from), end(to), t)!;
    }
    final restWidth = ui.lerpDouble(from.width, to.width, t)!;
    final stretched = ((s1 - s0 - restWidth) / (width / 8)).clamp(0.0, 1.0);
    final tint = _tint.transform(t);
    // долгое нажатие срабатывает под пальцем: Авто ещё нажата, иначе вспыхнула бы светлее
    final pressed =
        _c.status == AnimationStatus.forward ? 1 - _release.transform(t) : 0.0;
    final restCorner = ui.lerpDouble(
      ui.lerpDouble(
        widget.subscription.autoSelect
            ? ExpressiveToggleButton.squareCorner
            : ExpressiveToggleButton.pillCorner,
        ExpressiveToggleButton.squareCorner,
        tint,
      )!,
      ExpressiveToggleButton.pressedCorner,
      pressed,
    )!;
    final left = ltr ? s0 : width - s1;
    final right = ltr ? s1 : width - s0;
    return _MorphPill(
      rect: Rect.fromLTRB(
        left,
        from.top,
        max(right, left + ExpressiveToggleButton.height),
        from.bottom,
      ),
      startEdge: s0,
      fromStart: start(from),
      toStart: start(to),
      fromWidth: from.width,
      toWidth: to.width,
      ltr: ltr,
      tint: tint,
      pressed: pressed,
      // квадратные концы с глубокой талией выходили косточкой
      corner: ui.lerpDouble(restCorner, from.height / 2, stretched)!,
      neck: 2.5 * stretched,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sub = widget.subscription;
    final groups = widget.groups;
    final from = groups != null
        ? _SubscriptionTabsRow(
            subscription: sub,
            groups: groups,
            autoKey: _auto,
          )
        : _AutoSelectRow(subscription: sub, buttonKey: _auto);
    final to = _AutoSkipPickRow(
      subscription: sub,
      picking: widget.picking,
      doneKey: _done,
    );
    final scheme = Theme.of(context).colorScheme;
    final label = Theme.of(context).textTheme.labelLarge;
    final l10n = context.l10n;
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    _ltr = direction == TextDirection.ltr;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        // и в кадре переключения, пока контроллер ещё не сдвинулся
        final moving = widget.picking ? t < 1 : t > 0;
        final fromShown = groups != null && t < 0.5;
        // обе строки в дереве всю дорогу: Назад посреди перехода ловит PopScope строки выбора
        Widget side(Widget row, bool shown, bool isFrom) => KeyedSubtree(
          key: ValueKey(isFrom),
          child: ClipPath(
            clipper: moving ? _MorphSideClip(this, t, shown, isFrom) : null,
            clipBehavior: moving ? Clip.antiAlias : Clip.none,
            // спрятанная Авто не держит фокус пульта: OK посреди перехода щёлкнул бы её невидимо
            child: IgnorePointer(
              ignoring: moving,
              child: ExcludeFocus(excluding: moving, child: row),
            ),
          ),
        );
        return Stack(
          children: [
            if (moving || !widget.picking) side(from, fromShown, true),
            if (moving || widget.picking) side(to, !fromShown, false),
            if (moving)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _MorphPainter(
                      state: this,
                      t: t,
                      fromFill: sub.autoSelect
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                      fromInk: sub.autoSelect
                          ? scheme.onPrimary
                          : scheme.onSurfaceVariant,
                      toFill: scheme.primary,
                      toInk: scheme.onPrimary,
                      fromLabel: l10n.serversAutoSelect,
                      toLabel: l10n.serversAutoSkipDone,
                      style: label,
                      textScaler: textScaler,
                      textDirection: direction,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MorphPill {
  const _MorphPill({
    required this.rect,
    required this.startEdge,
    required this.fromStart,
    required this.toStart,
    required this.fromWidth,
    required this.toWidth,
    required this.ltr,
    required this.tint,
    required this.pressed,
    required this.corner,
    required this.neck,
  });

  final Rect rect;
  final double startEdge;
  final double fromStart;
  final double toStart;
  final double fromWidth;
  final double toWidth;
  final bool ltr;
  final double tint;
  final double pressed;
  final double corner;
  final double neck;
}

class _MorphSideClip extends CustomClipper<Path> {
  _MorphSideClip(this.state, this.t, this.shown, this.isFrom);

  final _AutoRowMorphState state;
  final double t;
  final bool shown;
  final bool isFrom;

  @override
  Path getClip(Size size) {
    final all = Path()..addRect(Offset.zero & size);
    if (!shown) return Path();
    final pill = state._pillAt(t);
    if (pill == null) return all;
    // пару прячет контур кнопки целиком: под тонкой серединой иначе проглядывала бы Авто,
    // а прямой обрез срезал бы пару у круглого конца
    if (isFrom) {
      return Path.combine(
        PathOperation.difference,
        all,
        Path()
          ..addRRect(
            RRect.fromRectAndRadius(pill.rect, Radius.circular(pill.corner)),
          ),
      );
    }
    // настоящая Готово не выглядывает, когда задний край на отскоке заходит за неё
    final edge = min(pill.startEdge + 1, pill.toStart - 1);
    return Path()
      ..addRect(
        pill.ltr
            ? Rect.fromLTRB(0, 0, edge, size.height)
            : Rect.fromLTRB(size.width - edge, 0, size.width, size.height),
      );
  }

  @override
  bool shouldReclip(_MorphSideClip oldClipper) => true;
}

class _MorphPainter extends CustomPainter {
  _MorphPainter({
    required this.state,
    required this.t,
    required this.fromFill,
    required this.fromInk,
    required this.toFill,
    required this.toInk,
    required this.fromLabel,
    required this.toLabel,
    required this.style,
    required this.textScaler,
    required this.textDirection,
  });

  final _AutoRowMorphState state;
  final double t;
  final Color fromFill;
  final Color fromInk;
  final Color toFill;
  final Color toInk;
  final String fromLabel;
  final String toLabel;
  final TextStyle? style;
  final TextScaler textScaler;
  final TextDirection textDirection;

  static const _fromText = Interval(0.15, 0.5);
  static const _toText = Interval(0.35, 0.7);

  Path _shape(Rect r, double corner, double neck) {
    final k = min(corner, min(r.width, r.height) / 2);
    final mid = r.center.dx;
    final a = r.left + k;
    final b = r.right - k;
    final q = (b - a) / 4;
    return Path()
      ..moveTo(a, r.top)
      ..cubicTo(a + q, r.top, mid - q, r.top + neck, mid, r.top + neck)
      ..cubicTo(mid + q, r.top + neck, b - q, r.top, b, r.top)
      ..arcToPoint(Offset(r.right, r.top + k), radius: Radius.circular(k))
      ..lineTo(r.right, r.bottom - k)
      ..arcToPoint(Offset(b, r.bottom), radius: Radius.circular(k))
      ..cubicTo(b - q, r.bottom, mid + q, r.bottom - neck, mid, r.bottom - neck)
      ..cubicTo(mid - q, r.bottom - neck, a + q, r.bottom, a, r.bottom)
      ..arcToPoint(Offset(r.left, r.bottom - k), radius: Radius.circular(k))
      ..lineTo(r.left, r.top + k)
      ..arcToPoint(Offset(a, r.top), radius: Radius.circular(k))
      ..close();
  }

  void _label(
    Canvas canvas,
    Offset at,
    String text,
    Color color,
    double alpha,
  ) {
    if (alpha <= 0) return;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: style?.copyWith(color: color.withValues(alpha: color.a * alpha)),
      ),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, at - Offset(painter.width / 2, painter.height / 2));
    painter.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pill = state._pillAt(t);
    if (pill == null) return;
    final r = pill.rect;
    final path = _shape(r, pill.corner, pill.neck);
    final ink = Color.lerp(fromInk, toInk, pill.tint)!;
    final fill = Color.alphaBlend(
      ink.withValues(alpha: 0.1 * pill.pressed),
      Color.lerp(fromFill, toFill, pill.tint)!,
    );
    canvas.drawPath(path, Paint()..color = fill);
    canvas
      ..save()
      ..clipPath(path);
    // старая надпись уходит с задним краем, новая встаёт у переднего: посередине не слипаются
    final y = r.center.dy;
    final fromX =
        pill.ltr ? r.left + pill.fromWidth / 2 : r.right - pill.fromWidth / 2;
    final toX = pill.ltr ? r.right - pill.toWidth / 2 : r.left + pill.toWidth / 2;
    _label(canvas, Offset(fromX, y), fromLabel, ink, 1 - _fromText.transform(t));
    _label(canvas, Offset(toX, y), toLabel, ink, _toText.transform(t));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MorphPainter oldDelegate) => true;
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
  var _shut = false;
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
        _shut = false;
        if (MediaQuery.disableAnimationsOf(context)) {
          _open.value = target;
        } else {
          // сама пружина после перелёта встаёт на 0,0002, и шапка считала группу приоткрытой.
          // сворачивание упруже: перелёт за ноль даёт отдачу, как у разворачивания перелёт за 1
          ExpressiveMotion.springTo(
            _open,
            target,
            snapToEnd: true,
            spring: next ? ExpressiveMotion.fold : ExpressiveMotion.spatialDefault,
          );
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

    final template =
        sub == null ? null : ref.watch(subscriptionTemplateProvider(sub.id));
    final picking =
        sub != null && ref.watch(autoSkipPickingProvider) == sub.id;
    final groupsOpen = template != null &&
        !picking &&
        ref.watch(serverGroupsTabProvider.select((m) => m[sub!.id] ?? false));

    final activeIndex = activeServerId == null
        ? -1
        : sortedServers.indexWhere((s) => s.id == activeServerId);
    if (activeIndex >= 0) {
      final row = activeIndex ~/ widget.layout.columns;
      ServerGroupAnchors.instance.registerActiveServer(
        serverId: activeServerId!,
        groupKey: collapseKey,
        offsetInGroup: collapsed || groupsOpen
            ? null
            : _GroupHeaderBackground.heightFor(
                  sub,
                  collapsed: false,
                  groups: template != null,
                ) +
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
                if (groupsOpen)
                  _TemplateGroupsSliver(
                    subscription: sub!,
                    template: template,
                    servers: widget.servers,
                    rowExtent: widget.rowExtent,
                    gap: widget.layout.gap,
                    accent: accent,
                    onSelectServer: widget.onSelectServer,
                  )
                else
                  _buildExpandedServerList(
                    servers: sortedServers,
                    // всё остальное идёт через группу шаблона, а не через нажатый сервер
                    activeServerId:
                        template?.mainChoice(sub!.groupChoices) != null
                            ? null
                            : activeServerId,
                    textLightColor: textLightColor,
                    accent: accent,
                    picking: picking,
                    autoOn: sub?.autoSelect ?? false,
                  ),
                SliverToBoxAdapter(
                  child: SizedBox(height: widget.layout.gap / 2),
                ),
              ],
            ),
            builder: (context, list) {
              // отдача пружины снова приоткрывала уже закрытый список серым краем:
              // дошёл до нуля, дальше пружинит одна шапка
              if (collapsed && _open.value <= 0) _shut = true;
              if (collapsed && (_shut || !_open.isAnimating)) {
                return const SliverToBoxAdapter();
              }
              return SliverReveal(factor: _open.value, sliver: list!);
            },
          ),
        ],
      ),
    );
  }

  void _toggleAutoSkip(ServerItem server, List<ServerItem> group) {
    // пометки в group старые: на них список не перестраивается
    final now = ref.read(serversProvider).byId;
    bool skipped(ServerItem s) => now[s.id]?.autoSkip ?? s.autoSkip;
    final last = !skipped(server) &&
        group.every((s) => s.id == server.id || skipped(s));
    if (last) {
      AppSnack.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.serversAutoSkipKeepOne)),
      );
      return;
    }
    ref.read(serversProvider.notifier).toggleAutoSkip(server.id);
  }

  Widget _buildExpandedServerList({
    required List<ServerItem> servers,
    required String? activeServerId,
    required Color textLightColor,
    required SubscriptionAccent? accent,
    required bool picking,
    required bool autoOn,
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
        picking: picking,
        autoOn: autoOn,
        onTap: picking
            ? () => _toggleAutoSkip(server, servers)
            : () => widget.onSelectServer(server),
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
