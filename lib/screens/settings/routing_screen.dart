part of '../settings_tab.dart';

class _RoutingScreen extends ConsumerStatefulWidget {
  const _RoutingScreen();

  @override
  ConsumerState<_RoutingScreen> createState() => _RoutingScreenState();
}

class _RoutingScreenState extends ConsumerState<_RoutingScreen> {
  late final TextEditingController _directRules;
  late final TextEditingController _proxyRules;
  late final TextEditingController _blockedRules;
  Timer? _debounce;
  String? _selectedPresetId;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsNotifierProvider).value;
    _directRules = TextEditingController(
      text: s?.directRules ?? RoutingPresets.defaultDirectRules,
    );
    _proxyRules = TextEditingController(
      text: s?.proxyRules ?? RoutingPresets.defaultProxyRules,
    );
    _blockedRules = TextEditingController(
      text: s?.blockedRules ?? RoutingPresets.defaultBlockedRules,
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _directRules.dispose();
    _proxyRules.dispose();
    _blockedRules.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    setState(() {}); // keep entry counts in sync while typing
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _persist);
  }

  Future<void> _persist() async {
    final current = ref.read(settingsNotifierProvider).value;
    if (current == null) return;
    await ref.read(settingsNotifierProvider.notifier).save(
          current.copyWith(
            directRules: _directRules.text,
            proxyRules: _proxyRules.text,
            blockedRules: _blockedRules.text,
          ),
        );
  }

  TextEditingController _controllerFor(RoutingField f) => switch (f) {
        RoutingField.direct => _directRules,
        RoutingField.proxy => _proxyRules,
        RoutingField.blocked => _blockedRules,
      };

  Future<void> _applyPreset(RoutingPreset preset, String label) async {
    final ctrl = _controllerFor(preset.field);
    ctrl.text = RoutingPresets.mergeValues(ctrl.text, preset.values);
    await _persist();
    if (!mounted) return;
    setState(() {});
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.settingsRoutingPresetApplied(label))),
    );
  }

  Future<void> _resetToDefaults() async {
    _directRules.text = RoutingPresets.defaultDirectRules;
    _proxyRules.text = RoutingPresets.defaultProxyRules;
    _blockedRules.text = RoutingPresets.defaultBlockedRules;
    await _persist();
    if (!mounted) return;
    setState(() {});
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.settingsRoutingResetDone)),
    );
  }

  String _presetTitle(AppLocalizations l10n, String id) => switch (id) {
        'ru' => l10n.settingsRoutingPresetRuTitle,
        'ru_geoip' => l10n.settingsRoutingPresetRuGeoipTitle,
        'ru_geosite' => l10n.settingsRoutingPresetRuGeositeTitle,
        'banks' => l10n.settingsRoutingPresetBanksTitle,
        'lan_ips' => l10n.settingsRoutingPresetLanIpsTitle,
        'ads' => l10n.settingsRoutingPresetAdsTitle,
        'ads_geosite' => l10n.settingsRoutingPresetAdsGeositeTitle,
        'streaming' => l10n.settingsRoutingPresetStreamingTitle,
        'messengers' => l10n.settingsRoutingPresetMessengersTitle,
        _ => id,
      };

  String _presetDesc(AppLocalizations l10n, String id) => switch (id) {
        'ru' => l10n.settingsRoutingPresetRuDesc,
        'ru_geoip' => l10n.settingsRoutingPresetRuGeoipDesc,
        'ru_geosite' => l10n.settingsRoutingPresetRuGeositeDesc,
        'banks' => l10n.settingsRoutingPresetBanksDesc,
        'lan_ips' => l10n.settingsRoutingPresetLanIpsDesc,
        'ads' => l10n.settingsRoutingPresetAdsDesc,
        'ads_geosite' => l10n.settingsRoutingPresetAdsGeositeDesc,
        'streaming' => l10n.settingsRoutingPresetStreamingDesc,
        'messengers' => l10n.settingsRoutingPresetMessengersDesc,
        _ => '',
      };

  IconData _presetIcon(String id) => switch (id) {
        'ru' => Icons.flag_outlined,
        'ru_geoip' => Icons.public,
        'ru_geosite' => Icons.travel_explore,
        'banks' => Icons.account_balance_outlined,
        'lan_ips' => Icons.lan_outlined,
        'ads' => Icons.block,
        'ads_geosite' => Icons.block_flipped,
        'streaming' => Icons.play_circle_outline,
        'messengers' => Icons.chat_bubble_outline,
        _ => Icons.tune,
      };

  Color _presetColor(BuildContext context, RoutingField f) => switch (f) {
        RoutingField.direct => AppTheme.green(context),
        RoutingField.proxy => AppTheme.accent(context),
        RoutingField.blocked => AppTheme.red(context),
      };

  static int _countEntries(String raw) => raw
      .split(RegExp(r'[\n,]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .length;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.bg(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppTheme.text(context)),
        title: Text(
          l10n.settingsRoutingTitle,
          style: TextStyle(color: AppTheme.text(context)),
        ),
        actions: [
          IconButton(
            tooltip: l10n.settingsResetRoutingTitle,
            icon: Icon(Icons.restore, color: AppTheme.text(context)),
            onPressed: _resetToDefaults,
          ),
        ],
      ),
      body: SmoothScroll(
        builder: (context, controller) => ListView(
          controller: controller,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _intro(context, l10n),
          const SizedBox(height: 16),
          _presetsCard(context, l10n),
          const SizedBox(height: 16),
          _section(
            context: context,
            color: AppTheme.green(context),
            icon: Icons.call_made,
            title: l10n.settingsRoutingDirectTitle,
            desc: l10n.settingsRoutingDirectDesc,
            controller: _directRules,
            hint: 'ru, vk.com, .example.com, 10.0.0.0/8',
            l10n: l10n,
          ),
          const SizedBox(height: 12),
          _section(
            context: context,
            color: AppTheme.accent(context),
            icon: Icons.vpn_lock,
            title: l10n.settingsRoutingProxyTitle,
            desc: l10n.settingsRoutingProxyDesc,
            controller: _proxyRules,
            hint: 'youtube.com, discord.com, 1.1.1.1',
            l10n: l10n,
          ),
          const SizedBox(height: 12),
          _section(
            context: context,
            color: AppTheme.red(context),
            icon: Icons.block,
            title: l10n.settingsRoutingBlockTitle,
            desc: l10n.settingsRoutingBlockDesc,
            controller: _blockedRules,
            hint: 'doubleclick.net, 0.0.0.0/8',
            l10n: l10n,
          ),
          const SizedBox(height: 16),
          _syntaxLegend(context, l10n),
        ],
      ),
      ),
    );
  }

  Widget _syntaxLegend(BuildContext context, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.help_outline, size: 18, color: AppTheme.textLight(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.settingsRoutingSyntaxHint,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: AppTheme.textLight(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _intro(BuildContext context, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.accent(context).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.alt_route, size: 20, color: AppTheme.accent(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.settingsRoutingHeaderDesc,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: AppTheme.text(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _presetsCard(BuildContext context, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settingsRoutingPresetsTitle,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.text(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.settingsRoutingPresetsHint,
            style: TextStyle(fontSize: 11.5, color: AppTheme.textLight(context)),
          ),
          const SizedBox(height: 12),
          _presetDropdown(context, l10n),
        ],
      ),
    );
  }

  Widget _presetDropdown(BuildContext context, AppLocalizations l10n) {
    RoutingPreset? findSelected() {
      for (final p in RoutingPresets.all) {
        if (p.id == _selectedPresetId) return p;
      }
      return null;
    }

    final selected = findSelected();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppTheme.bg(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedPresetId,
                    borderRadius: BorderRadius.circular(14),
                    hint: Text(
                      l10n.settingsRoutingPresetChoose,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: AppTheme.textLight(context),
                      ),
                    ),
                    dropdownColor: AppTheme.card(context),
                    icon: Icon(
                      Icons.arrow_drop_down,
                      color: AppTheme.textLight(context),
                    ),
                    items: RoutingPresets.all.map((preset) {
                      final color = _presetColor(context, preset.field);
                      return DropdownMenuItem<String>(
                        value: preset.id,
                        child: Row(
                          children: [
                            Icon(_presetIcon(preset.id), size: 18, color: color),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _presetTitle(l10n, preset.id),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: AppTheme.text(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (id) => setState(() => _selectedPresetId = id),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: selected == null
                  ? null
                  : () => _applyPreset(
                        selected,
                        _presetTitle(l10n, selected.id),
                      ),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.settingsRoutingPresetAdd),
            ),
          ],
        ),
        if (selected != null) ...[
          const SizedBox(height: 8),
          Text(
            _presetDesc(l10n, selected.id),
            style: TextStyle(fontSize: 11.5, color: AppTheme.textLight(context)),
          ),
        ],
      ],
    );
  }

  Widget _section({
    required BuildContext context,
    required Color color,
    required IconData icon,
    required String title,
    required String desc,
    required TextEditingController controller,
    required String hint,
    required AppLocalizations l10n,
  }) {
    final count = _countEntries(controller.text);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.text(context),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  l10n.settingsRoutingItemCount(count),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            desc,
            style: TextStyle(fontSize: 11.5, color: AppTheme.textLight(context)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 8,
            style: TextStyle(fontSize: 13, color: AppTheme.text(context)),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: TextStyle(color: AppTheme.textLight(context)),
              helperText: l10n.settingsRoutingValuesHint,
              helperStyle: TextStyle(
                fontSize: 10.5,
                color: AppTheme.textLight(context),
              ),
              filled: true,
              fillColor: AppTheme.bg(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (_) => _scheduleSave(),
          ),
        ],
      ),
    );
  }
}
