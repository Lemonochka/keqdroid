import 'dart:io';

import 'package:flutter/material.dart';

/// Насколько плотно картинка притушена под текстом.
///
/// Вуаль здесь не украшение: под текстом лежит произвольная фотография, и без
/// неё крупное значение трафика пропадает на любом светлом участке. Поэтому
/// [none] — осознанный выбор («картинка важнее»), а не то, что получают по
/// невнимательности: по умолчанию стоит [medium], то самое затемнение, с
/// которым карточка и была нарисована.
enum CardVeil {
  none,
  light,
  medium,
  strong;

  /// Прозрачности трёх опорных точек: под текстом → к середине → у правого
  /// края, где картинку и видно.
  List<double> get alphas => switch (this) {
        CardVeil.none => const [0, 0, 0],
        CardVeil.light => const [0.62, 0.38, 0.1],
        CardVeil.medium => const [0.9, 0.62, 0.22],
        CardVeil.strong => const [0.98, 0.86, 0.5],
      };

  /// Разбор значения из хранилища. Незнакомое имя — [medium]: настройку писала
  /// версия новее этой, и карточка со штатным затемнением лучше, чем упавший
  /// разбор списка подписок.
  static CardVeil byName(String? name) {
    for (final veil in values) {
      if (veil.name == name) return veil;
    }
    return CardVeil.medium;
  }
}

/// Вуаль поверх картинки: слева плотная (под текстом), справа картинка открыта.
///
/// Один виджет на оба места, где картинка темы лежит под текстом, — карточку
/// подписки и шапку её группы в списке серверов. Раньше это были два
/// одинаковых градиента в разных файлах, и «убрать затемнение» пришлось бы
/// делать дважды, а расходиться они начали бы с первой правки одного из них.
class CardVeilOverlay extends StatelessWidget {
  const CardVeilOverlay({
    super.key,
    required this.color,
    required this.veil,
  });

  /// Чем кроется картинка — фактическим фоном того, на чём она лежит. У группы
  /// серверов он подкрашен акцентом подписки, и цвет роли дал бы шов на стыке
  /// с первым сервером.
  final Color color;

  final CardVeil veil;

  @override
  Widget build(BuildContext context) {
    // Нулевая вуаль — это отсутствие слоя, а не прозрачный градиент: рисовать
    // невидимое на каждый кадр незачем.
    if (veil == CardVeil.none) return const SizedBox.shrink();
    final alphas = veil.alphas;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
          // Правая цифра и есть «насколько видно картинку». Левая держит
          // крупный текст, средняя отодвигает спад вправо — под цифрой трафика
          // ещё плотно, дальше уже видно картинку.
          stops: const [0, 0.45, 1],
          colors: [for (final alpha in alphas) color.withValues(alpha: alpha)],
        ),
      ),
    );
  }
}

/// Оформление карточки подписки: подложка под содержимым.
///
/// Зачем: список подписок — это несколько одинаковых прямоугольников, и
/// отличаются они только текстом. Своя подложка превращает «третью сверху» в
/// «вон ту», а заодно даёт списку лицо.
///
/// Два вида подложек. Палитровые рисуются кодом из текущей цветовой схемы —
/// значит перекрашиваются вместе с темой и не весят ничего. Картиночные берутся
/// из ассетов: положить свои файлы можно, не трогая код, — см.
/// `assets/card_themes/README.md`.
///
/// Контраст держится тем, что подложка ложится ПОВЕРХ обычного цвета карточки
/// полупрозрачной: текст на ней остаётся тем же `onSurface`, что и всюду, и
/// проверять каждую комбинацию отдельно не нужно. У картинок ту же роль играет
/// вуаль цветом карточки — без неё белый текст на светлом участке фотографии
/// исчезает, и это ровно та ошибка, ради которой всё это и обрамляется.
class SubscriptionCardTheme {
  /// Без подложки — обычная карточка. Дефолт: тему выбирают, а не получают.
  const SubscriptionCardTheme.plain()
      : id = '',
        palette = null,
        asset = null;

  const SubscriptionCardTheme.palette(this.id, this.palette) : asset = null;

  /// Картинка из ассетов. [id] совпадает с именем файла без расширения.
  const SubscriptionCardTheme.image(this.id, this.asset) : palette = null;

  /// Своя картинка пользователя: лежит в каталоге приложения, а не в ассетах.
  /// В настройках подписки хранится как `file:<имя файла>`.
  SubscriptionCardTheme.file(String fileName, String directory)
      : id = '$filePrefix$fileName',
        palette = null,
        asset = '$directory/$fileName';

  /// Отличает свою картинку от встроенной темы в одном и том же поле настроек.
  static const filePrefix = 'file:';

  /// Каталог, где лежат свои картинки пользователя.
  ///
  /// Статикой, потому что путь достаётся асинхронно (path_provider), а карточка
  /// рисуется синхронно: иначе весь список подписок пришлось бы заворачивать в
  /// FutureBuilder ради одного поля. Заполняется один раз на старте
  /// (`CardImageService.warmUp`); пока пусто — своя картинка выглядит как
  /// обычная карточка, а не как исключение (так же ведут себя тесты).
  static String? customDirectory;

  /// Уезжает в настройки подписки — переименование сбросит выбор на «без темы».
  final String id;

  final CardPalette? palette;
  final String? asset;

  bool get isPlain => palette == null && asset == null;

  /// Есть ли у темы КАРТИНКА, а не просто подложка.
  ///
  /// Палитра рисуется цветами схемы на месте и переносить её некуда: там, где
  /// картинка связывает группу с карточкой буквально, палитра уже отдала свой
  /// оттенок акценту группы, и рисовать поверх нечего. Отличать это от
  /// [isPlain] обязательно — «не пустая» и «с картинкой» разошлись ровно на
  /// палитрах, и шапка группы вырастала на полосу пустоты.
  bool get hasImage => asset != null;

  /// Подложка под содержимое карточки. Ложится в `Stack` под текстом и
  /// обрезается формой карточки снаружи.
  ///
  /// [veil] — насколько притушить картинку. Параметр обязателен и у палитр,
  /// хотя им он и не нужен: вызывающий обязан решить этот вопрос осознанно, а
  /// молчаливое «как всегда» — то, из-за чего шапка группы кроет картинку
  /// дважды. Шапка как раз и передаёт [CardVeil.none]: свою вуаль она рисует
  /// сама, цветом фона группы.
  Widget background(BuildContext context, {required CardVeil veil}) {
    final scheme = Theme.of(context).colorScheme;
    final asset = this.asset;
    if (asset != null) {
      return _ImageBackground(
        asset: asset,
        scheme: scheme,
        veil: veil,
        fromFile: id.startsWith(filePrefix),
      );
    }
    final palette = this.palette;
    if (palette == null) return const SizedBox.shrink();
    return CustomPaint(painter: _PaletteArtPainter(palette.colors(scheme)));
  }
}

/// Из каких ролей схемы собирается палитровая подложка.
///
/// Роли, а не цвета: карточка обязана перекраситься вместе с темой, иначе
/// «Sunset» останется оранжевой на лавандовой теме и будет выглядеть чужой.
enum CardPalette {
  sunset,
  aurora,
  dusk,
  mint,
  ember;

  /// Три опорных цвета: от левого верхнего угла к правому нижнему плюс блик.
  List<Color> colors(ColorScheme scheme) => switch (this) {
        CardPalette.sunset => [
            scheme.primary,
            scheme.tertiary,
            scheme.primaryContainer,
          ],
        CardPalette.aurora => [
            scheme.tertiary,
            scheme.primary,
            scheme.secondaryContainer,
          ],
        CardPalette.dusk => [
            scheme.secondary,
            scheme.primary,
            scheme.tertiaryContainer,
          ],
        CardPalette.mint => [
            scheme.tertiary,
            scheme.secondary,
            scheme.tertiaryContainer,
          ],
        CardPalette.ember => [
            scheme.primary,
            scheme.secondary,
            scheme.primaryContainer,
          ],
      };
}

/// Встроенный набор: «без темы», палитры, картинки сборки.
const kSubscriptionCardThemes = <SubscriptionCardTheme>[
  SubscriptionCardTheme.plain(),
  SubscriptionCardTheme.palette('sunset', CardPalette.sunset),
  SubscriptionCardTheme.palette('aurora', CardPalette.aurora),
  SubscriptionCardTheme.palette('dusk', CardPalette.dusk),
  SubscriptionCardTheme.palette('mint', CardPalette.mint),
  SubscriptionCardTheme.palette('ember', CardPalette.ember),
];

/// Тема по её id. Неизвестный id (тема удалена, картинку убрали из сборки) —
/// обычная карточка, а не пустое место и не исключение.
SubscriptionCardTheme resolveCardTheme(String? id) {
  if (id == null || id.isEmpty) return const SubscriptionCardTheme.plain();
  // Своя картинка не лежит в каталоге: она у каждой подписки своя и известна
  // только по имени файла. Собираем тему на месте — иначе выбранная картинка
  // оставалась бы записанной в настройках, но карточка её не показывала.
  if (id.startsWith(SubscriptionCardTheme.filePrefix)) {
    final directory = SubscriptionCardTheme.customDirectory;
    if (directory == null) return const SubscriptionCardTheme.plain();
    return SubscriptionCardTheme.file(
      id.substring(SubscriptionCardTheme.filePrefix.length),
      directory,
    );
  }
  for (final theme in kSubscriptionCardThemes) {
    if (theme.id == id) return theme;
  }
  return const SubscriptionCardTheme.plain();
}

class _ImageBackground extends StatelessWidget {
  const _ImageBackground({
    required this.asset,
    required this.scheme,
    required this.veil,
    this.fromFile = false,
  });

  final String asset;
  final ColorScheme scheme;
  final CardVeil veil;

  /// Своя картинка пользователя лежит файлом на диске, встроенная — в ассетах.
  final bool fromFile;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image(
          image: fromFile
              ? FileImage(File(asset)) as ImageProvider
              : AssetImage(asset),
          fit: BoxFit.cover,
          // Картинку выкинули из сборки или удалили с диска — карточка
          // остаётся обычной, а не показывает сломанную картинку.
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        // Вуаль цветом карточки: слева, под текстом, почти непрозрачная,
        // справа картинка открыта. Так текст читается на любой картинке, а не
        // только на тёмной. Насколько плотно — решает пользователь в редакторе
        // карточки; при [CardVeil.none] слоя нет вовсе.
        CardVeilOverlay(color: scheme.surfaceContainerHigh, veil: veil),
      ],
    );
  }
}

/// Мягкая подложка: диагональный градиент и два размытых пятна.
///
/// Прозрачности низкие намеренно — подложка тонирует карточку, а не заменяет
/// её цвет: иначе `onSurface`-текст поверх пришлось бы подбирать под каждую
/// комбинацию темы и палитры.
class _PaletteArtPainter extends CustomPainter {
  const _PaletteArtPainter(this.colors);

  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors[0].withValues(alpha: 0.26),
            colors[1].withValues(alpha: 0.14),
          ],
        ).createShader(rect),
    );

    void blob(Offset center, double radius, Color color, double alpha) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    // Пятна привязаны к размеру, а не к пикселям: карточка на телефоне и на
    // десктопе разной ширины, а рисунок должен читаться одинаково.
    blob(
      Offset(size.width * 0.86, size.height * 0.18),
      size.height * 0.9,
      colors[2],
      0.34,
    );
    blob(
      Offset(size.width * 0.12, size.height * 0.95),
      size.height * 0.7,
      colors[0],
      0.20,
    );
  }

  @override
  bool shouldRepaint(_PaletteArtPainter oldDelegate) =>
      !listEquals(oldDelegate.colors, colors);
}

bool listEquals(List<Color> a, List<Color> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
