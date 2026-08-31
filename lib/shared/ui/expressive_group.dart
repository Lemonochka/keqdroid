/// Containment из Material 3 Expressive — группа связанных строк.
///
/// В спеке containment стоит в одном ряду с цветом, формой, размером и
/// движением: это не декор, а способ сказать «эти пункты — одно целое».
/// Практически это значит, что стопка одинаковых отдельных карточек с равными
/// зазорами (наш прежний экран настроек) — не M3E: там нет ни группы, ни
/// иерархии внутри неё.
///
/// Правило формы у группы простое и держится на контрасте: **внешние углы
/// крупные, внутренние стыки почти квадратные**. Тогда группа читается как
/// один объект, а швы внутри — как разделители, а не как границы карточек.
library;

import 'package:flutter/material.dart';

import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:keqdroid/shared/ui/expressive_elements.dart';

/// Стопка сегментов в одном контейнере.
///
/// Форму каждого сегмента считает сама группа: у крайних скругляются внешние
/// углы ([outerCorner]), у стыков — [innerCorner]. Единственный сегмент
/// получает крупный радиус со всех сторон.
class ExpressiveGroup extends StatelessWidget {
  final List<Widget> children;

  /// Внешние углы группы. По умолчанию `extraLarge` (28) — «поверхностный»
  /// радиус M3E, заметно крупнее карточного `large`.
  final double outerCorner;

  /// Углы на стыках сегментов.
  final double innerCorner;

  /// Зазор между сегментами. 2 логических пикселя: шов виден, но группа не
  /// распадается на отдельные карточки.
  final double spacing;

  const ExpressiveGroup({
    super.key,
    required this.children,
    this.outerCorner = ExpressiveShape.extraLarge,
    this.innerCorner = ExpressiveShape.extraSmall,
    this.spacing = 2,
  });

  /// Форма сегмента [index] из [count] штук.
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
          _ExpressiveGroupScope(
            radius: segmentRadius(
              index: i,
              count: count,
              outerCorner: outerCorner,
              innerCorner: innerCorner,
            ),
            child: children[i],
          ),
        ],
      ],
    );
  }
}

/// Заголовок секции настроек.
///
/// Раньше каждый подэкран объявлял свой `sectionTitle()` прямо в `build()`, и
/// они разъехались: где-то `titleSmall` с трекингом 0.4, где-то без, отступы у
/// всех разные, а «Core settings» и «Routing» завели вообще свой вид — с
/// иконкой и в цвете `onSurface`. Роль по спеке — `labelLarge` в усиленном
/// варианте цветом `primary`: заголовок секции обязан читаться как разделитель,
/// а не как ещё одна строка серого текста.
///
/// [icon] опционален и остаётся деталью, а не вторым стилем: типографика,
/// цвет и отступы у обоих вариантов общие.
class ExpressiveSectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;

  const ExpressiveSectionHeader(this.title, {super.key, this.icon});

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

    return Padding(
      // По горизонтали почти вровень с карточками: экраны настроек уже дают
      // списку свои 16 px, и ещё 16 сверху уводили подпись на 32 — она висела
      // в стороне от группы, к которой относится.
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: icon == null
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
            ),
    );
  }
}

/// Одиночная карточка подэкрана настроек.
///
/// Заливка, форма и отступы в одном месте — прежде эта же связка была
/// переписана вручную примерно в десятке подэкранов, каждый раз чуть иначе
/// (`all(16)` против `symmetric(4)`, рамка против её отсутствия).
///
/// Внутри именно [Material], а не `DecoratedBox`: `ListTile` рисует ink-всплеск
/// на ближайшем Material-предке, и цветная прослойка между ними гасила рипл
/// (в debug сыпалось «ListTile background color or ink splashes may be
/// invisible»).
class ExpressiveCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  /// Подсветка состояния (включённый debug, идущая запись хоткея). Обычной
  /// карточке обводка не нужна: контейнер отделяет её от фона сам, а рамка на
  /// каждой карточке — тот самый визуальный шум.
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

/// Пункт-действие в шторке-меню.
///
/// Голый список `ListTile` внутри шторки читался как «набор слов»: границ у
/// пунктов нет, куда именно жать — неочевидно. Здесь у каждого пункта своя
/// форма (от [ExpressiveGroup]), заливка и иконка в цветном контейнере — тот же
/// приём, которым устроены строки настроек.
///
/// [danger] переводит пункт в роль `error`: удаление обязано отличаться от
/// «скопировать» не только подписью.
class ExpressiveActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final ExpressiveAccent accent;
  final bool danger;

  /// Шторка-выбор (сортировка, интервал, язык), а не список действий: текущий
  /// пункт заливается `secondaryContainer` и получает галочку — тем же
  /// способом, что активный сервер и чип «подключено».
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
      // На залитом сегменте кружок иконки берёт цвет самого текста, иначе
      // контейнер на контейнере сливается в пятно.
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

/// Передаёт сегменту его форму, чтобы [ExpressiveGroupTile] не пришлось
/// сообщать свой индекс вручную на каждом экране.
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

/// Сегмент группы: заливка, форма от группы, ripple и shape-морфинг нажатия.
///
/// Морфинг — подпись M3E («square morphing into a squircle» в анонсе Android
/// 16): на нажатии углы уходят на шаг ближе к квадрату и пружиной возвращаются
/// обратно. Пружина живёт на `AnimationController.unbounded`, потому что
/// [SpringSimulation] проскакивает мимо цели, а bounded-контроллер такой
/// перелёт обрезает и съедает весь отскок.
class ExpressiveGroupTile extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Заливка сегмента. По умолчанию — `surfaceContainerHigh`.
  final Color? color;

  /// Форма, если сегмент используется вне [ExpressiveGroup].
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
        // Пружина уходит за 1 — для формы это лишнее (углы «переморфились» бы
        // в другую сторону), поэтому под лерп значение зажимаем, а отскок
        // остаётся во времени возврата.
        final t = _press.value.clamp(0.0, 1.0);
        return ClipRRect(
          borderRadius: BorderRadius.lerp(base, pressed, t)!,
          child: child,
        );
      },
      child: Material(
        color: widget.color ?? scheme.surfaceContainerHigh,
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

/// Сегмент выразительного списка (M3 Expressive «expressive list»).
///
/// Спека переписала списки: baseline-вариант — строки встык, квадратные углы,
/// разделители — помечен «not recommended», и на его месте теперь
/// сегментированный список. Разница не косметическая, а структурная:
///
///  * строки — **отдельные залитые контейнеры с зазорами**; разделители спека
///    оставляет только неконтейнерным спискам («use gaps for contained lists»);
///  * **выбор показывается морфингом формы**: у невыбранного сегмента 4dp на
///    внутренних углах и 16dp на внешних, у выбранного — 16dp по кругу. Ни
///    подъёма, ни обводки, ни градиента: контейнер и его форма и есть выделение.
///
/// Нажатие форму НЕ морфит — в отличие от [ExpressiveGroupTile]. У сегмента с
/// углами 4dp морфить нечего (шкала там уже упирается в квадрат), а спека для
/// списков описывает нажатие только слоем состояния. Обратная связь — рипл.
///
/// Форму сегмента считает владелец списка ([segmentRadius]): только он знает,
/// где у сегмента сосед, а где край группы.
class ExpressiveListSegment extends StatefulWidget {
  final Widget child;

  /// Форма НЕвыбранного сегмента.
  final BorderRadius radius;

  final bool selected;

  /// Заливка сегмента и его выбранного состояния.
  final Color color;
  final Color selectedColor;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// На десктопе правым кликом обычно открывают то же, что длинным нажатием.
  final VoidCallback? onSecondaryTap;

  final Color? splashColor;
  final Color? highlightColor;

  /// Углы выбранного сегмента — 16dp по кругу.
  static const double selectedCorner = ExpressiveShape.large;

  /// Внутренние углы (там, где у сегмента сосед).
  static const double innerCorner = ExpressiveShape.extraSmall;

  /// Внешние углы (край группы).
  static const double outerCorner = ExpressiveShape.large;

  /// Зазор между сегментами. В отличие от [ExpressiveGroup] с его волосяным
  /// швом, список разделяет именно зазор: он и заменяет собой дивайдеры.
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

  /// Форма сегмента по его месту в группе.
  ///
  /// [columns] = 1 — обычный список; больше — сетка, и тогда внешним считается
  /// угол, за которым нет соседа. Нечётный хвост учитывается: у последней
  /// плитки в неполном ряду правые углы такие же внешние, как у края группы, —
  /// справа от неё пустой фон, а не сосед.
  ///
  /// [endCorner] — углы низа ПОСЛЕДНЕГО ряда. Задавать его нужно, когда список
  /// упирается в скруглённый угол своего контейнера: там радиус сегмента обязан
  /// быть КОНЦЕНТРИЧЕН контейнеру, то есть равен его радиусу минус отступ.
  /// Иначе дуги расходятся: вдоль прямых краёв поле нормальное, а на углу
  /// схлопывается почти в ноль, и сегмент выпирает за дугу контейнера.
  static BorderRadius segmentRadius({
    required int index,
    required int count,
    int columns = 1,
    double? endCorner,
  }) {
    final row = index ~/ columns;
    final col = index % columns;
    final rows = (count + columns - 1) ~/ columns;

    final isTop = row == 0;
    // Снизу пусто и тогда, когда ряд последний, и когда прямо под плиткой уже
    // кончились серверы (нечётный хвост в сетке).
    final isLastRow = row == rows - 1;
    final isBottom = isLastRow || index + columns >= count;
    final isStart = col == 0;
    final isEnd = col == columns - 1 || index == count - 1;

    const outer = Radius.circular(outerCorner);
    const inner = Radius.circular(innerCorner);
    // Концентричный радиус — только у настоящего последнего ряда: у плитки над
    // нечётным хвостом снизу тоже пусто, но до края контейнера ей далеко.
    final end = isLastRow && endCorner != null
        ? Radius.circular(endCorner)
        : outer;
    return BorderRadius.only(
      topLeft: isTop && isStart ? outer : inner,
      topRight: isTop && isEnd ? outer : inner,
      bottomLeft: isBottom && isStart ? end : inner,
      bottomRight: isBottom && isEnd ? end : inner,
    );
  }

  /// Отступы сегмента внутри шага списка.
  ///
  /// Зазор набирается ПОЛЯМИ САМОГО СЕГМЕНТА, а не расстоянием между ячейками:
  /// шаг списка (`ServerRow.height`) остаётся прежним, и от него по-прежнему
  /// считаются `mainAxisExtent` сетки и смещение якоря активного сервера.
  /// Иначе пришлось бы править обе формулы в трёх местах ради четырёх пикселей.
  static EdgeInsets segmentMargin({required int index, int columns = 1}) {
    const half = gap / 2;
    if (columns == 1) {
      return const EdgeInsets.fromLTRB(gap, half, gap, half);
    }
    final col = index % columns;
    return EdgeInsets.fromLTRB(
      col == 0 ? gap : half,
      half,
      col == columns - 1 ? gap : half,
      half,
    );
  }

  @override
  State<ExpressiveListSegment> createState() => _ExpressiveListSegmentState();
}

class _ExpressiveListSegmentState extends State<ExpressiveListSegment>
    with TickerProviderStateMixin {
  /// Форма и заливка едут РАЗНЫМИ пружинами — так их делит спека движения:
  /// форма пространственна и слегка отскакивает, цвет критически задемпфирован,
  /// потому что колебание яркости читается как дефект.
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

    return AnimatedBuilder(
      animation: Listenable.merge([_shape, _tint]),
      builder: (context, child) {
        // Пружина уходит за единицу — форме это лишнее (углы «переморфились» бы
        // дальше выбранных 16dp), поэтому под лерп значение зажимаем.
        final shape = _shape.value.clamp(0.0, 1.0);
        final tint = _tint.value.clamp(0.0, 1.0);
        return ClipRRect(
          borderRadius: BorderRadius.lerp(
            widget.radius,
            selectedRadius,
            shape,
          )!,
          child: Material(
            color: Color.lerp(widget.color, widget.selectedColor, tint),
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
    );
  }
}
