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
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: iconFg),
          ),
          const SizedBox(width: 14),
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
            Icon(Icons.check, size: 20, color: scheme.onSecondaryContainer),
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
