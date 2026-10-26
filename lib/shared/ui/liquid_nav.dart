import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/shared/ui/bottom_nav.dart';
import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:keqdroid/shared/ui/floating_bar.dart';
import 'package:keqdroid/shared/ui/haptics.dart';

// навигация Модерна: лента вкладок, кнопка действия, стрелка прокрутки и нижний край
// рисуются одной жидкостью. кнопка и стрелка отпочковываются от концов ленты, при прокрутке
// вниз лента каплей уходит в край
class LiquidBottomNav extends StatefulWidget {
  const LiquidBottomNav({
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

  // по положению страниц кнопка втекает в ленту на вкладке без действия
  final PageController? pages;

  @override
  State<LiquidBottomNav> createState() => _LiquidBottomNavState();

  // ширина ленты в покое с раскрытым пунктом label: по ней раскладывается то, что стоит рядом
  static double restWidth(BuildContext context, String label) =>
      _tabWidth * _count + _grow + _labelWidth(context, label) + _seam * (_count - 1);

  static double sideGap(LiquidBarStyle style) => _Look.of(style).sideGap;

}

const int _count = 3;
const int _settings = 2;
// стрелка прокрутки есть только у списка серверов
const int _jumpTab = 0;
const double _tabWidth = 60;
const double _grow = 16;
const double _seam = 2;
const double _outer = FloatingBar.height / 2;
const double _inner = 8;

double _labelWidth(BuildContext context, String label) {
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: DefaultTextStyle.of(context)
          .style
          .merge(Theme.of(context).textTheme.labelLarge),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

// лента: стрелка и кнопка стоят вплотную к вкладкам через тонкий шов;
// острова: стрелка, лента и кнопка отдельно с одинаковыми зазорами
class _Look {
  const _Look({
    required this.strip,
    required this.brightPlus,
    required this.sideGap,
    required this.jumpWidth,
    required this.plusWidth,
  });

  static const islandRadius = 22.0;

  static const _strip = _Look(
    strip: true,
    brightPlus: false,
    sideGap: _seam,
    jumpWidth: 60,
    plusWidth: 72,
  );
  static const _brightPlus = _Look(
    strip: true,
    brightPlus: true,
    sideGap: _seam,
    jumpWidth: 60,
    plusWidth: 72,
  );
  static const _islands = _Look(
    strip: false,
    brightPlus: true,
    sideGap: 10,
    jumpWidth: 64,
    plusWidth: 64,
  );

  static _Look of(LiquidBarStyle style) => switch (style) {
        LiquidBarStyle.strip => _strip,
        LiquidBarStyle.brightPlus => _brightPlus,
        LiquidBarStyle.islands => _islands,
      };

  final bool strip;
  final bool brightPlus;
  final double sideGap;
  final double jumpWidth;
  final double plusWidth;
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

class _LiquidBottomNavState extends State<LiquidBottomNav>
    with TickerProviderStateMixin {
  // сначала кнопка втягивается в ленту, потом лента уходит в край
  static const double _absorbShare = 0.4;
  // мягче системных: лента проходит около 150 dp, и за spatialDefault (0,25 с) это рывок.
  // без перелёта, оседает примерно за 0,6 с
  static const _sinkSpring =
      SpringDescription(mass: 1, stiffness: 60, damping: 2 * 7.75);
  // обратно чуть мягче spatialSlow: на нём лента выпрыгивала из края резче, чем уходила
  static const _riseSpring =
      SpringDescription(mass: 1, stiffness: 100, damping: 0.85 * 2 * 10);

  // unbounded: пружина должна перелетать за цель
  late final List<AnimationController> _ctrls = List.generate(
    _count,
    (i) => AnimationController.unbounded(
      vsync: this,
      value: widget.index == i ? 1 : 0,
    ),
  );

  late final AnimationController _hide = AnimationController(
    vsync: this,
    value: FloatingBar.hidden.value ? 1 : 0,
  );

  late final AnimationController _jumpIn = AnimationController(
    vsync: this,
    value: FloatingBar.jump.value == null ? 0 : 1,
  );
  FloatingJump? _jump;

  // версия и кнопка проверки выныривают из края, пока открыты настройки
  late final AnimationController _sideIn = AnimationController(
    vsync: this,
    value: widget.index == _settings ? 1 : 0,
  );

  final ui.FragmentShader? _shader = FloatingBar.newBarShader();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (current) {
        FloatingBar.barOnScreen.value = this;
      } else if (FloatingBar.barOnScreen.value == this) {
        FloatingBar.barOnScreen.value = null;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    // после Легаси панель приходит показанной и без чужой стрелки
    FloatingBar.hidden.value = false;
    FloatingBar.jump.value = null;
    FloatingBar.hidden.addListener(_onHidden);
    FloatingBar.jump.addListener(_onJump);
  }

  void _onHidden() {
    final hidden = FloatingBar.hidden.value;
    ExpressiveMotion.springTo(
      _hide,
      hidden ? 1 : 0,
      spring: hidden ? _sinkSpring : _riseSpring,
    );
  }

  void _onJump() {
    final jump = FloatingBar.jump.value;
    if (jump != null) _jump = jump;
    ExpressiveMotion.springTo(
      _jumpIn,
      jump == null ? 0 : 1,
      spring: jump == null ? _sinkSpring : ExpressiveMotion.spatialSlow,
    );
  }

  @override
  void didUpdateWidget(LiquidBottomNav old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;
    final settings = widget.index == _settings;
    ExpressiveMotion.springTo(
      _sideIn,
      settings ? 1 : 0,
      spring: settings ? ExpressiveMotion.spatialSlow : _sinkSpring,
    );
    for (var i = 0; i < _count; i++) {
      ExpressiveMotion.springTo(
        _ctrls[i],
        widget.index == i ? 1 : 0,
        spring: ExpressiveMotion.spatialFast,
      );
    }
  }

  @override
  void dispose() {
    FloatingBar.hidden.removeListener(_onHidden);
    FloatingBar.jump.removeListener(_onJump);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (FloatingBar.barOnScreen.value == this) FloatingBar.barOnScreen.value = null;
    });
    for (final c in _ctrls) {
      c.dispose();
    }
    _hide.dispose();
    _jumpIn.dispose();
    _sideIn.dispose();
    _shader?.dispose();
    super.dispose();
  }

  double _page() {
    final pages = widget.pages;
    if (pages != null && pages.hasClients && pages.position.hasContentDimensions) {
      return pages.page ?? widget.index.toDouble();
    }
    return widget.index.toDouble();
  }

  double _absorbedByPage(double page) {
    double without(int i) => i == _settings ? 1 : 0;
    final lo = page.floor().clamp(0, _count - 1);
    final hi = page.ceil().clamp(0, _count - 1);
    return without(lo) + (without(hi) - without(lo)) * (page - page.floor());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final items = appNavDestinations(
      l10n,
      showConnectedBadge: widget.showConnectedBadge,
    );

    final inset = MediaQuery.paddingOf(context).bottom;
    if (FloatingBar.bottomInset.value != inset) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => FloatingBar.bottomInset.value = inset,
      );
    }
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final labels = [for (final item in items) _labelWidth(context, item.label)];
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final look = _Look.of(widget.style);
    final pages = widget.pages;
    return SizedBox(
      height: FloatingBar.bottomMargin + inset + FloatingBar.height,
      child: LayoutBuilder(
        builder: (context, box) => AnimatedBuilder(
          animation: Listenable.merge(
            [..._ctrls, _hide, _jumpIn, _sideIn, FloatingBar.side, ?pages],
          ),
          builder: (context, _) {
            final width = box.maxWidth;
            final ts = [for (final c in _ctrls) c.value.clamp(0.0, 1.0)];
            final hide = _hide.value;
            final page = _page();
            final absorbed = math.max(
              _absorbedByPage(page),
              (hide / _absorbShare).clamp(0.0, 1.0),
            );
            final sink =
                ((hide - _absorbShare) / (1 - _absorbShare)).clamp(0.0, 1.0);
            final jumpT = _jumpIn.value.clamp(0.0, 1.0);

            // место под стрелку держим на всей вкладке серверов, а не только пока она видна:
            // она появляется на прокрутке, и лента не должна от неё дёргаться
            final leftSide = (look.jumpWidth + look.sideGap) *
                (1 - (page - _jumpTab).abs().clamp(0.0, 1.0));
            final rightSide = (look.plusWidth + look.sideGap) * (1 - absorbed);
            final budgets = _labelBudgets(
              ts,
              width -
                  2 * FloatingBar.margin -
                  leftSide -
                  rightSide -
                  _seam * (_count - 1),
            );
            final widths = [
              for (var i = 0; i < _count; i++)
                _tabWidth + ts[i] * (_grow + math.min(labels[i], budgets[i])),
            ];
            final stripWidth =
                widths.fold(0.0, (a, b) => a + b) + _seam * (_count - 1);

            final restY = box.maxHeight -
                FloatingBar.bottomMargin -
                inset -
                FloatingBar.height / 2;
            // за краем на полсклейки: край ещё тянется к ленте, и от спрятанной
            // панели остаётся бугорок в 1-2 dp. так задумано, на всю склейку он пропадает
            final centerY = restY +
                sink *
                    (FloatingBar.bottomMargin +
                        inset +
                        FloatingBar.height +
                        _LiquidBarPainter.poolGoo / 2 +
                        8);
            final top = centerY - FloatingBar.height / 2;

            // раскладка слева направо, в RTL зеркалим целиком
            final centered = (width - stripWidth) / 2;
            final left = math.min(
              math.max(centered, FloatingBar.margin + leftSide),
              width - FloatingBar.margin - rightSide - stripWidth,
            );
            Rect place(double x, double y, double w, double h) =>
                Rect.fromLTWH(rtl ? width - x - w : x, y, w, h);

            // в настройках к концам ленты пристыкована версия, и концы там внутренние
            final version = (1 - (page - _settings).abs()).clamp(0.0, 1.0);
            final tabs = <Rect>[];
            final radii = <(double, double)>[];
            var x = left;
            for (var i = 0; i < _count; i++) {
              tabs.add(place(x, top, widths[i], FloatingBar.height));
              var l = _inner;
              var r = _inner;
              if (i == 0) {
                l = look.strip
                    ? _lerp(_outer, _inner, math.max(jumpT, version))
                    : _outer;
              }
              if (i == _count - 1) {
                r = look.strip
                    ? _lerp(_inner, _outer, absorbed * (1 - version))
                    : _outer;
              }
              // выбранная вкладка целиком пилюлей, без углов из-под неё
              radii.add((_lerp(l, _outer, ts[i]), _lerp(r, _outer, ts[i])));
              x += widths[i] + _seam;
            }
            final stripRight = left + stripWidth;

            final out = Rect.fromLTWH(
              stripRight + look.sideGap,
              top,
              look.plusWidth,
              FloatingBar.height,
            );
            // втекая, капля сжимается в точку внутри крайней вкладки: остаток 24 на 40
            // под конец проступал сквозь подложку выбранной вкладки и пропадал рывком
            final inside = Rect.fromCenter(
              center: Offset(stripRight - 20, centerY),
              width: 0,
              height: 0,
            );
            final budLtr = Rect.lerp(out, inside, absorbed)!;
            final bud = place(budLtr.left, budLtr.top, budLtr.width, budLtr.height);
            final budScale = budLtr.height / FloatingBar.height;
            final budRadii = look.strip
                ? (_inner * budScale, _outer * budScale)
                : (_Look.islandRadius * budScale, _Look.islandRadius * budScale);

            // стрелка вытекает из начала ленты так же, как кнопка из её конца
            final jumpOut = Rect.fromLTWH(
              left - look.sideGap - look.jumpWidth,
              restY - FloatingBar.height / 2,
              look.jumpWidth,
              FloatingBar.height,
            );
            // стрелку в конце убираем совсем, поэтому она уходит за всю склейку:
            // бугорок от неё тает по пути, а не обрывается в последний кадр
            final gone = box.maxHeight +
                FloatingBar.height / 2 +
                _LiquidBarPainter.poolGoo +
                8;
            // когда лента ушла в край, втекать некуда: стрелка уходит в край вслед за ней
            final intoStrip = Rect.fromCenter(
              center: Offset(left + 20, restY),
              width: 0,
              height: 0,
            );
            final intoEdge = jumpOut.translate(0, gone - restY);
            final jumpIn = Rect.lerp(intoStrip, intoEdge, sink)!;
            final jumpLtr = Rect.lerp(jumpIn, jumpOut, jumpT)!;
            final jump = place(jumpLtr.left, jumpLtr.top, jumpLtr.width, jumpLtr.height);
            final jumpScale = jumpLtr.height / FloatingBar.height;
            // одна стрелка, когда лента ушла в край, круглая с обеих сторон
            final jumpRadii = look.strip
                ? (_outer * jumpScale, _lerp(_inner, _outer, sink) * jumpScale)
                : (_Look.islandRadius * jumpScale, _Look.islandRadius * jumpScale);

            final sideContent = FloatingBar.side.value;
            // плитка проверки встаёт на место кнопки: сначала кнопка втекает в ленту, потом
            // выныривают плитки, иначе они наезжают друг на друга
            final sideT = sideContent == null
                ? 0.0
                : math.min(
                    _sideIn.value.clamp(0.0, 1.0),
                    ((absorbed - 0.7) / 0.3).clamp(0.0, 1.0),
                  );
            // версия вытекает из кнопки серверов, как стрелка, проверка из конца ленты,
            // куда только что втекла кнопка действия
            final sideTop = restY - FloatingBar.height / 2;
            final sideLOut = Rect.fromLTWH(
              FloatingBar.margin,
              sideTop,
              math.max(0, left - look.sideGap - FloatingBar.margin),
              FloatingBar.height,
            );
            final sideROut = Rect.fromLTWH(
              stripRight + look.sideGap,
              sideTop,
              math.max(0, width - FloatingBar.margin - stripRight - look.sideGap),
              FloatingBar.height,
            );
            final sideLIn = intoStrip;
            final sideRIn = inside.translate(0, restY - centerY);
            final sideLLtr = Rect.lerp(sideLIn, sideLOut, sideT)!;
            final sideRLtr = Rect.lerp(sideRIn, sideROut, sideT)!;
            final sideL = place(sideLLtr.left, sideLLtr.top, sideLLtr.width, sideLLtr.height);
            final sideR = place(sideRLtr.left, sideRLtr.top, sideRLtr.width, sideRLtr.height);
            final sideScale = sideLLtr.height / FloatingBar.height;
            final sideLRadii = look.strip
                ? (_outer * sideScale, _inner * sideScale)
                : (_Look.islandRadius * sideScale, _Look.islandRadius * sideScale);
            final sideRRadii = (sideLRadii.$2, sideLRadii.$1);
            final sideOpacity = ((sideT - 0.4) / 0.6).clamp(0.0, 1.0);

            (double, double) side((double, double) r) => rtl ? (r.$2, r.$1) : r;
            final plusOnBright = look.brightPlus;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _LiquidBarPainter(
                      shader: _shader,
                      tabs: tabs,
                      tabRadii: [for (final r in radii) side(r)],
                      bud: absorbed < 1 ? bud : Rect.zero,
                      budRadii: side(budRadii),
                      jump: jumpT > 0.01 ? jump : Rect.zero,
                      jumpRadii: side(jumpRadii),
                      absorbed: absorbed,
                      jumpT: jumpT,
                      baseColor: FloatingBar.tileColor(cs),
                      budColor: plusOnBright ? cs.tertiary : FloatingBar.tileColor(cs),
                      jumpColor: cs.secondaryContainer,
                      sideL: sideT > 0.01 ? sideL : Rect.zero,
                      sideLRadii: side(sideLRadii),
                      sideR: sideT > 0.01 ? sideR : Rect.zero,
                      sideRRadii: side(sideRRadii),
                      sideT: sideT,
                      sideLColor: sideContent?.startColor ?? FloatingBar.tileColor(cs),
                      dpr: dpr,
                    ),
                  ),
                ),
                for (var i = 0; i < _count; i++)
                  Positioned.fromRect(
                    rect: tabs[i],
                    child: IgnorePointer(
                      ignoring: sink > 0,
                      child: _Tab(
                        icon: items[i].icon,
                        label: items[i].label,
                        badge: items[i].badge,
                        selected: widget.index == i,
                        t: ts[i],
                        labelMax: budgets[i],
                        onTap: () {
                          if (i != widget.index) AppHaptics.selection();
                          widget.onTap(i);
                        },
                      ),
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
                        color: plusOnBright ? cs.onTertiary : cs.primary,
                        radius: budRadii.$2,
                        onTap: () => FloatingBar.actions[widget.index]?.call(),
                      ),
                    ),
                  ),
                if (sideContent != null && sideT > 0.01) ...[
                  Positioned.fromRect(
                    rect: sideL,
                    child: IgnorePointer(
                      ignoring: sideT < 0.5,
                      child: _SideTap(
                        radii: side(sideLRadii),
                        tooltip: sideContent.startTooltip,
                        onTap: sideContent.onStartTap,
                        child: ClipRect(
                          child: Opacity(
                            opacity: sideOpacity,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: sideContent.start,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: sideR,
                    child: ClipRect(
                      child: Opacity(
                        opacity: sideOpacity,
                        child: Center(child: sideContent.end),
                      ),
                    ),
                  ),
                ],
                if (jumpT > 0.01)
                  Positioned.fromRect(
                    rect: jump,
                    child: IgnorePointer(
                      ignoring: jumpT < 0.5,
                      child: _Drop(
                        icon: Icons.arrow_downward_rounded,
                        turns: (_jump?.up ?? false) ? 0.5 : 0,
                        size: 26 * jumpScale,
                        // значок гаснет раньше плитки, одинокой стрелки не остаётся
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

  // явно, а не Flexible: доля Flex не знает минимума пункта, и узкий ряд переполнялся
  static List<double> _labelBudgets(List<double> ts, double maxWidth) {
    var fixed = 0.0;
    var openSum = 0.0;
    for (final t in ts) {
      fixed += _tabWidth + _grow * t;
      openSum += t;
    }
    if (!maxWidth.isFinite || openSum <= 0) {
      return List.filled(ts.length, double.infinity);
    }
    final budget = (maxWidth - fixed).clamp(0.0, double.infinity);
    return [for (final t in ts) budget * t / openSum];
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.icon,
    required this.label,
    required this.badge,
    required this.selected,
    required this.t,
    required this.labelMax,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool badge;
  final bool selected;
  final double t;
  final double labelMax;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const shape = StadiumBorder();
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: Material(
        color: Color.lerp(Colors.transparent, cs.primary, t),
        shape: shape,
        clipBehavior: Clip.antiAlias,
        // цвет ведём пружиной покадрово, неявная анимация Material отставала бы
        animationDuration: Duration.zero,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: Center(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              NavIcon(
                icon: icon,
                badge: badge,
                color: Color.lerp(cs.onSurface, cs.onPrimary, t)!,
              ),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: labelMax + 8),
                child: ClipRect(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: t,
                    // без heightFactor Align растёт до высоты экрана
                    heightFactor: 1,
                    child: Opacity(
                      opacity: t,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(start: 8),
                        child: Text(
                          label,
                          style: theme.textTheme.labelLarge
                              ?.copyWith(color: cs.onPrimary),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.fade,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SideTap extends StatelessWidget {
  const _SideTap({
    required this.radii,
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  final (double, double) radii;
  final String? tooltip;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l = Radius.circular(radii.$1);
    final r = Radius.circular(radii.$2);
    Widget tile = Material(
      type: MaterialType.transparency,
      child: InkWell(
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: l,
            bottomLeft: l,
            topRight: r,
            bottomRight: r,
          ),
        ),
        onTap: onTap,
        child: child,
      ),
    );
    final tooltip = this.tooltip;
    if (tooltip != null) tile = Tooltip(message: tooltip, child: tile);
    return tile;
  }
}

class _Drop extends StatelessWidget {
  const _Drop({
    required this.icon,
    required this.size,
    required this.opacity,
    required this.color,
    required this.radius,
    required this.onTap,
    this.turns = 0,
  });

  final IconData icon;
  final double size;
  final double opacity;
  final Color color;
  final double radius;
  final double turns;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
        onTap: onTap,
        // значок не вылезает за сужающуюся плитку
        child: ClipRect(
          child: Center(
            child: Opacity(
              opacity: opacity,
              child: AnimatedRotation(
                turns: turns,
                duration: ExpressiveMotion.durationFast,
                curve: ExpressiveMotion.emphasized,
                child: Icon(icon, size: size, color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidBarPainter extends CustomPainter {
  _LiquidBarPainter({
    required this.shader,
    required this.tabs,
    required this.tabRadii,
    required this.bud,
    required this.budRadii,
    required this.jump,
    required this.jumpRadii,
    required this.absorbed,
    required this.jumpT,
    required this.baseColor,
    required this.budColor,
    required this.jumpColor,
    required this.sideL,
    required this.sideLRadii,
    required this.sideR,
    required this.sideRRadii,
    required this.sideT,
    required this.sideLColor,
    required this.dpr,
  });

  static const _goo = 40.0;
  static const poolGoo = 48.0;

  final ui.FragmentShader? shader;
  final List<Rect> tabs;
  final List<(double, double)> tabRadii;
  final Rect bud;
  final (double, double) budRadii;
  final Rect jump;
  final (double, double) jumpRadii;
  final double absorbed;
  final double jumpT;
  final Color baseColor;
  final Color budColor;
  final Color jumpColor;
  final Rect sideL;
  final (double, double) sideLRadii;
  final Rect sideR;
  final (double, double) sideRRadii;
  final double sideT;
  final Color sideLColor;
  final double dpr;

  // перемычка есть, только пока капля втекает или вытекает: в покое шов виден,
  // а втёкшая не должна выпирать из конца ленты
  static double _gooFor(double t) =>
      _goo * (t / 0.25).clamp(0.0, 1.0) * ((1 - t) / 0.15).clamp(0.0, 1.0);

  static RRect _rrect(Rect r, (double, double) radii) {
    final h = r.height / 2;
    final l = Radius.circular(math.min(radii.$1, h));
    final rr = Radius.circular(math.min(radii.$2, h));
    return RRect.fromRectAndCorners(r,
        topLeft: l, bottomLeft: l, topRight: rr, bottomRight: rr);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // втекая, капля перекрашивается в цвет ленты
    final budColor = Color.lerp(
      this.budColor,
      baseColor,
      ((absorbed - 0.4) / 0.4).clamp(0.0, 1.0),
    )!;
    final jumpColor = Color.lerp(
      this.jumpColor,
      baseColor,
      ((0.6 - jumpT) / 0.4).clamp(0.0, 1.0),
    )!;
    final shader = this.shader;
    if (shader == null) {
      final base = Paint()..color = baseColor;
      for (var i = 0; i < tabs.length; i++) {
        canvas.drawRRect(_rrect(tabs[i], tabRadii[i]), base);
      }
      if (!bud.isEmpty) {
        canvas.drawRRect(_rrect(bud, budRadii), Paint()..color = budColor);
      }
      if (!jump.isEmpty) {
        canvas.drawRRect(_rrect(jump, jumpRadii), Paint()..color = jumpColor);
      }
      if (!sideL.isEmpty) {
        canvas.drawRRect(_rrect(sideL, sideLRadii), Paint()..color = sideLColor);
      }
      if (!sideR.isEmpty) canvas.drawRRect(_rrect(sideR, sideRRadii), base);
      return;
    }
    List<double> r(Rect rect) => rect.isEmpty
        ? const [0, 0, 0, 0]
        : [rect.left, rect.top, rect.right, rect.bottom];
    var i = 0;
    for (final v in [
      size.width,
      size.height,
      dpr,
      ...r(jump),
      jumpRadii.$1,
      jumpRadii.$2,
      for (var t = 0; t < 3; t++) ...[
        ...r(tabs[t]),
        tabRadii[t].$1,
        tabRadii[t].$2,
      ],
      ...r(bud),
      budRadii.$1,
      budRadii.$2,
      ...r(sideL),
      sideLRadii.$1,
      sideLRadii.$2,
      ...r(sideR),
      sideRRadii.$1,
      sideRRadii.$2,
      _gooFor(absorbed),
      _gooFor(1 - jumpT),
      _gooFor(1 - sideT),
      size.height,
      poolGoo,
      baseColor.r,
      baseColor.g,
      baseColor.b,
      baseColor.a,
      budColor.r,
      budColor.g,
      budColor.b,
      budColor.a,
      jumpColor.r,
      jumpColor.g,
      jumpColor.b,
      jumpColor.a,
      sideLColor.r,
      sideLColor.g,
      sideLColor.b,
      sideLColor.a,
    ]) {
      shader.setFloat(i++, v);
    }
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_LiquidBarPainter old) => true;
}
