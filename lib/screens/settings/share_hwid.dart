part of '../settings_tab.dart';

class _ShareHwidCard extends ConsumerWidget {
  final AsyncValue<AppSettings> settingsAsync;
  const _ShareHwidCard({required this.settingsAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = settingsAsync.value ?? const AppSettings();
    final enabled = settings.shareDeviceHwid;

    Future<void> save(bool value) async {
      // SubscriptionService читает shareDeviceHwid из настроек на каждый
      // fetch — отдельно уведомлять его не нужно.
      await ref.read(settingsNotifierProvider.notifier).save(settings.copyWith(shareDeviceHwid: value));
    }

    final textTheme = Theme.of(context).textTheme;
    // Включённое состояние — цветом иконки, как у LAN-прокси: рамка вокруг
    // карточки внутри группы обрезалась бы её же формой.
    final iconAccent =
        enabled ? ExpressiveAccent.tertiary : ExpressiveAccent.secondary;

    return ExpressiveGroupTile(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                      'Share device HWID',
                      style: textTheme.titleMedium?.copyWith(
                        color: AppTheme.text(context),
                      ),
                    ),
                    Text(
                      enabled ? 'HWID will be sent with subscription requests' : 'HWID not shared',
                      style: textTheme.bodyMedium?.copyWith(color: enabled ? AppTheme.accent(context) : AppTheme.textLight(context)),
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
          const SizedBox(height: 10),
          Text(
            'When enabled, your device\'s unique ID (HWID) is sent to subscription servers. '
            'Required by some providers for HWID binding. Disable to increase privacy.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textLight(context), height: 1.35),
          ),
        ],
      ),
    );
  }
}

