import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

typedef ReorderProxyFix =
    Widget Function(Widget proxy, Animation<double> animation);

// перенос в ReorderableList ставит поднятый элемент по экранной точке пальца минус точке
// захвата внутри элемента. под масштабом интерфейса (_UiZoom в app.dart) это разные единицы,
// и элемент уезжал вбок. логику выбора места не трогаем, поправляем только рисование
class ReorderZoomFix extends StatefulWidget {
  const ReorderZoomFix({super.key, required this.builder});

  final Widget Function(BuildContext context, ReorderProxyFix fix) builder;

  @override
  State<ReorderZoomFix> createState() => _ReorderZoomFixState();
}

class _ReorderZoomFixState extends State<ReorderZoomFix> {
  final _pointer = _DragPointer();

  Widget _fix(Widget proxy, Animation<double> animation) =>
      _ZoomedDragProxy(pointer: _pointer, animation: animation, child: proxy);

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => _pointer
        ..down = e.position
        ..current = e.position,
      onPointerMove: (e) => _pointer.current = e.position,
      child: widget.builder(context, _fix),
    );
  }
}

class _DragPointer {
  Offset? down;
  Offset? current;

  // список тянется только по вертикали: Flutter держит x точки захвата
  Offset? get dragPosition {
    final d = down;
    final c = current;
    return d == null || c == null ? null : Offset(d.dx, c.dy);
  }
}

class _ZoomedDragProxy extends SingleChildRenderObjectWidget {
  const _ZoomedDragProxy({
    required this.pointer,
    required this.animation,
    required super.child,
  });

  final _DragPointer pointer;
  final Animation<double> animation;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderZoomedDragProxy(pointer, animation);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderZoomedDragProxy renderObject,
  ) {
    renderObject
      ..pointer = pointer
      ..animation = animation
      ..markNeedsPaint();
  }
}

class _RenderZoomedDragProxy extends RenderProxyBox {
  _RenderZoomedDragProxy(this.pointer, this.animation);

  _DragPointer pointer;
  Animation<double> animation;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final origin = localToGlobal(Offset.zero);
    final scale = (localToGlobal(const Offset(1, 0)) - origin).dx;
    final drag = pointer.dragPosition;
    if (drag == null || scale <= 0 || (scale - 1).abs() < 0.001) {
      context.paintChild(child, offset);
      return;
    }
    final k = 1 / scale - 1;
    final lifted = drag * k;
    // при броске Flutter ведёт элемент к месту в тех же смешанных единицах
    final shift = animation.status == AnimationStatus.reverse
        ? Offset.lerp(origin / scale * k, lifted, animation.value)!
        : lifted;
    context.paintChild(child, offset + shift);
  }
}
