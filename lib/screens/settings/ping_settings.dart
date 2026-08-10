part of '../settings_tab.dart';

String _pingSettingsSubtitle(AppLocalizations l10n, AppSettings? settings) {
  final s = settings ?? const AppSettings();
  final mode = switch (s.pingType) {
    'url' => l10n.settingsPingMethodUrl,
    'speed' => l10n.settingsPingMethodSpeed,
    'icmp' => l10n.settingsPingMethodIcmp,
    _ => l10n.settingsPingMethodTcp,
  };
  if (s.pingType != 'url') return mode;
  final target = _pingTargetLabel(l10n, s.pingTestTarget);
  return '$mode · $target';
}

String _pingTargetLabel(AppLocalizations l10n, String target) =>
    switch (PingTestConfig.normalizeTarget(target)) {
      PingTestConfig.targetGstatic => l10n.settingsPingTargetGstatic,
      PingTestConfig.targetCloudflare => l10n.settingsPingTargetCloudflare,
      PingTestConfig.targetMicrosoft => l10n.settingsPingTargetMicrosoft,
      PingTestConfig.targetCustom => l10n.settingsPingTargetCustom,
      _ => l10n.settingsPingTargetGstatic,
    };

class _PingSettingsScreen extends ConsumerStatefulWidget {
  const _PingSettingsScreen();

  @override
  ConsumerState<_PingSettingsScreen> createState() => _PingSettingsScreenState();
}

class _PingSettingsScreenState extends ConsumerState<_PingSettingsScreen> {
  final _customUrlCtrl = TextEditingController();

  @override
  void dispose() {
    _customUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(AppSettings settings) async {
    await ref.read(settingsNotifierProvider.notifier).save(settings);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();
    final accent = AppTheme.accent(context);
    final isUrl = settings.pingType == 'url';
    final isCustom = settings.pingTestTarget == PingTestConfig.targetCustom;

    if (_customUrlCtrl.text.isEmpty && settings.pingTestUrlCustom.isNotEmpty) {
      _customUrlCtrl.text = settings.pingTestUrlCustom;
    }

    // Заголовок секции и карточка — общие на все подэкраны настроек
    // (`ExpressiveSectionHeader` / `ExpressiveCard`), локальных вариантов
    // больше нет: раньше каждый экран объявлял свои и они разъезжались.
    Widget card({required List<Widget> children}) => ExpressiveCard(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(children: children),
        );

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.bg(context),
        elevation: 0,
        title: Text(l10n.settingsPingTitle),
      ),
      body: SmoothScroll(
        builder: (context, controller) => ListView(
          controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          ExpressiveSectionHeader(l10n.settingsPingMethodTitle),
          card(
            children: [
              RadioGroup<String>(
                groupValue: settings.pingType,
                onChanged: (v) {
                  if (v != null) _save(settings.copyWith(pingType: v));
                },
                child: Column(
                  children: [
                    RadioListTile<String>(
                      value: 'tcp',
                      activeColor: accent,
                      title: Text(l10n.settingsPingMethodTcp),
                      subtitle: Text(l10n.settingsPingMethodTcpHint),
                    ),
                    RadioListTile<String>(
                      value: 'icmp',
                      activeColor: accent,
                      title: Text(l10n.settingsPingMethodIcmp),
                      subtitle: Text(l10n.settingsPingMethodIcmpHint),
                    ),
                    RadioListTile<String>(
                      value: 'url',
                      activeColor: accent,
                      title: Text(l10n.settingsPingMethodUrl),
                      subtitle: Text(l10n.settingsPingMethodUrlHint),
                    ),
                    RadioListTile<String>(
                      value: 'speed',
                      activeColor: accent,
                      title: Text(l10n.settingsPingMethodSpeed),
                      subtitle: Text(l10n.settingsPingMethodSpeedHint),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isUrl) ...[
            ExpressiveSectionHeader(l10n.settingsPingTargetTitle),
            card(
              children: [
                RadioGroup<String>(
                  groupValue: settings.pingTestTarget,
                  onChanged: (v) {
                    if (v != null) {
                      _save(settings.copyWith(pingTestTarget: v));
                    }
                  },
                  child: Column(
                    children: [
                      for (final target in PingTestConfig.targets)
                        if (target != PingTestConfig.targetCustom)
                          RadioListTile<String>(
                            value: target,
                            activeColor: accent,
                            title: Text(_pingTargetLabel(l10n, target)),
                            subtitle: Text(
                              PingTestConfig.presetUrls[target] ?? '',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textLight(context)),
                            ),
                          ),
                      RadioListTile<String>(
                        value: PingTestConfig.targetCustom,
                        activeColor: accent,
                        title: Text(l10n.settingsPingTargetCustom),
                        subtitle: Text(l10n.settingsPingCustomUrlHint),
                      ),
                    ],
                  ),
                ),
                if (isCustom)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: TextField(
                      controller: _customUrlCtrl,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.text(context)),
                      decoration: InputDecoration(
                        labelText: l10n.settingsPingCustomUrl,
                        hintText: 'https://example.com/generate_204',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(ExpressiveShape.medium),
                        ),
                      ),
                      onSubmitted: (v) {
                        final err = PingTestConfig.validateCustomUrl(v);
                        if (err != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.settingsPingCustomUrlInvalid)),
                          );
                          return;
                        }
                        _save(settings.copyWith(pingTestUrlCustom: v.trim()));
                      },
                      onEditingComplete: () {
                        final v = _customUrlCtrl.text;
                        final err = PingTestConfig.validateCustomUrl(v);
                        if (err != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.settingsPingCustomUrlInvalid)),
                          );
                          return;
                        }
                        _save(settings.copyWith(pingTestUrlCustom: v.trim()));
                      },
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
      ),
    );
  }
}
