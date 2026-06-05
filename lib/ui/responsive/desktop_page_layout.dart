import 'package:flutter/material.dart';

import '../../platform/platform_bootstrap.dart';

/// боковой отступ скролла на телефоне; на desktop — padding из DesktopPageLayout
const double mobileTabHorizontalInset = 16;

double tabContentHorizontalInset() =>
    PlatformBootstrap.isDesktop ? 0 : mobileTabHorizontalInset;

/// центрирует контент вкладки на широком desktop с разумной max width
class DesktopPageLayout extends StatelessWidget {
  const DesktopPageLayout({
    super.key,
    required this.child,
    this.maxWidth = 960,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (!PlatformBootstrap.isDesktop) return child;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// хелперы брейкпоинтов для общих вкладок на desktop
class DesktopBreakpoints {
  static const sidebarWide = 900.0;
  /// Max content width for the servers tab (header + list stay in one column).
  static const serversContentMaxWidth = 900.0;
  static const settingsTwoColumn = 880.0;
}
