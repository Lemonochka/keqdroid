import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Карточка с цветной полоской по левому краю — ей помечают исход/категорию
/// строки списка (например вердикт роутинга на экране «Соединения»).
///
/// Полоска здесь именно ребёнок, а не левая сторона рамки, и это принципиально:
/// `BoxDecoration` с `Border`, у которого стороны разного цвета, и одновременно
/// с `borderRadius` во Flutter не рисуется — `Border.paint` бросает прямо в
/// paint-фазе. Исключение ловится на уровне render object'а, поэтому приложение
/// не падает: молча пропадает содержимое карточки, а список выглядит пустым.
class AccentEdgeCard extends StatelessWidget {
  const AccentEdgeCard({
    super.key,
    required this.edgeColor,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.borderRadius = 14,
    this.edgeWidth = 3,
  });

  /// Цвет полоски-маркера.
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
      // Stack, а не Row со stretch: карточка живёт в ListView, где высота
      // приходит неограниченной, а stretch раздаёт детям tightFor(maxHeight) —
      // то есть бесконечную высоту. Здесь размер задаёт непозиционированный
      // ребёнок, а полоска просто растягивается по нему.
      child: Stack(
        children: [
          Padding(
            padding: padding.add(
              EdgeInsetsDirectional.only(start: edgeWidth),
            ),
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
