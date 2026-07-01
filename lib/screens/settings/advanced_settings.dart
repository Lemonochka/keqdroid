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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _SettingsCard(
            title: l10n.settingsPingTitle,
            subtitle: _pingSettingsSubtitle(l10n, settingsAsync.value),
            icon: Icons.network_ping,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const _PingSettingsScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            title: l10n.settingsXrayCoreTitle,
            subtitle: _xrayCoreSettingsSubtitle(l10n, settingsAsync.value),
            icon: Icons.settings_ethernet,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const _XrayCoreSettingsScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            title: l10n.settingsLocalPortsTitle,
            subtitle: l10n.settingsLocalPortsSubtitle(
              (settingsAsync.value ?? const AppSettings()).localPort.toString(),
              (settingsAsync.value ?? const AppSettings()).httpPort.toString(),
            ),
            icon: Icons.settings_input_component,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const _LocalProxyPortsScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            title: l10n.settingsRoutingTitle,
            subtitle: l10n.settingsRoutingSubtitle,
            icon: Icons.account_tree,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const _RoutingScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            title: l10n.settingsResetRoutingTitle,
            subtitle: l10n.settingsResetRoutingSubtitle,
            icon: Icons.restore,
            isDestructive: false,
            onTap: () async {
              final current = ref.read(settingsNotifierProvider).value;
              if (current == null) return;
              await ref.read(settingsNotifierProvider.notifier).save(
                    current.copyWith(
                      directRules: RoutingPresets.defaultDirectRules,
                      proxyRules: RoutingPresets.defaultProxyRules,
                      blockedRules: RoutingPresets.defaultBlockedRules,
                    ),
                  );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.settingsRoutingResetDone)),
                );
              }
            },
          ),
          const SizedBox(height: 12),
          _DebugModeCard(settingsAsync: settingsAsync),
          const SizedBox(height: 12),
          _ShareHwidCard(settingsAsync: settingsAsync),
        ],
      ),
      ),
    );
  }
}

