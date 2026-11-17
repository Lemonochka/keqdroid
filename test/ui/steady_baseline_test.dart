import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/shared/ui/steady_baseline.dart';

/// Строка с базовой линией в 10 dp от верха: в paint пишет, где эта линия
/// оказалась на экране в физических пикселях, как её округлит Skia.
class _Line extends LeafRenderObjectWidget {
  const _Line(this.painted);
  final List<double> painted;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLine(painted);
}

class _RenderLine extends RenderBox {
  _RenderLine(this.painted);
  final List<double> painted;

  @override
  void performLayout() => size = constraints.constrain(const Size(100, 14));

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => 10;

  @override
  void paint(PaintingContext context, Offset offset) {
    final toRoot = getTransformTo(null);
    painted.add(MatrixUtils.transformPoint(toRoot, const Offset(0, 10)).dy *
        1.25 /
        toRoot.getMaxScaleOnAxis());
  }
}

Future<List<double>> _paintAt(
  WidgetTester tester,
  List<double> ys, {
  required bool steady,
}) async {
  tester.view.devicePixelRatio = 1.25;
  tester.view.physicalSize = const Size(500, 500);
  addTearDown(tester.view.reset);
  final painted = <double>[];
  final y = ValueNotifier(ys.first);
  addTearDown(y.dispose);
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: ValueListenableBuilder<double>(
      valueListenable: y,
      builder: (_, dy, child) => Transform.translate(offset: Offset(0, dy), child: child),
      child: Align(
        alignment: Alignment.topLeft,
        child: steady ? SteadyBaseline(child: _Line(painted)) : _Line(painted),
      ),
    ),
  ));
  painted.clear();
  for (final v in ys) {
    y.value = v;
    await tester.pump();
  }
  return painted;
}

void main() {
  // (100 + 10) * 1.25 = 137.5: базовая линия ровно на середине пикселя экрана
  final noisy = [for (var i = 0; i < 20; i++) 100 + (i.isEven ? 1e-4 : -1e-4)];

  testWidgets('на середине пикселя сотые доли не перекидывают строку', (tester) async {
    final rows = (await _paintAt(tester, noisy, steady: true)).map((y) => y.round()).toSet();
    expect(rows, hasLength(1));
  });

  testWidgets('без неё та же строка прыгает на пиксель туда и обратно', (tester) async {
    final rows = (await _paintAt(tester, noisy, steady: false)).map((y) => y.round()).toSet();
    expect(rows, hasLength(2));
  });

  testWidgets('в покое строка стоит на целом пикселе', (tester) async {
    final painted = await _paintAt(tester, [100.3, 100.31], steady: true);
    for (final y in painted) {
      expect(y, closeTo(y.roundToDouble(), 1e-6));
    }
  });

  testWidgets('на ходу строка ползёт с долей пикселя, а встав, доезжает до целого', (tester) async {
    // по 0,05 dp за кадр, как обложка в конце прокрутки
    final ys = [for (var i = 0; i <= 40; i++) 100.3 + i * 0.05];
    final painted = await _paintAt(tester, ys, steady: true);
    final steps = [for (var i = 1; i < painted.length; i++) painted[i] - painted[i - 1]];
    // ни одного прыжка на целый пиксель, только ход вместе со строкой
    expect(steps.every((s) => s >= 0 && s < 0.2), isTrue, reason: '$steps');
    final truth = (ys.last + 10) * 1.25;
    expect(painted.last, closeTo(truth, 0.5));

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(painted.last, closeTo(painted.last.roundToDouble(), 1e-6));
    expect(painted.last, closeTo(truth, 0.5));
    // доезд до целого пикселя плавный, тоже без прыжка
    final settle = painted.skip(ys.length);
    var prev = painted[ys.length - 1];
    for (final y in settle) {
      expect((y - prev).abs(), lessThan(0.5));
      prev = y;
    }
  });
}
