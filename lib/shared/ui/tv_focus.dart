import 'package:flutter/material.dart';

import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/shared/ui/expressive.dart';

abstract final class TvFocus {
  static bool get enabled => PlatformBootstrap.isTelevision;

  static const focusedScale = 1.05;

  static Widget fab(WidgetBuilder builder) => TvFocusHighlight(
        radius: BorderRadius.circular(ExpressiveShape.largeIncreased),
        child: Builder(builder: builder),
      );

  // по умолчанию Slider забирает себе и стрелки вверх-вниз, и пульт не мог уйти с ползунка
  static Widget slider(Widget slider) => enabled
      ? Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(navigationMode: NavigationMode.directional),
            child: slider,
          ),
        )
      : slider;

  static ColorScheme invert(ColorScheme s) {
    final muted = Color.lerp(s.onInverseSurface, s.inverseSurface, 0.25)!;
    return s.copyWith(
      brightness:
          s.brightness == Brightness.light ? Brightness.dark : Brightness.light,
      surface: s.inverseSurface,
      onSurface: s.onInverseSurface,
      onSurfaceVariant: muted,
      surfaceContainerLowest: s.inverseSurface,
      surfaceContainerLow: s.inverseSurface,
      surfaceContainer: s.inverseSurface,
      surfaceContainerHigh: s.inverseSurface,
      surfaceContainerHighest: s.inverseSurface,
      primary: s.inversePrimary,
      primaryContainer: s.inverseSurface,
      onPrimaryContainer: s.onInverseSurface,
      secondaryContainer: s.inverseSurface,
      onSecondaryContainer: s.onInverseSurface,
      tertiaryContainer: s.inverseSurface,
      onTertiaryContainer: s.onInverseSurface,
      inverseSurface: s.surface,
      onInverseSurface: s.onSurface,
      inversePrimary: s.primary,
      outline: muted,
      outlineVariant: Color.lerp(s.onInverseSurface, s.inverseSurface, 0.6),
    );
  }

  static ButtonStyle buttonStyle(ColorScheme s, [ButtonStyle? base]) {
    WidgetStateProperty<Color?> layered(
      Color focused,
      WidgetStateProperty<Color?>? under,
    ) =>
        WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? focused
              : under?.resolve(states),
        );
    return (base ?? const ButtonStyle()).copyWith(
      backgroundColor: layered(s.inverseSurface, base?.backgroundColor),
      foregroundColor: layered(s.onInverseSurface, base?.foregroundColor),
      iconColor: layered(s.onInverseSurface, base?.iconColor),
      overlayColor: layered(Colors.transparent, base?.overlayColor),
    );
  }

  // цвет здесь: Icon и IconButton.color перебивают фокус, и тёмный значок терялся на тёмной заливке
  static ButtonStyle iconButtonStyle(
    BuildContext context, {
    Color? color,
    ButtonStyle? base,
  }) {
    final style = (base ?? const ButtonStyle()).copyWith(
      foregroundColor: color == null ? null : WidgetStatePropertyAll(color),
    );
    return enabled ? buttonStyle(Theme.of(context).colorScheme, style) : style;
  }
}

// у голого GestureDetector фокуса нет: пульт его обходит, и OK ничего не нажимает
class TvTappable extends StatelessWidget {
  const TvTappable({
    super.key,
    required this.onTap,
    required this.child,
    this.radius,
    this.shape,
  });

  final VoidCallback? onTap;
  final Widget child;
  final BorderRadiusGeometry? radius;
  final ShapeBorder? shape;

  @override
  Widget build(BuildContext context) {
    final onTap = this.onTap;
    return TvFocusHighlight(
      radius: radius,
      shape: shape,
      child: FocusableActionDetector(
        enabled: onTap != null,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => onTap?.call(),
          ),
        },
        child: child,
      ),
    );
  }
}

class TvFocusHighlight extends StatefulWidget {
  const TvFocusHighlight({
    super.key,
    required this.child,
    this.radius,
    this.shape,
  });

  final Widget child;

  final BorderRadiusGeometry? radius;

  // заливка по фигуре, а не по скруглённому прямоугольнику
  final ShapeBorder? shape;

  static Color? containerOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_TvFocusScope>()
      ?.container;

  @override
  State<TvFocusHighlight> createState() => _TvFocusHighlightState();
}

class _TvFocusHighlightState extends State<TvFocusHighlight>
    with SingleTickerProviderStateMixin {
  // не late: ленивое поле создалось бы в dispose посреди размонтирования и упало ассертом
  AnimationController? _lift;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    if (TvFocus.enabled) _lift = AnimationController.unbounded(vsync: this);
  }

  @override
  void dispose() {
    _lift?.dispose();
    super.dispose();
  }

  void _onFocusChange(bool focused) {
    final lift = _lift;
    if (focused == _focused || lift == null) return;
    setState(() => _focused = focused);
    ExpressiveMotion.springTo(
      lift,
      focused ? 1 : 0,
      spring: ExpressiveMotion.spatialFast,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lift = _lift;
    if (lift == null) return widget.child;
    // вложенная пара подняла и залила бы элемент дважды
    if (context.findAncestorStateOfType<_TvFocusHighlightState>() != null) {
      return widget.child;
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // структура одна в обоих состояниях: перестройка дерева на фокусе увела бы сам фокус
    final content = _TvFocusScope(
      container: _focused ? scheme.inverseSurface : null,
      child: Theme(
        data: theme.copyWith(
          focusColor: Colors.transparent,
          colorScheme: _focused ? TvFocus.invert(scheme) : scheme,
        ),
        child: DecoratedBox(
          decoration: widget.shape == null
              ? BoxDecoration(
                  color: _focused ? scheme.inverseSurface : null,
                  borderRadius: widget.radius,
                )
              : ShapeDecoration(
                  color: _focused ? scheme.inverseSurface : null,
                  shape: widget.shape!,
                ),
          child: widget.child,
        ),
      ),
    );

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: _onFocusChange,
      child: AnimatedBuilder(
        animation: lift,
        builder: (context, child) => Transform.scale(
          scale: 1 + (TvFocus.focusedScale - 1) * lift.value,
          child: child,
        ),
        child: content,
      ),
    );
  }
}

class _TvFocusScope extends InheritedWidget {
  const _TvFocusScope({required this.container, required super.child});

  final Color? container;

  @override
  bool updateShouldNotify(_TvFocusScope oldWidget) =>
      container != oldWidget.container;
}
