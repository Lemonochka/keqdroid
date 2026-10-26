part of '../settings_tab.dart';

class _DesktopSettingsScreen extends ConsumerStatefulWidget {
  const _DesktopSettingsScreen();

  @override
  ConsumerState<_DesktopSettingsScreen> createState() =>
      _DesktopSettingsScreenState();
}

class _DesktopSettingsScreenState
    extends ConsumerState<_DesktopSettingsScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_syncWithSystem());
  }

  Future<void> _save(AppSettings next) async {
    await ref.read(settingsNotifierProvider.notifier).save(next);
    await WindowsDesktopService.applySettings(next);
  }

  Future<void> _syncWithSystem() async {
    if (Platform.isLinux) {
      final enabled = LinuxAutostart.isEnabled();
      final settings = ref.read(settingsNotifierProvider).value;
      if (!mounted || settings == null) return;
      if (settings.launchAtStartup == enabled) return;
      await ref
          .read(settingsNotifierProvider.notifier)
          .save(settings.copyWith(launchAtStartup: enabled));
      return;
    }
    if (!Platform.isWindows) return;
    final elevated = await WindowsDesktopService.isLaunchAtStartupElevated();
    final run = await WindowsDesktopService.isLaunchAtStartupEnabled();
    if (!mounted) return;
    final settings = ref.read(settingsNotifierProvider).value;
    if (settings == null) return;
    final actual = settings.copyWith(
      launchAtStartup: elevated || run,
      launchAtStartupElevated: elevated,
    );
    if (actual == settings) return;
    await ref.read(settingsNotifierProvider.notifier).save(actual);
  }

  Future<void> _applyAutostart(AppSettings next) async {
    if (Platform.isLinux) {
      await LinuxAutostart.setEnabled(next.launchAtStartup);
      if (!mounted) return;
      await ref.read(settingsNotifierProvider.notifier).save(
            next.copyWith(launchAtStartup: LinuxAutostart.isEnabled()),
          );
      return;
    }
    final ok = await WindowsDesktopService.applyLaunchAtStartup(
      enabled: next.launchAtStartup,
      elevated: next.launchAtStartupElevated,
      allowElevation: true,
    );
    final elevated = await WindowsDesktopService.isLaunchAtStartupElevated();
    final run = await WindowsDesktopService.isLaunchAtStartupEnabled();
    if (!mounted) return;
    await ref.read(settingsNotifierProvider.notifier).save(
          next.copyWith(
            launchAtStartup: elevated || run,
            launchAtStartupElevated: elevated,
          ),
        );
    if (ok || !mounted) return;
    AppSnack.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.settingsAutostartAdminFailed),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();

    Widget note(String text) => Padding(
          padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
          child: Text(
            text,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppTheme.textLight(context)),
          ),
        );

    final linux = Platform.isLinux;
    return ExpressivePage(
      title: linux ? l10n.settingsDesktopTitleLinux : l10n.settingsDesktopTitle,
      physics: const ClampingScrollPhysics(),
      children: [
        ExpressiveGroup(
          children: [
            _AppearanceSwitchTile(
              icon: Icons.close_fullscreen_rounded,
              title: l10n.settingsMinimizeToTray,
              value: settings.minimizeToTray,
              onChanged: (v) => _save(settings.copyWith(minimizeToTray: v)),
            ),
            _AppearanceSwitchTile(
              icon: Icons.power_settings_new_rounded,
              title: linux
                  ? l10n.settingsLaunchAtLogin
                  : l10n.settingsLaunchAtStartup,
              value: settings.launchAtStartup,
              onChanged: (v) => unawaited(
                _applyAutostart(settings.copyWith(launchAtStartup: v)),
              ),
            ),
            if (!linux)
              _AppearanceSwitchTile(
                icon: Icons.admin_panel_settings_rounded,
                title: l10n.settingsLaunchAtStartupAdmin,
                value: settings.launchAtStartupElevated,
                onChanged: settings.launchAtStartup
                    ? (v) => unawaited(
                          _applyAutostart(
                            settings.copyWith(launchAtStartupElevated: v),
                          ),
                        )
                    : null,
              ),
            if (!linux)
              _AppearanceSwitchTile(
                icon: Icons.web_asset_off_rounded,
                title: l10n.settingsAutostartInTray,
                value: settings.autostartInTray,
                onChanged: settings.launchAtStartup
                    ? (v) => _save(settings.copyWith(autostartInTray: v))
                    : null,
              ),
            _AppearanceSwitchTile(
              icon: Icons.vpn_lock_rounded,
              title: l10n.settingsAutoConnectOnAutostart,
              value: settings.autoConnectLastServer,
              onChanged: settings.launchAtStartup
                  ? (v) => _save(settings.copyWith(autoConnectLastServer: v))
                  : null,
            ),
          ],
        ),
        if (!settings.launchAtStartup)
          note(linux
              ? l10n.settingsAutoConnectRequiresLogin
              : l10n.settingsAutoConnectRequiresAutostart),
      ],
    );
  }
}
