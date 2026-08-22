/// Перетекание шапки, когда контент заходит под неё.
///
/// Штатный механизм Flutter здесь бинарный: `AppBar` резолвит цвет по
/// состоянию `WidgetState.scrolledUnder`, и цвет меняется рывком в тот момент,
/// когда `extentBefore` становится больше нуля. Смягчить это флагом
/// `AppBar.animateColor` не выходит по двум причинам: его нет в
/// `AppBarThemeData` (пришлось бы дублировать на каждом экране) и его нет у
/// `SliverAppBar` вовсе — экраны с крупным заголовком остались бы резкими.
///
/// Поэтому прогресс считаем сами и привязываем к смещению прокрутки, а не ко
/// времени: заливка догоняет палец, а не стартует после него. У анимации по
/// таймеру на быстром флике видно отставание — цвет доезжает, когда список уже
/// остановился.
///
/// Подписка идёт на тот же `ScrollNotificationObserver`, которым пользуется
/// сам `AppBar`: его ставит `Scaffold` вокруг своего тела, поэтому никакой
/// обёртки над экраном не нужно — шапка подписывается сама, где бы она ни
/// стояла (в `Scaffold.appBar` или внутри списка слайверов).
library;

import 'package:flutter/material.dart';

/// Пересобирает ТОЛЬКО то, что вернёт [builder], — то есть саму шапку, а не
/// тело экрана.
///
/// Возвращать можно и обычный виджет, и слайвер: перестройкой занимается сам
/// этот виджет, а наружу он отдаёт результат [builder] как есть.
class ExpressiveScrolledUnderBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, Color background) builder;

  /// На какой дистанции прокрутки заливка доезжает до конечного уровня.
  /// 32 логических пикселя: заметно короче одного «щелчка» списка, поэтому
  /// переход читается как отклик на движение, а не как отдельная анимация.
  final double distance;

  const ExpressiveScrolledUnderBuilder({
    super.key,
    required this.builder,
    this.distance = 32,
  });

  @override
  State<ExpressiveScrolledUnderBuilder> createState() =>
      _ExpressiveScrolledUnderBuilderState();
}

class _ExpressiveScrolledUnderBuilderState
    extends State<ExpressiveScrolledUnderBuilder> {
  ScrollNotificationObserverState? _observer;
  double _progress = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final observer = ScrollNotificationObserver.maybeOf(context);
    if (observer == _observer) return;
    _observer?.removeListener(_onNotification);
    _observer = observer;
    _observer?.addListener(_onNotification);
  }

  @override
  void dispose() {
    _observer?.removeListener(_onNotification);
    _observer = null;
    super.dispose();
  }

  void _onNotification(ScrollNotification notification) {
    final metrics = notification.metrics;
    // Горизонтальные прокрутки (ряды чипов, свайп вкладок) под шапку ничего не
    // заводят — иначе они красили бы её заодно.
    if (metrics.axis != Axis.vertical) return;
    // Вложенные списки (например, список внутри карточки) не считаем: под
    // шапку заходит только основная прокрутка страницы.
    if (notification.depth != 0) return;

    final next = (metrics.extentBefore / widget.distance).clamp(0.0, 1.0);
    // Порог в четверть процента: цвет всё равно квантуется до 8 бит на канал,
    // а лишние setState на каждый пиксель прокрутки не бесплатны.
    if ((next - _progress).abs() < 0.0025) return;
    setState(() => _progress = next);
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, scrolledUnderColour(context, _progress));
}

/// То же самое, но пригодное для `Scaffold.appBar` — реализует
/// `PreferredSizeWidget`.
///
/// Высоту приходится объявлять снаружи: у экранов она разная (обычная шапка,
/// шапка с `TabBar`), а посчитать её здесь, не построив содержимое, нельзя.
class ExpressiveScrolledUnderBar extends StatelessWidget
    implements PreferredSizeWidget {
  final Widget Function(BuildContext context, Color background) builder;

  @override
  final Size preferredSize;

  const ExpressiveScrolledUnderBar({
    super.key,
    required this.builder,
    this.preferredSize = const Size.fromHeight(kToolbarHeight),
  });

  @override
  Widget build(BuildContext context) =>
      ExpressiveScrolledUnderBuilder(builder: builder);
}

/// Цвет шапки для прогресса [t].
///
/// Уровни те же, что в `appBarTheme`: иерархию несёт `surfaceContainer`, а не
/// тень с оттенком. Здесь просто появились промежуточные состояния.
Color scrolledUnderColour(BuildContext context, double t) {
  final scheme = Theme.of(context).colorScheme;
  return Color.lerp(scheme.surface, scheme.surfaceContainer, t)!;
}
