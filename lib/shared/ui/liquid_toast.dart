import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:keqdroid/shared/ui/floating_bar.dart';

// уведомление Модерна: капля вытекает из левого края экрана и растекается в плитку над
// лентой, уходит обратно в край. в письме справа налево из правого. смахивается в тот же край
class LiquidToast {
  const LiquidToast({
    required this.message,
    this.icon,
    this.color,
    this.ink,
    this.duration = const Duration(seconds: 4),
    this.actionLabel,
    this.onAction,
  });

  final Widget message;
  final IconData? icon;
  final Color? color;
  final Color? ink;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;

  static final current = ValueNotifier<LiquidToast?>(null);

  // включает главный экран, когда нижняя панель в Модерне
  static bool enabled = false;

  static void show(LiquidToast toast) => current.value = toast;

  static void hide() => current.value = null;
}

// уведомления приложения: в Модерне капля из края, иначе прежний SnackBar. берётся до
// await, как ScaffoldMessenger.of: после него context может быть уже не тот
class AppSnack {
  AppSnack._(this._messenger, this._theme);

  factory AppSnack.of(BuildContext context) =>
      AppSnack._(ScaffoldMessenger.of(context), Theme.of(context));

  final ScaffoldMessengerState _messenger;
  final ThemeData _theme;

  void showSnackBar(SnackBar bar) {
    if (!LiquidToast.enabled) {
      _messenger.showSnackBar(bar);
      return;
    }
    final color = bar.backgroundColor;
    final action = bar.action;
    LiquidToast.show(LiquidToast(
      message: bar.content,
      color: color,
      // значки в цветных уведомлениях покрашены под яркий фон, текст подстраиваем так же
      ink: color == null
          ? null
          : ThemeData.estimateBrightnessForColor(color) == Brightness.dark
          ? Colors.white
          : _theme.colorScheme.surface,
      duration: bar.duration,
      actionLabel: action?.label,
      onAction: action?.onPressed,
    ));
  }
}

class LiquidToastHost extends StatefulWidget {
  const LiquidToastHost({super.key, required this.child});

  final Widget child;

  @override
  State<LiquidToastHost> createState() => _LiquidToastHostState();
}

class _LiquidToastHostState extends State<LiquidToastHost>
    with TickerProviderStateMixin {
  // вытекает чуть медленнее spatialSlow: 0,35 с были резковаты, теперь около 0,5 с;
  // уходит мягко, без перелёта, как лента
  static const _riseSpring =
      SpringDescription(mass: 1, stiffness: 100, damping: 2 * 0.85 * 10);
  static const _sinkSpring =
      SpringDescription(mass: 1, stiffness: 60, damping: 2 * 7.75);
  static const _radius = 22.0;
  static const _goo = 40.0;
  static const _drop = Size(44, 36);

  late final AnimationController _t;
  // насколько плитку утянули пальцем к её краю, в пикселях
  late final AnimationController _pull;
  late final Listenable _motion;
  final ui.FragmentShader? _shader = FloatingBar.newDropShader();
  LiquidToast? _shown;
  // лента на момент показа: спрячет её прокрутка, уведомление не прыгает
  bool _bar = false;
  double _height = FloatingBar.height;
  Timer? _timer;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _t = AnimationController(vsync: this);
    _pull = AnimationController.unbounded(vsync: this);
    _motion = Listenable.merge([_t, _pull]);
    LiquidToast.current.addListener(_onToast);
  }

  @override
  void dispose() {
    LiquidToast.current.removeListener(_onToast);
    _timer?.cancel();
    _t.dispose();
    _pull.dispose();
    _shader?.dispose();
    super.dispose();
  }

  Future<void> _onToast() async {
    final next = LiquidToast.current.value;
    final generation = ++_generation;
    _timer?.cancel();
    if (_shown != null && _t.value > 0) {
      await _sink();
      if (!mounted || generation != _generation) return;
    }
    setState(() {
      _shown = next;
      _bar = FloatingBar.barOnScreen.value != null && !FloatingBar.hidden.value;
    });
    _pull.value = 0;
    if (next == null) return;
    await ExpressiveMotion.springTo(_t, 1, spring: _riseSpring)
        .orCancel
        .catchError((_) {});
    if (!mounted || generation != _generation) return;
    _arm(next);
  }

  void _arm(LiquidToast toast) {
    _timer?.cancel();
    _timer = Timer(toast.duration, () {
      if (LiquidToast.current.value == toast) LiquidToast.hide();
    });
  }

  Future<void> _sink() =>
      ExpressiveMotion.springTo(_t, 0, spring: _sinkSpring).orCancel.catchError((_) {});

  static double _width(Size screen) =>
      math.min(screen.width - 2 * FloatingBar.margin, 560.0);

  void _onDragUpdate(DragUpdateDetails d, bool rtl) {
    if (LiquidToast.current.value == null) return;
    _timer?.cancel();
    _pull.value = math.max(0, _pull.value + (rtl ? d.delta.dx : -d.delta.dx));
  }

  void _onDragEnd(DragEndDetails d, bool rtl) {
    final toast = LiquidToast.current.value;
    if (toast == null) return;
    final toEdge = (rtl ? 1 : -1) * (d.primaryVelocity ?? 0);
    // пороги как у Dismissible: бросок от 700 px/с или сдвиг на 0,4 ширины
    if (toEdge >= 700 || _pull.value >= 0.4 * _width(MediaQuery.sizeOf(context))) {
      LiquidToast.hide();
      return;
    }
    ExpressiveMotion.springTo(_pull, 0, spring: _riseSpring).orCancel.catchError((_) {});
    _arm(toast);
  }

  void _onSize(Size size) {
    if ((size.height - _height).abs() < 0.5) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _height = size.height);
    });
  }

  @override
  Widget build(BuildContext context) {
    final toast = _shown;
    return Stack(
      children: [
        widget.child,
        if (toast != null)
          AnimatedBuilder(
            animation: _motion,
            builder: (context, _) => _layout(context, toast),
          ),
      ],
    );
  }

  Widget _layout(BuildContext context, LiquidToast toast) {
    final mq = MediaQuery.of(context);
    final cs = Theme.of(context).colorScheme;
    final color = toast.color ?? FloatingBar.tileColor(cs);
    final ink = toast.ink ?? cs.onSurface;
    final width = _width(mq.size);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final restBottom = mq.padding.bottom +
        FloatingBar.bottomMargin +
        (_bar ? FloatingBar.height + 12 : 0);
    final centerY = mq.size.height - restBottom - _height / 2;
    final t = _t.value.clamp(0.0, 1.0);
    // капля выходит из-за края, а растекается в плитку уже на лету
    final grow = ((t - 0.2) / 0.8).clamp(0.0, 1.0);
    final size = Size.lerp(_drop, Size(width, _height), Curves.easeOut.transform(grow))!;
    final restStart = (mq.size.width - width) / 2;
    // начало за краем на всю склейку: бугорок у края тает, а не обрывается
    final start =
        -_drop.width - _goo + (restStart + _drop.width + _goo) * t - _pull.value;
    final rect = Rect.fromLTWH(
      rtl ? mq.size.width - start - size.width : start,
      centerY - size.height / 2,
      size.width,
      size.height,
    );
    // склейка с краем только в пути: в покое плитка стоит отдельно, а утянутую край ловит
    final goo = math.max(
      _goo * (t / 0.2).clamp(0.0, 1.0) * ((1 - t) / 0.25).clamp(0.0, 1.0),
      _pull.value.clamp(0.0, _goo),
    );
    final radius = math.min(_radius, size.height / 2);
    final edge = rtl ? (-1.0, 0.0, -mq.size.width) : (1.0, 0.0, 0.0);
    return Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _DropPainter(
                  shader: _shader,
                  rect: rect,
                  color: color,
                  radius: radius,
                  goo: goo,
                  edge: edge,
                  dpr: mq.devicePixelRatio,
                ),
              ),
            ),
          ),
          Positioned.fromRect(
            rect: rect,
            child: GestureDetector(
              onHorizontalDragUpdate: (d) => _onDragUpdate(d, rtl),
              onHorizontalDragEnd: (d) => _onDragEnd(d, rtl),
              onHorizontalDragCancel: () => _onDragEnd(DragEndDetails(), rtl),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: OverflowBox(
                  alignment: AlignmentDirectional.centerStart,
                  minWidth: width,
                  maxWidth: width,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: _SizeReporter(
                    onSize: _onSize,
                    child: Material(
                      type: MaterialType.transparency,
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(minHeight: FloatingBar.height),
                        child: Opacity(
                          opacity: ((grow - 0.6) / 0.4).clamp(0.0, 1.0),
                          child: _content(context, toast, ink),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
    );
  }

  Widget _content(BuildContext context, LiquidToast toast, Color ink) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          if (toast.icon != null) ...[
            Icon(toast.icon, size: 22, color: ink),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: DefaultTextStyle.merge(
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: ink),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              child: IconTheme.merge(
                data: IconThemeData(color: ink),
                child: toast.message,
              ),
            ),
          ),
          if (toast.actionLabel != null)
            TextButton(
              onPressed: () {
                toast.onAction?.call();
                LiquidToast.hide();
              },
              style: TextButton.styleFrom(foregroundColor: ink),
              child: Text(toast.actionLabel!),
            ),
        ],
      ),
    );
  }
}

class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderSizeReporter renderObject) {
    renderObject.onSize = onSize;
  }
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;

  @override
  void performLayout() {
    super.performLayout();
    onSize(size);
  }
}

class _DropPainter extends CustomPainter {
  _DropPainter({
    required this.shader,
    required this.rect,
    required this.color,
    required this.radius,
    required this.goo,
    required this.edge,
    required this.dpr,
  });

  final ui.FragmentShader? shader;
  final Rect rect;
  final Color color;
  final double radius;
  final double goo;
  final (double, double, double) edge;
  final double dpr;

  @override
  void paint(Canvas canvas, Size size) {
    final shader = this.shader;
    if (shader == null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        Paint()..color = color,
      );
      return;
    }
    var i = 0;
    for (final v in [
      size.width,
      size.height,
      dpr,
      rect.left,
      rect.top,
      rect.right,
      rect.bottom,
      radius,
      edge.$1,
      edge.$2,
      edge.$3,
      goo,
      color.r,
      color.g,
      color.b,
      color.a,
    ]) {
      shader.setFloat(i++, v);
    }
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_DropPainter old) =>
      old.rect != rect ||
      old.color != color ||
      old.radius != radius ||
      old.goo != goo ||
      old.edge != edge ||
      old.dpr != dpr ||
      old.shader != shader;
}
