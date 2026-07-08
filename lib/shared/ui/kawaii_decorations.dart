import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Цветовой «вкус» kawaii-оверлея: палитра дождика из частиц и акценты
/// стикеров. Цвета фиксированы, а не из ColorScheme: Material-тона из
/// fromSeed дают приглушённые mauve/оливковые цвета — совсем не kawaii.
class KawaiiFlavor {
  final Color petalLight;
  final Color petalDark;
  final Color sparkleLight;
  final Color sparkleDark;
  final Color heartLight;
  final Color heartDark;

  /// Акцент стикеров: лепестки цветка, внутренние ушки и т.п.
  final Color accentLight;
  final Color accentDark;
  final Color accentSoftLight;
  final Color accentSoftDark;

  const KawaiiFlavor({
    required this.petalLight,
    required this.petalDark,
    required this.sparkleLight,
    required this.sparkleDark,
    required this.heartLight,
    required this.heartDark,
    required this.accentLight,
    required this.accentDark,
    required this.accentSoftLight,
    required this.accentSoftDark,
  });

  /// Клубнично-сакуровый: розовые лепестки, золотые блёстки.
  static const sakura = KawaiiFlavor(
    petalLight: Color(0xFFF783B0),
    petalDark: Color(0xFFFFA8CC),
    sparkleLight: Color(0xFFF2A93B),
    sparkleDark: Color(0xFFFFD98A),
    heartLight: Color(0xFFF06CA0),
    heartDark: Color(0xFFFF8FB8),
    accentLight: Color(0xFFFF8FB8),
    accentDark: Color(0xFFFF9EC6),
    accentSoftLight: Color(0xFFFFD3E4),
    accentSoftDark: Color(0xFFFFC0D9),
  );

  /// Лавандово-молочный: сиреневые лепестки, те же золотые блёстки.
  static const lavender = KawaiiFlavor(
    petalLight: Color(0xFFB79CF0),
    petalDark: Color(0xFFCDB7FF),
    sparkleLight: Color(0xFFF2A93B),
    sparkleDark: Color(0xFFFFD98A),
    heartLight: Color(0xFFA981E8),
    heartDark: Color(0xFFC5A6F7),
    accentLight: Color(0xFFB39DF2),
    accentDark: Color(0xFFC5B0F8),
    accentSoftLight: Color(0xFFE4D9FB),
    accentSoftDark: Color(0xFFD8C9F9),
  );
}

/// Полноэкранный слой «финтифлюшек» kawaii-пресета поверх всего UI:
///  - дождик: медленно падающие лепестки, мерцающие звёздочки, сердечки;
///  - стикеры: крупные чиби-мордашки (котик, зайка, онигири, клубничка,
///    цветок сакуры, звёздочка) с белой die-cut обводкой, как настоящие
///    наклейки — они и делают тему «кавай-кор», а не просто розовой.
///
/// Дёшево по перфу: один CustomPainter, ~18 фигур дождика + 6 стикеров из
/// закешированных unit-Path за кадр, без per-particle виджетов и saveLayer;
/// IgnorePointer — слой не перехватывает тапы; RepaintBoundary — анимация не
/// заставляет перерисовываться само приложение под ней.
class KawaiiOverlay extends StatefulWidget {
  final Widget child;
  final KawaiiFlavor flavor;
  const KawaiiOverlay({
    super.key,
    this.flavor = KawaiiFlavor.sakura,
    required this.child,
  });

  @override
  State<KawaiiOverlay> createState() => _KawaiiOverlayState();
}

class _KawaiiOverlayState extends State<KawaiiOverlay>
    with SingleTickerProviderStateMixin {
  // Один длинный цикл: value 0..1 за минуту, частицы зациклены по модулю.
  static const _cycle = Duration(seconds: 60);
  late final AnimationController _t =
      AnimationController(vsync: this, duration: _cycle)..repeat();

  late final List<_Particle> _particles = _spawnParticles();
  late final List<_Sticker> _stickers = _spawnStickers();

  static List<_Particle> _spawnParticles() {
    // Фиксированный seed: раскладка частиц стабильна между перезапусками,
    // никаких «прыжков» при hot reload / пересоздании оверлея.
    final rnd = math.Random(20260706);
    return List.generate(18, (i) {
      final kind = switch (i % 6) {
        0 || 1 || 2 => _Kind.petal, // лепестков больше всего
        3 || 4 => _Kind.sparkle,
        _ => _Kind.heart,
      };
      return _Particle(
        kind: kind,
        x: rnd.nextDouble(),
        yOffset: rnd.nextDouble(),
        // 2–4 прохода экрана за цикл (падение ~15–30 с на экран)
        fallSpeed: 2 + rnd.nextDouble() * 2,
        size: switch (kind) {
          _Kind.petal => 7 + rnd.nextDouble() * 6,
          _Kind.sparkle => 3 + rnd.nextDouble() * 3.5,
          _Kind.heart => 5 + rnd.nextDouble() * 4,
        },
        swayAmp: 0.015 + rnd.nextDouble() * 0.03,
        swayFreq: 6 + rnd.nextDouble() * 8,
        spinSpeed: (rnd.nextDouble() - 0.5) * 60,
        phase: rnd.nextDouble() * 2 * math.pi,
      );
    });
  }

  static List<_Sticker> _spawnStickers() {
    final rnd = math.Random(20260708);
    const kinds = _StickerKind.values;
    return List.generate(kinds.length, (i) {
      return _Sticker(
        kind: kinds[i],
        x: 0.08 + rnd.nextDouble() * 0.84,
        // равномерно раскиданы по высоте, чтобы не сбивались в стайку
        yOffset: (i + rnd.nextDouble()) / kinds.length,
        // куда медленнее дождика: ~45–85 с на проход экрана
        fallSpeed: 0.7 + rnd.nextDouble() * 0.7,
        size: 15 + rnd.nextDouble() * 9, // полуразмер, px: стикер ~30–48 px
        swayAmp: 0.008 + rnd.nextDouble() * 0.012,
        swayFreq: 3 + rnd.nextDouble() * 4,
        wobbleAmp: 0.10 + rnd.nextDouble() * 0.10,
        wobbleFreq: 2 + rnd.nextDouble() * 3,
        phase: rnd.nextDouble() * 2 * math.pi,
      );
    });
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _t,
                builder: (context, _) => CustomPaint(
                  painter: _KawaiiPainter(
                    t: _t.value,
                    particles: _particles,
                    stickers: _stickers,
                    flavor: widget.flavor,
                    dark: dark,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum _Kind { petal, sparkle, heart }

class _Particle {
  final _Kind kind;
  final double x; // базовая горизонталь, доля ширины
  final double yOffset; // фаза падения, доля высоты
  final double fallSpeed; // проходов экрана за цикл
  final double size;
  final double swayAmp; // амплитуда покачивания, доля ширины
  final double swayFreq; // колебаний за цикл
  final double spinSpeed; // оборотов за цикл (±)
  final double phase;

  const _Particle({
    required this.kind,
    required this.x,
    required this.yOffset,
    required this.fallSpeed,
    required this.size,
    required this.swayAmp,
    required this.swayFreq,
    required this.spinSpeed,
    required this.phase,
  });
}

enum _StickerKind { cat, bunny, onigiri, strawberry, blossom, star }

class _Sticker {
  final _StickerKind kind;
  final double x;
  final double yOffset;
  final double fallSpeed;
  final double size; // масштаб unit-пространства → px (полуразмер стикера)
  final double swayAmp;
  final double swayFreq;
  final double wobbleAmp; // покачивание, радианы (не полное вращение)
  final double wobbleFreq;
  final double phase;

  const _Sticker({
    required this.kind,
    required this.x,
    required this.yOffset,
    required this.fallSpeed,
    required this.size,
    required this.swayAmp,
    required this.swayFreq,
    required this.wobbleAmp,
    required this.wobbleFreq,
    required this.phase,
  });
}

/// Палитра стикеров: заливки непрозрачные — это «наклейки», сквозь которые
/// UI просвечивать не должен (иначе обводка/заливка дают швы по краям).
class _StickerColors {
  final Color outline; // белая die-cut обводка
  final Color ink; // глазки/ротик
  final Color blush;
  final Color bodyWhite; // котик/зайка/онигири
  final Color accent; // от KawaiiFlavor: лепестки цветка
  final Color accentSoft; // внутренние ушки, серединки
  final Color berry;
  final Color leaf;
  final Color nori;
  final Color star;
  final Color core; // серединка цветка
  final double shadowAlpha;

  const _StickerColors._({
    required this.outline,
    required this.ink,
    required this.blush,
    required this.bodyWhite,
    required this.accent,
    required this.accentSoft,
    required this.berry,
    required this.leaf,
    required this.nori,
    required this.star,
    required this.core,
    required this.shadowAlpha,
  });

  factory _StickerColors.of(KawaiiFlavor f, bool dark) => _StickerColors._(
        outline: dark ? const Color(0xFFFFF3F8) : Colors.white,
        ink: const Color(0xFF69454F),
        blush: dark ? const Color(0xFFFF9FBE) : const Color(0xFFF78FB2),
        // в тёмной теме «белое» чуть приглушено, чтобы не слепило
        bodyWhite: dark ? const Color(0xFFF7EDF1) : const Color(0xFFFFFEFC),
        accent: dark ? f.accentDark : f.accentLight,
        accentSoft: dark ? f.accentSoftDark : f.accentSoftLight,
        berry: dark ? const Color(0xFFFF7F9C) : const Color(0xFFFF6B8A),
        leaf: dark ? const Color(0xFF9AD69A) : const Color(0xFF7FC383),
        nori: dark ? const Color(0xFF4A574A) : const Color(0xFF41503F),
        star: dark ? const Color(0xFFFFD97A) : const Color(0xFFFFC95C),
        core: dark ? const Color(0xFFFFE7B0) : const Color(0xFFFFE3A1),
        shadowAlpha: dark ? 0.30 : 0.12,
      );
}

class _KawaiiPainter extends CustomPainter {
  final double t;
  final List<_Particle> particles;
  final List<_Sticker> stickers;
  final KawaiiFlavor flavor;
  final bool dark;
  final _StickerColors _k;

  _KawaiiPainter({
    required this.t,
    required this.particles,
    required this.stickers,
    required this.flavor,
    required this.dark,
  }) : _k = _StickerColors.of(flavor, dark);

  @override
  void paint(Canvas canvas, Size size) {
    _paintRain(canvas, size);
    _paintStickers(canvas, size);
  }

  // ── дождик из мелких частиц ───────────────────────────────────────────────

  void _paintRain(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    // В тёмной теме частицы чуть ярче — иначе тонут в фоне.
    final baseAlpha = dark ? 0.38 : 0.30;
    final petalColor = dark ? flavor.petalDark : flavor.petalLight;
    final sparkleColor = dark ? flavor.sparkleDark : flavor.sparkleLight;
    final heartColor = dark ? flavor.heartDark : flavor.heartLight;

    for (final p in particles) {
      // Падение сверху вниз с запасом за края, чтобы не «рождались» на экране.
      final yFrac = (p.yOffset + t * p.fallSpeed) % 1.15 - 0.075;
      final xFrac =
          p.x + math.sin(t * p.swayFreq * 2 * math.pi + p.phase) * p.swayAmp;
      final pos = Offset(xFrac * size.width, yFrac * size.height);
      final angle = t * p.spinSpeed * 2 * math.pi + p.phase;

      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      switch (p.kind) {
        case _Kind.petal:
          canvas.rotate(angle);
          paint.color = petalColor.withValues(alpha: baseAlpha);
          _drawPetal(canvas, paint, p.size);
        case _Kind.sparkle:
          // Мерцание: альфа дышит со своей фазой.
          final twinkle =
              0.5 + 0.5 * math.sin(t * 40 * 2 * math.pi + p.phase);
          paint.color = sparkleColor.withValues(
            alpha: baseAlpha * (0.35 + 0.65 * twinkle),
          );
          _drawSparkle(canvas, paint, p.size);
        case _Kind.heart:
          canvas.rotate(math.sin(angle) * 0.35); // сердечки лишь покачиваются
          paint.color = heartColor.withValues(alpha: baseAlpha * 0.9);
          _drawHeart(canvas, paint, p.size);
      }
      canvas.restore();
    }
  }

  /// Лепесток сакуры: капля с выемкой на широком конце.
  static void _drawPetal(Canvas canvas, Paint paint, double s) {
    final path = Path()
      ..moveTo(0, -s) // остриё
      ..quadraticBezierTo(s * 0.8, -s * 0.3, s * 0.55, s * 0.55)
      ..quadraticBezierTo(s * 0.25, s * 0.95, 0, s * 0.7) // выемка
      ..quadraticBezierTo(-s * 0.25, s * 0.95, -s * 0.55, s * 0.55)
      ..quadraticBezierTo(-s * 0.8, -s * 0.3, 0, -s)
      ..close();
    canvas.drawPath(path, paint);
  }

  /// Четырёхлучевая звёздочка-блик.
  static void _drawSparkle(Canvas canvas, Paint paint, double s) {
    const waist = 0.28; // «талия» между лучами
    final path = Path()
      ..moveTo(0, -s)
      ..quadraticBezierTo(0, -s * waist, s, 0)
      ..quadraticBezierTo(0, s * waist, 0, s)
      ..quadraticBezierTo(0, s * waist, -s, 0)
      ..quadraticBezierTo(0, -s * waist, 0, -s)
      ..close();
    canvas.drawPath(path, paint);
  }

  static void _drawHeart(Canvas canvas, Paint paint, double s) {
    final path = Path()
      ..moveTo(0, s * 0.85)
      ..cubicTo(-s * 1.2, s * 0.05, -s * 0.7, -s * 0.9, 0, -s * 0.25)
      ..cubicTo(s * 0.7, -s * 0.9, s * 1.2, s * 0.05, 0, s * 0.85)
      ..close();
    canvas.drawPath(path, paint);
  }

  // ── стикеры ───────────────────────────────────────────────────────────────

  void _paintStickers(Canvas canvas, Size size) {
    for (final st in stickers) {
      // Запас 0.1 высоты за краями: стикер крупный, не должен «рождаться»
      // на глазах.
      final yFrac = (st.yOffset + t * st.fallSpeed) % 1.2 - 0.1;
      final xFrac =
          st.x + math.sin(t * st.swayFreq * 2 * math.pi + st.phase) * st.swayAmp;
      final wobble =
          math.sin(t * st.wobbleFreq * 2 * math.pi + st.phase) * st.wobbleAmp;

      canvas.save();
      canvas.translate(xFrac * size.width, yFrac * size.height);
      canvas.rotate(wobble);
      // Всё нарисовано в unit-пространстве (тело ≈ радиус 1) — масштаб
      // превращает его в пиксели, толщины штрихов масштабируются вместе.
      canvas.scale(st.size);
      _paintSticker(canvas, st.kind);
      canvas.restore();
    }
  }

  void _paintSticker(Canvas canvas, _StickerKind kind) {
    final fill = Paint();
    switch (kind) {
      case _StickerKind.cat:
        _stickerBase(canvas, _StickerArt.catBody, _k.bodyWhite);
        fill.color = _k.accentSoft;
        canvas.drawPath(_StickerArt.catInnerEars, fill);
        _drawFace(canvas, dy: 0.08, catMouth: true);
      case _StickerKind.bunny:
        _stickerBase(canvas, _StickerArt.bunnyBody, _k.bodyWhite);
        fill.color = _k.accentSoft;
        canvas.drawPath(_StickerArt.bunnyInnerEars, fill);
        _drawFace(canvas, dy: 0.24);
      case _StickerKind.onigiri:
        _stickerBase(canvas, _StickerArt.onigiriBody, _k.bodyWhite);
        fill.color = _k.nori;
        canvas.drawPath(_StickerArt.onigiriNori, fill);
        _drawFace(canvas, dy: -0.08);
      case _StickerKind.strawberry:
        _stickerBase(canvas, _StickerArt.berryBody, _k.berry);
        // семечки по краям, чтобы не мешали мордочке
        fill.color = _k.bodyWhite.withValues(alpha: 0.85);
        for (final seed in _StickerArt.berrySeeds) {
          canvas.drawOval(
            Rect.fromCenter(center: seed, width: 0.10, height: 0.16),
            fill,
          );
        }
        // листики поверх ягоды, со своей обводкой-наклейкой
        canvas.drawPath(_StickerArt.berryLeaves, _outlinePaint());
        fill.color = _k.leaf;
        canvas.drawPath(_StickerArt.berryLeaves, fill);
        _drawFace(canvas, dy: 0.10, fs: 0.9);
      case _StickerKind.blossom:
        // белые прожилки обводки между лепестками — это и есть «линворк»
        // наклейки, швы тут намеренные
        _stickerBase(canvas, _StickerArt.blossomPetals, _k.accent);
        fill.color = _k.core;
        canvas.drawCircle(Offset.zero, 0.40, fill);
        _drawFace(canvas, fs: 0.55);
      case _StickerKind.star:
        _stickerBase(canvas, _StickerArt.starBody, _k.star);
        _drawFace(canvas, dy: 0.10, fs: 0.6);
    }
  }

  Paint _outlinePaint() => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.20
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round
    ..color = _k.outline;

  /// Общая база стикера: мягкая тень → белая die-cut обводка → заливка.
  /// Обводка центрирована на контуре, заливка сверху накрывает её внутреннюю
  /// половину (и служебные рёбра составных Path), снаружи остаётся ровный
  /// белый кант — как у вырубленной наклейки.
  void _stickerBase(Canvas canvas, Path body, Color fillColor) {
    canvas.save();
    canvas.translate(0.05, 0.10);
    canvas.drawPath(
      body,
      Paint()..color = Colors.black.withValues(alpha: _k.shadowAlpha),
    );
    canvas.restore();
    canvas.drawPath(body, _outlinePaint());
    canvas.drawPath(body, Paint()..color = fillColor);
  }

  /// Мордочка: закрытые счастливые глазки ∩∩, ротик, румянец.
  /// [fs] — масштаб мордочки, [dy] — вертикальный сдвиг центра.
  void _drawFace(
    Canvas canvas, {
    double dy = 0,
    double fs = 1.0,
    bool catMouth = false,
  }) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.11 * fs
      ..strokeCap = StrokeCap.round
      ..color = _k.ink;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(-0.36 * fs, dy), radius: 0.15 * fs),
      math.pi,
      math.pi,
      false,
      stroke,
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset(0.36 * fs, dy), radius: 0.15 * fs),
      math.pi,
      math.pi,
      false,
      stroke,
    );
    if (catMouth) {
      // кошачий ротик «ω»: две маленькие дуги рядом
      for (final dx in const [-0.07, 0.07]) {
        canvas.drawArc(
          Rect.fromCircle(
            center: Offset(dx * fs, dy + 0.20 * fs),
            radius: 0.07 * fs,
          ),
          0.2,
          math.pi - 0.4,
          false,
          stroke,
        );
      }
    } else {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(0, dy + 0.18 * fs), radius: 0.10 * fs),
        0.35,
        math.pi - 0.7,
        false,
        stroke,
      );
    }
    final blush = Paint()..color = _k.blush.withValues(alpha: 0.55);
    for (final dx in const [-0.56, 0.56]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(dx * fs, dy + 0.14 * fs),
          width: 0.28 * fs,
          height: 0.17 * fs,
        ),
        blush,
      );
    }
  }

  @override
  bool shouldRepaint(_KawaiiPainter old) =>
      old.t != t || old.flavor != flavor || old.dark != dark;
}

/// Количество видов стикеров — для тестовых дампов/goldens.
@visibleForTesting
int get debugKawaiiStickerKindCount => _StickerKind.values.length;

/// Тестовый хук: рисует один стикер [kindIndex] в unit-пространстве вокруг
/// (0,0) — чтобы goldens/дампы не вскрывали приватные классы.
@visibleForTesting
void debugPaintKawaiiSticker(
  Canvas canvas, {
  required int kindIndex,
  KawaiiFlavor flavor = KawaiiFlavor.sakura,
  bool dark = false,
}) {
  _KawaiiPainter(
    t: 0,
    particles: const [],
    stickers: const [],
    flavor: flavor,
    dark: dark,
  )._paintSticker(canvas, _StickerKind.values[kindIndex]);
}

/// Контуры стикеров в unit-пространстве (тело ≈ радиус 1), построены один раз
/// на процесс — в кадре только drawPath по готовым Path.
class _StickerArt {
  _StickerArt._();

  /// Котик: круглая голова + треугольные ушки одним Path — заливка после
  /// обводки накрывает внутренние рёбра, снаружи остаётся общий кант.
  static final Path catBody = Path()
    ..moveTo(-0.80, -0.30)
    ..lineTo(-1.02, -1.05)
    ..lineTo(-0.24, -0.74)
    ..close()
    ..moveTo(0.80, -0.30)
    ..lineTo(1.02, -1.05)
    ..lineTo(0.24, -0.74)
    ..close()
    ..addOval(Rect.fromCircle(center: const Offset(0, 0.10), radius: 0.95));

  static final Path catInnerEars = Path()
    ..moveTo(-0.70, -0.46)
    ..lineTo(-0.86, -0.92)
    ..lineTo(-0.40, -0.66)
    ..close()
    ..moveTo(0.70, -0.46)
    ..lineTo(0.86, -0.92)
    ..lineTo(0.40, -0.66)
    ..close();

  static final Path bunnyBody = Path()
    ..addOval(
      Rect.fromCenter(
        center: const Offset(-0.40, -0.72),
        width: 0.46,
        height: 1.15,
      ),
    )
    ..addOval(
      Rect.fromCenter(
        center: const Offset(0.40, -0.72),
        width: 0.46,
        height: 1.15,
      ),
    )
    ..addOval(Rect.fromCircle(center: const Offset(0, 0.24), radius: 0.88));

  static final Path bunnyInnerEars = Path()
    ..addOval(
      Rect.fromCenter(
        center: const Offset(-0.40, -0.68),
        width: 0.20,
        height: 0.70,
      ),
    )
    ..addOval(
      Rect.fromCenter(
        center: const Offset(0.40, -0.68),
        width: 0.20,
        height: 0.70,
      ),
    );

  /// Онигири: скруглённый треугольник.
  static final Path onigiriBody = Path()
    ..moveTo(-0.22, -0.80)
    ..quadraticBezierTo(0, -1.02, 0.22, -0.80)
    ..lineTo(0.84, 0.34)
    ..quadraticBezierTo(1.00, 0.66, 0.62, 0.66)
    ..lineTo(-0.62, 0.66)
    ..quadraticBezierTo(-1.00, 0.66, -0.84, 0.34)
    ..close();

  static final Path onigiriNori = Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(0, 0.44), width: 0.70, height: 0.42),
        const Radius.circular(0.10),
      ),
    );

  /// Клубничка: капля остриём вниз.
  static final Path berryBody = Path()
    ..moveTo(0, -0.62)
    ..cubicTo(0.80, -0.72, 0.94, 0.02, 0.14, 0.88)
    ..quadraticBezierTo(0, 0.98, -0.14, 0.88)
    ..cubicTo(-0.94, 0.02, -0.80, -0.72, 0, -0.62)
    ..close();

  static const berrySeeds = <Offset>[
    Offset(-0.52, 0.02),
    Offset(0.52, 0.02),
    Offset(-0.30, 0.52),
    Offset(0.30, 0.52),
    Offset(0, 0.74),
  ];

  static final Path berryLeaves = _buildBerryLeaves();

  static Path _buildBerryLeaves() {
    final p = Path();
    void leaf(double dx, double rot) {
      final one = Path()
        ..addOval(
          Rect.fromCenter(center: Offset.zero, width: 0.34, height: 0.62),
        );
      final m = Matrix4.translationValues(dx, -0.70, 0)
          .multiplied(Matrix4.rotationZ(rot));
      p.addPath(one, Offset.zero, matrix4: m.storage);
    }

    leaf(-0.28, -0.5);
    leaf(0, 0);
    leaf(0.28, 0.5);
    return p;
  }

  /// Пять лепестков сакуры вокруг центра.
  static final Path blossomPetals = _buildBlossomPetals();

  static Path _buildBlossomPetals() {
    final p = Path();
    for (var i = 0; i < 5; i++) {
      final petal = Path()
        ..addOval(
          Rect.fromCenter(
            center: const Offset(0, -0.60),
            width: 0.70,
            height: 0.92,
          ),
        );
      p.addPath(
        petal,
        Offset.zero,
        matrix4: Matrix4.rotationZ(i * 2 * math.pi / 5).storage,
      );
    }
    return p;
  }

  static final Path starBody = _buildStar();

  static Path _buildStar() {
    final p = Path();
    for (var i = 0; i < 5; i++) {
      final aOut = -math.pi / 2 + i * 2 * math.pi / 5;
      final aIn = aOut + math.pi / 5;
      final out = Offset(math.cos(aOut), math.sin(aOut));
      final inn = Offset(math.cos(aIn) * 0.50, math.sin(aIn) * 0.50);
      if (i == 0) {
        p.moveTo(out.dx, out.dy);
      } else {
        p.lineTo(out.dx, out.dy);
      }
      p.lineTo(inn.dx, inn.dy);
    }
    p.close();
    return p;
  }
}
