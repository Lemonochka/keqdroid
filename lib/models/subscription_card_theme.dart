import 'dart:io';

import 'package:flutter/material.dart';

import '../shared/ui/card_video_view.dart';
import '../shared/ui/smooth_fade.dart';

enum CardVeil {
  none,
  light,
  medium,
  strong;

  List<double> get alphas => switch (this) {
        CardVeil.none => const [0, 0, 0],
        CardVeil.light => const [0.62, 0.38, 0.1],
        CardVeil.medium => const [0.9, 0.62, 0.22],
        CardVeil.strong => const [0.98, 0.86, 0.5],
      };

  static CardVeil byName(String? name) {
    for (final veil in values) {
      if (veil.name == name) return veil;
    }
    return CardVeil.medium;
  }
}

class CardVeilOverlay extends StatelessWidget {
  const CardVeilOverlay({
    super.key,
    required this.color,
    required this.veil,
  });

  final Color color;

  final CardVeil veil;

  @override
  Widget build(BuildContext context) {
    if (veil == CardVeil.none) return const SizedBox.shrink();
    return SmoothFadeBox(
      begin: AlignmentDirectional.centerStart,
      end: AlignmentDirectional.centerEnd,
      color: color,
      curve: FadeCurve.through(veil.alphas, 0.45),
    );
  }
}

class SubscriptionCardTheme {
  const SubscriptionCardTheme.plain()
      : id = '',
        palette = null,
        asset = null;

  const SubscriptionCardTheme.palette(this.id, this.palette) : asset = null;

  SubscriptionCardTheme.file(String fileName, String directory)
      : id = '$filePrefix$fileName',
        palette = null,
        asset = '$directory/$fileName';

  static const filePrefix = 'file:';

  static String? customDirectory;

  static Set<String>? customFiles;

  // id лежит в настройках подписок, переименование сбросит выбор
  final String id;

  final CardPalette? palette;
  final String? asset;

  bool get isPlain => palette == null && asset == null;

  bool get hasImage => asset != null;

  static bool isVideoFile(String path) => path.toLowerCase().endsWith('.mp4');

  // первый кадр видео рядом с ним: по нему цвет акцента и превью, и его видно, пока видео грузится
  static String posterFor(String videoPath) => '$videoPath.png';

  String? get still {
    final asset = this.asset;
    if (asset == null) return null;
    return isVideoFile(asset) ? posterFor(asset) : asset;
  }

  // overlay: затемнения поверх картинки. Над видео они обязаны лежать в одном с ним Stack:
  // из внешних обёрток на Pixel 6a их не было видно поверх кадров (26.10.2026)
  Widget background(
    BuildContext context, {
    required CardVeil veil,
    Widget? overlay,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final asset = this.asset;
    if (asset != null) {
      return _ImageBackground(
        asset: asset,
        scheme: scheme,
        veil: veil,
        overlay: overlay,
      );
    }
    final palette = this.palette;
    if (palette == null) return const SizedBox.shrink();
    return CustomPaint(painter: _PaletteArtPainter(palette.colors(scheme)));
  }
}

enum CardPalette {
  sunset,
  aurora,
  dusk,
  mint,
  ember;

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

const kSubscriptionCardThemes = <SubscriptionCardTheme>[
  SubscriptionCardTheme.plain(),
  SubscriptionCardTheme.palette('sunset', CardPalette.sunset),
  SubscriptionCardTheme.palette('aurora', CardPalette.aurora),
  SubscriptionCardTheme.palette('dusk', CardPalette.dusk),
  SubscriptionCardTheme.palette('mint', CardPalette.mint),
  SubscriptionCardTheme.palette('ember', CardPalette.ember),
];

SubscriptionCardTheme resolveCardTheme(String? id) {
  if (id == null || id.isEmpty) return const SubscriptionCardTheme.plain();
  if (id.startsWith(SubscriptionCardTheme.filePrefix)) {
    final directory = SubscriptionCardTheme.customDirectory;
    if (directory == null) return const SubscriptionCardTheme.plain();
    final name = id.substring(SubscriptionCardTheme.filePrefix.length);
    // подписка из бэкапа может приехать без своей картинки
    final known = SubscriptionCardTheme.customFiles;
    if (known != null && !known.contains(name)) {
      return const SubscriptionCardTheme.plain();
    }
    return SubscriptionCardTheme.file(name, directory);
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
    this.overlay,
  });

  final String asset;
  final ColorScheme scheme;
  final CardVeil veil;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final over = Stack(
      fit: StackFit.expand,
      children: [
        CardVeilOverlay(color: scheme.surfaceContainerHigh, veil: veil),
        ?overlay,
      ],
    );
    if (SubscriptionCardTheme.isVideoFile(asset)) {
      return CardVideoView(
        path: asset,
        poster: SubscriptionCardTheme.posterFor(asset),
        overlay: over,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Image(
          image: FileImage(File(asset)),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        over,
      ],
    );
  }
}

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
