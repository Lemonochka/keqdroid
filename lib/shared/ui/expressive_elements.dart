library;

import 'package:flutter/material.dart';

import 'package:keqdroid/models/icon_shape.dart';
import 'package:keqdroid/shared/ui/expressive.dart';

class ExpressiveIconShapeTheme
    extends ThemeExtension<ExpressiveIconShapeTheme> {
  const ExpressiveIconShapeTheme({this.shape = IconShape.circle});

  final IconShape shape;

  static IconShape of(BuildContext context) =>
      Theme.of(context).extension<ExpressiveIconShapeTheme>()?.shape ??
      IconShape.circle;

  @override
  ExpressiveIconShapeTheme copyWith({IconShape? shape}) =>
      ExpressiveIconShapeTheme(shape: shape ?? this.shape);

  @override
  ExpressiveIconShapeTheme lerp(
    ThemeExtension<ExpressiveIconShapeTheme>? other,
    double t,
  ) {
    if (other is! ExpressiveIconShapeTheme) return this;
    return t < 0.5 ? this : other;
  }
}

class ExpressiveIconBadge extends StatelessWidget {
  final IconData icon;

  final ExpressiveAccent accent;

  final Color? background;
  final Color? foreground;

  final double size;

  final double iconSize;

  final IconShape? shape;

  const ExpressiveIconBadge({
    super.key,
    required this.icon,
    this.accent = ExpressiveAccent.primary,
    this.background,
    this.foreground,
    this.size = 40,
    this.iconSize = ExpressiveIconSize.medium,
    this.shape,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effective = shape ?? ExpressiveIconShapeTheme.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: background ?? accent.container(scheme),
        shape: effective.border(size),
      ),
      child: Icon(
        icon,
        size: iconSize,
        color: foreground ?? accent.onContainer(scheme),
      ),
    );
  }
}

class ExpressiveNotice extends StatelessWidget {
  final Color color;

  final String text;

  final IconData? icon;

  final bool outlined;

  final Color? textColor;

  final Widget? action;

  static const double _fillOpacity = 0.12;
  static const double _outlineOpacity = 0.32;

  const ExpressiveNotice({
    super.key,
    required this.color,
    required this.text,
    this.icon,
    this.outlined = false,
    this.textColor,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(ExpressiveSpacing.medium),
      decoration: BoxDecoration(
        color: color.withValues(alpha: _fillOpacity),
        borderRadius: ExpressiveShape.radius(ExpressiveShape.medium),
        border: outlined
            ? Border.all(color: color.withValues(alpha: _outlineOpacity))
            : null,
      ),
      child: Row(
        crossAxisAlignment: action == null
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: ExpressiveIconSize.inline, color: color),
            const SizedBox(width: ExpressiveSpacing.small),
          ],
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.35,
                color: textColor ?? theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: ExpressiveSpacing.small),
            action!,
          ],
        ],
      ),
    );
  }
}
