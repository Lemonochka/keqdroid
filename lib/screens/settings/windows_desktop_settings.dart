part of '../settings_tab.dart';

class _WindowsDesktopSettingsScreen extends ConsumerWidget {
  const _WindowsDesktopSettingsScreen();

  Future<void> _save(WidgetRef ref, AppSettings next) async {
    await ref.read(settingsNotifierProvider.notifier).save(next);
    await WindowsDesktopService.applySettings(next);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();

    Widget toggleRow({
      required String title,
      required String subtitle,
      required bool value,
      required ValueChanged<bool>? onChanged,
    }) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.card(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.divider(context), width: 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.text(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textLight(context),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              activeThumbColor: AppTheme.accent(context),
              onChanged: onChanged,
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.bg(context),
        elevation: 0,
        title: Text(l10n.settingsDesktopTitle),
      ),
      body: SmoothScroll(
        builder: (context, controller) => ListView(
          controller: controller,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          toggleRow(
            title: l10n.settingsMinimizeToTray,
            subtitle: l10n.settingsMinimizeToTrayHint,
            value: settings.minimizeToTray,
            onChanged: (v) => _save(ref, settings.copyWith(minimizeToTray: v)),
          ),
          const SizedBox(height: 12),
          toggleRow(
            title: l10n.settingsLaunchAtStartup,
            subtitle: l10n.settingsLaunchAtStartupHint,
            value: settings.launchAtStartup,
            onChanged: (v) => _save(ref, settings.copyWith(launchAtStartup: v)),
          ),
          const SizedBox(height: 12),
          toggleRow(
            title: l10n.settingsAutoConnectOnAutostart,
            subtitle: l10n.settingsAutoConnectOnAutostartHint,
            value: settings.autoConnectLastServer,
            onChanged: settings.launchAtStartup
                ? (v) => _save(
                      ref,
                      settings.copyWith(autoConnectLastServer: v),
                    )
                : null,
          ),
          if (!settings.launchAtStartup)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
              child: Text(
                l10n.settingsAutoConnectRequiresAutostart,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textLight(context),
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }
}

