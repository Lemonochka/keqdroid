library;

import 'package:flutter/material.dart';

import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:keqdroid/shared/ui/expressive_elements.dart';
import 'package:keqdroid/shared/ui/tv_focus.dart';

class ExpressiveGroup extends StatelessWidget {
  final List<Widget> children;

  final double outerCorner;

  final double innerCorner;

  final double spacing;

  const ExpressiveGroup({
    super.key,
    required this.children,
    this.outerCorner = ExpressiveShape.extraLarge,
    this.innerCorner = ExpressiveShape.extraSmall,
    this.spacing = 2,
  });

  static BorderRadius segmentRadius({
    required int index,
    required int count,
    double outerCorner = ExpressiveShape.extraLarge,
    double innerCorner = ExpressiveShape.extraSmall,
  }) {
    final outer = Radius.circular(outerCorner);
    final inner = Radius.circular(innerCorner);
    final isFirst = index == 0;
    final isLast = index == count - 1;
    return BorderRadius.only(
      topLeft: isFirst ? outer : inner,
      topRight: isFirst ? outer : inner,
      bottomLeft: isLast ? outer : inner,
      bottomRight: isLast ? outer : inner,
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = children.length;
    if (count == 0) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) SizedBox(height: spacing),
          ExpressiveGroupSegment(
            index: i,
            count: count,
            outerCorner: outerCorner,
            innerCorner: innerCorner,
            child: children[i],
          ),
        ],
      ],
    );
  }
}

// строка группы там, где саму группу одним Column не собрать: в списке с переносом
class ExpressiveGroupSegment extends StatelessWidget {
  const ExpressiveGroupSegment({
    super.key,
    required this.index,
    required this.count,
    required this.child,
    this.outerCorner = ExpressiveShape.extraLarge,
    this.innerCorner = ExpressiveShape.extraSmall,
  });

  final int index;
  final int count;
  final Widget child;
  final double outerCorner;
  final double innerCorner;

  @override
  Widget build(BuildContext context) {
    final radius = ExpressiveGroup.segmentRadius(
      index: index,
      count: count,
      outerCorner: outerCorner,
      innerCorner: innerCorner,
    );
    return _ExpressiveGroupScope(
      radius: radius,
      child: TvFocusHighlight(radius: radius, child: child),
    );
  }
}

class ExpressiveSectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;

  final Widget? trailing;

  const ExpressiveSectionHeader(
    this.title, {
    super.key,
    this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = Text(
      title,
      style: theme.textTheme
          .emphasized(theme.textTheme.labelLarge)
          ?.copyWith(color: scheme.primary),
    );

    final heading = icon == null
        ? label
        : Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: ExpressiveShape.radius(ExpressiveShape.small),
                  ),
                  child: Icon(
                    icon,
                    size: 16,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(child: label),
              ],
            );

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: trailing == null
          ? heading
          : Row(
              children: [
                Expanded(child: heading),
                trailing!,
              ],
            ),
    );
  }
}

// внутри Material: ListTile рисует всплеск на ближайшем Material-предке
class ExpressiveCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  final Color? outline;

  final double corner;

  const ExpressiveCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.outline,
    this.corner = ExpressiveShape.extraLarge,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: color ?? scheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: ExpressiveShape.radius(corner),
        side: outline == null
            ? BorderSide.none
            : BorderSide(color: outline!, width: 1.5),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class ExpressiveActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final ExpressiveAccent accent;
  final bool danger;

  final bool selected;

  const ExpressiveActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.accent = ExpressiveAccent.secondary,
    this.danger = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final Color iconBg;
    final Color iconFg;
    final Color titleColor;
    if (danger) {
      iconBg = scheme.errorContainer;
      iconFg = scheme.onErrorContainer;
      titleColor = scheme.error;
    } else if (selected) {
      iconBg = scheme.onSecondaryContainer.withValues(alpha: 0.12);
      iconFg = scheme.onSecondaryContainer;
      titleColor = scheme.onSecondaryContainer;
    } else {
      iconBg = accent.container(scheme);
      iconFg = accent.onContainer(scheme);
      titleColor = scheme.onSurface;
    }

    return ExpressiveGroupTile(
      onTap: onTap,
      color: selected ? scheme.secondaryContainer : null,
      child: Row(
        children: [
          ExpressiveIconBadge(
            icon: icon,
            background: iconBg,
            foreground: iconFg,
          ),
          const SizedBox(width: ExpressiveSpacing.large),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style:
                      (selected
                              ? textTheme.emphasized(textTheme.titleMedium)
                              : textTheme.titleMedium)
                          ?.copyWith(color: titleColor),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: textTheme.bodyMedium?.copyWith(
                      color: selected
                          ? scheme.onSecondaryContainer.withValues(alpha: 0.8)
                          : scheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (selected)
            Icon(Icons.check_rounded, size: 20, color: scheme.onSecondaryContainer),
        ],
      ),
    );
  }
}

class _ExpressiveGroupScope extends InheritedWidget {
  final BorderRadius radius;

  const _ExpressiveGroupScope({required this.radius, required super.child});

  static BorderRadius? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_ExpressiveGroupScope>()
      ?.radius;

  @override
  bool updateShouldNotify(_ExpressiveGroupScope oldWidget) =>
      oldWidget.radius != radius;
}

// unbounded: SpringSimulation перелетает цель, bounded-контроллер срезал бы отскок
class ExpressiveGroupTile extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  final Color? color;

  final BorderRadius? radius;

  final EdgeInsetsGeometry padding;

  const ExpressiveGroupTile({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.color,
    this.radius,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  });

  @override
  State<ExpressiveGroupTile> createState() => _ExpressiveGroupTileState();
}

class _ExpressiveGroupTileState extends State<ExpressiveGroupTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController.unbounded(
    vsync: this,
  );

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _springTo(double target) {
    if (!mounted) return;
    ExpressiveMotion.springTo(
      _press,
      target,
      spring: ExpressiveMotion.spatialFast,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = widget.radius ??
        _ExpressiveGroupScope.maybeOf(context) ??
        ExpressiveShape.radius(ExpressiveShape.extraLarge);
    final pressed = ExpressiveShape.pressedRadius(base);
    final enabled = widget.onTap != null || widget.onLongPress != null;

    return AnimatedBuilder(
      animation: _press,
      builder: (context, child) {
        final t = _press.value.clamp(0.0, 1.0);
        return ClipRRect(
          borderRadius: BorderRadius.lerp(base, pressed, t)!,
          child: child,
        );
      },
      child: Material(
        color: TvFocusHighlight.containerOf(context) ??
            widget.color ??
            scheme.surfaceContainerHigh,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onTapDown: enabled ? (_) => _springTo(1) : null,
          onTapUp: enabled ? (_) => _springTo(0) : null,
          onTapCancel: enabled ? () => _springTo(0) : null,
          child: Padding(padding: widget.padding, child: widget.child),
        ),
      ),
    );
  }
}

class ExpressiveListSegment extends StatefulWidget {
  final Widget child;

  final BorderRadius radius;

  final bool selected;

  final Color color;
  final Color selectedColor;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  final VoidCallback? onSecondaryTap;

  final Color? splashColor;
  final Color? highlightColor;

  static const double selectedCorner = ExpressiveShape.large;

  static const double innerCorner = ExpressiveShape.extraSmall;

  static const double outerCorner = ExpressiveShape.large;

  static const double gap = ExpressiveSpacing.extraSmall;

  const ExpressiveListSegment({
    super.key,
    required this.child,
    required this.radius,
    required this.color,
    required this.selectedColor,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.splashColor,
    this.highlightColor,
  });

  // начало и конец, а не лево и право: в фарси сетка зеркалится
  static BorderRadiusDirectional segmentRadius({
    required int index,
    required int count,
    int columns = 1,
    double? endCorner,
  }) {
    final row = index ~/ columns;
    final col = index % columns;
    final rows = (count + columns - 1) ~/ columns;

    final isTop = row == 0;
    final isLastRow = row == rows - 1;
    final isBottom = isLastRow || index + columns >= count;
    final isStart = col == 0;
    final isEnd = col == columns - 1 || index == count - 1;

    const outer = Radius.circular(outerCorner);
    const inner = Radius.circular(innerCorner);
    final end = isLastRow && endCorner != null
        ? Radius.circular(endCorner)
        : outer;
    return BorderRadiusDirectional.only(
      topStart: isTop && isStart ? outer : inner,
      topEnd: isTop && isEnd ? outer : inner,
      bottomStart: isBottom && isStart ? end : inner,
      bottomEnd: isBottom && isEnd ? end : inner,
    );
  }

  // поля тоже направленные, иначе в фарси зазор между колонками двоится
  static EdgeInsetsDirectional segmentMargin({
    required int index,
    int columns = 1,
    double spacing = gap,
  }) {
    final half = spacing / 2;
    if (columns == 1) {
      return EdgeInsetsDirectional.fromSTEB(spacing, half, spacing, half);
    }
    final col = index % columns;
    return EdgeInsetsDirectional.fromSTEB(
      col == 0 ? spacing : half,
      half,
      col == columns - 1 ? spacing : half,
      half,
    );
  }

  @override
  State<ExpressiveListSegment> createState() => _ExpressiveListSegmentState();
}

class _ExpressiveListSegmentState extends State<ExpressiveListSegment>
    with TickerProviderStateMixin {
  late final AnimationController _shape = AnimationController.unbounded(
    vsync: this,
  )..value = widget.selected ? 1 : 0;
  late final AnimationController _tint = AnimationController.unbounded(
    vsync: this,
  )..value = widget.selected ? 1 : 0;

  @override
  void didUpdateWidget(covariant ExpressiveListSegment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected == widget.selected) return;
    final target = widget.selected ? 1.0 : 0.0;
    ExpressiveMotion.springTo(
      _shape,
      target,
      spring: ExpressiveMotion.spatialDefault,
    );
    ExpressiveMotion.springTo(
      _tint,
      target,
      spring: ExpressiveMotion.effectsDefault,
    );
  }

  @override
  void dispose() {
    _shape.dispose();
    _tint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedRadius = ExpressiveShape.radius(
      ExpressiveListSegment.selectedCorner,
    );

    return TvFocusHighlight(
      radius: widget.radius,
      child: AnimatedBuilder(
        animation: Listenable.merge([_shape, _tint]),
        builder: (context, child) {
          final shape = _shape.value.clamp(0.0, 1.0);
          final tint = _tint.value.clamp(0.0, 1.0);
          return ClipRRect(
            borderRadius: BorderRadius.lerp(
              widget.radius,
              selectedRadius,
              shape,
            )!,
            child: Material(
              color: TvFocusHighlight.containerOf(context) ??
                  Color.lerp(widget.color, widget.selectedColor, tint),
              child: child,
            ),
          );
        },
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onSecondaryTap: widget.onSecondaryTap,
          splashColor: widget.splashColor,
          highlightColor: widget.highlightColor,
          child: widget.child,
        ),
      ),
    );
  }
}
