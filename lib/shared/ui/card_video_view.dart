import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

// фон шапки подписки из видео. Плеер живёт, только пока видео на экране: на чужой вкладке
// (TickerMode) и за краем списка его нет. Шапки групп серверов строятся и за экраном: десять
// плееров разом держали по ~37 МБ буферов декодера и грузили сервис кодеков на ~47% ядра
// Pixel 6a (26.10.2026). Без звука и не забирает его у других приложений
class CardVideoView extends StatefulWidget {
  const CardVideoView({
    super.key,
    required this.path,
    required this.poster,
    this.overlay,
  });

  final String path;

  // первый кадр: виден, пока плеер готовится, и на ПК вместо видео
  final String poster;

  final Widget? overlay;

  @override
  State<CardVideoView> createState() => _CardVideoViewState();
}

class _CardVideoViewState extends State<CardVideoView> {
  VideoPlayerController? _controller;
  ValueListenable<TickerModeData>? _ticking;
  var _ready = false;
  var _shown = false;
  ScrollableState? _scrollable;
  // до первой проверки места не знаем: плеер не открываем
  var _inView = false;
  DateTime? _hiddenAt;
  Timer? _recheck;

  @override
  void initState() {
    super.initState();
    // сворачивание группы двигает шапки без прокрутки
    if (Platform.isAndroid) {
      _recheck = Timer.periodic(const Duration(seconds: 1), (_) => _checkView());
    }
  }

  @override
  void didUpdateWidget(CardVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path == widget.path) return;
    _close();
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ticking?.removeListener(_sync);
    _ticking = TickerMode.getValuesNotifier(context)..addListener(_sync);
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable != _scrollable) {
      _scrollable?.position.removeListener(_checkView);
      _scrollable = scrollable?..position.addListener(_checkView);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkView());
    _sync();
  }

  @override
  void dispose() {
    _recheck?.cancel();
    _ticking?.removeListener(_sync);
    _scrollable?.position.removeListener(_checkView);
    _close();
    super.dispose();
  }

  void _checkView() {
    if (!mounted) return;
    final box = context.findRenderObject();
    final viewport = _scrollable?.context.findRenderObject();
    var inView = true;
    if (box is RenderBox &&
        viewport is RenderBox &&
        box.attached &&
        box.hasSize &&
        viewport.hasSize) {
      final rect = MatrixUtils.transformRect(
        box.getTransformTo(viewport),
        Offset.zero & box.size,
      );
      inView = rect.overlaps(Offset.zero & viewport.size);
    }
    if (inView != _inView) {
      _inView = inView;
      _sync();
    }
    // при прокрутке туда-обратно у края плеер не пересоздаётся каждый раз
    final hiddenAt = _hiddenAt;
    if (hiddenAt != null &&
        _controller != null &&
        DateTime.now().difference(hiddenAt) > const Duration(seconds: 2)) {
      setState(_close);
    }
  }

  void _open() {
    if (!Platform.isAndroid) return;
    final controller = VideoPlayerController.file(
      File(widget.path),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = controller;
    controller.addListener(_onValue);
    controller.initialize().then((_) async {
      if (!mounted || _controller != controller) return;
      await controller.setLooping(true);
      await controller.setVolume(0);
      if (!mounted || _controller != controller) return;
      _ready = true;
      _sync();
    }).catchError((_) {});
  }

  // поверхность плеера чёрная до первого кадра: до тех пор виден постер, тот же первый кадр
  void _onValue() {
    final controller = _controller;
    if (_shown || controller == null) return;
    if (controller.value.position > Duration.zero) setState(() => _shown = true);
  }

  void _close() {
    _ready = false;
    _shown = false;
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_onValue);
    controller?.dispose();
  }

  void _sync() {
    final wanted = (_ticking?.value.enabled ?? true) && _inView;
    _hiddenAt = wanted ? null : (_hiddenAt ?? DateTime.now());
    final controller = _controller;
    if (controller == null) {
      if (wanted) _open();
      return;
    }
    if (!_ready) return;
    if (wanted) {
      controller.play();
    } else {
      controller.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image(
          image: FileImage(File(widget.poster)),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        if (_shown && controller != null)
          // у края декодер подмешивает служебные строки кадра: при растягивании списка они
          // светились полоской между шапкой и плитками. Край в 1 dp остаётся за постером
          ClipRect(
            clipper: const _Inset(1),
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
          ),
        ?widget.overlay,
      ],
    );
  }
}

class _Inset extends CustomClipper<Rect> {
  const _Inset(this.by);

  final double by;

  @override
  Rect getClip(Size size) => (Offset.zero & size).deflate(by);

  @override
  bool shouldReclip(_Inset oldClipper) => oldClipper.by != by;
}
