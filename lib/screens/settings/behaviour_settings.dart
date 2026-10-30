part of '../settings_tab.dart';

Widget behaviourSettingsScreenForTest() => const _BehaviourSettingsScreen();

String _updatePromptLabel(AppLocalizations l10n, int days) => switch (days) {
      1 => l10n.behaviourEveryDay,
      7 => l10n.behaviourEveryWeek,
      _ => l10n.behaviourEvery3Days,
    };

// в подписи значение стоит посреди фразы: «Обновления: раз в 3 дня»
String _lowerFirst(String s) =>
    s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

class _BehaviourSettingsCard extends StatelessWidget {
  final AsyncValue<AppSettings> settingsAsync;
  const _BehaviourSettingsCard({required this.settingsAsync});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = settingsAsync.value ?? const AppSettings();
    return _SettingsCard(
      title: l10n.settingsBehaviourTitle,
      subtitle: l10n.settingsBehaviourSubtitle(
        _lowerFirst(_updatePromptLabel(l10n, settings.updatePromptDays)),
      ),
      icon: Icons.tune_rounded,
      accent: ExpressiveAccent.secondary,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const _BehaviourSettingsScreen()),
      ),
    );
  }
}

class _BehaviourSettingsScreen extends ConsumerWidget {
  const _BehaviourSettingsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final current =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();

    Future<void> save(AppSettings next) =>
        ref.read(settingsNotifierProvider.notifier).save(next);

    return ExpressivePage(
      title: l10n.settingsBehaviourTitle,
      physics: const ClampingScrollPhysics(),
      children: [
        ExpressiveSectionHeader(
          l10n.behaviourUpdatesSection,
          icon: Icons.system_update_rounded,
        ),
        ExpressiveGroup(
          children: [
            ExpressiveGroupTile(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.behaviourUpdatePrompt,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppTheme.text(context),
                        ),
                  ),
                  const SizedBox(height: 12),
                  ExpressiveConnectedButtons<int>(
                    segments: [
                      ExpressiveSegment(value: 1, label: l10n.behaviourEveryDay),
                      ExpressiveSegment(
                        value: 3,
                        label: l10n.behaviourEvery3Days,
                      ),
                      ExpressiveSegment(
                        value: 7,
                        label: l10n.behaviourEveryWeek,
                      ),
                    ],
                    selected: current.updatePromptDays,
                    onChanged: (v) =>
                        save(current.copyWith(updatePromptDays: v)),
                    height: 48,
                  ),
                ],
              ),
            ),
          ],
        ),
        ExpressiveSectionHeader(
          l10n.appearanceNotifSectionTitle,
          icon: Icons.notifications_rounded,
        ),
        ExpressiveGroup(
          children: [
            _AppearanceSwitchTile(
              icon: Icons.speed_rounded,
              title: l10n.appearanceNotifSpeedTitle,
              value: current.showSpeedInNotification,
              onChanged: (v) =>
                  save(current.copyWith(showSpeedInNotification: v)),
            ),
            _AppearanceSwitchTile(
              icon: Icons.timer_outlined,
              title: l10n.appearanceNotifUptimeTitle,
              value: current.showUptimeInNotification,
              onChanged: (v) =>
                  save(current.copyWith(showUptimeInNotification: v)),
            ),
            _AppearanceSwitchTile(
              icon: Icons.sync_rounded,
              title: l10n.appearanceNotifSubUpdatesTitle,
              value: current.notifySubscriptionUpdates,
              onChanged: (v) =>
                  save(current.copyWith(notifySubscriptionUpdates: v)),
            ),
          ],
        ),
      ],
    );
  }
}
