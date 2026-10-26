part of '../servers_tab.dart';

String _formatVpnRate(int? bytesPerSec) {
  if (bytesPerSec == null || bytesPerSec <= 0) return '0 B/s';
  return '${_formatVpnBytes(bytesPerSec)}/s';
}

String _formatVpnBytes(int? bytes) {
  if (bytes == null || bytes <= 0) return '0 B';
  const kb = 1024.0;
  const mb = kb * 1024;
  const gb = mb * 1024;
  final b = bytes.toDouble();
  if (b >= gb) return '${(b / gb).toStringAsFixed(2)} GB';
  if (b >= mb) return '${(b / mb).toStringAsFixed(1)} MB';
  if (b >= kb) return '${(b / kb).toStringAsFixed(1)} KB';
  return '$bytes B';
}

String _formatVpnDuration(Duration? d) {
  if (d == null) return '0s';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

class _ConnectionStats extends ConsumerWidget {
  const _ConnectionStats({this.fill = false, this.withTime = true});

  final bool fill;
  final bool withTime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (showTraffic, timeSetting, showSplit) = ref.watch(
      settingsNotifierProvider.select((async) {
        final s = async.value ?? const AppSettings();
        return (s.showTrafficStats, s.showConnectionTime, s.showTrafficSplit);
      }),
    );
    final showTime = withTime && timeSetting;
    final showAnyTraffic = showTraffic || showSplit;
    if (!showAnyTraffic && !showTime) return const SizedBox.shrink();

    final stats = ref.watch(
      vpnStateProvider.select((a) {
        final v = a.value;
        if (v == null) return (null, null, null, null);
        return (v.downloadSpeed, v.uploadSpeed, v.totalDownload, v.duration);
      }),
    );

    final split = showSplit ? ref.watch(trafficSplitProvider).value : null;

    final l10n = context.l10n;
    return StatStrip(
      fill: fill,
      metrics: [
        if (showAnyTraffic) ...[
          if (split != null) ...[
            _channelMetric(
              l10n,
              tag: l10n.statsSplitVpnTag,
              label: l10n.statsSplitVpnLabel,
              traffic: split.vpn,
            ),
            _channelMetric(
              l10n,
              tag: l10n.statsSplitDirectTag,
              label: l10n.statsSplitDirectLabel,
              traffic: split.direct,
            ),
          ] else ...[
            StatMetric(
              icon: Icons.arrow_downward_rounded,
              label: l10n.statsDownloadLabel,
              value: _formatVpnRate(stats.$1),
              template: _kRateTemplate,
            ),
            StatMetric(
              icon: Icons.arrow_upward_rounded,
              label: l10n.statsUploadLabel,
              value: _formatVpnRate(stats.$2),
              template: _kRateTemplate,
            ),
            StatMetric(
              icon: Icons.data_usage_rounded,
              label: l10n.statsInLabel,
              value: _formatVpnBytes(stats.$3),
              template: _kBytesTemplate,
            ),
          ],
        ],
        if (showTime)
          StatMetric(
            icon: Icons.schedule_rounded,
            label: l10n.statsTimeLabel,
            value: _formatVpnDuration(stats.$4),
            template: _kDurationTemplate,
          ),
      ],
    );
  }
}

StatMetric _channelMetric(
  AppLocalizations l10n, {
  required String tag,
  required String label,
  required ChannelTraffic traffic,
}) =>
    StatMetric.channel(
      tag: tag,
      label: label,
      lines: [
        StatLine(
          icon: Icons.arrow_downward_rounded,
          label: l10n.statsDownloadLabel,
          value: _formatVpnRate(traffic.downloadSpeed),
          template: _kRateTemplate,
        ),
        StatLine(
          icon: Icons.arrow_upward_rounded,
          label: l10n.statsUploadLabel,
          value: _formatVpnRate(traffic.uploadSpeed),
          template: _kRateTemplate,
        ),
        StatLine(
          icon: Icons.data_usage_rounded,
          label: l10n.statsSplitTotalLabel,
          value: _formatVpnBytes(traffic.total),
          template: _kBytesTemplate,
        ),
      ],
    );

// выдвигается из-под того, что над ней, и уезжает обратно, а не проявляется на пустом месте.
// пружина мягче шапочной: за 0,38 с на easeOutCubic строка вставала раньше, чем двигалась вода
class _StatsReveal extends StatefulWidget {
  const _StatsReveal({
    required this.shown,
    required this.child,
    this.alignment = Alignment.bottomCenter,
  });

  final bool shown;
  final Widget child;
  final AlignmentGeometry alignment;

  @override
  State<_StatsReveal> createState() => _StatsRevealState();
}

class _StatsRevealState extends State<_StatsReveal>
    with SingleTickerProviderStateMixin {
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 55,
    damping: 0.85 * 2 * 7.42,
  );

  late final AnimationController _out = AnimationController.unbounded(
    vsync: this,
    value: widget.shown ? 1 : 0,
  );

  @override
  void didUpdateWidget(_StatsReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shown == widget.shown) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _out.value = widget.shown ? 1 : 0;
    } else {
      ExpressiveMotion.springTo(_out, widget.shown ? 1 : 0, spring: _spring);
    }
  }

  @override
  void dispose() {
    _out.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _out,
      builder: (context, child) {
        // пружина замирает в долях пикселя от цели, а не ровно на ней
        if (!_out.isAnimating || (!widget.shown && _out.value < 0.01)) {
          return widget.shown
              ? child!
              : const SizedBox(width: double.infinity);
        }
        return ClipRect(
          child: Align(
            alignment: widget.alignment,
            heightFactor: max(0.0, _out.value),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

// строка вытекает каплей из плашки или кнопки над ней, раздувается и только потом проявляет цифры.
// при скрытии тот же путь назад: капля втекает обратно
class _StatsBud extends StatefulWidget {
  const _StatsBud({
    required this.shown,
    required this.child,
    required this.source,
    required this.sourceRadius,
    required this.sourceColor,
    this.bead = 44,
    this.neck,
    this.goo = 22,
  });

  final bool shown;
  final Widget child;
  final GlobalKey? source;
  final double sourceRadius;
  final Color sourceColor;

  // у кнопки ровного низа мало: пока капля висит на ней, она уже (neck), иначе вылезала бы
  // за углы, и набухает до bead, только оторвавшись
  final double bead;
  final double? neck;
  final double goo;

  @override
  State<_StatsBud> createState() => _StatsBudState();
}

class _StatsBudState extends State<_StatsBud>
    with SingleTickerProviderStateMixin {
  // капля набухает, отрывается и падает, потом растекается в строку
  static const _drop = Interval(0, 0.3, curve: Curves.easeOut);
  static const _fall = Interval(0.22, 0.6, curve: Curves.easeInOutCubic);
  static const _snap = Interval(0.3, 0.55);
  static const _spread = Interval(0.5, 0.92, curve: Cubic(0.34, 1.3, 0.64, 1));
  static const _tint = Interval(0.2, 0.7);
  static const _open = Interval(0.05, 0.8, curve: Curves.easeInOutCubic);
  static const _fade = Interval(0.78, 1, curve: Curves.easeOut);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    reverseDuration: const Duration(milliseconds: 600),
    value: widget.shown ? 1 : 0,
  );
  final _strip = GlobalKey();
  final ui.FragmentShader? _shader = LiquidBud.newShader();

  @override
  void didUpdateWidget(_StatsBud oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shown == widget.shown) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = widget.shown ? 1 : 0;
    } else if (widget.shown) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        if (t == 0) return const SizedBox(width: double.infinity);
        final moving = t < 1;
        return CustomPaint(
          painter: moving
              ? _BudPainter(
                  state: this,
                  t: t,
                  budColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                  devicePixelRatio:
                      MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
                )
              : null,
          child: ClipRect(
            clipBehavior: moving ? Clip.hardEdge : Clip.none,
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: _open.transform(t),
              child: Opacity(
                opacity: _fade.transform(t),
                child: Padding(
                  padding: const EdgeInsets.only(top: ExpressiveSpacing.medium),
                  child: KeyedSubtree(key: _strip, child: child!),
                ),
              ),
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _BudPainter extends CustomPainter {
  _BudPainter({
    required this.state,
    required this.t,
    required this.budColor,
    required this.devicePixelRatio,
  });

  final _StatsBudState state;
  final double t;
  final Color budColor;
  final double devicePixelRatio;

  Rect? _rectOf(RenderObject? box, RenderBox self) {
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return MatrixUtils.transformRect(
      box.getTransformTo(self),
      Offset.zero & box.size,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final shader = state._shader;
    final self = state.context.findRenderObject();
    if (shader == null || self is! RenderBox) return;
    final target = _rectOf(state._strip.currentContext?.findRenderObject(), self);
    if (target == null || target.isEmpty) return;
    final source = _rectOf(
      state.widget.source?.currentContext?.findRenderObject(),
      self,
    );
    final drop = _StatsBudState._drop.transform(t);
    final fall = _StatsBudState._fall.transform(t);
    final spread = _StatsBudState._spread.transform(t);
    final sx = source?.center.dx ?? target.center.dx;
    final sb = source?.bottom ?? target.top;
    final hanging = sb + ui.lerpDouble(-6, 12, drop)!;
    final neck = state.widget.neck ?? state.widget.bead;
    // падает отвесно под местом, откуда вытекла, и растекается уже оттуда
    final bead = Rect.fromCenter(
      center: Offset(sx, ui.lerpDouble(hanging, target.center.dy, fall)!),
      width: ui.lerpDouble(
        ui.lerpDouble(neck * 0.45, neck, drop)!,
        state.widget.bead,
        fall,
      )!,
      height: ui.lerpDouble(10, 34, drop)!,
    );
    final bud = Rect.lerp(bead, target, spread)!;
    canvas
      ..save()
      // сильно ниже раскрытого места капля легла бы на список, а 20 dp под строкой пустые и в
      // легаси, и в модерне: без запаса падающая капля срезалась ровной линией
      ..clipRect(
        Rect.fromLTRB(
          -size.width,
          -size.height - 400,
          size.width * 2,
          size.height + 20,
        ),
      );
    LiquidBud.paint(
      canvas,
      shader,
      devicePixelRatio: devicePixelRatio,
      source: source ?? Rect.zero,
      sourceRadius: state.widget.sourceRadius,
      bud: bud,
      budRadius: ui.lerpDouble(
        bead.shortestSide / 2,
        ExpressiveShape.large,
        spread.clamp(0.0, 1.0),
      )!,
      goo: source == null
          ? 0
          : state.widget.goo * (1 - _StatsBudState._snap.transform(t)),
      sourceColor: state.widget.sourceColor,
      budColor: Color.lerp(
        state.widget.sourceColor,
        budColor,
        _StatsBudState._tint.transform(t),
      )!,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BudPainter old) =>
      old.t != t ||
      old.budColor != budColor ||
      old.devicePixelRatio != devicePixelRatio;
}

const _kRateTemplate = '999.9 MB/s';
const _kBytesTemplate = '999.99 GB';
const _kDurationTemplate = '59m 59s';

