import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/shared/ui/bottom_nav.dart';
import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:keqdroid/shared/ui/haptics.dart';

/// Навигационная рейка — та же навигация, что [AppBottomNav], но у переднего
/// края окна шириной от «expanded» (телефон боком, планшет). Обе сразу спека M3
/// не показывает: на компактной ширине панель, шире — рейка.
///
/// Свёрнутый вариант M3E, числа из токенов AndroidX
/// (NavigationRailCollapsedTokens, NavigationRailVerticalItemTokens): ширина
/// 96, индикатор 56×32, подпись `labelMedium` под значком. Пункты по центру
/// высоты: лежащий телефон держат за края, и до верха рейки тянуться дальше.
class AppNavRail extends StatefulWidget {
  final int index;
  final bool showConnectedBadge;
  final void Function(int) onTap;

  const AppNavRail({
    super.key,
    required this.index,
    required this.showConnectedBadge,
    required this.onTap,
  });

  static const double width = 96;

  @override
  State<AppNavRail> createState() => _AppNavRailState();
}

class _AppNavRailState extends State<AppNavRail> with TickerProviderStateMixin {
  static const int _count = 3;

  /// Unbounded — пружина M3E недодемпфирована и обязана перелетать за цель.
  late final List<AnimationController> _ctrls = List.generate(
    _count,
    (i) => AnimationController.unbounded(
      vsync: this,
      value: widget.index == i ? 1 : 0,
    ),
  );

  @override
  void didUpdateWidget(AppNavRail old) {
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
    final items = appNavDestinations(
      l10n,
      showConnectedBadge: widget.showConnectedBadge,
    );
    final atLeft = Directionality.of(context) == TextDirection.ltr;

    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      // Врезки со стороны края — рейкины: вырез камеры у лежащего телефона
      // приходится как раз на неё. Сверху и снизу — статус-бар и жестовая
      // полоса.
      child: SafeArea(
        left: atLeft,
        right: !atLeft,
        child: SizedBox(
          width: AppNavRail.width,
          child: AnimatedBuilder(
            animation: Listenable.merge(_ctrls),
            builder: (context, _) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _count; i++)
                  _RailItem(
                    icon: items[i].icon,
                    label: items[i].label,
                    badge: items[i].badge,
                    selected: widget.index == i,
                    t: _ctrls[i].value,
                    onTap: () {
                      if (i != widget.index) AppHaptics.selection();
                      widget.onTap(i);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool badge;
  final bool selected;

  /// 0 — не выбран, 1 — выбран; пружина может перелетать за 1.
  final double t;
  final VoidCallback onTap;

  const _RailItem({
    required this.icon,
    required this.label,
    required this.badge,
    required this.selected,
    required this.t,
    required this.onTap,
  });

  static const double _indicatorWidth = 56;
  static const double _indicatorHeight = 32;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final textTheme = theme.textTheme;
    final shape = ExpressiveShape.border(ExpressiveShape.full);
    final tc = t.clamp(0.0, 1.0);

    // Цель нажатия по спеке — вся ширина рейки, а state layer — только по
    // индикатору. Внешний детектор ловит поля, внутренний InkWell выигрывает
    // спор жестов на самом индикаторе, так что нажатие не срабатывает дважды.
    return MergeSemantics(
      child: Semantics(
        selected: selected,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: ExpressiveSpacing.extraSmall / 2,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  type: MaterialType.transparency,
                  shape: shape,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onTap,
                    customBorder: shape,
                    child: SizedBox(
                      width: _indicatorWidth,
                      height: _indicatorHeight,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Индикатор раскрывается от центра значка — так его
                          // появление описывает спека. Ink, а не Container:
                          // рисуется на слое Material, и рипл остаётся поверх.
                          Ink(
                            width: lerpDouble(
                              _indicatorHeight,
                              _indicatorWidth,
                              t,
                            ),
                            height: _indicatorHeight,
                            decoration: ShapeDecoration(
                              color: Color.lerp(
                                Colors.transparent,
                                cs.secondaryContainer,
                                tc,
                              ),
                              shape: shape,
                            ),
                          ),
                          NavIcon(
                            icon: icon,
                            badge: badge,
                            color: Color.lerp(
                              cs.onSurfaceVariant,
                              cs.onSecondaryContainer,
                              tc,
                            )!,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: ExpressiveSpacing.extraSmall),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ExpressiveSpacing.extraSmall,
                  ),
                  // Подпись не режется: спека запрещает многоточие в пункте
                  // навигации, длинное слово переносится на вторую строку.
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: (selected
                            ? textTheme.emphasized(textTheme.labelMedium)
                            : textTheme.labelMedium)
                        ?.copyWith(
                      color: Color.lerp(cs.onSurfaceVariant, cs.secondary, tc),
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
