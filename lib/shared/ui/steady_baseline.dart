import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

// Skia ставит строку текста ровно в пиксель экрана. если место строки складывается из встречных сдвигов
// (подпись последней обложки быстрого перехода, пока стопка садится на дно) и выпадает на середину
// пикселя, сотые доли перекидывали её на 1 px туда и обратно
class SteadyBaseline extends SingleChildRenderObjectWidget {
  const SteadyBaseline({super.key, required super.child});

  @override
  RenderSteadyBaseline createRenderObject(BuildContext context) =>
      RenderSteadyBaseline(MediaQuery.devicePixelRatioOf(context));

  @override
  void updateRenderObject(BuildContext context, RenderSteadyBaseline renderObject) =>
      renderObject.devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
}

class RenderSteadyBaseline extends RenderProxyBox {
  RenderSteadyBaseline(this.devicePixelRatio);

  double devicePixelRatio;
  double? _row;
  double _dy = 0;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final toRoot = getTransformTo(null);
    final base = child.getDistanceToBaseline(TextBaseline.alphabetic) ?? 0;
    // корень может уже умножать на масштаб экрана, может и нет
    final y = MatrixUtils.transformPoint(toRoot, Offset(0, base)).dy *
        devicePixelRatio /
        toRoot.getMaxScaleOnAxis();
    final row = _row;
    // запас больше половины пикселя: на самой середине и сотые доли перекидывали бы строку
    if (row == null || (y - row).abs() > 0.75) _row = y.roundToDouble();
    _dy = (_row! - y) / devicePixelRatio;
    context.paintChild(child, offset.translate(0, _dy));
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.translateByDouble(0, _dy, 0, 1);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintOffset(
        offset: Offset(0, _dy),
        position: position,
        hitTest: (result, position) => child?.hitTest(result, position: position) ?? false,
      );
}
