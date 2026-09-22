import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'expressive.dart';
import 'haptics.dart';

/// Кнопка-переключатель M3 Expressive размера XS.
///
/// Выбор показан формой и заливкой: невыбранная — пилюля на нейтральной
/// подложке, выбранная — скруглённый квадрат цвета primary (filled-вариант
/// переключателя). Подпись одна на оба состояния и того же веса: ширина не
/// меняется, и соседи на переключении не ездят.
class ExpressiveToggleButton extends StatefulWidget {
  const ExpressiveToggleButton({
    super.key,
    required this.selected,
    required this.label,
    required this.onPressed,
  });

  final bool selected;
  final String label;
  final VoidCallback onPressed;

  /// Высота, углы и боковые отступы — токены размера XS со страницы кнопок
  /// M3E. Зона нажатия при этом до 48dp, сколько даст место вокруг.
  static const double height = 32;
  static const double squareCorner = ExpressiveShape.medium;
  static const double pressedCorner = ExpressiveShape.small;
  static const double sidePadding = ExpressiveSpacing.medium;

  /// Радиус пилюли — половина высоты, а не [ExpressiveShape.full]. От 999 к 12
  /// лерп почти всю дорогу держится выше потолка в 16, и кнопка стоит пилюлей,
  /// а в последние проценты схлопывается в квадрат — края будто прыгают,
  /// достраивая углы. От 16 к 12 форма меняется вся, с первого кадра.
  static const double pillCorner = height / 2;

  /// Пружина формы — тоже токен XS: жёсткая и почти без отскока, мелкой
  /// кнопке заметная отдача ни к чему.
  static final shapeSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 1400,
    ratio: 0.9,
  );

  /// Радиус углов при долях выбора [selected] и нажатия [pressed] (0..1).
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

  /// Нажатие берём из состояний самой кнопки, а не из своего детектора:
  /// так морф нажатия знает ровно то же, что и её подсветка, в том числе
  /// про тапы в расширенной зоне вокруг кнопки.
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelLarge;
    return MergeSemantics(
      child: Semantics(
        toggled: widget.selected,
        child: AnimatedBuilder(
          animation: Listenable.merge([_shape, _tint, _press]),
          builder: (context, _) {
            final tint = _tint.value.clamp(0.0, 1.0);
            final corner = ExpressiveToggleButton.cornerAt(
              selected: _shape.value,
              pressed: _press.value,
            );
            return FilledButton(
              onPressed: () {
                AppHaptics.selection();
                widget.onPressed();
              },
              statesController: _states,
              style: FilledButton.styleFrom(
                // Невыбранная — на уровень выше спекового surfaceContainer:
                // группа серверов сама лежит на surfaceContainerLow, и шаг в
                // один уровень на ней не считывается как кнопка.
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
                // Плотность десктопа ужала бы кнопку на 8dp в высоту: размер
                // здесь задан спекой, а не платформой.
                visualDensity: VisualDensity.standard,
                // Форму и цвет ведут пружины покадрово; своя неявная анимация
                // Material только перезапускалась бы на каждом кадре.
                animationDuration: Duration.zero,
              ),
              child: Text(widget.label, maxLines: 1),
            );
          },
        ),
      ),
    );
  }
}
