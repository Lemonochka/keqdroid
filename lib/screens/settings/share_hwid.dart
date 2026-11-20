part of '../settings_tab.dart';

class _ShareHwidCard extends ConsumerWidget {
  final AsyncValue<AppSettings> settingsAsync;
  const _ShareHwidCard({required this.settingsAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = settingsAsync.value ?? const AppSettings();
    final enabled = settings.shareDeviceHwid;

    Future<void> save(bool value) async {
      await ref
          .read(settingsNotifierProvider.notifier)
          .save(settings.copyWith(shareDeviceHwid: value));
    }

    final textTheme = Theme.of(context).textTheme;
    final iconAccent = enabled
        ? ExpressiveAccent.tertiary
        : ExpressiveAccent.secondary;

    return ExpressiveGroupTile(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          ExpressiveIconBadge(
            icon: Icons.fingerprint_rounded,
            accent: iconAccent,
          ),
          const SizedBox(width: ExpressiveSpacing.large),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsShareHwidTitle,
                  style: textTheme.titleMedium?.copyWith(
                    color: AppTheme.text(context),
                  ),
                ),
                Text(
                  enabled
                      ? l10n.settingsShareHwidOn
                      : l10n.settingsShareHwidOff,
                  style: textTheme.bodyMedium?.copyWith(
                    color: enabled
                        ? AppTheme.accent(context)
                        : AppTheme.textLight(context),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            activeThumbColor: AppTheme.accent(context),
            onChanged: save,
          ),
        ],
      ),
    );
  }
}
