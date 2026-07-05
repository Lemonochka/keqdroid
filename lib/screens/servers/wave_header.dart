part of '../servers_tab.dart';

// волна в собственном RepaintBoundary: её непрерывная перерисовка не тянет
// за собой остальной хедер
class _WavePaintWidget extends StatelessWidget {
  final AnimationController waveCtrl;
  final AnimationController stateCtrl;
  final double height;

  const _WavePaintWidget({
    required this.waveCtrl,
    required this.stateCtrl,
    this.height = 36,
  });

  @override
  Widget build(BuildContext context) {
    // кэшируем цвета, чтобы не дёргать Theme.of() внутри AnimatedBuilder
    final accentColor = AppTheme.accent(context);
    final greenColor = AppTheme.green(context);

    final compact = height <= 24;
    final large = height > 36;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([waveCtrl, stateCtrl]),
          builder: (context, _) {
            final t = stateCtrl.value;
            final color = Color.lerp(accentColor, greenColor, t)!;
            return CustomPaint(
              painter: _M3WavePainter(
                progress: waveCtrl.value,
                amplitude: _lerp(
                  compact ? 2.5 : (large ? 6.0 : 4.0),
                  compact ? 5.0 : (large ? 14.0 : 10.0),
                  t,
                ),
                strokeWidth: _lerp(
                  compact ? 2.0 : (large ? 3.0 : 2.5),
                  compact ? 3.0 : (large ? 4.5 : 4.0),
                  t,
                ),
                color: color,
              ),
              size: Size(double.infinity, height),
            );
          },
        ),
      ),
    );
  }
}

class _M3WavePainter extends CustomPainter {
  final double progress;
  final double amplitude;
  final double strokeWidth;
  final Color color;

  _M3WavePainter({
    required this.progress,
    required this.amplitude,
    required this.strokeWidth,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final mid = size.height / 2;

    const wl = 56.0;
    final path = Path();
    // 2px шаг: на синусоиде визуально неотличим от 1px, но вдвое меньше точек в
    // пути — дешевле, т.к. волна перерисовывается непрерывно на 60fps.
    for (double x = 0; x <= w; x += 2.0) {
      final y = mid + amplitude * sin(2 * pi * (x / wl - progress));
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_M3WavePainter old) =>
      old.progress != progress ||
      old.amplitude != amplitude ||
      old.strokeWidth != strokeWidth ||
      old.color != color;
}

double _lerp(double a, double b, double t) => a + (b - a) * t;
