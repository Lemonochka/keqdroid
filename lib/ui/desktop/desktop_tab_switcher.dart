import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../shared/ui/expressive.dart';

// как IndexedStack: живут все три, скрытые не рисуются и не ловят нажатия и фокус.
// тикеры у скрытых стоят, иначе гифки подписок крутятся и на чужой вкладке
class DesktopTabSwitcher extends StatefulWidget {
  const DesktopTabSwitcher({
    super.key,
    required this.index,
    required this.children,
    this.preparing,
    this.onPrepared,
  });

  final int index;
  final List<Widget> children;

  // под выключенным TickerMode Riverpod 3 держит подписки виджета на паузе, и скрытая вкладка до первого
  // показа пустая. её первый кадр со сборкой шейдеров Skia стоил 75 мс посреди перехода, поэтому новую
  // вкладку пару кадров рисуют под текущей, а переход начинают после
  final int? preparing;
  final ValueChanged<int>? onPrepared;

  static const double shift = 56;

  @override
  State<DesktopTabSwitcher> createState() => _DesktopTabSwitcherState();
}

typedef _Under = ({int index, double opacity, double dy});

class _DesktopTabSwitcherState extends State<DesktopTabSwitcher>
    with SingleTickerProviderStateMixin {
  late int _to = widget.index;
  var _under = <_Under>[];
  int _dir = 1;
  late final _t = AnimationController.unbounded(vsync: this, value: 1);

  @override
  void initState() {
    super.initState();
    final i = widget.preparing;
    if (i != null) _prepare(i, 0);
  }

  // пока идёт переход, снизу её было бы видно сквозь проявляющуюся вкладку
  bool get _canPrepare => _under.isEmpty;

  // два кадра: третий движок не начнёт, пока не растеризует тяжёлый первый, и переход тронется уже после него
  void _prepare(int i, int painted) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.preparing != i) return;
      if (_canPrepare) painted++;
      if (painted >= 2) {
        widget.onPrepared?.call(i);
        return;
      }
      _prepare(i, painted);
      SchedulerBinding.instance.scheduleFrame();
    });
  }

  // новая проявляется поверх уходящей, а та гаснет, только когда её уже накрыли.
  // через ноль, как в спеке M3, экран 75 мс проваливался в фон и моргал
  double _inOpacity(double t) => (t / 0.5).clamp(0.0, 1.0);
  double _inOffset(double t) => _dir * DesktopTabSwitcher.shift * (1 - t);
  double _underOpacity(_Under l, double t) =>
      l.opacity * (1 - ((t - 0.5) / 0.3).clamp(0.0, 1.0));
  double _underOffset(_Under l, double t) =>
      l.dy - _dir * DesktopTabSwitcher.shift * t;

  @override
  void didUpdateWidget(DesktopTabSwitcher old) {
    super.didUpdateWidget(old);
    final preparing = widget.preparing;
    if (preparing != null && preparing != old.preparing) _prepare(preparing, 0);
    if (widget.index == _to) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _t.value = 1;
      _under = [];
      _to = widget.index;
      return;
    }
    // перебили на ходу: всё, что было видно, остаётся под новой как было, иначе вспышка
    final t = _t.value;
    final moving = _under.isNotEmpty;
    _under = [
      for (final l in _under)
        if (l.index != widget.index && _underOpacity(l, t) > 0)
          (index: l.index, opacity: _underOpacity(l, t), dy: _underOffset(l, t)),
      (
        index: _to,
        opacity: moving ? _inOpacity(t) : 1,
        dy: moving ? _inOffset(t) : 0,
      ),
    ];
    _dir = widget.index > _to ? 1 : -1;
    _to = widget.index;
    _t.value = 0;
    ExpressiveMotion.springTo(_t, 1,
            spring: ExpressiveMotion.spatialSlow, snapToEnd: true)
        .whenComplete(() {
      if (mounted) setState(() => _under = []);
    });
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final t = _t.value;
        final under = {for (final l in _under) l.index};
        return Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < widget.children.length; i++)
              if (i != _to && !under.contains(i))
                _layer(i,
                    shown: false,
                    preparing: i == widget.preparing && _canPrepare),
            for (final l in _under)
              _layer(l.index,
                  opacity: _underOpacity(l, t), dy: _underOffset(l, t)),
            if (_under.isEmpty)
              _layer(_to)
            else
              _layer(_to, opacity: _inOpacity(t), dy: _inOffset(t)),
          ],
        );
      },
    );
  }

  Widget _layer(
    int i, {
    bool shown = true,
    bool preparing = false,
    double opacity = 1,
    double dy = 0,
  }) {
    final current = i == _to;
    return KeyedSubtree(
      key: ValueKey(i),
      child: Offstage(
        offstage: !shown && !preparing,
        child: TickerMode(
          enabled: shown || preparing,
          child: ExcludeFocus(
            excluding: !current,
            child: ExcludeSemantics(
              excluding: !current,
              child: IgnorePointer(
                ignoring: !current,
                child: Opacity(
                  opacity: opacity,
                  child: Transform.translate(
                    offset: Offset(0, dy),
                    child: widget.children[i],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
