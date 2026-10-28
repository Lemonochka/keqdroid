import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_settings.dart';
import '../../providers/providers.dart';
import '../../shared/ui/expressive.dart';
import '../../shared/ui/expressive_button_group.dart';
import '../../shared/ui/halloween/halloween_icons.dart';
import '../../tunnel/connection_mode.dart';
import 'desktop_connection_mode.dart';
import 'sidebar_group_nav.dart';

// боковая навигация M3E: развёрнутая с подписью справа и свёрнутая с подписью под значком
// превращаются друг в друга по кнопке меню. разделы ведут себя как кнопки-переключатели M3E:
// выбранный из круглого становится квадратным, нажатый растёт, соседи на миг уступают
class DesktopRail extends ConsumerStatefulWidget {
  const DesktopRail({super.key, required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  static const double collapsedWidth = 96;
  static const double expandedWidth = 272;
  // в окне уже 900 dp развёрнутая панель отнимает у списка слишком много
  static const double expandFrom = 900;

  @override
  ConsumerState<DesktopRail> createState() => _DesktopRailState();
}

const _count = 3;
const _pop = SpringDescription(mass: 1, stiffness: 420, damping: 0.62 * 2 * 20.49);
const _soft = SpringDescription(mass: 1, stiffness: 260, damping: 0.85 * 2 * 16.12);
const _bounce = SpringDescription(mass: 1, stiffness: 380, damping: 0.42 * 2 * 19.49);

double _lerp(double a, double b, double t) => a + (b - a) * t;

class _DesktopRailState extends ConsumerState<DesktopRail> with TickerProviderStateMixin {
  late final _indicator = [
    for (var i = 0; i < _count; i++)
      AnimationController.unbounded(vsync: this, value: i == widget.index ? 1 : 0),
  ];
  late final _square = [
    for (var i = 0; i < _count; i++)
      AnimationController.unbounded(vsync: this, value: i == widget.index ? 1 : 0),
  ];
  late final _press = [for (var i = 0; i < _count; i++) AnimationController.unbounded(vsync: this)];
  late final _hover = [for (var i = 0; i < _count; i++) AnimationController.unbounded(vsync: this)];
  late final _expand = AnimationController.unbounded(vsync: this);
  late final _menu = AnimationController.unbounded(vsync: this);
  bool? _expanded;
  bool? _roomy;

  @override
  void didUpdateWidget(DesktopRail old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;
    // по спеке подложка раскрывается из центра значка
    _indicator[old.index].animateTo(0, duration: const Duration(milliseconds: 120));
    _indicator[widget.index].value = 0;
    ExpressiveMotion.springTo(_indicator[widget.index], 1, spring: _pop);
    ExpressiveMotion.springTo(_square[widget.index], 1, spring: _soft);
    ExpressiveMotion.springTo(_square[old.index], 0, spring: _soft);
  }

  @override
  void dispose() {
    for (final c in [..._indicator, ..._square, ..._press, ..._hover, _expand, _menu]) {
      c.dispose();
    }
    super.dispose();
  }

  void _sync(AnimationController controller, bool? was, bool now) {
    if (was == now) return;
    if (was == null) {
      controller.value = now ? 1 : 0;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ExpressiveMotion.springTo(controller, now ? 1 : 0, spring: _soft, snapToEnd: true);
      }
    });
  }

  void _toggle(AppSettings settings) {
    ref.read(settingsNotifierProvider.notifier).save(
          settings.copyWith(desktopRailExpanded: !settings.desktopRailExpanded),
        );
  }

  void _pressDown(int i) {
    for (var k = 0; k < _count; k++) {
      final target = k == i ? 1.0 : ((k - i).abs() == 1 ? -1.0 : 0.0);
      ExpressiveMotion.springTo(_press[k], target, spring: _pop);
    }
  }

  void _pressUp() {
    for (final c in _press) {
      ExpressiveMotion.springTo(c, 0, spring: _bounce);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsNotifierProvider).value ?? const AppSettings();
    final roomy = MediaQuery.sizeOf(context).width >= DesktopRail.expandFrom;
    final expanded = roomy && settings.desktopRailExpanded;
    _sync(_expand, _expanded, expanded);
    _sync(_menu, _roomy, roomy);
    _expanded = expanded;
    _roomy = roomy;
    final hasMode = Platform.isWindows || Platform.isLinux;
    final destinations = [
      (Icons.dns_outlined, Icons.dns_rounded, l10n.navServers),
      (Icons.subscriptions_outlined, Icons.subscriptions_rounded, l10n.navSubscriptions),
      (Icons.settings_outlined, Icons.settings_rounded, l10n.navSettings),
    ];

    return AnimatedBuilder(
      animation: Listenable.merge([..._indicator, ..._square, ..._press, ..._hover, _expand, _menu]),
      builder: (context, _) {
        final ec = _expand.value.clamp(0.0, 1.0);
        final menu = _menu.value.clamp(0.0, 1.0);
        // без перелёта пружины: он на 1 dp сужал список, и на пограничной ширине окна плитки
        // серверов мигали компактными
        final width = _lerp(DesktopRail.collapsedWidth, DesktopRail.expandedWidth, ec);
        final menuTooltip = ec > 0.5 ? l10n.desktopRailCollapse : l10n.desktopRailExpand;
        return ClipRect(
          child: SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                if (menu > 0)
                  ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: menu,
                      child: Opacity(
                        opacity: menu,
                        child: IgnorePointer(
                          ignoring: !roomy,
                          child: Padding(
                            padding: EdgeInsets.only(bottom: hasMode ? _lerp(12, 16, ec) : 0),
                            child: SizedBox(
                              height: 48,
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Padding(
                                  padding: const EdgeInsetsDirectional.only(start: 24),
                                  child: IconButton(
                                    tooltip: menuTooltip,
                                    onPressed: () => _toggle(settings),
                                    icon: Icon(
                                      ec > 0.5 ? Icons.menu_open_rounded : Icons.menu_rounded,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (hasMode) ...[
                  SizedBox(
                    height: _lerp(48, 68, ec),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (ec > 0.02)
                          PositionedDirectional(
                            start: 20,
                            top: 0,
                            width: DesktopRail.expandedWidth - 40,
                            child: Opacity(
                              opacity: ((ec - 0.3) / 0.7).clamp(0.0, 1.0),
                              child: const _ConnectionModeChip(),
                            ),
                          ),
                        if (ec < 0.98)
                          PositionedDirectional(
                            start: 24,
                            top: 0,
                            width: 48,
                            height: 48,
                            child: Opacity(
                              opacity: (1 - ec / 0.6).clamp(0.0, 1.0),
                              child: const _ConnectionModeMenuButton(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                SizedBox(height: _lerp(20, 24, ec)),
                _Destinations(
                  destinations: destinations,
                  index: widget.index,
                  expand: ec,
                  width: width,
                  indicator: _indicator,
                  square: _square,
                  press: _press,
                  hover: _hover,
                  onSelect: widget.onSelect,
                  onPressDown: _pressDown,
                  onPressUp: _pressUp,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: SidebarGroupNav(
                      labels: ec,
                      onOpenServers: () => widget.onSelect(0),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Destinations extends StatelessWidget {
  const _Destinations({
    required this.destinations,
    required this.index,
    required this.expand,
    required this.width,
    required this.indicator,
    required this.square,
    required this.press,
    required this.hover,
    required this.onSelect,
    required this.onPressDown,
    required this.onPressUp,
  });

  final List<(IconData, IconData, String)> destinations;
  final int index;
  final double expand;
  final double width;
  final List<AnimationController> indicator;
  final List<AnimationController> square;
  final List<AnimationController> press;
  final List<AnimationController> hover;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onPressDown;
  final VoidCallback onPressUp;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final ec = expand;
    final step = _lerp(68, 60, ec);
    final baseHeight = _lerp(64, 56, ec);
    final gap = step - baseHeight;
    double heightOf(int i) {
      final p = press[i].value;
      return baseHeight + (p > 0 ? 12 * p : 8 * p);
    }

    double topOf(int i) {
      var y = 0.0;
      for (var k = 0; k < i; k++) {
        y += heightOf(k) + gap;
      }
      return y;
    }

    // раскладка слева направо, в RTL зеркалим
    Rect place(Rect r) => rtl ? Rect.fromLTRB(width - r.right, r.top, width - r.left, r.bottom) : r;

    Rect container(int i, double grow) {
      final top = topOf(i);
      final h = heightOf(i);
      final collapsed = Rect.fromCenter(
        center: Offset(48, top + 20),
        width: 56,
        height: 32 + (h - baseHeight),
      );
      final expanded = Rect.fromLTWH(12, top, width - 24, h);
      final full = Rect.lerp(collapsed, expanded, ec)!;
      final g = grow.clamp(0.0, 1.2);
      final center = Offset(48, _lerp(top + 20, top + h / 2, ec));
      // вширь без перелёта: иначе подложка вылезает за край панели
      return place(Rect.fromLTRB(
        _lerp(center.dx, full.left, math.min(g, 1.0)),
        _lerp(center.dy, full.top, g),
        _lerp(center.dx, full.right, math.min(g, 1.0)),
        _lerp(center.dy, full.bottom, g),
      ));
    }

    final labelStyle = tt.labelLarge;
    return SizedBox(
      height: 3 * step,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < destinations.length; i++) ...[
            if (hover[i].value > 0.01 && i != index)
              Positioned.fromRect(
                rect: container(i, 1),
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: cs.onSurface.withValues(alpha: 0.08 * hover[i].value.clamp(0.0, 1.0)),
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
            if (indicator[i].value > 0.01)
              Builder(builder: (context) {
                final r = container(i, indicator[i].value);
                final round = math.min(r.width, r.height) / 2;
                final q = square[i].value.clamp(0.0, 1.1);
                return Positioned.fromRect(
                  rect: r,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: cs.secondaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          math.max(4.0, _lerp(round, _lerp(10, 16, ec), q)),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            Positioned(
              left: 0,
              width: width,
              top: topOf(i),
              height: heightOf(i),
              child: _Destination(
                icon: destinations[i].$1,
                selectedIcon: destinations[i].$2,
                label: destinations[i].$3,
                selected: i == index,
                expand: ec,
                height: heightOf(i),
                labelStyle: labelStyle,
                onTap: () => onSelect(i),
                onTapDown: () => onPressDown(i),
                onTapUp: onPressUp,
                onHover: (v) => ExpressiveMotion.springTo(hover[i], v ? 1 : 0, spring: _soft),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Destination extends StatelessWidget {
  const _Destination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.expand,
    required this.height,
    required this.labelStyle,
    required this.onTap,
    required this.onTapDown,
    required this.onTapUp,
    required this.onHover,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final double expand;
  final double height;
  final TextStyle? labelStyle;
  final VoidCallback onTap;
  final VoidCallback onTapDown;
  final VoidCallback onTapUp;
  final ValueChanged<bool> onHover;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final ec = expand;
    final style = (selected ? tt.emphasized(labelStyle) : labelStyle)?.copyWith(
      color: selected ? cs.onSurface : cs.onSurfaceVariant,
      fontSize: _lerp(12, labelStyle?.fontSize ?? 14, ec),
    );
    final iconTop = _lerp(8, height / 2 - 12, ec);
    return Semantics(
      selected: selected,
      child: InkWell(
        onTap: onTap,
        onTapDown: (_) => onTapDown(),
        onTapUp: (_) => onTapUp(),
        onTapCancel: onTapUp,
        onHover: onHover,
        customBorder: const StadiumBorder(),
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? cs.onSurface.withValues(alpha: 0.1)
              : Colors.transparent,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            PositionedDirectional(
              start: 36,
              top: iconTop,
              child: SeasonalIcon(
                selected ? selectedIcon : icon,
                size: 24,
                color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
              ),
            ),
            // в свёрнутой подпись под значком по центру, в развёрнутой справа от него
            PositionedDirectional(
              start: _lerp(0, 72, ec),
              end: _lerp(0, 12, ec),
              top: _lerp(42, height / 2 - 10, ec),
              child: Align(
                alignment: Alignment.lerp(
                  Alignment.topCenter,
                  AlignmentDirectional.topStart.resolve(Directionality.of(context)),
                  ec,
                )!,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: style,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionModeMenuButton extends ConsumerWidget {
  const _ConnectionModeMenuButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();
    final mode = settings.connectionModeEnum;

    return PopupMenuButton<ConnectionMode>(
      tooltip: AppLocalizations.of(context)!.desktopConnectionMode,
      icon: SeasonalIcon(
        mode == ConnectionMode.tun ? Icons.vpn_lock_rounded : Icons.lan_rounded,
        size: 22,
      ),
      onSelected: (next) =>
          applyDesktopConnectionMode(context, DesktopModeDeps.of(ref), settings, next),
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: ConnectionMode.proxy,
          checked: mode == ConnectionMode.proxy,
          child: Text(AppLocalizations.of(context)!.trayModeProxy),
        ),
        CheckedPopupMenuItem(
          value: ConnectionMode.tun,
          checked: mode == ConnectionMode.tun,
          child: const Text('TUN'),
        ),
      ],
    );
  }
}

class _ConnectionModeChip extends ConsumerWidget {
  const _ConnectionModeChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();
    final mode = settings.connectionModeEnum;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            AppLocalizations.of(context)!.desktopModeShort,
            style: Theme.of(context).textTheme
                .emphasized(Theme.of(context).textTheme.labelLarge)
                ?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
        ),
        ExpressiveConnectedButtons<ConnectionMode>(
          segments: [
            ExpressiveSegment(
              value: ConnectionMode.proxy,
              label: AppLocalizations.of(context)!.trayModeProxy,
              icon: Icons.lan_rounded,
            ),
            const ExpressiveSegment(
              value: ConnectionMode.tun,
              label: 'TUN',
              icon: Icons.vpn_lock_rounded,
            ),
          ],
          selected: mode,
          onChanged: (next) =>
              applyDesktopConnectionMode(context, DesktopModeDeps.of(ref), settings, next),
        ),
      ],
    );
  }
}
