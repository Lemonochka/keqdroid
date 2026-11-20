import 'dart:io';

import 'package:flutter/material.dart';

import '../shared/ui/card_art.dart';
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
  const CardVeilOverlay({super.key, required this.color, required this.veil});

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
  const SubscriptionCardTheme.plain() : id = '', art = null, asset = null;

  const SubscriptionCardTheme.art(this.id, this.art) : asset = null;

  SubscriptionCardTheme.file(String fileName, String directory)
    : id = '$filePrefix$fileName',
      art = null,
      asset = '$directory/$fileName';

  static const filePrefix = 'file:';

  static String? customDirectory;

  static Set<String>? customFiles;

  // id лежит в настройках подписок, переименование сбросит выбор
  final String id;

  final CardArt? art;
  final String? asset;

  bool get isPlain => art == null && asset == null;

  bool get hasImage => asset != null;

  static bool isVideoFile(String path) => path.toLowerCase().endsWith('.mp4');

  // первый кадр видео рядом с ним: по нему цвет акцента и превью, и его видно, пока видео грузится
  static String posterFor(String videoPath) => '$videoPath.png';

  // фото 4000 px с телефона занимает 53 МБ в пикселях, а на AMD картинка стоила в 5-6 раз больше (проба 30.10.2026);
  // карточка не шире 920 dp, и крупнее 2048 декодер работал бы впустую
  static ImageProvider coverImage(String path) => ResizeImage(
    FileImage(File(path)),
    width: 2048,
    height: 2048,
    policy: ResizeImagePolicy.fit,
  );

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
    final art = this.art;
    if (art == null) return const SizedBox.shrink();
    return CustomPaint(
      painter: CardArtPainter(
        art,
        scheme,
        rtl: Directionality.of(context) == TextDirection.rtl,
      ),
    );
  }
}

const kSubscriptionCardThemes = <SubscriptionCardTheme>[
  SubscriptionCardTheme.plain(),
  SubscriptionCardTheme.art('halftone', CardArt.halftone),
  SubscriptionCardTheme.art('depth', CardArt.depth),
  SubscriptionCardTheme.art('cookieLayers', CardArt.cookieLayers),
  SubscriptionCardTheme.art('cookieShift', CardArt.cookieShift),
  SubscriptionCardTheme.art('shapePattern', CardArt.shapePattern),
  SubscriptionCardTheme.art('shapeEdge', CardArt.shapeEdge),
  SubscriptionCardTheme.art('shapeAccent', CardArt.shapeAccent),
];

// прежние заготовки, их id остались в настройках подписок и в бэкапах
String migrateCardThemeId(String id) => switch (id) {
  'sunset' => 'halftone',
  'aurora' => 'depth',
  'dusk' => 'cookieLayers',
  'mint' => 'shapePattern',
  'ember' => 'cookieShift',
  _ => id,
};

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
          image: SubscriptionCardTheme.coverImage(asset),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        over,
      ],
    );
  }
}
