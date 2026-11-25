part of '../settings_tab.dart';

@visibleForTesting
Widget advancedSettingsScreenForTest() => const _AdvancedSettingsScreen();

class _AdvancedSettingsScreen extends ConsumerWidget {
  const _AdvancedSettingsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settingsAsync = ref.watch(settingsNotifierProvider);

    return ExpressivePage(
      title: l10n.settingsAdvanced,
      physics: const ClampingScrollPhysics(),
      children: [
        ExpressiveSectionHeader(l10n.settingsAdvancedGroupTraffic),
        ExpressiveGroup(
          children: [
            _SettingsCard(
              title: l10n.settingsPingTitle,
              subtitle: _pingSettingsSubtitle(l10n, settingsAsync.value),
              icon: Icons.network_ping_rounded,
              accent: ExpressiveAccent.primary,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const _PingSettingsScreen(),
                ),
              ),
            ),
            _SettingsCard(
              title: l10n.settingsXrayCoreTitle,
              subtitle: _xrayCoreSettingsSubtitle(l10n, settingsAsync.value),
              icon: Icons.settings_ethernet_rounded,
              accent: ExpressiveAccent.secondary,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const _XrayCoreSettingsScreen(),
                ),
              ),
            ),
            _SettingsCard(
              title: l10n.settingsRoutingTitle,
              subtitle: l10n.settingsRoutingRouteCount(
                ref.watch(routesProvider).value?.length ?? 0,
              ),
              icon: Icons.account_tree_rounded,
              accent: ExpressiveAccent.tertiary,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const _RoutingScreen()),
              ),
            ),
          ],
        ),
        if (HotkeyService.isSupported ||
            Platform.isAndroid ||
            Platform.isLinux ||
            Platform.isMacOS) ...[
          ExpressiveSectionHeader(l10n.settingsAdvancedGroupSystem),
          ExpressiveGroup(
            children: [
              if (HotkeyService.isSupported)
                _SettingsCard(
                  title: l10n.settingsHotkeysTitle,
                  subtitle: l10n.settingsHotkeysSubtitle,
                  icon: Icons.keyboard_rounded,
                  accent: ExpressiveAccent.secondary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const _HotkeySettingsScreen(),
                    ),
                  ),
                ),
              if (Platform.isAndroid || Platform.isLinux || Platform.isMacOS)
                _SettingsCard(
                  title: l10n.settingsPermissionsTitle,
                  subtitle: l10n.settingsPermissionsSubtitle,
                  icon: Icons.admin_panel_settings_rounded,
                  accent: ExpressiveAccent.primary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const _PermissionsScreen(),
                    ),
                  ),
                ),
            ],
          ),
        ],
        ExpressiveSectionHeader(l10n.settingsAdvancedGroupDiagnostics),
        ExpressiveGroup(
          children: [
            _SettingsCard(
              title: l10n.settingsConnectionsLogsTitle,
              subtitle: l10n.settingsConnectionsLogsSubtitle,
              icon: Icons.lan_rounded,
              accent: ExpressiveAccent.primary,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const _ConnectionsLogsScreen(),
                ),
              ),
            ),
            _ShareHwidCard(settingsAsync: settingsAsync),
          ],
        ),
      ],
    );
  }
}
