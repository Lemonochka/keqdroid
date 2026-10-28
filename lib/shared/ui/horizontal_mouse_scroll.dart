import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show CarouselController;
import 'package:flutter/widgets.dart';

// колесо шлёт только dy, а горизонтальный Scrollable берёт dx, и мыши нет в dragDevices
class HorizontalMouseScroll extends StatefulWidget {
  const HorizontalMouseScroll({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController controller;

  final Widget child;

  @override
  State<HorizontalMouseScroll> createState() => _HorizontalMouseScrollState();
}

class _HorizontalMouseScrollState extends State<HorizontalMouseScroll> {
  double _wheel = 0;
  int? _target;
  Timer? _idle;

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.mouse,
        },
      ),
      child: Listener(onPointerSignal: _onPointerSignal, child: widget.child),
    );
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // только dy: горизонтальную дельту Scrollable разбирает сам
    final delta = event.scrollDelta.dy;
    final controller = widget.controller;
    if (delta == 0 || !controller.hasClients) return;
    final position = controller.position;
    // у края колесо отдаём странице вокруг
    final atStart = position.pixels <= position.minScrollExtent &&
        (controller is! CarouselController || (_target ?? 0) <= 0);
    if (delta > 0 ? position.pixels >= position.maxScrollExtent : atStart) return;
    // забираем щелчок себе, иначе его же разбирала страница вокруг
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (controller is CarouselController) {
        _step(controller, delta);
      } else {
        // pointerScroll, а не jumpTo: тот же вход, что у Scrollable, сглаживание остаётся
        position.pointerScroll(delta);
      }
    });
  }

  // карусель с привязкой после pointerScroll доводилась обратно к той же картинке. шагаем по
  // картинке на щелчок сразу, от цели, а не от того, куда успела доехать анимация
  void _step(CarouselController controller, double delta) {
    if (_wheel.sign != delta.sign) _wheel = 0;
    _wheel += delta;
    if (_wheel.abs() < 40) return;
    _wheel = 0;
    final next = math.max(0, (_target ?? controller.leadingItem) + (delta > 0 ? 1 : -1));
    _target = next;
    controller.animateToItem(
      next,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    _idle?.cancel();
    _idle = Timer(const Duration(milliseconds: 400), () => _target = null);
  }
}
