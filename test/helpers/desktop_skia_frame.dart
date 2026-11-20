import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Кадр, собранный из слоёв так, как его собирает движок на ПК. Skia с растровым
/// кэшем ставит начало DisplayListLayer, OpacityLayer и клипа с saveLayer в целый
/// пиксель экрана (ComputeIntegralTransCTM в engine/src/flutter/flow), а
/// `matchesGoldenFile` рисует без кэша и этих прыжков не показывает.
class DesktopSkiaFrame {
  DesktopSkiaFrame._(this._rgba, this.width, this.height);

  final Uint8List _rgba;
  final int width;
  final int height;

  Uint8List get rgba => _rgba;

  static Future<DesktopSkiaFrame> capture(
    WidgetTester tester, {
    bool snap = true,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawColor(const Color(0xFF000000), BlendMode.src);
    _Compositor(
      canvas,
      snap,
    ).paint(tester.binding.renderViews.first.debugLayer!, Matrix4.identity());
    final picture = recorder.endRecording();
    final size = tester.view.physicalSize;
    final w = size.width.toInt(), h = size.height.toInt();
    final rgba = await tester.runAsync(() async {
      final image = await picture.toImage(w, h);
      final data = await image.toByteData();
      image.dispose();
      return data!.buffer.asUint8List();
    });
    picture.dispose();
    return DesktopSkiaFrame._(rgba!, w, h);
  }

  /// Верхний и нижний край того, что в столбце [x] покрывает [coverage] (0..1 на
  /// пиксель), с долями пикселя по сглаживанию. Строки от [from] до [to].
  ({double top, double bottom})? edges(
    int x,
    double Function(Color pixel) coverage, {
    required int from,
    required int to,
  }) {
    double at(int y) {
      final i = (y * width + x) * 4;
      return coverage(
        Color.fromARGB(255, _rgba[i], _rgba[i + 1], _rgba[i + 2]),
      ).clamp(0.0, 1.0);
    }

    int? first, last;
    for (var y = from.clamp(0, height); y < to.clamp(0, height); y++) {
      if (at(y) > 0.03) {
        first ??= y;
        last = y;
      }
    }
    if (first == null) return null;
    return (top: first + 1 - at(first), bottom: last! + at(last));
  }
}

class _Compositor {
  _Compositor(this.canvas, this.snap);

  final Canvas canvas;
  final bool snap;

  Matrix4 _integral(Matrix4 ctm) {
    final m = ctm.storage;
    final scaleTranslate =
        m[1] == 0 &&
        m[2] == 0 &&
        m[3] == 0 &&
        m[4] == 0 &&
        m[6] == 0 &&
        m[7] == 0 &&
        m[8] == 0 &&
        m[9] == 0 &&
        m[11] == 0 &&
        m[15] == 1;
    if (!snap || !scaleTranslate) return ctm;
    final out = ctm.clone();
    out.storage[12] = m[12].roundToDouble();
    out.storage[13] = m[13].roundToDouble();
    return out;
  }

  void _children(ContainerLayer layer, Matrix4 ctm) {
    for (
      var child = layer.firstChild;
      child != null;
      child = child.nextSibling
    ) {
      paint(child, ctm);
    }
  }

  void _clip(ContainerLayer layer, Path path, Clip behavior, Matrix4 ctm) {
    canvas
      ..save()
      ..clipPath(
        path.transform(ctm.storage),
        doAntiAlias: behavior != Clip.hardEdge,
      );
    if (behavior == Clip.antiAliasWithSaveLayer) {
      canvas.saveLayer(null, Paint());
      _children(layer, _integral(ctm));
      canvas.restore();
    } else {
      _children(layer, ctm);
    }
    canvas.restore();
  }

  void paint(Layer layer, Matrix4 ctm) {
    switch (layer) {
      case PictureLayer():
        canvas
          ..save()
          ..transform(_integral(ctm).storage)
          ..drawPicture(layer.picture!)
          ..restore();
      case TransformLayer():
        final t = Matrix4.translationValues(layer.offset.dx, layer.offset.dy, 0)
          ..multiply(layer.transform!);
        _children(layer, ctm.multiplied(t));
      case OpacityLayer():
        final at = ctm.multiplied(
          Matrix4.translationValues(layer.offset.dx, layer.offset.dy, 0),
        );
        canvas.saveLayer(
          null,
          Paint()..color = Color.fromARGB(layer.alpha ?? 255, 0, 0, 0),
        );
        _children(layer, _integral(at));
        canvas.restore();
      case OffsetLayer():
        _children(
          layer,
          ctm.multiplied(
            Matrix4.translationValues(layer.offset.dx, layer.offset.dy, 0),
          ),
        );
      case ClipRectLayer():
        _clip(layer, Path()..addRect(layer.clipRect!), layer.clipBehavior, ctm);
      case ClipRRectLayer():
        _clip(
          layer,
          Path()..addRRect(layer.clipRRect!),
          layer.clipBehavior,
          ctm,
        );
      case ClipPathLayer():
        _clip(layer, layer.clipPath!, layer.clipBehavior, ctm);
      case AnnotatedRegionLayer():
        _children(layer, ctm);
      case ContainerLayer() when layer.runtimeType == ContainerLayer:
        _children(layer, ctm);
      default:
        throw UnsupportedError(
          '${layer.runtimeType} пока не умеет: допиши по flow/layers',
        );
    }
  }
}
