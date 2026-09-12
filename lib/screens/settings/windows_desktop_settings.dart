part of '../settings_tab.dart';

/// Настройки Windows: трей и автозапуск.
///
/// Экран с состоянием, потому что автозапуск живёт не только в наших
/// настройках: обычный — в ключе реестра Run, повышенный — задачей
/// планировщика. И то и другое можно снести мимо приложения, поэтому при
/// открытии экрана переключатели сверяются с системой.
class _WindowsDesktopSettingsScreen extends ConsumerStatefulWidget {
  const _WindowsDesktopSettingsScreen();

  @override
  ConsumerState<_WindowsDesktopSettingsScreen> createState() =>
      _WindowsDesktopSettingsScreenState();
}

class _WindowsDesktopSettingsScreenState
    extends ConsumerState<_WindowsDesktopSettingsScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_syncWithSystem());
  }

  Future<void> _save(AppSettings next) async {
    await ref.read(settingsNotifierProvider.notifier).save(next);
    await WindowsDesktopService.applySettings(next);
  }

  /// Приводит настройки к тому, что на самом деле сделано в системе.
  ///
  /// Без спроса UAC: экран всего лишь открыли. Если задачу планировщика удалили
  /// руками или папку с приложением перенесли (задача осталась на старом пути),
  /// переключатель честно гаснет, и включить его можно заново.
  Future<void> _syncWithSystem() async {
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

  /// Меняет автозапуск и сохраняет то, что из этого вышло.
  ///
  /// Задачу планировщика заводит и сносит только администратор, поэтому здесь
  /// может всплыть UAC — один раз, в момент переключения. Отказались — сохраним
  /// не намерение, а факт: оба переключателя обязаны показывать то, что система
  /// действительно делает на входе в систему.
  Future<void> _applyAutostart(AppSettings next) async {
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
    ScaffoldMessenger.of(context).showSnackBar(
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

    // Подписи под названиями здесь были пересказом самих названий, поэтому их
    // нет вовсе. Остались только пояснения под недоступными строками — они
    // отвечают на вопрос «почему серое», из названия этого не узнать.
    Widget toggleRow({
      required String title,
      required bool value,
      required ValueChanged<bool>? onChanged,
    }) {
      return ExpressiveCard(
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.text(context),
                ),
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

    return ExpressivePage(
      title: l10n.settingsDesktopTitle,
      physics: const ClampingScrollPhysics(),
      children: [
        toggleRow(
          title: l10n.settingsMinimizeToTray,
          value: settings.minimizeToTray,
          onChanged: (v) => _save(settings.copyWith(minimizeToTray: v)),
        ),
        const SizedBox(height: 12),
        toggleRow(
          title: l10n.settingsLaunchAtStartup,
          value: settings.launchAtStartup,
          onChanged: (v) => unawaited(
            _applyAutostart(settings.copyWith(launchAtStartup: v)),
          ),
        ),
        const SizedBox(height: 12),
        toggleRow(
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
        const SizedBox(height: 12),
        toggleRow(
          title: l10n.settingsAutoConnectOnAutostart,
          value: settings.autoConnectLastServer,
          onChanged: settings.launchAtStartup
              ? (v) => _save(settings.copyWith(autoConnectLastServer: v))
              : null,
        ),
        if (!settings.launchAtStartup)
          note(l10n.settingsAutoConnectRequiresAutostart),
      ],
    );
  }
}
