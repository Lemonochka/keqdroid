import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jovial_svg/jovial_svg.dart';

import '../../models/server_flag.dart';
import 'app_theme.dart';
import 'expressive_elements.dart';

enum ServerIconPalette {
  protocol,

  themed,
}

class ServerIconPaletteTheme extends ThemeExtension<ServerIconPaletteTheme> {
  const ServerIconPaletteTheme({this.palette = ServerIconPalette.themed});

  final ServerIconPalette palette;

  static ServerIconPalette of(BuildContext context) =>
      Theme.of(context).extension<ServerIconPaletteTheme>()?.palette ??
      ServerIconPalette.themed;

  @override
  ServerIconPaletteTheme copyWith({ServerIconPalette? palette}) =>
      ServerIconPaletteTheme(palette: palette ?? this.palette);

  @override
  ServerIconPaletteTheme lerp(
    ThemeExtension<ServerIconPaletteTheme>? other,
    double t,
  ) {
    if (other is! ServerIconPaletteTheme) return this;
    return t < 0.5 ? this : other;
  }
}

({Color background, Color foreground}) serverIconColors(
  BuildContext context,
  String protocol,
) =>
    switch (ServerIconPaletteTheme.of(context)) {
      ServerIconPalette.themed => (
          background: AppTheme.accentContainer(context),
          foreground: AppTheme.onAccentContainer(context),
        ),
      ServerIconPalette.protocol => (
          background: serverProtocolColor(context, protocol),
          foreground: Colors.white,
        ),
    };

Color serverProtocolColor(BuildContext context, String protocol) =>
    switch (protocol) {
      'vless' => AppTheme.harmonize(context, const Color(0xFF4A90D9)),
      'awg' => AppTheme.harmonize(context, const Color(0xFF2E7D32)),
      'vmess' => AppTheme.harmonize(context, const Color(0xFF7B68EE)),
      'trojan' => AppTheme.harmonize(context, const Color(0xFFE53935)),
      'ss' => AppTheme.harmonize(context, const Color(0xFF43A047)),
      'hysteria' => AppTheme.harmonize(context, const Color(0xFF00897B)),
      'hysteria2' => AppTheme.harmonize(context, const Color(0xFF00695C)),
      'hy2' => AppTheme.harmonize(context, const Color(0xFF004D40)),
      'tuic' => AppTheme.harmonize(context, const Color(0xFF00838F)),
      'anytls' => AppTheme.harmonize(context, const Color(0xFF5E35B1)),
      'ssr' => AppTheme.harmonize(context, const Color(0xFF2E7D32)),
      'mieru' => AppTheme.harmonize(context, const Color(0xFFEF6C00)),
      'socks' => AppTheme.harmonize(context, const Color(0xFF546E7A)),
      'custom' => AppTheme.harmonize(context, const Color(0xFFF9A825)),
      'chain' => AppTheme.harmonize(context, const Color(0xFF8E24AA)),
      _ => AppTheme.textLight(context),
    };

// у пакета кэш нулевого размера, без своего fromSISource разбирал ассет на каждый билд
final _flagArtCache = ScalableImageCache(size: 96);

const flagArtKey = Key('serverAvatar_flagArt');

const flatFlagKey = Key('serverAvatar_flatFlag');

class ServerAvatar extends StatelessWidget {
  final ServerFlag? flag;
  final String protocol;
  final double size;

  final int? chainHops;

  const ServerAvatar({
    super.key,
    required this.flag,
    required this.protocol,
    this.size = 40,
    this.chainHops,
  });

  @override
  Widget build(BuildContext context) {
    final circle = _circle(context);
    final hops = chainHops;
    if (hops == null) return circle;

    final badgeSize = size * 0.44;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          circle,
          PositionedDirectional(
            bottom: -1,
            end: -1,
            child: Container(
              width: badgeSize,
              height: badgeSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.card(context), width: 1.5),
              ),
              child: FittedBox(
                child: Padding(
                  padding: const EdgeInsets.all(1),
                  child: Text(
                    '$hops',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circle(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: ClipPath(
      clipper: ShapeBorderClipper(
        shape: ExpressiveIconShapeTheme.of(context).border(size),
      ),
      clipBehavior: Clip.antiAlias,
      child: switch (flag) {
        FlagArt(:final assetPath) => ScalableImageWidget.fromSISource(
          key: flagArtKey,
          si: ScalableImageSource.fromSI(rootBundle, assetPath),
          fit: BoxFit.cover,
          cache: _flagArtCache,
          // без этого пакет рисует белый квадрат с вопросом
          onError: (_) => _protocolBadge(context),
        ),
        FlagGlyph(:final emoji) => _flagWithoutArt(context, emoji),
        null => _protocolBadge(context),
      },
    ),
  );

  Widget _flagWithoutArt(BuildContext context, String emoji) {
    final flat = _flatFlags[emoji.replaceAll('\u{FE0F}', '')];
    return flat == null
        ? _GlyphFlag(emoji: emoji, size: size)
        : _FlatFlag(art: flat, size: size);
  }

  Widget _protocolBadge(BuildContext context) {
    final colors = serverIconColors(context, protocol);
    return ColoredBox(
      color: colors.background,
      child: Center(
        child: protocol == 'chain'
            ? Icon(
                Icons.link_rounded,
                size: size * 0.5,
                color: colors.foreground,
              )
            : Text(
                protocol.isNotEmpty ? protocol[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: size * 0.35,
                  fontWeight: FontWeight.w700,
                  color: colors.foreground,
                ),
              ),
      ),
    );
  }
}

class _FlatFlagArt {
  final List<Color> stripes;
  final String? emblem;
  final bool chequered;

  const _FlatFlagArt(this.stripes, {this.emblem, this.chequered = false});
}

// системный эмодзи-флаг развевается и выбивается из ряда плоских, рисуем сами.
// ключ без U+FE0F, а эмблеме селектор нужен, иначе шрифт нарисует её чёрно-белой
const _flatFlags = <String, _FlatFlagArt>{
  // 🏳️ белый
  '\u{1F3F3}': _FlatFlagArt([Color(0xFFFAFAFA)]),
  // 🏴 чёрный
  '\u{1F3F4}': _FlatFlagArt([Color(0xFF1B1B1B)]),
  // 🏴‍☠️ пиратский
  '\u{1F3F4}\u{200D}\u{2620}': _FlatFlagArt(
    [Color(0xFF1B1B1B)],
    emblem: '\u{2620}\u{FE0F}',
  ),
  // 🏳️‍🌈 радужный
  '\u{1F3F3}\u{200D}\u{1F308}': _FlatFlagArt([
    Color(0xFFE40303),
    Color(0xFFFF8C00),
    Color(0xFFFFED00),
    Color(0xFF008026),
    Color(0xFF24408E),
    Color(0xFF732982),
  ]),
  // 🏳️‍⚧️ трансгендерный
  '\u{1F3F3}\u{200D}\u{26A7}': _FlatFlagArt([
    Color(0xFF5BCEFA),
    Color(0xFFF5A9B8),
    Color(0xFFFFFFFF),
    Color(0xFFF5A9B8),
    Color(0xFF5BCEFA),
  ]),
  // 🚩 красный флажок
  '\u{1F6A9}': _FlatFlagArt([Color(0xFFD52B1E)]),
  // 🏁 клетчатый
  '\u{1F3C1}': _FlatFlagArt([], chequered: true),
};

class _FlatFlag extends StatelessWidget {
  final _FlatFlagArt art;
  final double size;

  const _FlatFlag({required this.art, required this.size});

  @override
  Widget build(BuildContext context) {
    final field = CustomPaint(key: flatFlagKey, painter: _FlatFlagPainter(art));
    final emblem = art.emblem;
    if (emblem == null) return field;
    return Stack(
      fit: StackFit.expand,
      children: [
        field,
        Center(
          child: Text(
            emblem,
            style: TextStyle(fontSize: size * 0.5, height: 1),
          ),
        ),
      ],
    );
  }
}

class _FlatFlagPainter extends CustomPainter {
  final _FlatFlagArt art;

  const _FlatFlagPainter(this.art);

  @override
  void paint(Canvas canvas, Size size) {
    // полосы перекрываются на полпикселя, иначе на дробном devicePixelRatio видна щель
    const bleed = 0.5;

    if (art.chequered) {
      const cols = 6;
      const rows = 4;
      final w = size.width / cols;
      final h = size.height / rows;
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFFFAFAFA),
      );
      final black = Paint()..color = const Color(0xFF1B1B1B);
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          if ((r + c).isEven) {
            canvas.drawRect(
              Rect.fromLTWH(c * w, r * h, w + bleed, h + bleed),
              black,
            );
          }
        }
      }
      return;
    }

    final h = size.height / art.stripes.length;
    for (var i = 0; i < art.stripes.length; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, i * h, size.width, h + bleed),
        Paint()..color = art.stripes[i],
      );
    }
  }

  @override
  bool shouldRepaint(_FlatFlagPainter oldDelegate) => oldDelegate.art != art;
}

class _GlyphFlag extends StatelessWidget {
  final String emoji;
  final double size;

  static const double _fillFactor = 1.45;

  const _GlyphFlag({required this.emoji, required this.size});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppTheme.inset(context),
    // без OverflowBox Text ужмётся до кружка
    child: Center(
      child: OverflowBox(
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: Text(
          emoji,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: size * _fillFactor, height: 1),
        ),
      ),
    ),
  );
}
