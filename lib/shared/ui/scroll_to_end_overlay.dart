import 'dart:async';

import 'package:flutter/material.dart';

import 'expressive.dart';

/// Кружок «в конец списка», всплывающий во время прокрутки.
///
/// Длинный список подписки листается десятками свайпов, а прыгнуть в его конец
/// на телефоне нечем: боковой навигатор — десктопный. Кнопка живёт по трём
/// правилам, и все три про «чтобы не мешалась»:
///
///  * появляется ТОЛЬКО от настоящей прокрутки (`ScrollUpdateNotification`),
///    а не от перестроений списка;
///  * только когда до конца ещё далеко ([minRemainingExtent]) — на списке в
///    шесть серверов её не бывает вовсе;
///  * прячется сама через [idleTimeout] после последнего движения.
///
/// Слушатель стоит вокруг всего экрана, а не внутри списка: уведомления
/// всплывают, и так виджет остаётся независимым от того, как именно собран
/// список (у нас это `CustomScrollView` внутри `SmoothScroll`).
class ScrollToEndOverlay extends StatefulWidget {
  final Widget child;

  /// Выключенная обёртка не вешает слушателя и не рисует кнопку. На десктопе
  /// её роль исполняет боковой навигатор по группам.
  final bool enabled;

  /// Подпись для тултипа и скринридера.
  final String label;

  /// Отступ кнопки от низа. Считает вызывающий: под ней бывает и панель
  /// вкладок, и системные врезки.
  final double bottomInset;

  /// Ниже этого остатка кнопка не нужна: докрутить проще, чем целиться.
  final double minRemainingExtent;

  final Duration idleTimeout;

  const ScrollToEndOverlay({
    super.key,
    required this.child,
    required this.label,
    this.enabled = true,
    this.bottomInset = 20,
    this.minRemainingExtent = 600,
    this.idleTimeout = const Duration(milliseconds: 1600),
  });

  @override
  State<ScrollToEndOverlay> createState() => _ScrollToEndOverlayState();
}

class _ScrollToEndOverlayState extends State<ScrollToEndOverlay> {
  ScrollPosition? _position;
  Timer? _hideTimer;
  bool _visible = false;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    // depth 0 — только сам список: вложенные горизонтальные ленты внутри
    // карточек не должны поднимать кнопку списка.
    if (notification.depth != 0) return false;
    if (notification is! ScrollUpdateNotification &&
        notification is! ScrollEndNotification) {
      return false;
    }

    final context = notification.context;
    if (context != null) {
      _position = Scrollable.maybeOf(context)?.position;
    }

    final metrics = notification.metrics;
    final remaining = metrics.maxScrollExtent - metrics.pixels;
    final worth =
        metrics.hasContentDimensions && remaining > widget.minRemainingExtent;

    if (!worth) {
      _hideTimer?.cancel();
      if (_visible) setState(() => _visible = false);
      return false;
    }

    _hideTimer?.cancel();
    _hideTimer = Timer(widget.idleTimeout, () {
      if (mounted && _visible) setState(() => _visible = false);
    });
    if (!_visible) setState(() => _visible = true);
    return false;
  }

  Future<void> _scrollToEnd() async {
    final position = _position;
    if (position == null || !position.hasContentDimensions) return;
    _hideTimer?.cancel();
    if (_visible) setState(() => _visible = false);
    try {
      await position.animateTo(
        position.maxScrollExtent,
        duration: const Duration(milliseconds: 420),
        curve: ExpressiveMotion.emphasized,
      );
    } catch (_) {
      // Список пересобрали прямо во время прыжка — молча, кнопка сама уйдёт.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          Positioned(
            left: 0,
            right: 0,
            bottom: widget.bottomInset,
            // IgnorePointer на невидимой кнопке: иначе она ловила бы тапы по
            // тайлу под собой всё время, пока её не видно.
            child: IgnorePointer(
              ignoring: !_visible,
              child: Center(
                child: AnimatedScale(
                  scale: _visible ? 1 : 0.7,
                  duration: const Duration(milliseconds: 180),
                  curve: ExpressiveMotion.emphasized,
                  child: AnimatedOpacity(
                    opacity: _visible ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: _ScrollToEndButton(
                      label: widget.label,
                      onTap: _scrollToEnd,
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
}

class _ScrollToEndButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ScrollToEndButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 600),
      child: Material(
        // Не FAB: тот по рангу равен «добавить сервер» в углу, а это подсказка
        // на время прокрутки. Отсюда и размер вдвое меньше, и тихая роль цвета.
        color: scheme.secondaryContainer,
        shape: const CircleBorder(),
        elevation: 2,
        shadowColor: scheme.shadow,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Semantics(
              button: true,
              label: label,
              child: Icon(
                Icons.keyboard_double_arrow_down_rounded,
                size: 20,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
