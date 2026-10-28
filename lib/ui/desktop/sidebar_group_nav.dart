import 'dart:async';
import 'dart:math' as math;

import 'package:androidx_graphics_shapes/material_shapes.dart';
import 'package:androidx_graphics_shapes/shapes.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/server_group.dart';
import '../../models/subscription_card_theme.dart';
import '../../providers/providers.dart';
import '../../shared/ui/server_group_anchors.dart';
import '../../shared/ui/expressive.dart';
import '../../tunnel/tunnel_state.dart';

// быстрый переход каруселью M3 (hero по центру): большая обложка группы, на которой стоит список,
// края соседних сверху и снизу. карусель едет за прокруткой списка
class SidebarGroupNav extends ConsumerStatefulWidget {
  const SidebarGroupNav({
    super.key,
    required this.labels,
    required this.onOpenServers,
  });

  // подписи гаснут вместе со сворачиванием панели
  final double labels;

  final VoidCallback onOpenServers;

  @override
  ConsumerState<SidebarGroupNav> createState() => _SidebarGroupNavState();
}

class _SidebarGroupNavState extends ConsumerState<SidebarGroupNav> {
  static const _weights = [1, 6, 1];

  final _carousel = _CoverController();
  List<ServerGroupRef> _groups = const [];
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    ServerGroupAnchors.instance.currentGroup.addListener(_follow);
  }

  @override
  void dispose() {
    ServerGroupAnchors.instance.currentGroup.removeListener(_follow);
    _settle?.cancel();
    _carousel.dispose();
    super.dispose();
  }

  void _follow() {
    final key = ServerGroupAnchors.instance.currentGroup.value;
    final i = _groups.indexWhere((g) => g.key == key);
    // пока колесо крутят, список стоит на прежней группе и тянул бы карусель назад
    if (i < 0 || i == _shown || _settle != null || _jumps > 0) return;
    _go(i);
  }

  // список едет к группе анимацией через промежуточные, и карусель откатывалась за ним:
  // пролистанная обложка вспухала и сжималась
  int _jumps = 0;

  void _go(int i, {Duration duration = const Duration(milliseconds: 520)}) {
    _shown = i;
    _target = i;
    unawaited(_carousel.animateToItem(i, duration: duration, curve: Curves.easeOutCubic));
  }

  // moveCarousel: false, когда карусель уже едет туда сама (колесо, тяга)
  void _open(int i, {bool moveCarousel = true}) {
    final key = _groups[i].key;
    widget.onOpenServers();
    if (moveCarousel) {
      _go(i);
    } else {
      _shown = i;
      _target = i;
    }
    final before = ServerGroupAnchors.instance.currentGroup.value;
    // сразу, а не в кадре прыжка: пересборка до него сверяла карусель со старой группой списка
    _jumps++;
    // список мог ещё ни разу не строиться, прыгаем после кадра, когда якоря на месте
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ServerGroupAnchors.instance.jumpTo(key);
      } finally {
        _jumps--;
      }
      // прыжок перебили прокруткой списка: карусель встаёт туда, где он остановился
      if (mounted && ServerGroupAnchors.instance.currentGroup.value != before) _follow();
    });
    // на уже открытой вкладке кадр никто не просит, и после тяги список ждал движения мыши
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  double _wheel = 0;
  int _target = 0;
  Timer? _settle;
  bool _dragging = false;

  // своя прокрутка карусели после каждого щелчка доводилась до ближайшей обложки и дёргалась
  // туда-обратно. щелчок (в Windows 100 пикселей при трёх строках) = шаг сразу, без ожидания
  // анимации; список догоняет один раз, когда колесо остановилось
  void _onWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final dy = (event as PointerScrollEvent).scrollDelta.dy;
      if (dy == 0) return;
      if (_wheel.sign != dy.sign) _wheel = 0;
      _wheel += dy;
      if (_wheel.abs() < 40) return;
      final next = (_target + (_wheel > 0 ? 1 : -1)).clamp(0, _groups.length - 1);
      _wheel = 0;
      if (next == _target) return;
      _target = next;
      _springTo(next);
      _settle?.cancel();
      _settle = Timer(const Duration(milliseconds: 260), () {
        _settle = null;
        if (mounted && _target != _shown) _open(_target, moveCarousel: false);
      });
    });
  }

  static final _wheelSpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 160, ratio: 1);
  _SpringActivity? _spring;

  double _unit(ScrollPosition position) =>
      position.viewportDimension * _weights.first / _weights.reduce((a, b) => a + b);

  // с каждым щелчком пружина подхватывает текущую скорость: animateToItem начинал с места,
  // и пролистанная обложка на торможении успевала вспухнуть и сжаться обратно
  void _springTo(int index) {
    if (!_carousel.hasClients) return;
    final position = _carousel.position;
    if (position is! ScrollPositionWithSingleContext) return;
    final target = (_unit(position) * index)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    final activity = _SpringActivity(
      position,
      ScrollSpringSimulation(_wheelSpring, position.pixels, target, _spring?.velocity ?? 0),
      position.context.vsync,
      onDisposed: (a) {
        if (identical(_spring, a)) _spring = null;
      },
    );
    _spring = activity;
    position.beginActivity(activity);
  }

  // высота карусели известна только после раскладки: до неё надпись не знала, куда опуститься
  double? _viewport;

  bool _onMetrics(ScrollMetricsNotification n) {
    if (n.depth == 0 && n.metrics.viewportDimension != _viewport) {
      setState(() => _viewport = n.metrics.viewportDimension);
    }
    return false;
  }

  // мышкой карусель тянут как пальцем: где осела, туда и список
  bool _onCarouselScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is ScrollStartNotification && n.dragDetails != null) _dragging = true;
    if (n is ScrollEndNotification && _dragging) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_dragging || !_carousel.hasClients) return;
        final position = _carousel.position;
        if (position.isScrollingNotifier.value) return;
        _dragging = false;
        final i = (position.pixels / _unit(position)).round().clamp(0, _groups.length - 1);
        if (i != _shown) _open(i, moveCarousel: false);
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(serversProvider.select((s) => s.servers));
    final activeId = ref.watch(serversProvider.select((s) => s.activeServerId));
    final subs = ref.watch(subscriptionsProvider).value ?? const [];
    final connected = ref.watch(
      vpnStateProvider.select((a) => a.value?.status == VpnStatus.connected),
    );

    _groups = buildServerGroups(servers: servers, subscriptions: subs);
    if (_groups.length < 2) return const SizedBox.shrink();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _follow();
    });

    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final labels = widget.labels.clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (labels > 0.01)
          // над первой группой пустой край под предыдущую: надпись опускается к обложке
          AnimatedBuilder(
            animation: _carousel,
            builder: (context, child) {
              var shift = 0.0;
              if (_carousel.hasClients && _carousel.position.hasContentDimensions) {
                final unit = _unit(_carousel.position);
                shift = unit * (1 - (_carousel.position.pixels / unit).clamp(0.0, 1.0));
              }
              return Transform.translate(offset: Offset(0, shift), child: child);
            },
            child: ClipRect(
              child: Align(
                alignment: AlignmentDirectional.topStart,
                heightFactor: labels,
                child: Opacity(
                  opacity: labels,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 8),
                    child: Text(
                      l10n.sidebarJumpTitle,
                      maxLines: 1,
                      softWrap: false,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        Expanded(
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: _onMetrics,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onCarouselScroll,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      // полоса прокрутки, которую Flutter на ПК ставит сам, у карусели елозила сбоку
                      scrollbars: false,
                      physics: const ClampingScrollPhysics(),
                      dragDevices: const {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.stylus,
                        PointerDeviceKind.invertedStylus,
                        PointerDeviceKind.trackpad,
                        PointerDeviceKind.mouse,
                      },
                    ),
                    child: _RelayoutAfterRebuild(
                      child: CarouselView.weighted(
                        controller: _carousel,
                        scrollDirection: Axis.vertical,
                        // при [6, 1] последняя группа во Flutter 3.44 не становится большой: прокрутка упирается в конец.
                        // по кругу не крутим: список не круговой, и прыжок с последней на первую путал
                        flexWeights: _weights,
                        itemSnapping: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        backgroundColor: scheme.surfaceContainerHigh,
                        // картинка и затемнение сглаживались по краю каждое само, и край светился
                        // полоской. сперва слой, потом скругление; фон обложки шире её на 1 dp
                        itemClipBehavior: Clip.antiAliasWithSaveLayer,
                        onTap: _open,
                        children: [
                          for (final group in _groups)
                            _GroupCover(
                              group: group,
                              title: _titleFor(group, l10n),
                              labels: labels,
                              through: connected && group.servers.any((s) => s.id == activeId),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // колесо забираем поверх карусели, раньше её Scrollable: тянуть и нажимать
                  // сквозь этот слой можно, у Flutter прокрутка колесом и тяга разрешаются вместе
                  Positioned.fill(
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerSignal: _onWheel,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _titleFor(ServerGroupRef group, AppLocalizations l10n) =>
      switch (group.kind) {
        ServerGroupKind.chains => l10n.chainGroupTitle,
        ServerGroupKind.manual => l10n.serversManualGroup,
        ServerGroupKind.subscription => group.subscriptionName.isEmpty
            ? l10n.serversManualGroup
            : group.subscriptionName,
      };
}

class _GroupCover extends StatelessWidget {
  const _GroupCover({
    required this.group,
    required this.title,
    required this.labels,
    required this.through,
  });

  final ServerGroupRef group;
  final String title;
  final double labels;
  // подключено через сервер из этой группы
  final bool through;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final themeId = group.subscription?.cardThemeId ?? '';
    final theme = themeId.isEmpty ? null : resolveCardTheme(themeId);
    final picture = theme != null && !theme.isPlain;
    final colors = _coverColors(scheme, group);
    final onCover = picture ? Colors.white : colors.on;
    final count = group.servers.length;
    final titleStyle = textTheme.emphasized(textTheme.titleSmall)?.copyWith(color: onCover);
    final line = MediaQuery.textScalerOf(context).scale(titleStyle?.fontSize ?? 14) *
        (titleStyle?.height ?? 20 / 14);

    return Semantics(
      label: '$title, $count',
      child: LayoutBuilder(
        builder: (context, box) {
          // на узкой обложке подпись посередине, на большой у нижнего края
          final bottom = math.min(14.0, (box.maxHeight - line) / 2);
          final text = labels * ((box.maxHeight - line) / 12).clamp(0.0, 1.0);
          return Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                left: -1,
                top: -1,
                right: -1,
                bottom: -1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (picture)
                      // обложка не сжимается вместе с элементом, а обрезается: так в спеке
                      OverflowBox(
                        maxHeight: math.max(box.maxHeight + 2, 320),
                        child: theme.background(context, veil: CardVeil.medium),
                      )
                    else
                      CustomPaint(
                        painter: _DefaultCoverPainter(
                          seed: _stableHash(group.key),
                          kind: group.kind,
                          colors: colors,
                        ),
                      ),
                    if (picture)
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.center,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x00000000), Color(0x8C000000)],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (text > 0.01)
                PositionedDirectional(
                  start: 16,
                  end: 14,
                  bottom: bottom,
                  child: Opacity(
                    opacity: text,
                    child: Row(
                      children: [
                        if (through) ...[
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: onCover,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.fade,
                            style: titleStyle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$count',
                          style: textTheme.labelMedium?.copyWith(
                            color: onCover.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// String.hashCode между запусками не обещан, а обложка подписки должна быть всегда одной
int _stableHash(String s) {
  var h = 17;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return h;
}

typedef _CoverColors = ({Color background, Color shape, Color on});

_CoverColors _coverColors(ColorScheme cs, ServerGroupRef group) {
  final subscriptions = <_CoverColors>[
    (background: cs.primaryContainer, shape: cs.primary, on: cs.onPrimaryContainer),
    (background: cs.tertiaryContainer, shape: cs.tertiary, on: cs.onTertiaryContainer),
  ];
  // свои серверы и цепочки нейтральные, чтобы не путались с подписками
  return switch (group.kind) {
    ServerGroupKind.subscription => subscriptions[_stableHash(group.key) % subscriptions.length],
    _ => (background: cs.secondaryContainer, shape: cs.secondary, on: cs.onSecondaryContainer),
  };
}

final _softShapes = [
  MaterialShapes.cookie9Sided,
  MaterialShapes.sunny,
  MaterialShapes.clover4Leaf,
  MaterialShapes.flower,
  MaterialShapes.softBurst,
  MaterialShapes.puffy,
  MaterialShapes.cookie12Sided,
];
final _sharpShapes = [
  MaterialShapes.gem,
  MaterialShapes.slanted,
  MaterialShapes.square,
  MaterialShapes.arch,
  MaterialShapes.pentagon,
  MaterialShapes.triangle,
];
final _shapePaths = <RoundedPolygon, Path>{};

// обложка группы без картинки: крупная мягкая форма M3 срезана краем, маленькая острая с другой
// стороны, не касаясь её. по спеке M3E абстрактные формы уместны в декоративной графике
class _DefaultCoverPainter extends CustomPainter {
  _DefaultCoverPainter({required this.seed, required this.kind, required this.colors});

  final int seed;
  final ServerGroupKind kind;
  final _CoverColors colors;

  void _shape(Canvas canvas, RoundedPolygon polygon, Offset center, double side, double turns, Color color) {
    final path = _shapePaths.putIfAbsent(polygon, polygon.toPath);
    final bounds = path.getBounds();
    final scale = side / math.max(bounds.width, bounds.height);
    final matrix = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..rotateZ(turns * 2 * math.pi)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-bounds.center.dx, -bounds.center.dy, 0, 1);
    canvas.drawPath(path.transform(matrix.storage), Paint()..color = color);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.background);
    final w = size.width;
    // от меньшей стороны: большая обложка в карусели почти квадратная, и формы иначе наезжали
    final m = math.min(w, size.height);
    final soft = switch (kind) {
      ServerGroupKind.manual => MaterialShapes.puffy,
      ServerGroupKind.chains => MaterialShapes.clover8Leaf,
      ServerGroupKind.subscription => _softShapes[(seed ~/ 3) % _softShapes.length],
    };
    final sharp = switch (kind) {
      ServerGroupKind.manual => MaterialShapes.slanted,
      ServerGroupKind.chains => MaterialShapes.gem,
      ServerGroupKind.subscription => _sharpShapes[(seed ~/ 21) % _sharpShapes.length],
    };
    final flip = (seed ~/ 7).isOdd;
    _shape(
      canvas,
      soft,
      Offset(flip ? w * 0.15 : w * 0.85, m * 0.1),
      m * 0.9,
      (seed % 12) / 12,
      Color.alphaBlend(colors.shape.withValues(alpha: 0.30), colors.background),
    );
    _shape(
      canvas,
      sharp,
      // выше подписи: светлая форма под светлым текстом его съедала
      Offset(flip ? w * 0.73 : w * 0.27, size.height - 40 - m * 0.2),
      m * 0.32,
      ((seed ~/ 5) % 8) / 8,
      colors.shape.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(_DefaultCoverPainter old) =>
      old.seed != seed || old.kind != kind || old.colors != colors;
}

// смещение карусели на 1/8 высоты уже меняет большую обложку целиком (6 весов против 1):
// мышь тянула её в шесть раз резвее, чем шла сама, а бросок проскакивал соседнюю обложку.
// снаружи CarouselScrollPhysics, иначе до её доводки скорость не доходит поделённой
class _CoverController extends CarouselController {
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) =>
      super.createScrollPosition(_CoverDragPhysics(parent: physics), context, oldPosition);
}

class _CoverDragPhysics extends ScrollPhysics {
  const _CoverDragPhysics({super.parent});

  @override
  _CoverDragPhysics applyTo(ScrollPhysics? ancestor) =>
      _CoverDragPhysics(parent: buildParent(ancestor));

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) =>
      super.applyPhysicsToUserOffset(position, offset) / 6;

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) =>
      super.createBallisticSimulation(position, velocity / 6);
}

// SliverMultiBoxAdaptorElement на каждой пересборке ставит первому элементу смещение 0, а у карусели над
// первой обложкой пустое место (consumeMaxWeight): без новой раскладки она наезжала на надпись
class _RelayoutAfterRebuild extends SingleChildRenderObjectWidget {
  const _RelayoutAfterRebuild({required super.child});

  @override
  RenderProxyBox createRenderObject(BuildContext context) => RenderProxyBox();

  @override
  void updateRenderObject(BuildContext context, RenderProxyBox renderObject) {
    void visit(RenderObject child) {
      if (child is RenderSliverMultiBoxAdaptor) {
        child.markNeedsLayout();
      } else {
        child.visitChildren(visit);
      }
    }

    renderObject.visitChildren(visit);
  }
}

// своя, а не BallisticScrollActivity: та на каждом пересчёте размеров карусели перезапускала
// доводку, бросала цель и прилипала к ближайшей обложке (второй щелчок колеса терялся)
class _SpringActivity extends ScrollActivity {
  _SpringActivity(
    super.delegate,
    this._simulation,
    TickerProvider vsync, {
    required this.onDisposed,
  }) {
    _ticker = vsync.createTicker(_tick)..start();
  }

  final Simulation _simulation;
  final void Function(_SpringActivity) onDisposed;
  late final Ticker _ticker;
  double _time = 0;

  void _tick(Duration elapsed) {
    _time = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    delegate.setPixels(_simulation.x(_time));
    if (_simulation.isDone(_time)) delegate.goBallistic(0);
  }

  @override
  bool get shouldIgnorePointer => false;

  @override
  bool get isScrolling => true;

  @override
  double get velocity => _simulation.dx(_time);

  @override
  void dispose() {
    onDisposed(this);
    _ticker.dispose();
    super.dispose();
  }
}
