import 'package:flutter/material.dart';

import 'app_theme.dart';

// полоска ребёнком: Border с разными цветами сторон и borderRadius бросает в paint,
// и карточка молча пропадает
class AccentEdgeCard extends StatelessWidget {
  const AccentEdgeCard({
    super.key,
    required this.edgeColor,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.borderRadius = 14,
    this.edgeWidth = 3,
  });

  final Color edgeColor;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double edgeWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: AppTheme.divider(context)),
      ),
      // Stack: в ListView высота не ограничена, и Row со stretch получил бы бесконечность
      child: Stack(
        children: [
          Padding(
            padding: padding.add(EdgeInsetsDirectional.only(start: edgeWidth)),
            child: child,
          ),
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            width: edgeWidth,
            child: ColoredBox(color: edgeColor),
          ),
        ],
      ),
    );
  }
}
