part of '../servers_tab.dart';

/// Индикатор состояния туннеля — линейный wavy progress indicator M3
/// Expressive, со всей его анатомией: **трек**, **активный индикатор** и
/// **точка-стоп** в конце трека.
///
/// Раньше здесь был один штрих без трека и без точки — от компонента оставалась
/// только волнистость, поэтому он и читался как «нарисованная синусоида», а не
/// как индикатор. Числа теперь тоже из спеки, а не выведены из толщины штриха:
/// амплитуда [_M3ProgressPainter.maxAmplitude], длина волны
/// [_M3ProgressPainter._wavelength], зазор и точка-стоп по 4dp. Амплитуда — это
/// ПОТОЛОК: выше начинается график синуса.
///
/// Поверх спеки живут три канала данных — ради них индикатор здесь и стоит:
///  - **цвет** активного индикатора — задержка сервера (см. [_latencyColor]);
///  - **амплитуда** — реальный трафик: тишина идёт почти прямой, загрузка
///    поднимает волну до потолка. Канал отключается вместе с чипами трафика,
///    см. [AppSettings.showTrafficStats];
///  - **форма** — отключено: один прямой трек; подключение: бегущий
///    indeterminate-сегмент, который в момент успеха разворачивается ИЗ ТОЙ
///    ТОЧКИ, где его застало событие.
///
/// У СОСТОЯВШЕГОСЯ соединения активная часть до конца трека не доходит (см.
/// [_M3ProgressPainter.maxTail]): соединение — состояние, а не задача с
/// финишем, и полоса, залитая до края, врала бы про завершённую загрузку.
/// Бегущий сегмент это не касается — он проходит трек целиком.
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
    // Роль трека по спеке — `secondaryContainer`. Прежний приглушённый
    // `onSurfaceVariant` был не ролью, а просто «серым»: на тёмной теме он
    // почти пропадал, и отключённое состояние выглядело как пустое место.
    final trackColor = Theme.of(context).colorScheme.secondaryContainer;

    // Толщина. Спека даёт образцы 4dp и 8dp и прямо говорит, что толстые
    // варианты — образец, который делают под своё место. Под кнопкой на 136dp
    // и 8dp читались полоской, поэтому здесь 12dp; в узком окне (трей) —
    // спековые 8dp, иначе индикатор не влезает в отведённую высоту.
    final compact = height <= 24;
    final thickness = compact ? 8.0 : 12.0;

    final load = showTraffic ? _loadFactor(bytesPerSec) : _steadyLoad;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([waveCtrl, stateCtrl, _settleCtrl]),
          builder: (context, _) {
            final t = stateCtrl.value;
            // Пока идёт подключение, волна всегда полная: это indeterminate, и
            // его работа — показывать, что процесс жив, а не сколько байт идёт.
            //
            // У подключённого амплитуду ведёт трафик, но не до нуля: полностью
            // прямой активный индикатор неотличим от трека, и «связь есть»
            // выглядело бы как «связи нет».
            final target = isConnecting
                ? _M3ProgressPainter.maxAmplitude
                : t *
                    _M3ProgressPainter.maxAmplitude *
                    (_idleWaveFloor + (1 - _idleWaveFloor) * load);
            // Экспоненциальное сглаживание к цели: ~1/8 разницы за кадр даёт
            // время выхода около четверти секунды и полностью убирает рывок,
            // который был виден на каждом обновлении скорости.
            _amp += (target - _amp) * 0.12;
            if ((target - _amp).abs() < 0.02) _amp = target;

            final (start, end) = isConnecting
                ? waveRunningWindow(waveCtrl.value)
                : waveExpandedWindow(_settleFrom, _settleCtrl.value);

            // Хвост есть только у состоявшегося соединения. Пока сегмент бежит,
            // он проходит трек целиком; хвост вырастает вместе с разворотом
            // (`_settleCtrl`) и тает вместе с отключением (`t`) — поэтому в
            // отключённом состоянии активная часть снова занимает всю ширину и
            // становится обычным треком, без зазора посередине.
            final tail = isConnecting
                ? 0.0
                : _M3ProgressPainter.maxTail *
                    _settleCtrl.value.clamp(0.0, 1.0) *
                    t;

            return CustomPaint(
              painter: _M3ProgressPainter(
                progress: waveCtrl.value,
                amplitude: _amp,
                thickness: thickness,
                // Отключённый индикатор — это один трек. Красить активную часть
                // в цвет трека дешевле и честнее, чем сжимать её в ноль:
                // окном в это время управляет разворот после подключения, и
                // две анимации на одну геометрию дрались бы друг с другом.
                color: Color.lerp(trackColor, activeColor, t)!,
                trackColor: trackColor,
                windowStart: start,
                windowEnd: end,
                tail: tail,
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

  /// Доля потолка амплитуды, ниже которой подключённый индикатор не опускается
  /// даже в полной тишине.
  static const double _idleWaveFloor = 0.35;


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
  // Канал выключен — индикатор живёт на акценте темы. Выключают его не от
  // ненужности: цвет тут меняется от смены сервера и от переизмерения пинга, а
  // красный на главном экране читается как авария, даже когда речь о трёхстах
  // миллисекундах.
  if (!settings.waveLatencyColor) return AppTheme.accent(context);
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

/// Рисует линейный wavy progress indicator по анатомии M3: трек, активный
/// индикатор и точка-стоп. Волной идёт ТОЛЬКО активная часть — трек в спеке
/// прямой всегда.
class _M3ProgressPainter extends CustomPainter {
  _M3ProgressPainter({
    required this.progress,
    required this.amplitude,
    required this.thickness,
    required this.color,
    required this.trackColor,
    required this.windowStart,
    required this.windowEnd,
    required this.tail,
  });

  final double progress;
  final double amplitude;
  final double thickness;
  final Color color;
  final Color trackColor;

  /// Сколько пикселей трека справа отдано под хвост ПРЯМО СЕЙЧАС. 0 — активная
  /// часть меряется по всей ширине (бегущий сегмент), [maxTail] — по укороченной
  /// (соединение установлено). Промежуточные значения — кадры перехода.
  final double tail;

  /// Активный индикатор в долях ширины: во время подключения это бегущее окно,
  /// при подключённом — вся ширина, между ними — кадры разворота.
  final double windowStart;
  final double windowEnd;

  /// Потолок амплитуды. В измерениях спеки это 3dp при обеих её толщинах
  /// (полная высота 4+3+3=10 и 8+3+3=14), но там и самый толстый образец вдвое
  /// тоньше нашего: на штрихе 12dp волна в 3dp читается как дрожь толстой
  /// колбасы. Держим ту же долю от высоты, что у спекового образца 4dp.
  static const double maxAmplitude = 4;

  /// Хвост трека справа, который активный индикатор не закрывает у СОСТОЯВШЕГОСЯ
  /// соединения.
  ///
  /// Соединение — состояние, а не задача с концом: заполненная до края полоса
  /// читалась бы как «загрузка завершена», хотя завершаться тут нечему.
  ///
  /// К бегущему indeterminate-сегменту это не относится вовсе — он проходит
  /// трек целиком, как и положено. Поэтому хвост приезжает не константой, а
  /// [tail]: он растёт вместе с разворотом сегмента и тает вместе с отключением.
  ///
  /// Видно из него на 4dp меньше: столько уходит на зазор до активной части.
  static const double maxTail = 48;

  /// Длина волны — КОНСТАНТА и никогда не анимируется.
  ///
  /// Спека даёт 40dp. Помимо этого: фаза в `sin(2π·x/λ)` зависит от λ, поэтому
  /// её изменение мгновенно сдвигает всю волну по ширине — она телепортируется.
  /// Именно это выглядело как «лаги при смене трафика»: нагрузка меняла λ раз в
  /// секунду. Скорость показываем только амплитудой.
  static const double _wavelength = 40;

  /// Зазор между активным индикатором и треком.
  static const double _gap = 4;

  /// Диаметр точки-стопа в конце трека.
  static const double _stopIndicator = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final mid = size.height / 2;
    // Круглый торец выходит за конец отрезка на радиус — иначе индикатор
    // вылезал бы за отведённую ширину на пол-штриха с каждой стороны.
    final cap = thickness / 2;
    final left = cap;
    final right = w - cap;
    if (right <= left) return;

    final track = Paint()
      ..color = trackColor
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final active = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Единица для активной части — не конец трека, а начало его хвоста.
    final activeRight = max(left, right - tail);
    double at(double fraction) => left + (activeRight - left) * fraction;
    final start = at(windowStart);
    final end = at(windowEnd);

    // Трек — по обе стороны от активного индикатора, через зазор.
    //
    // Зазор меряется между ВИДИМЫМИ краями, а `drawLine` берёт центры торцов:
    // круглый торец выходит за точку на радиус штриха, и с обеих сторон стыка
    // это `thickness`. Без этой поправки зазор в 4dp на штрихе 12dp уходил в
    // минус — активная часть и хвост слипались в одну полосу.
    final trackInset = _gap + thickness;
    if (start - trackInset > left) {
      canvas.drawLine(Offset(left, mid), Offset(start - trackInset, mid), track);
    }
    if (end + trackInset < right) {
      canvas.drawLine(Offset(end + trackInset, mid), Offset(right, mid), track);
      // Точка-стоп живёт в конце ТРЕКА: когда активный индикатор дошёл до
      // конца, её не видно, и рисовать её незачем.
      canvas.drawCircle(
        Offset(right, mid),
        _stopIndicator / 2,
        Paint()..color = color,
      );
    }

    if (end - start < 0.5) return;

    // Амплитуда 0 — ровный активный индикатор с круглыми торцами.
    if (amplitude < 0.05) {
      canvas.drawLine(Offset(start, mid), Offset(end, mid), active);
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
    canvas.drawPath(path, active);
  }

  @override
  bool shouldRepaint(_M3ProgressPainter old) =>
      old.progress != progress ||
      old.amplitude != amplitude ||
      old.thickness != thickness ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.windowStart != windowStart ||
      old.windowEnd != windowEnd ||
      old.tail != tail;
}

