import 'package:flutter/material.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/shared/ui/app_theme.dart';
import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:keqdroid/shared/ui/halloween/halloween_icons.dart';
import 'package:keqdroid/shared/ui/haptics.dart';

List<({IconData icon, String label, bool badge})> appNavDestinations(
  AppLocalizations l10n, {
  required bool showConnectedBadge,
}) =>
    [
      (icon: Icons.lan_rounded, label: l10n.navServers, badge: showConnectedBadge),
      (icon: Icons.language_rounded, label: l10n.navSubscriptions, badge: false),
      (icon: Icons.settings_rounded, label: l10n.navSettings, badge: false),
    ];

// своя реализация: у NavigationBar во Flutter 3.44 подпись только под иконкой;
// анимация здесь, а не в пунктах, потому что доля ряда считается из той же величины, что отступы
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

  // unbounded: пружина должна перелетать за цель
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
    final items = appNavDestinations(
      l10n,
      showConnectedBadge: widget.showConnectedBadge,
    );

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
                        icon: items[i].icon,
                        label: items[i].label,
                        badge: items[i].badge,
                        selected: widget.index == i,
                        t: _ctrls[i].value,
                        maxLabelWidth: budgets[i],
                        onTap: () {
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

  // явно, а не Flexible: доля Flex не знает минимума пункта, и узкий ряд переполнялся
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

  final double t;

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

  static double fixedWidth(double t) =>
      _iconSize + 2 * (_padMin + _padGrowth * t.clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shape = ExpressiveShape.border(ExpressiveShape.full);
    final tc = t.clamp(0.0, 1.0);

    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: Material(
        color: Color.lerp(Colors.transparent, cs.secondaryContainer, tc),
        shape: shape,
        clipBehavior: Clip.antiAlias,
        // цвет ведём пружиной покадрово, неявная анимация Material отставала бы
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
                NavIcon(
                  icon: icon,
                  badge: badge,
                  color: Color.lerp(cs.onSurfaceVariant, cs.onSurface, tc)!,
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxLabelWidth),
                  child: ClipRect(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: tc,
                      // без heightFactor Align растёт до высоты экрана
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

class NavIcon extends StatelessWidget {
  final IconData icon;
  final bool badge;
  final Color color;

  const NavIcon({
    super.key,
    required this.icon,
    required this.badge,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SeasonalIcon(icon, size: 24, color: color),
        if (badge)
          Positioned(
            top: -1,
            right: -1,
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
