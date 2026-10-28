import 'dart:async';

import 'package:flutter/material.dart';

import 'expressive.dart';
import 'floating_bar.dart';

class ScrollJumpOverlay extends StatefulWidget {
  final Widget child;

  final bool enabled;

  final String endLabel;
  final String topLabel;

  final double bottomInset;

  final double minRemainingExtent;

  final Duration idleTimeout;

  const ScrollJumpOverlay({
    super.key,
    required this.child,
    required this.endLabel,
    required this.topLabel,
    this.enabled = true,
    this.bottomInset = 20,
    this.minRemainingExtent = 600,
    this.idleTimeout = const Duration(milliseconds: 1600),
  });

  @override
  State<ScrollJumpOverlay> createState() => _ScrollJumpOverlayState();
}

class _ScrollJumpOverlayState extends State<ScrollJumpOverlay> {
  ScrollPosition? _position;
  Timer? _hideTimer;
  bool _visible = false;

  bool _up = false;

  // в Модерне стрелку рисует лента, снизу или сбоку, список только говорит, когда и куда
  bool _external = false;

  void _sync() {
    if (!_external) return;
    FloatingBar.jump.value =
        _visible ? FloatingJump(up: _up, onTap: _jump) : null;
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    if (FloatingBar.jump.value?.onTap == _jump) FloatingBar.jump.value = null;
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
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
    final middle = (metrics.minScrollExtent + metrics.maxScrollExtent) / 2;
    final up = metrics.pixels > middle;
    final remaining = up
        ? metrics.pixels - metrics.minScrollExtent
        : metrics.maxScrollExtent - metrics.pixels;
    final worth =
        metrics.hasContentDimensions && remaining > widget.minRemainingExtent;

    if (!worth) {
      _hideTimer?.cancel();
      if (_visible) {
        setState(() => _visible = false);
        _sync();
      }
      return false;
    }

    _hideTimer?.cancel();
    _hideTimer = Timer(widget.idleTimeout, () {
      if (mounted && _visible) {
        setState(() => _visible = false);
        _sync();
      }
    });
    if (!_visible || _up != up) {
      setState(() {
        _visible = true;
        _up = up;
      });
      _sync();
    }
    return false;
  }

  Future<void> _jump() async {
    final position = _position;
    if (position == null || !position.hasContentDimensions) return;
    _hideTimer?.cancel();
    if (_visible) {
      setState(() => _visible = false);
      _sync();
    }
    try {
      await position.animateTo(
        _up ? position.minScrollExtent : position.maxScrollExtent,
        duration: const Duration(milliseconds: 420),
        curve: ExpressiveMotion.emphasized,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    _external = FloatingBar.owns(context);
    if (_external) {
      return NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: widget.child,
      );
    }

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
            // невидимая кнопка иначе ловила бы тапы по тайлу под собой
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
                    child: _ScrollJumpButton(
                      up: _up,
                      label: _up ? widget.topLabel : widget.endLabel,
                      onTap: _jump,
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

class _ScrollJumpButton extends StatelessWidget {
  final bool up;
  final String label;
  final VoidCallback onTap;

  const _ScrollJumpButton({
    required this.up,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 600),
      child: Material(
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
              child: AnimatedRotation(
                turns: up ? 0.5 : 0,
                duration: ExpressiveMotion.durationFast,
                curve: ExpressiveMotion.emphasized,
                child: Icon(
                  Icons.arrow_downward_rounded,
                  size: 20,
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
