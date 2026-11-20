library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../../utils/bidi.dart';
import 'expressive.dart';
import 'halloween/halloween_icons.dart';

class StatLine {
  final IconData icon;

  final String label;

  final String value;

  final String template;

  const StatLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.template,
  });
}

class StatMetric {
  final String tag;

  final String label;

  final List<StatLine> lines;

  StatMetric({
    required IconData icon,
    required String label,
    required String value,
    required String template,
  }) : tag = '',
       label = label,
       lines = [
         StatLine(icon: icon, label: label, value: value, template: template),
       ];

  const StatMetric.channel({
    required this.tag,
    required this.label,
    required this.lines,
  });
}

typedef _CellWidths = ({double tag, double slot});

class StatStrip extends StatelessWidget {
  final List<StatMetric> metrics;

  // во всю ширину: ячейки делят её поровну, значение прижато к значку, а не стоит
  // посередине места под самое длинное значение
  final bool fill;

  const StatStrip({super.key, required this.metrics, this.fill = false});

  static const double _cellPadding = ExpressiveSpacing.medium;
  static const double _gap = 6;

  static const double _divider = 1;

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        // замеры текста раз за раскладку: значения меняются каждый тик телеметрии
        final valueStyle = _valueStyle(theme);
        final tagStyle = _tagStyle(theme);
        final widths = [
          for (final m in metrics)
            (
              tag: _tagWidth(context, m, tagStyle),
              slot: _slotWidth(context, m, valueStyle),
            ),
        ];
        final cellWidth = widths.map(_cellWidth).reduce(max);
        final columns = statStripColumns(
          count: metrics.length,
          cellWidth: cellWidth,
          dividerWidth: _divider,
          maxWidth: constraints.maxWidth,
        );

        final rows = <List<int>>[];
        for (var i = 0; i < metrics.length; i += columns) {
          rows.add([
            for (var j = i; j < min(i + columns, metrics.length); j++) j,
          ]);
        }
        final table = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0)
                Divider(
                  height: _divider,
                  thickness: _divider,
                  indent: _cellPadding,
                  endIndent: _cellPadding,
                  color: scheme.outlineVariant,
                ),
              _buildRow(context, rows[r], widths, cellWidth, columns),
            ],
          ],
        );

        return DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: ExpressiveShape.radius(ExpressiveShape.large),
          ),
          child: fill ? table : IntrinsicWidth(child: table),
        );
      },
    );
  }

  Widget _buildRow(
    BuildContext context,
    List<int> row,
    List<_CellWidths> widths,
    double cellWidth,
    int columns,
  ) {
    final scheme = Theme.of(context).colorScheme;
    Widget cell(int i) => _buildCell(context, metrics[row[i]], widths[row[i]]);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < columns; i++) ...[
          if (i > 0)
            Container(
              width: _divider,
              height: 20,
              color: scheme.outlineVariant,
            ),
          if (fill)
            Expanded(child: i < row.length ? cell(i) : const SizedBox.shrink())
          else
            SizedBox(width: cellWidth, child: i < row.length ? cell(i) : null),
        ],
      ],
    );
  }

  Widget _buildCell(
    BuildContext context,
    StatMetric metric,
    _CellWidths widths,
  ) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final valueStyle = _valueStyle(theme);
    final tagWidth = widths.tag;
    final slotWidth = widths.slot;

    return Semantics(
      label: metric.label,
      value: metric.lines.length == 1
          ? metric.lines.first.value
          : [
              for (final line in metric.lines) '${line.label} ${line.value}',
            ].join(', '),
      // иначе для скринридера подпись ячейки слилась бы со значением в одну строку
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _cellPadding,
          vertical: 10,
        ),
        child: Row(
          mainAxisAlignment: fill
              ? MainAxisAlignment.start
              : MainAxisAlignment.center,
          children: [
            if (tagWidth > 0) ...[
              SizedBox(
                width: tagWidth,
                child: Text(metric.tag, style: _tagStyle(theme), maxLines: 1),
              ),
              const SizedBox(width: _gap),
            ],
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in metric.lines)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SeasonalIcon(
                        line.icon,
                        size: ExpressiveIconSize.inline,
                        color: color,
                      ),
                      const SizedBox(width: _gap),
                      SizedBox(
                        width: slotWidth,
                        child: Text(
                          // в фарси цифры и латиница вокруг пробела переставляются: MB/s 1.5
                          ltrIsolate(line.value),
                          style: valueStyle,
                          maxLines: 1,
                          textAlign: fill ? TextAlign.start : TextAlign.center,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static double _cellWidth(_CellWidths w) =>
      _cellPadding * 2 +
      (w.tag > 0 ? w.tag + _gap : 0) +
      ExpressiveIconSize.inline +
      _gap +
      w.slot;

  static TextStyle? _valueStyle(ThemeData theme) =>
      theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurface,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle? _tagStyle(ThemeData theme) => theme.textTheme.labelSmall
      ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

  static double _tagWidth(
    BuildContext context,
    StatMetric metric,
    TextStyle? style,
  ) => metric.tag.isEmpty
      ? 0
      : _measureFixed(context, metric.tag, style).ceilToDouble();

  static double _slotWidth(
    BuildContext context,
    StatMetric metric,
    TextStyle? style,
  ) {
    var width = 0.0;
    for (final line in metric.lines) {
      // образец в той же обёртке: изоляторы для движка обычные символы со своей шириной
      width = max(
        width,
        _measureFixed(context, ltrIsolate(line.template), style),
      );
      width = max(width, _measure(context, ltrIsolate(line.value), style));
    }
    return width.ceilToDouble();
  }

  static final _fixedWidths =
      <(String, TextStyle?, TextScaler, TextDirection), double>{};
  static var _watchingFonts = false;

  // образцы и метки не меняются, а меряются на каждом тике, и на A55 такой замер занимает заметную долю кадра
  static double _measureFixed(
    BuildContext context,
    String text,
    TextStyle? style,
  ) {
    if (!_watchingFonts) {
      _watchingFonts = true;
      PaintingBinding.instance.systemFonts.addListener(_fixedWidths.clear);
    }
    if (_fixedWidths.length > 64) _fixedWidths.clear();
    final key = (
      text,
      style,
      MediaQuery.textScalerOf(context),
      Directionality.of(context),
    );
    return _fixedWidths[key] ??= _measure(context, text, style);
  }

  static double _measure(BuildContext context, String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

int statStripColumns({
  required int count,
  required double cellWidth,
  required double dividerWidth,
  required double maxWidth,
}) {
  if (count <= 1) return 1;
  bool fits(int columns) =>
      columns * cellWidth + (columns - 1) * dividerWidth <= maxWidth;

  for (final columns in <int>{count, (count / 2).ceil(), 2, 1}) {
    if (columns >= 1 && fits(columns)) return columns;
  }
  return 1;
}
