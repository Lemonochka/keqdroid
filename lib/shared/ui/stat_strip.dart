/// Полоса показателей: один контейнер с ячейками, а не россыпь отдельных чипов.
///
/// Четыре чипа под кнопкой подключения жили каждый своей плашкой. В строку они
/// влезали не всегда, а поделённые пополам занимали два ряда и добрую часть
/// экрана — при том что несут четыре коротких числа. Здесь это один объект:
/// показатели стоят ячейками внутри общей поверхности, разделённые волосяной
/// линией, и читаются как приборная панель, а не как рассыпанные значки.
///
/// Ширина ячейки под значение постоянна (считается по образцу): значения
/// обновляются раз в секунду, и без этого полоса дышала бы на каждом кадре.
library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../../utils/bidi.dart';
import 'expressive.dart';

/// Одна строка внутри ячейки: свой значок и своё значение.
class StatLine {
  final IconData icon;

  /// Название для доступности: на экране его заменяет значок, но незрячему
  /// пользователю «часы» ничего не скажут.
  final String label;

  final String value;

  /// Самое широкое значение, какое сюда может приехать.
  final String template;

  const StatLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.template,
  });
}

/// Одна ячейка полосы.
class StatMetric {
  /// Подпись ячейки слева. Пусто — ячейка без подписи.
  ///
  /// Нужна, когда ячеек несколько и различает их не показатель, а то, о чём
  /// они: у разбивки трафика одна ячейка про туннель, другая про обход, а
  /// строки внутри у обеих одинаковые.
  final String tag;

  /// Название ячейки для доступности.
  final String label;

  final List<StatLine> lines;

  StatMetric({
    required IconData icon,
    required String label,
    required String value,
    required String template,
  })  : tag = '',
        label = label,
        lines = [
          StatLine(icon: icon, label: label, value: value, template: template),
        ];

  /// Ячейка про один канал: подпись слева, показатели канала строками.
  ///
  /// Раскладка «столбец = канал», а не «столбец = показатель»: числа одного
  /// канала стоят рядом и складываются в ответ на вопрос «а сюда вообще
  /// что-нибудь идёт», вместо того чтобы искать вторую половину ответа в
  /// соседней ячейке.
  const StatMetric.channel({
    required this.tag,
    required this.label,
    required this.lines,
  });
}

class StatStrip extends StatelessWidget {
  final List<StatMetric> metrics;

  const StatStrip({super.key, required this.metrics});

  /// Поля ячейки и зазор между значком и значением.
  static const double _cellPadding = ExpressiveSpacing.medium;
  static const double _gap = 6;


  /// Толщина разделителя между ячейками.
  static const double _divider = 1;

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = metrics
            .map((m) => _cellWidth(context, m))
            .reduce(max);
        final columns = statStripColumns(
          count: metrics.length,
          cellWidth: cellWidth,
          dividerWidth: _divider,
          maxWidth: constraints.maxWidth,
        );

        final rows = <List<StatMetric>>[];
        for (var i = 0; i < metrics.length; i += columns) {
          rows.add(metrics.skip(i).take(columns).toList());
        }

        return DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: ExpressiveShape.radius(ExpressiveShape.large),
          ),
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var r = 0; r < rows.length; r++) ...[
                  if (r > 0)
                    Divider(
                      height: _divider,
                      thickness: _divider,
                      // Линия не доходит до краёв: у M3 разделитель внутри
                      // контейнера — не рамка, а подсказка о границе ячейки.
                      indent: _cellPadding,
                      endIndent: _cellPadding,
                      color: scheme.outlineVariant,
                    ),
                  _buildRow(context, rows[r], cellWidth, columns),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRow(
    BuildContext context,
    List<StatMetric> row,
    double cellWidth,
    int columns,
  ) {
    final scheme = Theme.of(context).colorScheme;
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
          SizedBox(
            width: cellWidth,
            // Неполный последний ряд оставляет пустую ячейку, а не сжимает
            // остальные: колонки обязаны совпадать между рядами.
            child: i < row.length ? _buildCell(context, row[i]) : null,
          ),
        ],
      ],
    );
  }

  Widget _buildCell(BuildContext context, StatMetric metric) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final valueStyle = _valueStyle(theme);
    final tagWidth = _tagWidth(context, metric, _tagStyle(theme));
    final slotWidth = _slotWidth(context, metric, valueStyle);

    return Semantics(
      label: metric.label,
      // У ячейки с одной строкой значение и есть эта строка: подпись показателя
      // уже стоит меткой, и повторять её внутри значения незачем.
      value: metric.lines.length == 1
          ? metric.lines.first.value
          : [
              for (final line in metric.lines) '${line.label} ${line.value}',
            ].join(', '),
      // Собственную семантику содержимого гасим: иначе подпись ячейки слилась
      // бы с текстом значения в одну строку («Время 44s»), и по названию
      // показателя её было бы уже не найти.
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _cellPadding,
          vertical: 10,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (tagWidth > 0) ...[
              SizedBox(
                width: tagWidth,
                child: Text(
                  metric.tag,
                  style: _tagStyle(theme),
                  maxLines: 1,
                ),
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
                      Icon(
                        line.icon,
                        size: ExpressiveIconSize.inline,
                        color: color,
                      ),
                      const SizedBox(width: _gap),
                      SizedBox(
                        width: slotWidth,
                        child: Text(
                          // `1.5 MB/s`, `1h 30m` — цифры и латиница вокруг
                          // нейтрального пробела: в персидском абзаце они
                          // переставляются в `MB/s 1.5`.
                          ltrIsolate(line.value),
                          style: valueStyle,
                          maxLines: 1,
                          textAlign: TextAlign.center,
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

  double _cellWidth(BuildContext context, StatMetric metric) {
    final theme = Theme.of(context);
    final tagWidth = _tagWidth(context, metric, _tagStyle(theme));
    return _cellPadding * 2 +
        (tagWidth > 0 ? tagWidth + _gap : 0) +
        ExpressiveIconSize.inline +
        _gap +
        _slotWidth(context, metric, _valueStyle(theme));
  }

  static TextStyle? _valueStyle(ThemeData theme) =>
      theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurface,
        // Табличные цифры: у пропорциональных «1» уже остальных, и число
        // дёргалось бы даже внутри слота постоянной ширины.
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Подпись ячейки — ступенью мельче и приглушена: данные здесь числа, а
  /// подпись лишь говорит, к какому каналу их отнести.
  static TextStyle? _tagStyle(ThemeData theme) =>
      theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      );

  /// Ширина колонки подписей. Ноль — подписи нет, колонки тоже.
  static double _tagWidth(
    BuildContext context,
    StatMetric metric,
    TextStyle? style,
  ) =>
      metric.tag.isEmpty
          ? 0
          : _measure(context, metric.tag, style).ceilToDouble();

  /// Ширина слота под значение — по образцу, но не уже реального текста:
  /// на аномально длинном значении слот разово подрастёт, зато не обрежет.
  ///
  /// Слот один на все строки ячейки: разъехавшиеся по ширине строки читались
  /// бы как несколько разных показателей, а не как один канал.
  static double _slotWidth(
    BuildContext context,
    StatMetric metric,
    TextStyle? style,
  ) {
    var width = 0.0;
    for (final line in metric.lines) {
      // Образец меряем в той же обёртке, что и значение: изоляты — обычные
      // символы для движка текста, и шрифт вправе дать им ширину.
      width = max(width, _measure(context, ltrIsolate(line.template), style));
      width = max(width, _measure(context, ltrIsolate(line.value), style));
    }
    return width.ceilToDouble();
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

/// Сколько ячеек ставить в ряд.
///
/// Всё в одну строку, пока влезает; дальше — деление пополам. Раскладка «три
/// сверху, один снизу» центрована верно, но колонки в ней не совпадают ни с
/// чем и читается она как поломка.
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
