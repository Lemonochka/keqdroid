import 'dart:math';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

// показывает долю сливера сверху и обрезает остальное. AnimatedSize над группой строил бы
// все её плитки разом, а так ленивый список внутри строит только видимые
class SliverReveal extends SingleChildRenderObjectWidget {
  const SliverReveal({super.key, required this.factor, required Widget sliver})
      : super(child: sliver);

  final double factor;

  @override
  RenderSliverReveal createRenderObject(BuildContext context) =>
      RenderSliverReveal(factor);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSliverReveal renderObject,
  ) =>
      renderObject.factor = factor;
}

class RenderSliverReveal extends RenderProxySliver {
  RenderSliverReveal(this._factor);

  double _factor;
  double get factor => _factor;
  set factor(double value) {
    if (value == _factor) return;
    _factor = value;
    markNeedsLayout();
  }

  final _clip = LayerHandle<ClipRectLayer>();

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      geometry = SliverGeometry.zero;
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    final full = child.geometry!;
    if (full.scrollOffsetCorrection != null) {
      geometry = full;
      return;
    }
    // пружина перелетает за 1: группа чуть вытягивается и возвращается
    final extent = full.scrollExtent * max(0.0, _factor);
    final paintExtent = calculatePaintOffset(constraints, from: 0, to: extent);
    geometry = SliverGeometry(
      scrollExtent: extent,
      paintExtent: paintExtent,
      maxPaintExtent: extent,
      cacheExtent: calculateCacheOffset(constraints, from: 0, to: extent),
      hitTestExtent: paintExtent,
      hasVisualOverflow: _factor < 1 || full.hasVisualOverflow,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    final paintExtent = geometry!.paintExtent;
    if (child == null || !child.geometry!.visible || paintExtent <= 0) {
      _clip.layer = null;
      return;
    }
    final downward = applyGrowthDirectionToAxisDirection(
          constraints.axisDirection,
          constraints.growthDirection,
        ) ==
        AxisDirection.down;
    if (_factor >= 1 || !downward) {
      _clip.layer = null;
      super.paint(context, offset);
      return;
    }
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & Size(constraints.crossAxisExtent, paintExtent),
      super.paint,
      oldLayer: _clip.layer,
    );
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }
}
