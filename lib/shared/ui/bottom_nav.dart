import 'package:flutter/material.dart';
import 'package:keqdroid/l10n/app_localizations.dart';

class AppBottomNav extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(context, 0, Icons.lan, l10n.navServers, badge: showConnectedBadge),
              _navItem(context, 1, Icons.language, l10n.navSubscriptions),
              _navItem(context, 2, Icons.settings, l10n.navSettings),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(BuildContext context, int i, IconData icon, String label, {bool badge = false}) {
    final active = index == i;
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => onTap(i),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(horizontal: active ? 18 : 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? cs.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 22, color: active ? cs.onSurface : cs.onSurfaceVariant),
                if (badge)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            if (active) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

