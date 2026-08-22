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

    // Цепочки живут в списке обычными серверами, но своей группой: у них своя
    // логика («маршрут», а не «сервер»), и в куче с ручными они бы потерялись.
    final chains = serversState.servers
        .where((s) => s.protocol == 'chain')
        .toList();
    final manual = serversState.servers
        .where((s) => s.subscriptionId == null && s.protocol != 'chain')
        .toList();
    final bySubId = <String, List<ServerItem>>{};
    for (final s in serversState.servers.where(
      (s) => s.subscriptionId != null,
    )) {
      bySubId.putIfAbsent(s.subscriptionId!, () => []).add(s);
    }

    final groups = <_ServerGroupEntry>[];
    if (chains.isNotEmpty) {
      groups.add(
        _ServerGroupEntry(
          key: const ValueKey('server-group-chains'),
          subscription: null,
          servers: chains,
          groupKey: ServersNotifier.chainsGroupKey,
          groupTitle: context.l10n.chainGroupTitle,
          onRefresh: null,
          onPingAll: () => ref.read(serversProvider.notifier).pingChains(),
        ),
      );
    }
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

    // Режим колонок читаем здесь и раздаём карточкам ПАРАМЕТРОМ, а не вотчем
    // внутри _SubCard: при смене настройки AnimatedSwitcher ниже держит старое
    // поддерево на кросс-фейде, и вотч внутри него мгновенно перестроил бы
    // «уходящий» список в новую раскладку — перехода не было бы видно.
    final twoColumns = ref.watch(
      settingsNotifierProvider.select(
        (a) => a.value?.serversTwoColumns ?? false,
      ),
    );

    // CustomScrollView + sliver-группы: тайлы серверов строятся лениво по мере
    // прокрутки (SliverList.builder в _SubCard), а не все разом Column'ом —
    // раскрытая группа на сотни серверов иначе джанкает свайп (build +
    // семантика каждого тайла на каждый кадр).
    final list = SmoothScroll(
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
                groupKey: groups[index].groupKey,
                groupTitle: groups[index].groupTitle,
                twoColumns: twoColumns,
                onSelectServer: onSelectServer,
                onRefresh: groups[index].onRefresh,
                onPingAll: groups[index].onPingAll,
              ),
            ),
        ],
      ),
    );

    // Плавная смена раскладки 1↔2 колонки: мягкий фейд с лёгким масштабом
    // (в стиле остальных AnimatedSwitcher приложения) вместо резкого скачка.
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
        key: ValueKey(twoColumns),
        child: list,
      ),
    );
  }
}

/// Подложка карточки подписки, перенесённая в шапку её группы серверов.
///
/// Зачем: цвет, выведенный из картинки, связывает группу с карточкой лишь
/// намёком — «похожий оттенок» ещё нужно заметить. Та же картинка связывает их
/// буквально, с одного взгляда.
///
/// Почему это отдельный виджет, а не пара строк в шапке: подложка обязана
/// обрезаться по форме карточки группы, а форма зависит от того, свёрнута ли
/// группа. Держать эту связку рядом с деревом из семи уровней Row/Padding —
/// верный способ однажды её потерять.
class _GroupHeaderBackground extends StatelessWidget {
  const _GroupHeaderBackground({
    required this.subscription,
    required this.surface,
    required this.collapsed,
    required this.child,
  });

  final Subscription? subscription;

  /// Фон карточки группы — им же кроется картинка, чтобы текст читался.
  final Color surface;
  final bool collapsed;
  final Widget child;

  /// Насколько картинка заходит НИЖЕ строки заголовка.
  ///
  /// Эта полоса и есть весь смысл: обрезанная точно по строке картинка даёт
  /// прямой горизонтальный шов — на нём взгляд и спотыкается. Продолженная
  /// вниз и растворённая в фоне, она кончается там, где её край уже не виден.
  ///
  /// Полосу видно, только когда группа развёрнута: у свёрнутой снизу край
  /// карточки, растворять картинку не во что.
  static const fadeHeight = 26.0;

  /// Высота шапки с учётом полосы растворения — её же занимает
  /// SliverToBoxAdapter. Группы без картинки остаются прежней высоты: лишняя
  /// полоса пустоты в каждой из них дороже, чем польза от единообразия.
  static double heightFor(Subscription? subscription, {required bool collapsed}) =>
      _showsImage(subscription) && !collapsed
          ? _subCardRowHeight + fadeHeight
          : _subCardRowHeight;

  static bool _showsImage(Subscription? sub) =>
      sub != null &&
      sub.cardThemeInServers &&
      sub.cardThemeId.isNotEmpty &&
      !resolveCardTheme(sub.cardThemeId).isPlain;

  @override
  Widget build(BuildContext context) {
    final sub = subscription;
    // Группы без подписки (цепочки, ручные серверы) картинки не имеют вовсе,
    // и выключенный тумблер оставляет от темы только цвета.
    if (!_showsImage(sub)) return child;
    final theme = resolveCardTheme(sub!.cardThemeId);

    // Внутренний радиус на 1 меньше внешнего: шапка живёт под рамкой
    // DecoratedSliver, и совпадающий радиус оставлял бы вдоль дуги волосяную
    // полоску картинки поверх линии рамки.
    const outer = ExpressiveShape.extraLarge - 1;
    // Доля высоты, на которой стоит строка заголовка. Ниже — только картинка.
    final headerFraction = collapsed
        ? 1.0
        : _subCardRowHeight / (_subCardRowHeight + fadeHeight);

    return ClipRRect(
      borderRadius: BorderRadius.vertical(
        top: const Radius.circular(outer),
        bottom: Radius.circular(collapsed ? outer : 0),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          theme.background(context),
          // Вуаль поверх картинки — та же роль, что у карточки подписки: слева
          // плотная (под заголовком), справа картинка открыта. Но цвет берётся
          // из ФАКТИЧЕСКОГО фона группы, уже подкрашенного акцентом, а не из
          // роли темы: иначе на стыке с первым сервером был бы виден шов.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.centerStart,
                end: AlignmentDirectional.centerEnd,
                stops: const [0, 0.45, 1],
                colors: [
                  surface.withValues(alpha: 0.9),
                  surface.withValues(alpha: 0.62),
                  surface.withValues(alpha: 0.22),
                ],
              ),
            ),
          ),
          // Растворение вниз. Начинается ВЫШЕ строки заголовка (на 0.72 от
          // неё), иначе плавным был бы только хвост, а на самой границе строки
          // всё равно читался бы уступ яркости.
          if (!collapsed)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, headerFraction * 0.72, 1],
                  colors: [
                    surface.withValues(alpha: 0),
                    surface.withValues(alpha: 0),
                    surface,
                  ],
                ),
              ),
            ),
          // Строка заголовка держится ВЕРХА, а не центра всей области: иначе
          // полоса растворения утащила бы её вниз, и шапка перестала бы
          // совпадать по высоте с обычными группами.
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(height: _subCardRowHeight, child: child),
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

  /// Ключ группы для сворачивания/сортировки/пинга. null — считается из
  /// подписки (`sub.id`, либо `__manual__`).
  final String? groupKey;

  /// Заголовок вместо выведенного из подписки.
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
const _subCardRowHeight = ServerRow.height;

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
  /// Своя пара «ключ + заголовок» для групп, которых нет среди подписок
  /// (цепочки). null — берётся из подписки, как раньше.
  final String? groupKey;
  final String? groupTitle;
  /// Раскладка списка приходит параметром сверху (см. _ServersListPanel):
  /// вотч настройки внутри карточки сломал бы кросс-фейд смены колонок.
  final bool twoColumns;
  final void Function(ServerItem) onSelectServer;
  final Future<void> Function()? onRefresh;
  final Future<void> Function() onPingAll;

  const _SubCard({
    super.key,
    required this.subscription,
    required this.servers,
    this.groupKey,
    this.groupTitle,
    required this.twoColumns,
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

  /// Цвета, выведенные из картинки подписки. Группа связывает себя с карточкой
  /// на вкладке «Подписки» именно ими.
  SubscriptionAccent? _accent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAccent();
  }

  @override
  void didUpdateWidget(_SubCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Подписке сменили картинку — группа обязана перекраситься следом.
    if (oldWidget.subscription?.cardThemeId !=
        widget.subscription?.cardThemeId) {
      _syncAccent();
    }
  }

  /// Достаёт акцент из кэша, а при промахе досчитывает его в фоне.
  ///
  /// Синхронный кэш — не оптимизация, а условие: список серверов
  /// перестраивается на каждый пинг и на каждую смену активного сервера, и
  /// FutureBuilder на этом пути дёргал бы квантование картинки постоянно, а
  /// заодно мигал бы пустым кадром. Первый показ до готовности проходит без
  /// подсветки — это ровно то, как выглядит группа без своей темы.
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
      // Пока считали, карточку могли увести с экрана, а подписке — сменить
      // картинку: показывать акцент от прошлой было бы хуже, чем никакого.
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
    final collapseKey =
        widget.groupKey ?? sub?.id ?? ServersNotifier.manualGroupKey;
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
    final pingScope = collapseKey;
    final isPingingAll = ref.watch(
      pingingScopesProvider.select((scopes) => scopes.contains(pingScope)),
    );
    final activeServerId = ref.watch(
      serversProvider.select((s) => s.activeServerId),
    );
    final title = widget.groupTitle ??
        (sub != null
            ? '${sub.name}  |  ${ltrIsolate(sub.usageLabel)}'
            : context.l10n.serversManualGroup);

    // кэшируем цвета, чтобы не дёргать Theme.of() на каждый вложенный виджет
    final accent = _accent;
    final cardColor = accent?.surface(AppTheme.card(context)) ??
        AppTheme.card(context);
    final dividerColor = accent?.outline(AppTheme.divider(context)) ??
        AppTheme.divider(context);
    // Иконки шапки и спиннеры уводим в цвет подписки — это те самые элементы,
    // что уже есть на её карточке (обновление, «12h»), и связь читается без
    // единого нового пикселя.
    final accentColor = accent?.seed ?? AppTheme.accent(context);
    final textLightColor = AppTheme.textLight(context);

    // Sliver-карточка: DecoratedSliver рисует фон/рамку/тень на всю длину
    // группы (включая невидимую часть), а тайлы строятся лениво SliverList'ом.
    return DecoratedSliver(
      decoration: BoxDecoration(
        color: cardColor,
        // Группа серверов — «поверхность», а не карточка: extraLarge, чтобы
        // читался контраст с формой поднятого активного тайла внутри.
        borderRadius: ExpressiveShape.radius(ExpressiveShape.extraLarge),
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
                  height: _GroupHeaderBackground.heightFor(
                    sub,
                    collapsed: collapsed,
                  ),
                  child: _GroupHeaderBackground(
                    subscription: sub,
                    surface: cardColor,
                    // Свёрнутая группа — это только шапка, и снизу у неё тоже
                    // край карточки: не скругли мы его, картинка вылезла бы
                    // прямыми углами из-под скруглённой рамки.
                    collapsed: collapsed,
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
                                          Icons.expand_more_rounded,
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
                                      // Заголовок группы — роль подзаголовка
                                      // списка в M3, а не свой кегль 13.
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(color: textLightColor),
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
                          padding: const EdgeInsetsDirectional.only(start: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (sub != null && sub.autoUpdate) ...[
                                // InkWell, а не GestureDetector: чип нажимается,
                                // и до сих пор об этом ничем не сообщал.
                                Material(
                                  color: accentColor.withValues(alpha: 0.18),
                                  shape: ExpressiveShape.border(
                                    ExpressiveShape.small,
                                  ),
                                  child: InkWell(
                                    onTap: () =>
                                        _showIntervalPicker(context, sub),
                                    customBorder: ExpressiveShape.border(
                                      ExpressiveShape.small,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      child: Text(
                                        '${sub.updateIntervalHours}h',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(color: accentColor),
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
                                      ? Icons.sort_rounded
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
                                      ? SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: accentColor,
                                          ),
                                        )
                                      : Icon(
                                          Icons.refresh_rounded,
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
                                              content: Text(_shortError(e)),
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
                                        Icons.network_ping_rounded,
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
            ),

            // Свёрнутая группа — просто без sliver'а тайлов. Никакого
            // AnimatedSize вокруг: он требует построить все тайлы разом и
            // несовместим с ленивым sliver-построением (анимируется шеврон).
            if (!collapsed)
              _buildExpandedServerList(
                servers: sortedServers,
                activeServerId: activeServerId,
                textLightColor: textLightColor,
                twoColumns: widget.twoColumns,
                accent: accent,
              ),
          ],
        ),
      ),
    );
  }

  /// Sliver с тайлами: SliverList.builder строит только видимые в viewport,
  /// чтобы раскрытая группа на сотни серверов не собирала все тайлы разом.
  /// [twoColumns] — опциональная сетка в две колонки, строится так же лениво
  /// через SliverGrid.
  Widget _buildExpandedServerList({
    required List<ServerItem> servers,
    required String? activeServerId,
    required Color textLightColor,
    required bool twoColumns,
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

    if (twoColumns) {
      // Нижний ряд: при нечётном числе серверов последняя плитка одна слева,
      // пустая правая половина — фон карточки (DecoratedSliver) со своим
      // скруглением. У плиток нижнего ряда скругляется только внешний угол.
      final lastRowStart =
          servers.length.isEven ? servers.length - 2 : servers.length - 1;
      return SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisExtent: _subCardRowHeight,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final server = servers[index];
            final inLastRow = index >= lastRowStart;
            return _ServerTile(
              key: ValueKey(server.id),
              server: server,
              isActive: server.id == activeServerId,
              isFirst: index < 2,
              isLast: inLastRow,
              accent: accent,
              radius: BorderRadius.only(
                bottomLeft: inLastRow && index.isEven
                    ? const Radius.circular(ExpressiveShape.extraLarge)
                    : Radius.zero,
                bottomRight: inLastRow && index.isOdd
                    ? const Radius.circular(ExpressiveShape.extraLarge)
                    : Radius.zero,
              ),
              onTap: () => widget.onSelectServer(server),
              onDelete: () =>
                  ref.read(serversProvider.notifier).delete(server.id),
              onPing: () =>
                  ref.read(serversProvider.notifier).pingSingle(server.id),
            );
          },
          childCount: servers.length,
          addAutomaticKeepAlives: false,
          // _ServerTile сам оборачивается в RepaintBoundary — не дублируем.
          addRepaintBoundaries: false,
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
          accent: accent,
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
    final l10n = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExpressiveSectionHeader(l10n.serversSortTitle),
              // Это выбор, а не список действий: текущий режим виден заливкой
              // и галочкой, а не только чуть более жирной подписью.
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
        );
      },
    );
  }

  void _showIntervalPicker(BuildContext context, Subscription sub) {
    const options = [1, 3, 6, 12, 24, 48, 72];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final maxHeight = MediaQuery.sizeOf(ctx).height * 0.85;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                Text(
                  context.l10n.subscriptionsAutoUpdateInterval,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme
                      .emphasized(Theme.of(context).textTheme.titleLarge)
                      ?.copyWith(color: AppTheme.text(context)),
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10n.subscriptionsCurrentInterval(
                    sub.updateIntervalHours,
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textLight(context)),
                ),
                const SizedBox(height: 12),
                // Тот же вид, что у пикера интервала в карточке подписки:
                // выбор, а не список действий, поэтому текущее значение
                // заливается сегментом, а не отличается жирной подписью.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ExpressiveGroup(
                    children: [
                      // «Выключить» есть и здесь: пикер тот же самый, и
                      // расходиться со шторкой из карточки подписки он не
                      // должен.
                      ExpressiveActionTile(
                        icon: Icons.update_disabled_rounded,
                        title: context.l10n.subscriptionsAutoUpdateOff,
                        selected: !sub.autoUpdate,
                        onTap: () {
                          ref
                              .read(subscriptionsProvider.notifier)
                              .setUpdateSchedule(sub.id, autoUpdate: false);
                          Navigator.of(ctx).pop();
                        },
                      ),
                      for (final h in options)
                        ExpressiveActionTile(
                          icon: h < 24
                              ? Icons.schedule_rounded
                              : Icons.calendar_today_rounded,
                          title: h == 1
                              ? context.l10n.subscriptionsEveryHour
                              : h < 24
                              ? context.l10n.subscriptionsEveryHours(h)
                              : h == 24
                              ? context.l10n.subscriptionsEveryDay
                              : context.l10n.subscriptionsEveryDays(h ~/ 24),
                          selected:
                              sub.autoUpdate && h == sub.updateIntervalHours,
                          onTap: () {
                            ref
                                .read(subscriptionsProvider.notifier)
                                .setUpdateSchedule(
                                  sub.id,
                                  autoUpdate: true,
                                  hours: h,
                                );
                            Navigator.pop(ctx);
                          },
                        ),
                    ],
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
