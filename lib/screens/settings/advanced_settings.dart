part of '../settings_tab.dart';

class _AdvancedSettingsScreen extends ConsumerWidget {
  const _AdvancedSettingsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settingsAsync = ref.watch(settingsNotifierProvider);

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.bg(context),
        elevation: 0,
        title: Text(l10n.settingsAdvanced),
      ),
      body: SmoothScroll(
        builder: (context, controller) => ListView(
          controller: controller,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          // Та же группировка, что на верхнем уровне настроек: «трафик и
          // ядро», «система», «диагностика». Раньше это была стопка из семи
          // отдельных карточек через 12 px — ровно тот вид, из-за которого
          // экран читался как свалка.
          ExpressiveSectionHeader(l10n.settingsAdvancedGroupTraffic),
          ExpressiveGroup(
            children: [
              _SettingsCard(
                title: l10n.settingsPingTitle,
                subtitle: _pingSettingsSubtitle(l10n, settingsAsync.value),
                icon: Icons.network_ping,
                accent: ExpressiveAccent.primary,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const _PingSettingsScreen()),
                ),
              ),
              _SettingsCard(
                title: l10n.settingsXrayCoreTitle,
                subtitle: _xrayCoreSettingsSubtitle(l10n, settingsAsync.value),
                icon: Icons.settings_ethernet,
                accent: ExpressiveAccent.secondary,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const _XrayCoreSettingsScreen(),
                  ),
                ),
              ),
              _SettingsCard(
                title: l10n.settingsRoutingTitle,
                subtitle: l10n.settingsRoutingSubtitle,
                icon: Icons.account_tree,
                accent: ExpressiveAccent.tertiary,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const _RoutingScreen()),
                ),
              ),
            ],
          ),
          if (HotkeyService.isSupported ||
              Platform.isAndroid ||
              Platform.isLinux) ...[
            ExpressiveSectionHeader(l10n.settingsAdvancedGroupSystem),
            ExpressiveGroup(
              children: [
                if (HotkeyService.isSupported)
                  _SettingsCard(
                    title: l10n.settingsHotkeysTitle,
                    subtitle: l10n.settingsHotkeysSubtitle,
                    icon: Icons.keyboard_outlined,
                    accent: ExpressiveAccent.secondary,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const _HotkeySettingsScreen(),
                      ),
                    ),
                  ),
                if (Platform.isAndroid || Platform.isLinux)
                  _SettingsCard(
                    title: l10n.settingsPermissionsTitle,
                    subtitle: l10n.settingsPermissionsSubtitle,
                    icon: Icons.admin_panel_settings_outlined,
                    accent: ExpressiveAccent.primary,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
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
              _DebugModeCard(settingsAsync: settingsAsync),
              _ShareHwidCard(settingsAsync: settingsAsync),
            ],
          ),
        ],
      ),
      ),
    );
  }
}

