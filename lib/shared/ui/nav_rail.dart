import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/shared/ui/bottom_nav.dart';
import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:keqdroid/shared/ui/haptics.dart';
import 'package:keqdroid/shared/ui/tv_focus.dart';

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

  // unbounded: пружина должна перелетать за цель
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

    // внешний детектор ловит поля, InkWell выигрывает спор на индикаторе, двойного нажатия нет
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
                TvFocusHighlight(
                  radius: BorderRadius.circular(ExpressiveShape.full),
                  child: Builder(
                    builder: (context) {
                      final fcs = Theme.of(context).colorScheme;
                      return Material(
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
                                      fcs.secondaryContainer,
                                      tc,
                                    ),
                                    shape: shape,
                                  ),
                                ),
                                NavIcon(
                                  icon: icon,
                                  badge: badge,
                                  color: Color.lerp(
                                    fcs.onSurfaceVariant,
                                    fcs.onSecondaryContainer,
                                    tc,
                                  )!,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: ExpressiveSpacing.extraSmall),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ExpressiveSpacing.extraSmall,
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style:
                        (selected
                                ? textTheme.emphasized(textTheme.labelMedium)
                                : textTheme.labelMedium)
                            ?.copyWith(
                              color: Color.lerp(
                                cs.onSurfaceVariant,
                                cs.secondary,
                                tc,
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
