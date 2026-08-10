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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(18),
        border: enabled
            ? Border.all(color: AppTheme.accent(context).withValues(alpha: 0.5), width: 1.5)
            : Border.all(color: AppTheme.divider(context), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.accent(context).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.fingerprint,
                  size: 20,
                  color: enabled ? AppTheme.accent(context) : AppTheme.text(context),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Share device HWID',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.text(context),
                      ),
                    ),
                    Text(
                      enabled ? 'HWID will be sent with subscription requests' : 'HWID not shared',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: enabled ? AppTheme.accent(context) : AppTheme.textLight(context)),
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

