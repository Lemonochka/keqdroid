import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jovial_svg/jovial_svg.dart';

import '../../models/server_flag.dart';
import 'app_theme.dart';
import 'expressive_elements.dart';

/// Цвет протокола сервера.
///
/// Оттенки свои (протокол — это идентичность сервера, роль схемы её не
/// выражает), но гармонизированные: на динамической теме сырой `0xFF4A90D9`
/// выпадал из палитры, потому что не имел к сиду никакого отношения.
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
      // Готовый конфиг ядра: протокол внутри может быть любым, поэтому цвет
      // отдельный — «это конфиг целиком, со своим роутингом».
      'custom' => AppTheme.harmonize(context, const Color(0xFFF9A825)),
      // Цепочка: протоколы узлов могут быть разными, поэтому цвет тоже свой.
      'chain' => AppTheme.harmonize(context, const Color(0xFF8E24AA)),
      _ => AppTheme.textLight(context),
    };

/// Разобранные картинки флагов. Без общего кэша `fromSISource` разбирает ассет
/// заново на каждый билд виджета (кэш пакета по умолчанию нулевого размера), а
/// в списке серверов один и тот же флаг встречается десятками и переезжает при
/// каждом скролле.
final _flagArtCache = ScalableImageCache(size: 96);

/// Ключ векторной картинки флага: сам виджет пакета — приватный подкласс, по
/// типу его в тестах не найти.
const flagArtKey = Key('serverAvatar_flagArt');

/// Ключ нарисованного нами плоского флага — см. [_flatFlags].
const flatFlagKey = Key('serverAvatar_flatFlag');

/// Кругляш сервера: флажок, а без него — буква протокола на его цвете.
///
/// У цепочки во флажке страна ВЫХОДА (её видят сайты), а число узлов
/// приезжает значком в углу — см. [chainHops].
class ServerAvatar extends StatelessWidget {
  final ServerFlag? flag;
  final String protocol;
  final double size;

  /// Число узлов цепочки. null — обычный сервер, значка нет.
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

    // Значок «сколько узлов» сидит на краю кружка: у цепочки флаг показывает
    // только выход, и без счётчика её не отличить от обычного сервера.
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

  /// Аватарка подчиняется выбранной форме иконок: в списке серверов это самая
  /// частая «иконка» приложения, и оставить её кругом, когда всё остальное
  /// сменило форму, — то же самое, что лаунчер с одним неподчинившимся значком.
  /// Значок-счётчик узлов в углу остаётся круглым: он не иконка, а бейдж.
  Widget _circle(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: ClipPath(
      clipper: ShapeBorderClipper(
        shape: ExpressiveIconShapeTheme.of(context).border(size),
      ),
      clipBehavior: Clip.antiAlias,
      child: switch (flag) {
        // Картинка шире круга, поэтому cover — обрезаем по бокам, а не жмём.
        FlagArt(:final assetPath) => ScalableImageWidget.fromSISource(
          key: flagArtKey,
          si: ScalableImageSource.fromSI(rootBundle, assetPath),
          fit: BoxFit.cover,
          cache: _flagArtCache,
          // Ассет пропал (пакет переехал) — лучше буква протокола, чем пустой
          // круг: пакетный виджет в этом случае рисует белый квадрат с «?».
          onError: (_) => _protocolBadge(context),
        ),
        FlagGlyph(:final emoji) => _flagWithoutArt(context, emoji),
        null => _protocolBadge(context),
      },
    ),
  );

  /// Флаг, которого нет в ассетах: известный рисуем сами плоским, остальные —
  /// системным эмодзи.
  Widget _flagWithoutArt(BuildContext context, String emoji) {
    final flat = _flatFlags[emoji.replaceAll('\u{FE0F}', '')];
    return flat == null
        ? _GlyphFlag(emoji: emoji, size: size)
        : _FlatFlag(art: flat, size: size);
  }

  Widget _protocolBadge(BuildContext context) => ColoredBox(
    color: serverProtocolColor(context, protocol),
    child: Center(
      // У цепочки первая буква («C») ничего не сообщает и путается с custom —
      // рисуем звенья.
      child: protocol == 'chain'
          ? Icon(Icons.link_rounded, size: size * 0.5, color: Colors.white)
          : Text(
              protocol.isNotEmpty ? protocol[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: size * 0.35,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
    ),
  );
}

/// Рисунок полотнища: горизонтальные полосы (сверху вниз) либо клетка, плюс
/// необязательная эмблема поверх.
class _FlatFlagArt {
  final List<Color> stripes;
  final String? emblem;
  final bool chequered;

  const _FlatFlagArt(this.stripes, {this.emblem, this.chequered = false});
}

/// Плоские версии флагов, которых нет в `country_flags`.
///
/// Системный шрифт рисует эмодзи-флаг развевающимся на ветру — в ряду ровных
/// прямоугольников из ассетов он выглядит кривым и «не тем элементом». Рисунок
/// у этих полотнищ известный и простой, поэтому рисуем их сами: те же плоские
/// прямоугольники во всю ширину кружка, что и у стран.
///
/// Ключ — эмодзи БЕЗ вариационного селектора (U+FE0F): один и тот же флаг
/// приходит и с ним, и без него. Эмблеме, наоборот, селектор нужен — иначе
/// шрифт вправе нарисовать её текстовым чёрно-белым знаком.
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
    // Полосы и клетки перекрываются на полпикселя: без этого между ними на
    // дробном devicePixelRatio просвечивает волосяная щель.
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

/// Флаг, которого нет ни в ассетах, ни в [_flatFlags] (🎌, флаги субъектов
/// вроде 🏴󠁵󠁳󠁴󠁸󠁿) — рисуем сам эмодзи системным шрифтом. Подложка нужна
/// прозрачным флагам, иначе на светлой теме от них остаётся один контур.
///
/// Эмодзи растянут так, чтобы ЗАПОЛНИТЬ кружок, а не сидеть картинкой в его
/// середине: страновые флаги приходят картинкой и рисуются `BoxFit.cover`, и
/// эмодзи-флаг рядом с ними иначе выглядит вдвое мельче и «не тем элементом».
/// Лишнее по краям срезает `ClipOval` снаружи — ровно как у картинок.
class _GlyphFlag extends StatelessWidget {
  final String emoji;
  final double size;

  /// Во сколько раз кегль больше диаметра. Само полотнище занимает примерно
  /// 0.7 высоты em-квадрата (остальное — внутренние поля шрифта), поэтому
  /// «в размер кружка» — это заметно больше самого кружка.
  static const double _fillFactor = 1.45;

  const _GlyphFlag({required this.emoji, required this.size});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppTheme.inset(context),
    // OverflowBox снимает ограничение по размеру: без него Text ужимается до
    // кружка и заполнения не выходит. Обрезку делает ClipOval у ServerAvatar.
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
