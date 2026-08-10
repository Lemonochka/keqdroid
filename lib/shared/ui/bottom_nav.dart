import 'package:flutter/material.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/shared/ui/app_theme.dart';
import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:keqdroid/shared/ui/haptics.dart';

/// Нижняя навигация в горизонтальной раскладке M3 Expressive: иконка и подпись
/// стоят в один ряд внутри пилюли-индикатора, а не подпись под иконкой.
///
/// Своя реализация вместо [NavigationBar] нужна ровно из-за этой раскладки —
/// во Flutter 3.44 у навбара есть только вертикальная. Всё остальное берём по
/// анатомии M3: пилюля-индикатор, state layer с рипплом по её форме, цель
/// нажатия не меньше 48 логических пикселей, переход выбора — пружиной.
///
/// Анимация живёт здесь, а не в самих пунктах, и это принципиально: доля ряда
/// под пункт считается из той же величины, что и его отступы. Когда доля падала
/// мгновенно (по булеву `selected`), а отступы ещё ехали, пункт переполнял ряд.
class AppBottomNav extends StatefulWidget {
  final int index;
  final bool showConnectedBadge;
  final void Function(int) onTap;

  const AppBottomNav({
    super.key,
    required this.index,
    required this.onTap,
    required this.showConnectedBadge,
  });

  @override
  State<AppBottomNav> createState() => _AppBottomNavState();
}

class _AppBottomNavState extends State<AppBottomNav>
    with TickerProviderStateMixin {
  static const int _count = 3;

  /// Unbounded — пружина M3E недодемпфирована и обязана перелетать за цель,
  /// иначе движение вырождается обратно в обычный ease.
  late final List<AnimationController> _ctrls = List.generate(
    _count,
    (i) => AnimationController.unbounded(
      vsync: this,
      value: widget.index == i ? 1 : 0,
    ),
  );

  @override
  void didUpdateWidget(AppBottomNav old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;
    for (var i = 0; i < _count; i++) {
      ExpressiveMotion.springTo(
        _ctrls[i],
        widget.index == i ? 1 : 0,
        spring: ExpressiveMotion.spatialFast,
      );
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final items = <(IconData, String, bool)>[
      (Icons.lan, l10n.navServers, widget.showConnectedBadge),
      (Icons.language, l10n.navSubscriptions, false),
      (Icons.settings, l10n.navSettings, false),
    ];

    return Container(
      color: cs.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: AnimatedBuilder(
            animation: Listenable.merge(_ctrls),
            builder: (context, _) => LayoutBuilder(
              builder: (context, constraints) {
                final ts = [
                  for (final c in _ctrls) c.value.clamp(0.0, 1.0),
                ];
                final budgets = _labelBudgets(ts, constraints.maxWidth);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (var i = 0; i < _count; i++)
                      _NavItem(
                        icon: items[i].$1,
                        label: items[i].$2,
                        badge: items[i].$3,
                        selected: widget.index == i,
                        t: _ctrls[i].value,
                        maxLabelWidth: budgets[i],
                        onTap: () {
                          // Повторный тап по своей же вкладке ничего не меняет —
                          // и отдаваться ему нечем.
                          if (i != widget.index) AppHaptics.selection();
                          widget.onTap(i);
                        },
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Сколько места остаётся каждой подписи.
  ///
  /// Считаем явно, а не через `Flexible`: доля Flex ничего не знает про
  /// минимальный размер пункта, и в узком окне 48 px иконки с отступами не
  /// влезали в свои 42 — ряд переполнялся. Здесь неснимаемая часть пунктов
  /// вычитается первой, а остаток делится пропорционально раскрытию, поэтому
  /// сумма ширин по построению не превышает доступную.
  static List<double> _labelBudgets(List<double> ts, double maxWidth) {
    var fixed = 0.0;
    var openSum = 0.0;
    for (final t in ts) {
      fixed += _NavItem.fixedWidth(t);
      openSum += t;
    }
    if (!maxWidth.isFinite || openSum <= 0) {
      return List.filled(ts.length, double.infinity);
    }
    final budget = (maxWidth - fixed).clamp(0.0, double.infinity);
    return [for (final t in ts) budget * t / openSum];
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool badge;

  /// 0 — свёрнут до иконки, 1 — раскрыт с подписью. Может перелетать за 1:
  /// это пружина, и перелёт нужен геометрии.
  final double t;

  /// Потолок ширины подписи, посчитанный родителем из остатка ряда.
  final double maxLabelWidth;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.t,
    required this.maxLabelWidth,
    required this.onTap,
    this.badge = false,
  });

  static const double _iconSize = 24;
  static const double _padMin = 12;
  static const double _padGrowth = 8;

  /// Часть ширины, которая не ужимается ни при каких обстоятельствах: иконка и
  /// горизонтальные отступы. Родитель вычитает её из ряда до дележа остатка.
  static double fixedWidth(double t) =>
      _iconSize + 2 * (_padMin + _padGrowth * t.clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shape = ExpressiveShape.border(ExpressiveShape.full);
    // Перелёт пружины полезен геометрии, но не цвету и не ширине подписи: там
    // он читается как дефект.
    final tc = t.clamp(0.0, 1.0);

    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: Material(
        color: Color.lerp(Colors.transparent, cs.secondaryContainer, tc),
        shape: shape,
        clipBehavior: Clip.antiAlias,
        // Цвет пилюли мы ведём пружиной покадрово — неявная 200-миллисекундная
        // анимация Material тянулась бы следом и отставала от отступов.
        animationDuration: Duration.zero,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: _padMin + _padGrowth * tc,
              vertical: 12,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Icon(
                  icon: icon,
                  badge: badge,
                  color: Color.lerp(cs.onSurfaceVariant, cs.onSurface, tc)!,
                ),
                // Подпись выезжает из-под иконки: ClipRect + widthFactor растит
                // её по месту, без рывка при появлении.
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxLabelWidth),
                  child: ClipRect(
                    child: Align(
                      // Подпись выезжает от иконки, а иконка в RTL стоит
                      // справа — с физическим centerLeft она бы выползала
                      // не с той стороны.
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: tc,
                      // heightFactor обязателен: без него Align растёт в высоту
                      // до максимума ограничений, а bottomNavigationBar
                      // получает от Scaffold высоту всего экрана.
                      heightFactor: 1,
                      child: Opacity(
                        opacity: tc,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(start: 8),
                          child: Text(
                            label,
                            style: theme.textTheme.labelLarge
                                ?.copyWith(color: cs.onSurface),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.fade,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Icon extends StatelessWidget {
  final IconData icon;
  final bool badge;
  final Color color;

  const _Icon({required this.icon, required this.badge, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, size: 24, color: color),
        if (badge)
          Positioned(
            top: -1,
            right: -1,
            // Обводка цветом поверхности: без неё точка сливается с иконкой,
            // когда попадает на её штрих.
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(1.5),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppTheme.green(context),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
