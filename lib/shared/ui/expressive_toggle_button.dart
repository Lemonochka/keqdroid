import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'expressive.dart';
import 'haptics.dart';
import 'tv_focus.dart';

class ExpressiveToggleButton extends StatefulWidget {
  const ExpressiveToggleButton({
    super.key,
    required this.selected,
    required this.label,
    required this.onPressed,
    this.onLongPress,
  });

  final bool selected;
  final String label;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;

  static const double height = 32;
  static const double squareCorner = ExpressiveShape.medium;
  static const double pressedCorner = ExpressiveShape.small;
  static const double sidePadding = ExpressiveSpacing.medium;

  // половина высоты, а не full: от 999 форма почти всю дорогу стоит пилюлей и в конце прыгает
  static const double pillCorner = height / 2;

  static final shapeSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 1400,
    ratio: 0.9,
  );

  @visibleForTesting
  static double cornerAt({required double selected, required double pressed}) {
    final rest = lerpDouble(pillCorner, squareCorner, selected.clamp(0.0, 1.0))!;
    return lerpDouble(rest, pressedCorner, pressed.clamp(0.0, 1.0))!;
  }

  @override
  State<ExpressiveToggleButton> createState() => _ExpressiveToggleButtonState();
}

class _ExpressiveToggleButtonState extends State<ExpressiveToggleButton>
    with TickerProviderStateMixin {
  late final AnimationController _shape = AnimationController.unbounded(
    vsync: this,
  )..value = widget.selected ? 1 : 0;
  late final AnimationController _tint = AnimationController.unbounded(
    vsync: this,
  )..value = widget.selected ? 1 : 0;
  late final AnimationController _press = AnimationController.unbounded(
    vsync: this,
  );

  final _states = WidgetStatesController();
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _states.addListener(_onStates);
  }

  void _onStates() {
    final pressed = _states.value.contains(WidgetState.pressed);
    if (pressed == _pressed) return;
    _pressed = pressed;
    ExpressiveMotion.springTo(
      _press,
      pressed ? 1 : 0,
      spring: ExpressiveToggleButton.shapeSpring,
    );
  }

  @override
  void didUpdateWidget(covariant ExpressiveToggleButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected == widget.selected) return;
    final target = widget.selected ? 1.0 : 0.0;
    ExpressiveMotion.springTo(
      _shape,
      target,
      spring: ExpressiveToggleButton.shapeSpring,
    );
    ExpressiveMotion.springTo(
      _tint,
      target,
      spring: ExpressiveMotion.effectsDefault,
    );
  }

  @override
  void dispose() {
    _states
      ..removeListener(_onStates)
      ..dispose();
    _shape.dispose();
    _tint.dispose();
    _press.dispose();
    super.dispose();
  }

  void _activate() {
    AppHaptics.selection();
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelLarge;
    final longPress = widget.onLongPress;
    Widget button = AnimatedBuilder(
      animation: Listenable.merge([_shape, _tint, _press]),
      builder: (context, _) {
        final tint = _tint.value.clamp(0.0, 1.0);
        final corner = ExpressiveToggleButton.cornerAt(
          selected: _shape.value,
          pressed: _press.value,
        );
        return FilledButton(
          onPressed: _activate,
          onLongPress: longPress,
          statesController: _states,
          style: FilledButton.styleFrom(
            backgroundColor: Color.lerp(
              scheme.surfaceContainerHighest,
              scheme.primary,
              tint,
            ),
            foregroundColor: Color.lerp(
              scheme.onSurfaceVariant,
              scheme.onPrimary,
              tint,
            ),
            textStyle: labelStyle,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(corner),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: ExpressiveToggleButton.sidePadding,
            ),
            minimumSize: const Size(0, ExpressiveToggleButton.height),
            fixedSize: const Size.fromHeight(ExpressiveToggleButton.height),
            tapTargetSize: MaterialTapTargetSize.padded,
            // плотность десктопа ужала бы кнопку на 8dp
            visualDensity: VisualDensity.standard,
            // форму и цвет ведут пружины покадрово, неявная анимация Material перезапускалась бы
            animationDuration: Duration.zero,
          ),
          child: Text(widget.label, maxLines: 1),
        );
      },
    );
    if (longPress != null) {
      button = TvLongPress(
        onPressed: _activate,
        onLongPress: longPress,
        child: GestureDetector(onSecondaryTap: longPress, child: button),
      );
    }
    return MergeSemantics(
      child: Semantics(toggled: widget.selected, child: button),
    );
  }
}
