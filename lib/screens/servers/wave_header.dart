part of '../servers_tab.dart';

/// Индикатор состояния туннеля в духе M3 Expressive (wavy progress indicator).
///
/// Раньше это была просто синусоида, менявшая цвет по факту «подключён». Теперь
/// у неё три канала данных, то есть на неё есть смысл смотреть:
///  - **цвет** — задержка активного сервера (см. [_latencyColor]);
///  - **амплитуда** — реальный трафик: тишина почти прямая, загрузка идёт
///    крупной волной. Канал отключается вместе с чипами трафика, см.
///    [AppSettings.showTrafficStats];
///  - **форма** — в отключённом состоянии прямая приглушённая линия, в
///    подключении бегущий indeterminate-сегмент, который в момент успеха
///    разворачивается на всю ширину ИЗ ТОЙ ТОЧКИ, где его застало событие.
///
/// Пропорции взяты у M3-компонента (толстый штрих, малая амплитуда, короткая
/// длина волны), а не у графика синуса.
class _WavePaintWidget extends ConsumerStatefulWidget {
  final AnimationController waveCtrl;
  final AnimationController stateCtrl;
  final double height;

  const _WavePaintWidget({
    required this.waveCtrl,
    required this.stateCtrl,
    this.height = 36,
  });

  @override
  ConsumerState<_WavePaintWidget> createState() => _WavePaintWidgetState();
}

class _WavePaintWidgetState extends ConsumerState<_WavePaintWidget>
    with SingleTickerProviderStateMixin {
  /// Текущая (сглаженная) амплитуда. Трафик приходит скачками раз в секунду, и
  /// если гнать его в painter напрямую, волна дёргается на каждом обновлении.
  /// Тянем значение к цели покадрово — на глаз это плавный «вдох».
  double _amp = 0;

  /// Разворот сегмента в полную ширину после подключения. Unbounded: пружина
  /// M3E перелетает за цель, а края всё равно зажимаются в painter.
  late final AnimationController _settleCtrl = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );

  /// Где стоял бегущий сегмент в момент события — из этой точки и разворачиваем.
  (double, double) _settleFrom = (0, 1);

  @override
  void dispose() {
    _settleCtrl.dispose();
    super.dispose();
  }

  static bool _isRunning(VpnStatus? status) =>
      status == VpnStatus.connecting || status == VpnStatus.disconnecting;

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final waveCtrl = widget.waveCtrl;
    final stateCtrl = widget.stateCtrl;
    final height = widget.height;

    // Слушаем именно смену статуса, а не значение: разворот запускается один
    // раз на переход, и делать это из build нельзя.
    ref.listen<VpnStatus?>(
      vpnStateProvider.select((s) => s.value?.status),
      (prev, next) {
        final was = _isRunning(prev);
        final now = _isRunning(next);
        if (was == now) return;
        if (now) {
          // Пошёл бег — окно снова живое, разворачивать нечего.
          _settleCtrl.value = 1;
          return;
        }
        _settleFrom = waveRunningWindow(waveCtrl.value);
        _settleCtrl.value = 0;
        ExpressiveMotion.springTo(
          _settleCtrl,
          1,
          spring: ExpressiveMotion.spatialSlow,
        );
      },
    );

    final status = ref.watch(vpnStateProvider.select((s) => s.value?.status));
    final isConnecting = _isRunning(status);

    final server = ref.watch(serversProvider.select((s) => s.activeServer));
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();

    // Чипы трафика выключены — волна не должна дышать: канал данных скрыт
    // целиком, а не наполовину. На скорость не подписываемся вовсе, чтобы не
    // перестраивать виджет раз в секунду впустую.
    final showTraffic = settings.showTrafficStats;
    // Скорость берём суммой: волна показывает «сколько сейчас идёт», без
    // разделения на приём и отдачу — для этого рядом есть чипы со цифрами.
    final bytesPerSec = showTraffic
        ? ref.watch(
            vpnStateProvider.select((s) {
              final v = s.value;
              return (v?.downloadSpeed ?? 0) + (v?.uploadSpeed ?? 0);
            }),
          )
        : 0;
    // Цвета резолвим здесь: внутри AnimatedBuilder дёргать Theme.of() на каждый
    // кадр не надо.
    final activeColor = _latencyColor(context, server, settings);
    final idleColor = AppTheme.textLight(context).withValues(alpha: 0.35);

    // Пропорции индикатора M3, а не синусоиды: штрих толстый, амплитуда меньше
    // штриха вдвое-втрое, длина волны короткая. Именно это отличает «шевелящуюся
    // линию» M3 от графика синуса.
    final compact = height <= 24;
    final stroke = compact ? 3.0 : 4.0;
    final idleAmp = stroke * 0.75;
    final busyAmp = compact ? stroke * 1.6 : stroke * 2.2;

    final load = showTraffic ? _loadFactor(bytesPerSec) : _steadyLoad;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([waveCtrl, stateCtrl, _settleCtrl]),
          builder: (context, _) {
            final t = stateCtrl.value;
            final target = _lerp(0, _lerp(idleAmp, busyAmp, load), t);
            // Экспоненциальное сглаживание к цели: ~1/8 разницы за кадр даёт
            // время выхода около четверти секунды и полностью убирает рывок,
            // который был виден на каждом обновлении скорости.
            _amp += (target - _amp) * 0.12;
            if ((target - _amp).abs() < 0.02) _amp = target;

            final (start, end) = isConnecting
                ? waveRunningWindow(waveCtrl.value)
                : waveExpandedWindow(_settleFrom, _settleCtrl.value);

            return CustomPaint(
              painter: _M3WavePainter(
                progress: waveCtrl.value,
                amplitude: _amp,
                strokeWidth: stroke,
                color: Color.lerp(idleColor, activeColor, t)!,
                windowStart: start,
                windowEnd: end,
              ),
              size: Size(double.infinity, height),
            );
          },
        ),
      ),
    );
  }

  /// Постоянная «нагрузка» для режима без чипов трафика: волна видна как волна,
  /// но её размер ни от чего не зависит.
  static const double _steadyLoad = 0.45;


  /// 0…1 из байт/с. 8 МБ/с и выше — потолок: выше уже некуда расти визуально.
  static double _loadFactor(int bytesPerSec) {
    if (bytesPerSec <= 0) return 0;
    const ceiling = 8 * 1024 * 1024;
    final normalized = log(1 + bytesPerSec) / log(1 + ceiling);
    return normalized.clamp(0.0, 1.0);
  }
}

/// Цвет волны по задержке активного сервера.
///
/// Берём ТУ ЖЕ шкалу, что и плитка сервера ([PingService.pingLatencyQuality]):
/// своя градация здесь давала расхождение — 266 мс на плитке зелёные, а волна
/// красила их как среднюю ступень. Пороги ещё и зависят от типа пинга (tcp —
/// прямой коннект, десятки мс; url — через xray и socks, планка выше), поэтому
/// тип тоже берём общий, через [PingService.pingColorTypeForServer].
Color _latencyColor(
  BuildContext context,
  ServerItem? server,
  AppSettings settings,
) {
  final ping = server?.pingMs;
  // Пинг не измерен — не врём цветом, показываем нейтральный акцент.
  if (server == null || ping == null || ping <= 0) {
    return AppTheme.accent(context);
  }
  final type = PingService.pingColorTypeForServer(server, settings);
  return switch (PingService.pingLatencyQuality(ping, type)) {
    PingLatencyQuality.good => AppTheme.green(context),
    PingLatencyQuality.fair => AppTheme.orange(context),
    PingLatencyQuality.poor => AppTheme.red(context),
  };
}

class _M3WavePainter extends CustomPainter {
  _M3WavePainter({
    required this.progress,
    required this.amplitude,
    required this.strokeWidth,
    required this.color,
    required this.windowStart,
    required this.windowEnd,
  });

  final double progress;
  final double amplitude;
  final double strokeWidth;
  final Color color;

  /// Видимый отрезок в долях ширины: во время подключения это бегущее окно, при
  /// подключённом — вся ширина, между ними — кадры разворота.
  final double windowStart;
  final double windowEnd;

  /// Длина волны — КОНСТАНТА и никогда не анимируется.
  ///
  /// Фаза в `sin(2π·x/λ)` зависит от λ, поэтому её изменение мгновенно сдвигает
  /// всю волну по ширине — она телепортируется. Именно это выглядело как «лаги
  /// при смене трафика»: нагрузка меняла λ раз в секунду. Скорость показываем
  /// только амплитудой, длина волны неподвижна.
  static const double _wavelength = 40;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final mid = size.height / 2;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final start = w * windowStart;
    final end = w * windowEnd;

    // Амплитуда 0 (отключено) — ровная линия с круглыми торцами.
    if (amplitude < 0.05) {
      canvas.drawLine(Offset(start, mid), Offset(end, mid), paint);
      return;
    }

    // Гладкая кривая по контрольным точкам вместо ломаной из отрезков: на
    // толстом штрихе M3 стыки отрезков заметны как огранка.
    final path = Path();
    const step = 3.0;
    double yAt(double x) =>
        mid + amplitude * sin(2 * pi * (x / _wavelength - progress));

    path.moveTo(start, yAt(start));
    for (double x = start; x < end; x += step) {
      final next = (x + step).clamp(start, end);
      final midX = (x + next) / 2;
      path.quadraticBezierTo(x, yAt(x), midX, yAt(midX));
    }
    path.lineTo(end, yAt(end));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_M3WavePainter old) =>
      old.progress != progress ||
      old.amplitude != amplitude ||
      old.strokeWidth != strokeWidth ||
      old.color != color ||
      old.windowStart != windowStart ||
      old.windowEnd != windowEnd;
}

double _lerp(double a, double b, double t) => a + (b - a) * t;
