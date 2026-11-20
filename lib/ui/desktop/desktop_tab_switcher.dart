import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/ui/expressive.dart';

// как IndexedStack: живут все три, скрытые не рисуются и не ловят нажатия и фокус;
// тикеры у скрытых стоят, иначе гифки подписок крутятся и на чужой вкладке
class DesktopTabSwitcher extends StatefulWidget {
  const DesktopTabSwitcher({
    super.key,
    required this.index,
    required this.children,
    this.warmUpAfter,
    this.windowHidden,
  });

  final int index;
  final List<Widget> children;

  // Skia на Windows собирает шейдеры при первом показе и не хранит их между запусками: первый заход на подписки
  // стоил 75 мс растра посреди перехода, поэтому скрытые вкладки заранее рисуются под текущей
  final Duration? warmUpAfter;

  // в трее окна не видно, и тогда прогоняются ещё и позы самого перехода
  final bool Function()? windowHidden;

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

  Timer? _warmTimer;
  // стопка одного кадра прогрева снизу вверх, null когда прогрева нет
  List<_Under>? _scene;

  @override
  void initState() {
    super.initState();
    final after = widget.warmUpAfter;
    if (after != null) _warmTimer = Timer(after, _warmUp);
  }

  void _warmUp() {
    _warmTimer = null;
    if (!mounted) return;
    if (_under.isNotEmpty || !SchedulerBinding.instance.framesEnabled) {
      _warmTimer = Timer(const Duration(seconds: 1), _warmUp);
      return;
    }
    final current = _to;
    final hidden = [
      for (var i = 0; i < widget.children.length; i++)
        if (i != current) i,
    ];
    // под выключенным TickerMode Riverpod 3 держит подписки виджета на паузе, и скрытая вкладка с запуска
    // показывает загрузку; перестройка читает свежие данные, пауза при этом остаётся
    _rebuildConsumers(hidden.toSet());
    final scenes = <List<_Under>>[
      for (final opacity in const [1.0, 0.5])
        [
          for (final i in hidden) (index: i, opacity: opacity, dy: 0.0),
          (index: current, opacity: 1.0, dy: 0.0),
        ],
      if (widget.windowHidden?.call() ?? false)
        for (final i in hidden)
          for (final (from, to) in [(current, i), (i, current)])
            for (final t in const [0.2, 0.65])
              [
                (
                  index: from,
                  opacity: _fade(t),
                  dy: -_sign(from, to) * DesktopTabSwitcher.shift * t,
                ),
                (
                  index: to,
                  opacity: _inOpacity(t),
                  dy: _sign(from, to) * DesktopTabSwitcher.shift * (1 - t),
                ),
              ],
    ];
    _play(scenes, 0, current);
  }

  void _play(List<List<_Under>> scenes, int k, int current) {
    if (!mounted || _to != current) return;
    setState(() => _scene = k < scenes.length ? scenes[k] : null);
    if (_scene == null) return;
    SchedulerBinding.instance.addPostFrameCallback((_) => _play(scenes, k + 1, current));
  }

  void _rebuildConsumers(Set<int> tabs) {
    void mark(Element e) {
      if (e is WidgetRef) e.markNeedsBuild();
      e.visitChildren(mark);
    }

    void find(Element e) {
      final key = e.widget.key;
      if (e.widget is KeyedSubtree && key is ValueKey<int> && tabs.contains(key.value)) {
        e.visitChildren(mark);
        return;
      }
      e.visitChildren(find);
    }

    context.visitChildElements(find);
  }

  int _sign(int from, int to) => to > from ? 1 : -1;

  // новая проявляется поверх уходящей, а та гаснет, только когда её уже накрыли;
  // через ноль, как в спецификации M3, экран 75 мс проваливался в фон и моргал
  double _inOpacity(double t) => (t / 0.5).clamp(0.0, 1.0);
  double _fade(double t) => 1 - ((t - 0.5) / 0.3).clamp(0.0, 1.0);
  double _inOffset(double t) => _dir * DesktopTabSwitcher.shift * (1 - t);
  double _underOpacity(_Under l, double t) => l.opacity * _fade(t);
  double _underOffset(_Under l, double t) =>
      l.dy - _dir * DesktopTabSwitcher.shift * t;

  @override
  void didUpdateWidget(DesktopTabSwitcher old) {
    super.didUpdateWidget(old);
    if (widget.index == _to) return;
    _scene = null;
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
    _warmTimer?.cancel();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final scene = _scene;
        if (scene != null) {
          final inScene = {for (final l in scene) l.index};
          return Stack(
            fit: StackFit.expand,
            children: [
              for (var i = 0; i < widget.children.length; i++)
                if (!inScene.contains(i)) _layer(i, shown: false),
              for (final l in scene)
                _layer(l.index,
                    shown: l.index == _to, warm: true, opacity: l.opacity, dy: l.dy),
            ],
          );
        }
        final t = _t.value;
        final under = {for (final l in _under) l.index};
        return Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < widget.children.length; i++)
              if (i != _to && !under.contains(i)) _layer(i, shown: false),
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
    bool warm = false,
    double opacity = 1,
    double dy = 0,
  }) {
    final current = i == _to;
    return KeyedSubtree(
      key: ValueKey(i),
      child: Offstage(
        offstage: !shown && !warm,
        child: TickerMode(
          enabled: shown,
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
