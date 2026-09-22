import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'expressive.dart';

/// Кнопка поверх списка, которая уходит, пока список листают к концу, и
/// возвращается на прокрутке обратно.
///
/// M3 такого не требует: по спеке обычный FAB при прокрутке остаётся на месте,
/// сжимается только расширенный. Но здесь список и есть содержимое экрана, а
/// кнопка стоит ровно над последней его строкой и закрывает её. Возвращается по
/// прокрутке вверх, а не по остановке: иначе она всплывала бы обратно через миг
/// после ухода и мигала на каждом свайпе.
class ScrollHiddenFab extends StatefulWidget {
  /// Содержимое со списком. Уведомления о прокрутке ловим от него.
  final Widget child;

  /// Сама кнопка.
  final Widget fab;

  /// Отступы кнопки от правого и нижнего края — считает вызывающий: под ней
  /// бывают и панель вкладок, и системные врезки.
  final double right;
  final double bottom;

  const ScrollHiddenFab({
    super.key,
    required this.child,
    required this.fab,
    this.right = 16,
    this.bottom = 16,
  });

  @override
  State<ScrollHiddenFab> createState() => _ScrollHiddenFabState();
}

class _ScrollHiddenFabState extends State<ScrollHiddenFab> {
  bool _visible = true;

  void _show() {
    if (!_visible) setState(() => _visible = true);
  }

  void _hide() {
    if (_visible) setState(() => _visible = false);
  }

  bool _onScroll(ScrollNotification notification) {
    // depth 0 — только сам список: горизонтальные ленты внутри строк не должны
    // управлять кнопкой экрана.
    if (notification.depth != 0) return false;

    if (notification is UserScrollNotification) {
      switch (notification.direction) {
        // reverse — смещение растёт, список уходит к концу: кнопка мешает.
        case ScrollDirection.reverse:
          _hide();
        // forward — обратно к началу: возвращаем.
        case ScrollDirection.forward:
          _show();
        // idle приходит и когда палец отпустили, и когда прокрутка кончилась;
        // по нему решать нельзя, иначе кнопка вернётся сразу после ухода.
        case ScrollDirection.idle:
          break;
      }
      return false;
    }

    // У самого верха кнопка нужна всегда: список могли прокрутить программно
    // (прыжок к активному серверу) или укоротить фильтром, и тогда прокрутки
    // «вверх», которая её вернёт, уже не будет.
    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      final metrics = notification.metrics;
      if (!metrics.hasContentDimensions ||
          metrics.pixels <= metrics.minScrollExtent) {
        _show();
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          Positioned(
            right: widget.right,
            bottom: widget.bottom,
            child: IgnorePointer(
              ignoring: !_visible,
              child: AnimatedScale(
                scale: _visible ? 1 : 0.7,
                duration: const Duration(milliseconds: 180),
                curve: ExpressiveMotion.emphasized,
                child: AnimatedOpacity(
                  opacity: _visible ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: widget.fab,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
