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

    // Разбиение на группы — общее с боковым навигатором (`buildServerGroups`):
    // кнопка «перейти к группе», которой в списке нет или которая там стоит не
    // там, — это не мелочь оформления, а сломанная навигация. Здесь к каждой
    // группе добавляются только заголовок и действия, состав и порядок — оттуда.
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


    // Режим колонок читаем здесь и раздаём карточкам параметром, а не вотчем
    // внутри _SubCard: при смене настройки AnimatedSwitcher ниже держит старое
    // поддерево на кросс-фейде, и вотч внутри него мгновенно перестроил бы
    // «уходящий» список в новую раскладку — перехода не было бы видно.
    final twoColumns = ref.watch(
      settingsNotifierProvider.select(
        (a) => a.value?.serversTwoColumns ?? false,
      ),
    );
    final textScaler = MediaQuery.textScalerOf(context);
    final cardHeight = ServerRow.cardHeight(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _ServerListLayout.resolve(
          twoColumns: twoColumns,
          width: constraints.maxWidth,
          textScaler: textScaler,
        );
        final rowExtent =
            layout == _ServerListLayout.cards ? cardHeight : ServerRow.height;

        // CustomScrollView + sliver-группы: тайлы серверов строятся лениво по
        // мере прокрутки (SliverList.builder в _SubCard), а не все разом
        // Column'ом — раскрытая группа на сотни серверов иначе джанкает свайп
        // (build + семантика каждого тайла на каждый кадр).
        // Отступ прыжка: список накрыт градиентом шапки, и выровненная «в ноль»
        // группа уехала бы под него. Здесь же живёт слежение за тем, на какой
        // группе список стоит сейчас, — по нему навигатор ставит подсветку.
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

        // Плавная смена раскладки — от настройки или от поворота экрана: мягкий
        // фейд с лёгким масштабом (в стиле остальных AnimatedSwitcher
        // приложения) вместо резкого скачка.
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

/// Подложка карточки подписки, перенесённая в шапку её группы серверов.
///
/// Цвет, выведенный из картинки, связывает группу с карточкой лишь
/// намёком — «похожий оттенок» ещё нужно заметить. Та же картинка связывает их
/// буквально, с одного взгляда.
///
/// Отдельным виджетом, а не парой строк в шапке: подложка обязана
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

  /// Насколько картинка заходит ниже строки заголовка.
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
  ///
  /// Переключатель «Авто» занимает свою строку, а не втискивается в ряд с
  /// иконками: там у каждой кнопки 32dp с зазором в 8, и ещё одна цель рядом
  /// означала бы промахи пальцем по соседней.
  ///
  /// Но и целой строки шапка не получает: у группы с картинкой под заголовком
  /// уже есть полоса растворения, и кнопка садится на неё. Шапка вырастает на
  /// разницу, то есть на полтора десятка точек, а не на сорок — иначе
  /// включённая плашка раздувала бы карточку у каждой подписки.
  static double heightFor(Subscription? subscription, {required bool collapsed}) {
    if (collapsed) return _subCardRowHeight;
    final below = [
      if (_showsImage(subscription)) fadeHeight,
      if (subscription?.autoSelectVisible == true) autoRowHeight,
      0.0,
    ].reduce((a, b) => a > b ? a : b);
    return _subCardRowHeight + below;
  }

  /// Полоса под заголовком, когда в ней живёт переключатель «Авто»: кнопка
  /// размера XS (32dp) плюс по четыре точки, которые тоже ловят палец.
  static const autoRowHeight = 40.0;

  /// Именно `hasImage`, а не «тема выбрана»: у палитровой темы картинки нет
  /// вовсе, и шапка вырастала на [fadeHeight] пустоты — подложку из ролей
  /// схемы съедала та же вуаль, которой кроется картинка. Со стороны это и
  /// выглядело как «картинка не загрузилась».
  static bool _showsImage(Subscription? sub) =>
      sub != null &&
      sub.cardThemeInServers &&
      sub.cardThemeId.isNotEmpty &&
      resolveCardTheme(sub.cardThemeId).hasImage;

  @override
  Widget build(BuildContext context) {
    final sub = subscription;
    // Группы без подписки (цепочки, ручные серверы) картинки не имеют вовсе,
    // и выключенный тумблер оставляет от темы только цвета.
    if (!_showsImage(sub)) return child;
    final theme = resolveCardTheme(sub!.cardThemeId);

    // Радиус ровно карточный: рамки у группы больше нет, и «минус пиксель»,
    // которым от неё уходили, оставлял бы вдоль дуги полоску фона.
    const outer = ExpressiveShape.extraLarge;
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
          // Своя вуаль у подложки выключена: шапка кроет картинку сама, ниже.
          // Иначе слоя два, и «убрать затемнение» убирало бы только один.
          theme.background(context, veil: CardVeil.none),
          // Вуаль поверх картинки — та же роль, что у карточки подписки: слева
          // плотная (под заголовком), справа картинка открыта. Но цвет берётся
          // из фактического фона группы, уже подкрашенного акцентом, а не из
          // роли темы: иначе на стыке с первым сервером был бы виден шов.
          CardVeilOverlay(color: surface, veil: sub.cardVeil),
          // Растворение вниз. Начинается выше строки заголовка (на 0.72 от
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
          // Строка заголовка держится верха, а не центра всей области: иначе
          // полоса растворения утащила бы её вниз, и шапка перестала бы
          // совпадать по высоте с обычными группами.
          Align(
            alignment: Alignment.topCenter,
            // Высота ровно по содержимому шапки, включая строку «Авто».
            // Фиксированная высота строки заголовка обрезала бы её по нижней
            // границе: нарисована кнопка была видна (Stack не обрезает), а
            // нажатия до неё не доходили — попадание проверяется по границам
            // родителя, и за ними его нет.
            child: SizedBox(
              height: heightFor(sub, collapsed: collapsed),
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

/// боковое поле списка серверов; от него же считается ширина ячейки сетки
const _listSideInset = 16.0;

/// Как лягут серверы в группе.
///
/// Две колонки бывают двух видов. Строкой ряд читается, пока ячейке хватает
/// ширины: телефон боком, планшет, десктоп. На вертикальном телефоне её нет —
/// строка сжимала имя до «Росс…», — и там те же две колонки встают карточками.
enum _ServerListLayout {
  list,
  grid,
  cards;

  int get columns => this == list ? 1 : 2;

  double get gap =>
      this == cards ? ServerRow.cardGap : ExpressiveListSegment.gap;

  ServerRowLayout get rowLayout =>
      this == cards ? ServerRowLayout.card : ServerRowLayout.inline;

  static _ServerListLayout resolve({
    required bool twoColumns,
    required double width,
    required TextScaler textScaler,
  }) {
    if (!twoColumns) return list;
    // Ширина самого сегмента: минус поля списка и поля сегмента — полный
    // зазор у края группы и половина у соседа.
    final segment = (width - _listSideInset * 2) / 2 -
        ExpressiveListSegment.gap * 1.5;
    return ServerRow.fitsInline(segment, textScaler) ? grid : cards;
  }
}

/// Действия в шапке группы — XSmall-кнопка M3E: контейнер 32dp, глиф 20dp.
const _subCardHeaderIconSize = 32.0;
const _subCardHeaderActionGap = ExpressiveSpacing.small;
const _subCardHeaderIntervalGap = ExpressiveSpacing.small;

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


/// Шапка группы серверов: название, счётчики, сортировка, обновление, пинг.
///
/// Отдельный виджет, а не кусок общего `build()`: он сам подписан на то,
/// свёрнута ли группа, идёт ли обновление и не пингуется ли она — поэтому
/// вращение любой из этих кнопок перерисовывает шапку, а не всю группу вместе
/// со списком серверов под ней.
class _ServerGroupHeader extends ConsumerWidget {
  const _ServerGroupHeader({
    required this.subscription,
    required this.servers,
    required this.groupKey,
    required this.groupTitle,
    required this.onRefresh,
    required this.onPingAll,
    required this.accent,
  });

  final Subscription? subscription;
  final List<ServerItem> servers;
  final String? groupKey;
  final String? groupTitle;
  final Future<void> Function()? onRefresh;
  final Future<void> Function() onPingAll;

  /// Акцент подписки разрешается асинхронно в состоянии карточки, поэтому
  /// шапка его не вычисляет, а получает.
  final SubscriptionAccent? accent;

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
    // Иконки шапки и спиннеры уводим в цвет подписки — это те самые элементы,
    // что уже есть на её карточке (обновление, «12h»), и связь читается без
    // единого нового пикселя.
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
        child: SizedBox(
          height: _GroupHeaderBackground.heightFor(
            sub,
            collapsed: collapsed,
          ),
          child: _GroupHeaderBackground(
            subscription: sub,
            surface: groupColor,
            // Свёрнутая группа — это только шапка, и снизу у неё тоже
            // край карточки: не скругли мы его, картинка вылезла бы
            // прямыми углами из-под скруглённой рамки.
            collapsed: collapsed,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
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
                  padding: const EdgeInsetsDirectional.only(
                    start: ExpressiveSpacing.small,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (sub != null && sub.autoUpdate) ...[
                        // InkWell, а не GestureDetector: чип нажимается,
                        // и до сих пор об этом ничем не сообщал.
                        Material(
                          color: accentColor.withValues(alpha: 0.18),
                          // Маленькая метка-действие у M3E — пилюля,
                          // как и бейдж протокола в строке сервера.
                          shape: ExpressiveShape.border(
                            ExpressiveShape.full,
                          ),
                          child: InkWell(
                            onTap: () =>
                                showUpdateIntervalSheet(context, ref, sub),
                            customBorder: ExpressiveShape.border(
                              ExpressiveShape.full,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: ExpressiveSpacing.small,
                                vertical: ExpressiveSpacing.extraSmall,
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
                        onPressed: () => _serverGroupSortMenu(ref, 
                          context,
                          collapseKey,
                          sortMode,
                        ),
                        icon: Icon(
                          sortMode == ServerSortMode.defaultOrder
                              ? Icons.sort_rounded
                              : sortMode.icon,
                          size: ExpressiveIconSize.medium,
                          color: sortMode == ServerSortMode.defaultOrder
                              ? textLightColor
                              : accentColor,
                        ),
                      ),
                      const SizedBox(width: _subCardHeaderActionGap),
                      if (onRefresh != null) ...[
                        _subCardHeaderIconButton(
                          tooltip: AppLocalizations.of(
                            context,
                          )!.serversRefreshSubscription,
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
                              : Icon(
                                  Icons.refresh_rounded,
                                  size: ExpressiveIconSize.medium,
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
                            : Icon(
                                Icons.network_ping_rounded,
                                size: ExpressiveIconSize.medium,
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
                if (sub != null && sub.autoSelectVisible && !collapsed)
                  _AutoSelectRow(subscription: sub),
              ],
            ),
        ),
        ),
      ),
      );
  }
}

/// Строка с переключателем «Авто» под заголовком группы.
///
/// Кнопка-переключатель, а не чип: галочка у M3 Expressive осталась приёмом
/// фильтров, которые ходят наборами. Имя выбранного сервера здесь не пишется —
/// оно живёт в плашке под главной кнопкой и подсветкой строки в списке.
class _AutoSelectRow extends ConsumerWidget {
  const _AutoSelectRow({required this.subscription});

  final Subscription subscription;

  /// Включение — это сразу выбор сервера, а не обещание выбрать потом.
  ///
  /// Иначе переключатель горит, а подключение осталось на прежнем сервере:
  /// снаружи это «нажала, ничего не произошло». Выбранный отмечается в списке
  /// как обычно — разница с ручным выбором только в том, кто его сделал. «Авто»
  /// в других подписках при этом гаснет: сервер теперь выбирает эта.
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
    } catch (_) {
      // Ошибку показывать нечем — шапка группы не знает про снек-бар экрана,
      // а состояние подключения и так покраснеет под главной кнопкой.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return SizedBox(
      height: _GroupHeaderBackground.autoRowHeight,
      // Без вертикальных отступов: вся высота строки — зона нажатия кнопки,
      // сама она рисуется по центру своими 32dp.
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
  /// Своя пара «ключ + заголовок» для групп, которых нет среди подписок
  /// (цепочки). null — берётся из подписки, как раньше.
  final String? groupKey;
  final String? groupTitle;
  /// Раскладка и шаг строки приходят параметром сверху (см. _ServersListPanel):
  /// вотч настройки внутри карточки сломал бы кросс-фейд смены колонок, а
  /// ширину ячейки знает только список.
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
  /// подсветки — это то, как выглядит группа без своей темы.
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
    // Обновление, ошибка, пинг и заголовок здесь больше не нужны: на них
    // подписана сама шапка, и перерисовывается от них она одна.
    final activeServerId = ref.watch(
      serversProvider.select((s) => s.activeServerId),
    );

    // Где стоит активный сервер — для прыжка к нему с главного экрана.
    //
    // Пишем из build, а не из initState, как якорь группы: смещение строки
    // меняется от сортировки, числа колонок и от того, какой сервер активен, —
    // то есть ровно на тех перестроениях, что здесь и происходят. Запись
    // дешёвая (поле в реестре, без уведомлений), а расчёт живёт там, где
    // известна раскладка.
    final activeIndex = activeServerId == null
        ? -1
        : sortedServers.indexWhere((s) => s.id == activeServerId);
    if (activeIndex >= 0) {
      // Шаг строки общий с `mainAxisExtent` сетки, потому и считается одинаково.
      final row = activeIndex ~/ widget.layout.columns;
      ServerGroupAnchors.instance.registerActiveServer(
        serverId: activeServerId!,
        groupKey: collapseKey,
        offsetInGroup: collapsed
            ? null
            : _GroupHeaderBackground.heightFor(sub, collapsed: false) +
                // разделитель шапки и списка сегментов
                widget.layout.gap / 2 +
                row * widget.rowExtent,
      );
    } else {
      // Активного сервера в этой группе нет — если запись всё же наша, она
      // протухла (сервер удалили, перенесли, спрятал фильтр).
      ServerGroupAnchors.instance.unregisterActiveServer(collapseKey);
    }

    // кэшируем цвета, чтобы не дёргать Theme.of() на каждый вложенный виджет
    final accent = _accent;
    final scheme = Theme.of(context).colorScheme;
    // Группа — поверхность уровнем ниже своих сегментов.
    //
    // Раньше карточка группы и строки в ней были одного цвета, и разделить их
    // было нечем, кроме рамки. Иерархию в M3 несут уровни `surfaceContainer`:
    // перепад уровня и делает строки залитыми пунктами внутри контейнера, а не
    // полосами на нём.
    final groupColor = accent?.surface(scheme.surfaceContainerLow) ??
        scheme.surfaceContainerLow;
    final textLightColor = AppTheme.textLight(context);

    // Sliver-карточка: DecoratedSliver рисует фон/рамку/тень на всю длину
    // группы (включая невидимую часть), а тайлы строятся лениво SliverList'ом.
    return DecoratedSliver(
      // Заливка и форма — и всё. Здесь стояли одновременно рамка, тень и
      // заливка, то есть три варианта карточки M3 сразу (outlined + elevated +
      // filled); ни один контейнер приложения так больше не выглядит, и именно
      // это делало список серверов «вставленным из другого приложения».
      decoration: BoxDecoration(
        color: groupColor,
        // Группа серверов — «поверхность», а не карточка: extraLarge, заметно
        // крупнее 16dp у сегментов внутри.
        borderRadius: ExpressiveShape.radius(ExpressiveShape.extraLarge),
      ),
      sliver: SliverPadding(
        // Снизу — вторая половина зазора последнего сегмента (первую он
        // отступает сам), чтобы поля группы были одинаковы со всех сторон.
        padding: EdgeInsets.only(
          bottom: collapsed ? 0 : widget.layout.gap / 2,
        ),
        sliver: SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              // Шапка — цель прыжка из бокового навигатора. Именно она, а не
              // сама sliver-карточка: `SliverToBoxAdapter` строит и раскладывает
              // ребёнка всегда, даже когда группа далеко за экраном, так что у
              // якоря есть живой render object и посчитанное смещение.
              child: _ServerGroupHeader(
                subscription: widget.subscription,
                servers: widget.servers,
                groupKey: widget.groupKey,
                groupTitle: widget.groupTitle,
                onRefresh: widget.onRefresh,
                onPingAll: widget.onPingAll,
                accent: _accent,
              ),
            ),

            // Первая половина зазора между шапкой и верхним сегментом: вторую
            // сегмент отступает сам, и вместе выходит ровно зазор раскладки —
            // столько же, сколько между сегментами.
            if (!collapsed)
              SliverToBoxAdapter(
                child: SizedBox(height: widget.layout.gap / 2),
              ),

            // Свёрнутая группа — просто без sliver'а тайлов. Никакого
            // AnimatedSize вокруг: он требует построить все тайлы разом и
            // несовместим с ленивым sliver-построением (анимируется шеврон).
            if (!collapsed)
              _buildExpandedServerList(
                servers: sortedServers,
                activeServerId: activeServerId,
                textLightColor: textLightColor,
                accent: accent,
              ),
          ],
        ),
      ),
    );
  }

  /// Sliver с тайлами: SliverList.builder строит только видимые в viewport,
  /// чтобы раскрытая группа на сотни серверов не собирала все тайлы разом.
  /// В две колонки — SliverGrid, строится так же лениво.
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

    // Форму и поля сегмента считает список: только он знает, где у тайла сосед,
    // а где край группы. Нечётный хвост в сетке при этом получается сам собой —
    // у одинокой нижней плитки справа не сосед, а фон группы.
    final layout = widget.layout;
    final columns = layout.columns;
    Widget tileAt(int index) {
      final server = servers[index];
      return _ServerTile(
        key: ValueKey(server.id),
        server: server,
        isActive: server.id == activeServerId,
        layout: layout.rowLayout,
        height: widget.rowExtent,
        accent: accent,
        radius: layout == _ServerListLayout.cards
            // Карточки сетки одинаковы, 12dp по спеке карточек. Форма по месту
            // — приём вертикального списка: в два ряда 4dp-стыки с соседями
            // читались случайным набором углов. У угла группы поле с 8dp
            // сужается до пяти, но карточка остаётся внутри её дуги.
            ? ExpressiveShape.radius(ExpressiveShape.medium)
            : ExpressiveListSegment.segmentRadius(
                index: index,
                count: servers.length,
                columns: columns,
                // Низ последнего ряда упирается в скруглённый угол карточки
                // группы, и радиус там обязан быть концентричным её
                // собственному: тот же центр дуги, поле по 4dp со всех сторон.
                // Со спековыми 16dp поле на углу схлопывалось, и последний
                // сервер выпирал за край списка.
                endCorner:
                    ExpressiveShape.extraLarge - ExpressiveListSegment.gap,
              ),
        margin: ExpressiveListSegment.segmentMargin(
          index: index,
          columns: columns,
          spacing: layout.gap,
        ),
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
          // _ServerTile сам оборачивается в RepaintBoundary — не дублируем.
          addRepaintBoundaries: false,
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => tileAt(index),
        childCount: servers.length,
        addAutomaticKeepAlives: false,
        // _ServerTile сам оборачивается в RepaintBoundary — не дублируем.
        addRepaintBoundaries: false,
      ),
    );
  }

  /// Долгое нажатие на шапку группы → выбор сортировки серверов.
}
