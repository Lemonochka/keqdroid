import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../platform/platform_bootstrap.dart';

// небо шире кнопки, но место в шапке занимает как она: раскладка от праздника не сдвигается
class HalloweenSky extends StatefulWidget {
  const HalloweenSky({super.key, required this.child});

  final Widget child;

  @override
  State<HalloweenSky> createState() => _HalloweenSkyState();
}

class _HalloweenSkyState extends State<HalloweenSky> {
  static const double _side = 136;

  ui.Image? _image;
  (ColorScheme, double)? _imageFor;

  // небо рисуется один раз в картинку: Impeller не кэширует слои, и размытия неба
  // пересчитывались в каждом кадре мерцания тыквы, +50% ядра на Pixel 6a
  ui.Image _sky(ColorScheme scheme, double ratio) {
    final cached = _image;
    if (cached != null && _imageFor == (scheme, ratio)) return cached;
    final recorder = ui.PictureRecorder();
    _SkyPainter(scheme, desktop: PlatformBootstrap.isDesktop).paint(
      Canvas(recorder)..scale(ratio),
      const Size(_SkyPainter.width, _SkyPainter.height),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      (_SkyPainter.width * ratio).ceil(),
      (_SkyPainter.height * ratio).ceil(),
    );
    picture.dispose();
    cached?.dispose();
    _imageFor = (scheme, ratio);
    return _image = image;
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _sky(
      Theme.of(context).colorScheme,
      MediaQuery.devicePixelRatioOf(context),
    );
    return SizedBox.square(
      dimension: _side,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -_SkyPainter.dx,
            top: -_SkyPainter.dy,
            width: _SkyPainter.width,
            height: _SkyPainter.height,
            child: IgnorePointer(
              child: RepaintBoundary(
                child: RawImage(
                  image: image,
                  width: _SkyPainter.width,
                  height: _SkyPainter.height,
                  fit: BoxFit.fill,
                ),
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _SkyPainter extends CustomPainter {
  _SkyPainter(this.scheme, {required this.desktop});

  final ColorScheme scheme;
  final bool desktop;

  static const dx = 190.0, dy = 40.0, width = 516.0, height = 210.0;

  static Rect _o(double x, double y, double w, double h) =>
      Rect.fromCenter(center: Offset(x, y), width: w, height: h);

  static Path _night(double baseY, List<Rect> lobes) {
    var p = Path();
    for (final r in lobes) {
      p = Path.combine(PathOperation.union, p, Path()..addOval(r));
    }
    return Path.combine(
      PathOperation.intersect,
      p,
      Path()..addRect(Rect.fromLTRB(-1000, -1000, 1000, baseY)),
    );
  }

  static (Path, List<Rect>) _day(
    double left,
    double right,
    double baseY,
    double thick,
    List<Rect> lobes,
  ) {
    final w = right - left;
    var p = Path()
      ..moveTo(left, baseY - 2)
      ..cubicTo(
        left + w * .3,
        baseY + 3,
        left + w * .7,
        baseY + 3,
        right,
        baseY - 2,
      )
      ..cubicTo(
        left + w * .7,
        baseY - thick,
        left + w * .3,
        baseY - thick,
        left,
        baseY - 2,
      )
      ..close();
    for (final r in lobes) {
      p = Path.combine(PathOperation.union, p, Path()..addOval(r));
    }
    return (p, lobes);
  }

  static final _nightClouds = [
    _night(46, [
      _o(-64, 32, 36, 32),
      _o(-85, 40, 26, 18),
      _o(-44, 38, 28, 20),
      _o(-26, 43, 34, 8),
      _o(-100, 44, 20, 6),
    ]),
    _night(76, [_o(-78, 70, 18, 14), _o(-65, 73, 18, 8), _o(-90, 74, 14, 5)]),
    _night(34, [
      _o(196, 20, 36, 32),
      _o(175, 27, 26, 18),
      _o(215, 26, 24, 18),
      _o(236, 31, 36, 8),
      _o(158, 32, 18, 6),
    ]),
    _night(86, [_o(216, 80, 18, 13), _o(229, 83, 20, 7), _o(204, 84, 12, 5)]),
    _night(104, [_o(182, 99, 13, 10), _o(191, 102, 16, 5)]),
  ];

  static final _dayClouds = [
    _day(146, 258, 64, 14, [
      _o(214, 42, 46, 34),
      _o(236, 52, 30, 20),
      _o(192, 50, 34, 20),
      _o(172, 57, 22, 10),
    ]),
    _day(-120, -30, 74, 10, [
      _o(-92, 63, 34, 20),
      _o(-74, 66, 24, 12),
      _o(-106, 68, 18, 9),
    ]),
    _day(-82, -22, 30, 8, [
      _o(-56, 21, 26, 16),
      _o(-42, 25, 18, 9),
      _o(-68, 26, 14, 7),
    ]),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 1.2, sigmaY: 1.2),
    );
    // на ПК над кнопкой меньше места, и ореол упирался в край окна
    canvas.translate(dx, dy + (desktop ? 12 : 0));
    final dark = scheme.brightness == Brightness.dark;
    final center = dark ? const Offset(-64, 20) : const Offset(196, 30);
    final light = dark ? const Color(0xFFF1EAFF) : const Color(0xFFFFC09A);
    final halo = dark ? scheme.secondary : const Color(0xFFFFB27E);
    final body = dark
        ? Path.combine(
            PathOperation.difference,
            Path()..addOval(Rect.fromCircle(center: center, radius: 24)),
            Path()..addOval(
              Rect.fromCircle(
                center: center + const Offset(11, -7),
                radius: 21,
              ),
            ),
          )
        : (Path()..addOval(Rect.fromCircle(center: center, radius: 21)));

    void drawLight({
      double blur = 0,
      double alpha = 1,
      BlendMode mode = BlendMode.srcOver,
    }) {
      canvas.drawCircle(
        center,
        52,
        Paint()
          ..blendMode = mode
          ..shader = RadialGradient(
            colors: [
              halo.withValues(alpha: (dark ? .22 : .35) * alpha),
              halo.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: 52)),
      );
      final p = Paint()
        ..blendMode = mode
        ..color = light.withValues(alpha: alpha);
      if (blur > 0) p.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
      canvas.drawPath(body, p);
    }

    drawLight();
    if (dark) {
      _paintNight(canvas, drawLight);
    } else {
      _paintDay(canvas, drawLight);
    }
    canvas.restore();
  }

  void _paintNight(
    Canvas canvas,
    void Function({double blur, double alpha, BlendMode mode}) drawLight,
  ) {
    final top = Color.lerp(
      scheme.surfaceContainerHigh,
      scheme.onSurface,
      .26,
    )!.withValues(alpha: .84);
    final bottom = Color.lerp(
      scheme.surfaceContainerHigh,
      scheme.onSurface,
      .1,
    )!.withValues(alpha: .8);
    for (final cloud in _nightClouds) {
      final b = cloud.getBounds().inflate(12);
      // край растушёван маской из размытого контура: заливка по ней srcIn, луна поверх srcATop,
      // с жёстким краем облака выглядели мультяшными
      canvas.saveLayer(b, Paint());
      canvas.drawPath(
        cloud,
        Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.6),
      );
      canvas.drawRect(
        b,
        Paint()
          ..blendMode = BlendMode.srcIn
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, bottom],
          ).createShader(cloud.getBounds()),
      );
      drawLight(blur: 7, alpha: .6, mode: BlendMode.srcATop);
      canvas.restore();
    }
  }

  void _paintDay(
    Canvas canvas,
    void Function({double blur, double alpha, BlendMode mode}) drawLight,
  ) {
    final top = Colors.white.withValues(alpha: .9);
    final bottom = Color.lerp(
      Colors.white,
      scheme.onSurfaceVariant,
      .5,
    )!.withValues(alpha: .88);
    final rim = Colors.white.withValues(alpha: .6);
    for (final (cloud, lobes) in _dayClouds) {
      final b = cloud.getBounds();
      canvas.save();
      canvas.clipPath(cloud);
      canvas.drawRect(
        b,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, Color.lerp(top, bottom, .45)!, bottom],
            stops: const [0, .5, 1],
          ).createShader(b),
      );
      for (final r in lobes) {
        final c = r.center + Offset(r.width * .22, -r.height * .3);
        final hr = Rect.fromCenter(
          center: c,
          width: r.width * .8,
          height: r.height * .7,
        );
        canvas.drawOval(
          hr,
          Paint()
            ..shader = RadialGradient(
              colors: [rim, rim.withValues(alpha: 0)],
            ).createShader(hr),
        );
      }
      drawLight(blur: 7, alpha: .6);
      canvas.restore();
    }
    final bird = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 1.4
      ..color = scheme.onSurfaceVariant.withValues(alpha: .5);
    for (final (x, y, w) in const [
      (-32.0, 4.0, 7.0),
      (-48.0, -6.0, 5.4),
      (-36.0, -14.0, 4.2),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(x - w, y - w * .25)
          ..quadraticBezierTo(x - w * .45, y - w * .6, x, y)
          ..quadraticBezierTo(x + w * .45, y - w * .6, x + w, y - w * .25),
        bird,
      );
    }
  }

  @override
  bool shouldRepaint(_SkyPainter old) =>
      old.scheme != scheme || old.desktop != desktop;
}
