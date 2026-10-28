part of 'liquid_nav.dart';

// Модерн боком: та же лента стоит у края экрана, стрелка вытекает из верхнего конца,
// кнопка действия из нижнего
class LiquidSideNav extends StatefulWidget {
  const LiquidSideNav({
    super.key,
    required this.index,
    required this.onTap,
    required this.showConnectedBadge,
    required this.style,
    this.pages,
  });

  final int index;
  final bool showConnectedBadge;
  final void Function(int) onTap;
  final LiquidBarStyle style;
  final PageController? pages;

  // столько же, сколько у прежней боковой панели
  static const double width = FloatingBar.margin * 2 + FloatingBar.height;

  @override
  State<LiquidSideNav> createState() => _LiquidSideNavState();
}

const double _railTab = 56;
const double _railGrow = 28;

class _LiquidSideNavState extends State<LiquidSideNav>
    with TickerProviderStateMixin {
  late final List<AnimationController> _ctrls = List.generate(
    _count,
    (i) => AnimationController.unbounded(
      vsync: this,
      value: widget.index == i ? 1 : 0,
    ),
  );

  late final AnimationController _jumpIn = AnimationController(
    vsync: this,
    value: FloatingBar.jump.value == null ? 0 : 1,
  );
  late FloatingJump? _jump = FloatingBar.jump.value;

  final ui.FragmentShader? _shader = FloatingBar.newBarShader();

  late final AnimationController _grab = AnimationController.unbounded(vsync: this);
  final _finger = ValueNotifier<double>(0);
  int? _hover;
  var _grabbing = false;
  List<Rect> _tabRects = const [];

  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  double _waveY = 0;

  @override
  void initState() {
    super.initState();
    FloatingBar.jump.addListener(_onJump);
  }

  void _onJump() {
    final jump = FloatingBar.jump.value;
    if (jump != null) _jump = jump;
    ExpressiveMotion.springTo(
      _jumpIn,
      jump == null ? 0 : 1,
      spring: jump == null
          ? _LiquidBottomNavState._sinkSpring
          : ExpressiveMotion.spatialSlow,
    );
  }

  @override
  void didUpdateWidget(LiquidSideNav old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;
    for (var i = 0; i < _count; i++) {
      ExpressiveMotion.springTo(
        _ctrls[i],
        widget.index == i ? 1 : 0,
        spring: _LiquidBottomNavState._switchSpring,
      );
    }
  }

  @override
  void dispose() {
    FloatingBar.jump.removeListener(_onJump);
    for (final c in _ctrls) {
      c.dispose();
    }
    _jumpIn.dispose();
    _grab.dispose();
    _wave.dispose();
    _finger.dispose();
    _shader?.dispose();
    super.dispose();
  }

  int? _tabAt(double y) {
    int? best;
    var bestGap = double.infinity;
    for (var i = 0; i < _tabRects.length; i++) {
      final r = _tabRects[i];
      final gap = y < r.top ? r.top - y : (y > r.bottom ? y - r.bottom : 0.0);
      if (gap < bestGap) {
        bestGap = gap;
        best = i;
      }
    }
    return best;
  }

  double _localY(Offset global) =>
      (context.findRenderObject()! as RenderBox).globalToLocal(global).dy;

  void _grabStart(LongPressStartDetails details) {
    _grabbing = true;
    _finger.value = _localY(details.globalPosition);
    _hover = _tabAt(_finger.value);
    AppHaptics.impact();
    ExpressiveMotion.springTo(_grab, 1);
  }

  void _grabMove(LongPressMoveUpdateDetails details) {
    _finger.value = _localY(details.globalPosition);
    final hover = _tabAt(_finger.value);
    if (hover == _hover) return;
    _hover = hover;
    AppHaptics.selection();
  }

  void _grabEnd() {
    if (!_grabbing) return;
    _grabbing = false;
    final hover = _hover;
    _hover = null;
    if (hover != null && hover != widget.index) widget.onTap(hover);
    _waveY = _finger.value;
    _wave.forward(from: 0);
    ExpressiveMotion.springTo(_grab, 0, spring: _LiquidBottomNavState._sinkSpring);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final items = appNavDestinations(
      l10n,
      showConnectedBadge: widget.showConnectedBadge,
    );
    final padding = MediaQuery.paddingOf(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final edge = rtl ? padding.right : padding.left;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final look = _Look.of(widget.style);
    final pages = widget.pages;
    const thick = FloatingBar.height;
    final jumpLength = look.strip ? 52.0 : thick;
    final plusLength = look.strip ? 60.0 : thick;
    return SizedBox(
      width: edge + LiquidSideNav.width,
      child: LayoutBuilder(
        builder: (context, box) => AnimatedBuilder(
          animation: Listenable.merge(
            [..._ctrls, _jumpIn, _grab, _wave, _finger, ?pages],
          ),
          builder: (context, _) {
            final width = box.maxWidth;
            final ts = [for (final c in _ctrls) c.value.clamp(0.0, 1.0)];
            final page = _pageOf(pages, widget.index);
            final absorbed = _LiquidBottomNavState._absorbedByPage(page);
            final jumpT = _jumpIn.value.clamp(0.0, 1.0);

            final lengths = [
              for (final c in _ctrls) _railTab + c.value.clamp(-0.25, 1.25) * _railGrow,
            ];
            final stripLength =
                lengths.fold(0.0, (a, b) => a + b) + _seam * (_count - 1);
            final x = edge + FloatingBar.margin;
            const centerX = thick / 2;
            final above = (jumpLength + look.sideGap) *
                (1 - (page - _jumpTab).abs().clamp(0.0, 1.0));
            final below = (plusLength + look.sideGap) * (1 - absorbed);
            final topLimit = padding.top + FloatingBar.margin;
            final bottomLimit = box.maxHeight - padding.bottom - FloatingBar.margin;
            final top = math.min(
              math.max((topLimit + bottomLimit - stripLength) / 2, topLimit + above),
              bottomLimit - below - stripLength,
            );
            Rect place(double l, double t, double w, double h) =>
                Rect.fromLTWH(rtl ? width - l - w : l, t, w, h);

            final tabs = <Rect>[];
            final radii = <(double, double)>[];
            var y = top;
            for (var i = 0; i < _count; i++) {
              tabs.add(place(x, y, thick, lengths[i]));
              var a = _inner;
              var b = _inner;
              if (i == 0) a = look.strip ? _lerp(_outer, _inner, jumpT) : _outer;
              if (i == _count - 1) {
                b = look.strip ? _lerp(_inner, _outer, absorbed) : _outer;
              }
              radii.add((_lerp(a, _outer, ts[i]), _lerp(b, _outer, ts[i])));
              y += lengths[i] + _seam;
            }
            final stripBottom = top + stripLength;
            _tabRects = List.of(tabs);
            final strip = tabs.reduce((a, b) => a.expandToInclude(b));

            final grab = _grab.value.clamp(0.0, 1.0);
            final finger = _finger.value.clamp(strip.top + 24, strip.bottom - 24);
            final hovers = [
              for (final r in tabs)
                grab *
                    math.exp(
                      -math.pow(
                            math.max(0, math.max(r.top - finger, finger - r.bottom)),
                            2,
                          ) /
                          (2 * 18 * 18),
                    ),
            ];
            // от края экрана к списку
            final away = rtl ? -1.0 : 1.0;
            for (var i = 0; i < _count; i++) {
              final c = tabs[i].center.dy;
              var dx = 0.0;
              var dy = 0.0;
              if (grab > 0) {
                final d = finger - c;
                final pull = math.exp(-(d * d) / (2 * 70 * 70));
                dy += grab * pull * d * 0.12;
                dx += away * grab * pull * 5;
              }
              if (_wave.isAnimating) {
                final tau = _wave.value * 1.1 - (c - _waveY).abs() / 700;
                if (tau > 0) dx += away * 7 * math.exp(-tau * 6) * math.sin(tau * 18);
              }
              tabs[i] = tabs[i].translate(dx, dy);
            }
            final bumpLtr = Rect.fromLTRB(
              x + centerX,
              finger - 32 * grab,
              x + thick + 14 * grab,
              finger + 32 * grab,
            );
            final bump = grab > 0.01
                ? place(bumpLtr.left, bumpLtr.top, bumpLtr.width, bumpLtr.height)
                : Rect.zero;

            final budOut = Rect.fromLTWH(x, stripBottom + look.sideGap, thick, plusLength);
            final budInside = Rect.fromCenter(
              center: Offset(x + centerX, stripBottom - 20),
              width: 0,
              height: 0,
            );
            final budLtr = Rect.lerp(budOut, budInside, absorbed)!;
            final bud = place(budLtr.left, budLtr.top, budLtr.width, budLtr.height);
            final budScale = budLtr.width / thick;
            final budRadii = look.strip
                ? (_inner * budScale, _outer * budScale)
                : (_Look.islandRadius * budScale, _Look.islandRadius * budScale);

            final jumpOut = Rect.fromLTWH(
              x,
              top - look.sideGap - jumpLength,
              thick,
              jumpLength,
            );
            final jumpInside = Rect.fromCenter(
              center: Offset(x + centerX, top + 20),
              width: 0,
              height: 0,
            );
            final jumpLtr = Rect.lerp(jumpInside, jumpOut, jumpT)!;
            final jump = place(jumpLtr.left, jumpLtr.top, jumpLtr.width, jumpLtr.height);
            final jumpScale = jumpLtr.width / thick;
            final jumpRadii = look.strip
                ? (_outer * jumpScale, _inner * jumpScale)
                : (_Look.islandRadius * jumpScale, _Look.islandRadius * jumpScale);

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _LiquidBarPainter(
                      shader: _shader,
                      tabs: tabs,
                      tabRadii: radii,
                      bud: absorbed < 1 ? bud : Rect.zero,
                      budRadii: budRadii,
                      jump: jumpT > 0.01 ? jump : Rect.zero,
                      jumpRadii: jumpRadii,
                      absorbed: absorbed,
                      jumpT: jumpT,
                      baseColor: FloatingBar.tileColor(cs),
                      budColor: cs.tertiary,
                      jumpColor: cs.secondaryContainer,
                      sideL: Rect.zero,
                      sideLRadii: (0, 0),
                      sideR: Rect.zero,
                      sideRRadii: (0, 0),
                      sideT: 0,
                      sideLColor: FloatingBar.tileColor(cs),
                      finger: bump,
                      fingerGoo: 24 * grab,
                      dpr: dpr,
                      vertical: true,
                    ),
                  ),
                ),
                for (var i = 0; i < _count; i++)
                  Positioned.fromRect(
                    rect: tabs[i],
                    child: _RailTab(
                      icon: items[i].icon,
                      label: items[i].label,
                      badge: items[i].badge,
                      selected: widget.index == i,
                      t: ts[i],
                      hover: hovers[i],
                      onTap: () {
                        if (i != widget.index) AppHaptics.selection();
                        widget.onTap(i);
                      },
                    ),
                  ),
                if (absorbed < 1)
                  Positioned.fromRect(
                    rect: bud,
                    child: IgnorePointer(
                      ignoring: absorbed > 0.5,
                      child: _Drop(
                        icon: Icons.add_rounded,
                        size: 28 * budScale,
                        opacity: (1 - 2 * absorbed).clamp(0.0, 1.0),
                        color: cs.onTertiary,
                        radius: budRadii.$2,
                        onTap: () => FloatingBar.actions[widget.index]?.call(),
                      ),
                    ),
                  ),
                Positioned.fromRect(
                  rect: strip,
                  child: RawGestureDetector(
                    behavior: HitTestBehavior.translucent,
                    gestures: {
                      LongPressGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                              LongPressGestureRecognizer>(
                        () => LongPressGestureRecognizer(
                          duration: const Duration(milliseconds: 300),
                          debugOwner: this,
                        ),
                        (r) {
                          r
                            ..onLongPressStart = _grabStart
                            ..onLongPressMoveUpdate = _grabMove
                            ..onLongPressEnd = ((_) => _grabEnd())
                            ..onLongPressCancel = _grabEnd;
                        },
                      ),
                    },
                    child: const SizedBox.expand(),
                  ),
                ),
                if (jumpT > 0.01)
                  Positioned.fromRect(
                    rect: jump,
                    child: IgnorePointer(
                      ignoring: jumpT < 0.5,
                      child: _Drop(
                        icon: Icons.arrow_downward_rounded,
                        turns: (_jump?.up ?? false) ? 0.5 : 0,
                        size: 26 * jumpScale,
                        opacity: ((jumpT - 0.4) / 0.6).clamp(0.0, 1.0),
                        color: cs.onSecondaryContainer,
                        radius: jumpRadii.$1,
                        onTap: () => _jump?.onTap(),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// подпись под значком: в ряд при ширине ленты 64 dp ей негде встать
class _RailTab extends StatelessWidget {
  const _RailTab({
    required this.icon,
    required this.label,
    required this.badge,
    required this.selected,
    required this.t,
    required this.hover,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool badge;
  final bool selected;
  final double t;
  final double hover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const shape = StadiumBorder();
    final reveal = (t / 0.9).clamp(0.0, 1.0);
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: Material(
        color: Color.lerp(Colors.transparent, cs.primary, t),
        shape: shape,
        clipBehavior: Clip.antiAlias,
        animationDuration: Duration.zero,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: Center(
            child: Transform.scale(
              scale: 1 + 0.12 * hover,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  NavIcon(
                    icon: icon,
                    badge: badge,
                    color: Color.lerp(cs.onSurface, cs.onPrimary, t)!,
                  ),
                  ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: reveal,
                      child: Opacity(
                        opacity: t,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: SizedBox(
                            width: FloatingBar.height - 12,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                label,
                                style: theme.textTheme.labelMedium
                                    ?.copyWith(color: cs.onPrimary),
                                maxLines: 1,
                                softWrap: false,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
