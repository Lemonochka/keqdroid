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

  /// Сохраняет финальное действие вместе с текущим текстом полей (сбрасывая
  /// debounce), чтобы незакоммиченные правки списков не потерялись.
  Future<void> _saveFinalOutbound(String value) async {
    _debounce?.cancel();
    final current = ref.read(settingsNotifierProvider).value;
    if (current == null) return;
    await ref.read(settingsNotifierProvider.notifier).save(
          current.copyWith(
            directRules: _directRules.text,
            proxyRules: _proxyRules.text,
            blockedRules: _blockedRules.text,
            finalOutbound: value,
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
    // Единственная кнопка сброса правил (из «Дополнительно» карточка убрана),
    // и она стирает все три списка — спрашиваем подтверждение.
    if (!await _confirmReset(
      context,
      message: AppLocalizations.of(context)!.settingsResetRoutingConfirm,
    )) {
      return;
    }
    if (!mounted) return;
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
        'telegram_geo' => l10n.settingsRoutingPresetTelegramGeoTitle,
        'refilter' => l10n.settingsRoutingPresetRefilterTitle,
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
        'telegram_geo' => l10n.settingsRoutingPresetTelegramGeoDesc,
        'refilter' => l10n.settingsRoutingPresetRefilterDesc,
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
        'telegram_geo' => Icons.send_outlined,
        'refilter' => Icons.shield_outlined,
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
    // Правила читаются только в момент connect() — при активном туннеле
    // изменения вступят в силу после переподключения.
    final vpnStatus = ref.watch(
      vpnStateProvider.select((a) => a.value?.status),
    );
    final tunnelActive = vpnStatus == VpnStatus.connected ||
        vpnStatus == VpnStatus.connecting;
    final finalOutbound = ref.watch(
      settingsNotifierProvider.select(
        (a) => a.value?.finalOutbound ?? AppSettings.finalOutboundProxy,
      ),
    );
    // Коды из поставляемых geo-баз: по ним подсвечиваем несуществующие токены
    // (ядро на таком коде роняет весь конфиг, поэтому они выкидываются перед
    // подключением) и наполняем пикер кодов.
    final geoIndex =
        ref.watch(geoAssetIndexProvider).value ?? GeoAssetIndex.empty;
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
            tooltip: l10n.routingCheatSheetTitle,
            icon: Icon(Icons.help_outline, color: AppTheme.text(context)),
            onPressed: () => _showCheatSheet(context, l10n),
          ),
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
          if (tunnelActive) ...[
            _reconnectHintBanner(context, l10n),
            const SizedBox(height: 12),
          ],
          _intro(context, l10n),
          const SizedBox(height: 16),
          _finalOutboundCard(context, l10n, finalOutbound),
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
            field: RoutingField.direct,
            geoIndex: geoIndex,
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
            field: RoutingField.proxy,
            geoIndex: geoIndex,
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
            field: RoutingField.blocked,
            geoIndex: geoIndex,
          ),
          const SizedBox(height: 16),
          _advancedRulesCard(context, l10n),
          const SizedBox(height: 16),
          _syntaxLegend(context, l10n),
        ],
      ),
      ),
    );
  }

  Widget _reconnectHintBanner(BuildContext context, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.orange(context).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: AppTheme.orange(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.splitTunnelingReconnectHint,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: AppTheme.text(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Финальное действие (глобал-прокси / обход / блок) ──────────────────────

  String _finalLabel(AppLocalizations l10n, String value) => switch (value) {
        AppSettings.finalOutboundDirect => l10n.settingsRoutingFinalDirect,
        AppSettings.finalOutboundBlock => l10n.settingsRoutingFinalBlock,
        _ => l10n.settingsRoutingFinalProxy,
      };

  IconData _finalIcon(String value) => switch (value) {
        AppSettings.finalOutboundDirect => Icons.call_made,
        AppSettings.finalOutboundBlock => Icons.block,
        _ => Icons.vpn_lock,
      };

  Color _finalColor(BuildContext context, String value) => switch (value) {
        AppSettings.finalOutboundDirect => AppTheme.green(context),
        AppSettings.finalOutboundBlock => AppTheme.red(context),
        _ => AppTheme.accent(context),
      };

  Widget _finalOutboundCard(
      BuildContext context, AppLocalizations l10n, String current) {
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
              Icon(Icons.alt_route, size: 18, color: AppTheme.accent(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.settingsRoutingFinalTitle,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.text(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            l10n.settingsRoutingFinalDesc,
            style: TextStyle(fontSize: 11.5, color: AppTheme.textLight(context)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final value in AppSettings.finalOutbounds) ...[
                Expanded(
                  child: _finalSegment(
                    context: context,
                    label: _finalLabel(l10n, value),
                    icon: _finalIcon(value),
                    color: _finalColor(context, value),
                    selected: current == value,
                    onTap: () => _saveFinalOutbound(value),
                  ),
                ),
                if (value != AppSettings.finalOutbounds.last)
                  const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _finalSegment({
    required BuildContext context,
    required String label,
    required IconData icon,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : AppTheme.bg(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : AppTheme.divider(context),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 20,
                color: selected ? color : AppTheme.textLight(context)),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? color : AppTheme.text(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Структурированные правила (RoutingRule) ────────────────────────────────

  String _actionLabel(AppLocalizations l10n, RuleAction a) => switch (a) {
        RuleAction.direct => l10n.settingsRoutingFinalDirect,
        RuleAction.proxy => l10n.settingsRoutingFinalProxy,
        RuleAction.block => l10n.settingsRoutingFinalBlock,
      };

  Color _actionColor(BuildContext context, RuleAction a) => switch (a) {
        RuleAction.direct => AppTheme.green(context),
        RuleAction.proxy => AppTheme.accent(context),
        RuleAction.block => AppTheme.red(context),
      };

  String _typeLabel(AppLocalizations l10n, RuleType t) => switch (t) {
        RuleType.domain => l10n.settingsRoutingRuleTypeDomain,
        RuleType.ipCidr => l10n.settingsRoutingRuleTypeIp,
        RuleType.geoip => l10n.settingsRoutingRuleTypeGeoip,
        RuleType.geosite => l10n.settingsRoutingRuleTypeGeosite,
        RuleType.processName => l10n.settingsRoutingRuleTypeDomain,
      };

  Widget _advancedRulesCard(BuildContext context, AppLocalizations l10n) {
    final rulesAsync = ref.watch(routingRulesProvider);
    // processName-правила не поддержаны в этом редакторе (пер-аппный роутинг —
    // отдельный экран split tunneling); прячем их, чтобы не путать.
    final rules = (rulesAsync.value ?? const <RoutingRule>[])
        .where((r) => r.type != RuleType.processName)
        .toList();
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
              Icon(Icons.tune, size: 18, color: AppTheme.accent(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.settingsRoutingAdvancedTitle,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.text(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            l10n.settingsRoutingAdvancedHint,
            style: TextStyle(fontSize: 11.5, color: AppTheme.textLight(context)),
          ),
          const SizedBox(height: 12),
          if (rules.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: Text(
                  l10n.settingsRoutingAdvancedEmpty,
                  style: TextStyle(
                      fontSize: 12.5, color: AppTheme.textLight(context)),
                ),
              ),
            )
          else
            for (final rule in rules) _ruleTile(context, l10n, rule),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: () => _openRuleEditor(l10n, null),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.settingsRoutingAdvancedAdd),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ruleTile(
      BuildContext context, AppLocalizations l10n, RoutingRule rule) {
    final color = _actionColor(context, rule.action);
    final valuesPreview = rule.values.join(', ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppTheme.bg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        rule.name.trim().isEmpty
                            ? valuesPreview
                            : rule.name.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: rule.enabled
                              ? AppTheme.text(context)
                              : AppTheme.textLight(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _pill(_typeLabel(l10n, rule.type),
                        AppTheme.textLight(context)),
                    const SizedBox(width: 4),
                    _pill(_actionLabel(l10n, rule.action), color),
                  ],
                ),
                if (rule.name.trim().isNotEmpty && valuesPreview.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    valuesPreview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textLight(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: l10n.settingsRoutingRuleEditTitle,
            icon: Icon(Icons.edit_outlined,
                size: 18, color: AppTheme.textLight(context)),
            onPressed: () => _openRuleEditor(l10n, rule),
          ),
          Switch(
            value: rule.enabled,
            activeThumbColor: color,
            activeTrackColor: color.withValues(alpha: 0.32),
            onChanged: (_) =>
                ref.read(routingRulesProvider.notifier).toggle(rule.id),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: color),
        ),
      );

  // Использует context/mounted самого State (не переданный параметр), чтобы
  // проверки mounted были «связаны» с BuildContext после await (линтер).
  Future<void> _openRuleEditor(
      AppLocalizations l10n, RoutingRule? existing) async {
    final result = await showDialog<_RuleEditorResult>(
      context: context,
      builder: (_) => _RuleEditorDialog(existing: existing),
    );
    if (result == null || !mounted) return;
    final notifier = ref.read(routingRulesProvider.notifier);
    switch (result) {
      case _RuleSave(:final rule):
        if (existing == null) {
          await notifier.add(rule);
        } else {
          await notifier.updateRule(rule);
        }
      case _RuleDelete():
        if (existing == null) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            content: Text(l10n.settingsRoutingRuleDeleteConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.subscriptionsCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.subscriptionsDelete),
              ),
            ],
          ),
        );
        if (ok == true) await notifier.remove(existing.id);
    }
  }

  // ── Шпаргалка «как писать правила» ─────────────────────────────────────────

  void _showCheatSheet(BuildContext context, AppLocalizations l10n) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.card(context),
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.routingCheatSheetTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.text(context),
                ),
              ),
              const SizedBox(height: 10),
              ..._cheatLines(context, l10n.routingCheatSheetBody),
            ],
          ),
        ),
      ),
    );
  }

  /// Разбивает текст шпаргалки на строки; строки с префиксом `## ` рисуются как
  /// заголовки секций (акцентом), остальные — обычным текстом. Так один
  /// локализованный текст остаётся живой заметкой, а не стеной.
  List<Widget> _cheatLines(BuildContext context, String body) {
    final out = <Widget>[];
    for (final raw in body.split('\n')) {
      final isHeader = raw.startsWith('## ');
      if (raw.trim().isEmpty) {
        out.add(const SizedBox(height: 10));
        continue;
      }
      out.add(Padding(
        padding: EdgeInsets.only(top: isHeader ? 8 : 1, bottom: isHeader ? 4 : 1),
        child: Text(
          isHeader ? raw.substring(3) : raw,
          style: isHeader
              ? TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  color: AppTheme.accent(context),
                )
              : TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: AppTheme.text(context),
                ),
        ),
      ));
    }
    return out;
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
    required RoutingField field,
    required GeoAssetIndex geoIndex,
  }) {
    final count = _countEntries(controller.text);
    final unknown = unknownGeoTokens(controller.text, geoIndex);
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
              if (!geoIndex.isEmpty)
                IconButton(
                  tooltip: l10n.settingsRoutingGeoPickerTooltip,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(Icons.travel_explore, size: 18, color: color),
                  onPressed: () => _showGeoCodePicker(field, geoIndex),
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
              // inset (surfaceContainerLowest) заметно контрастнее карточки, чем
              // bg/surface — на дынамик-тёмных темах, где surface ≈
              // surfaceContainerHigh, поле иначе сливалось с карточкой.
              fillColor: AppTheme.inset(context),
              // Явная граница: заливки мало, когда тона поверхностей близки —
              // тогда поле выглядело как текст без рамки (видно было только на ПК).
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.divider(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.divider(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.accent(context), width: 1.5),
              ),
            ),
            onChanged: (_) => _scheduleSave(),
          ),
          if (unknown.isNotEmpty) ...[
            const SizedBox(height: 8),
            _unknownGeoWarning(context, l10n, unknown),
          ],
        ],
      ),
    );
  }

  /// Токены, которых нет в поставляемых базах. Ядро на неизвестном geo-коде не
  /// игнорирует правило, а падает на разборе всего конфига, поэтому такие записи
  /// выкидываются перед подключением — раньше молча, из-за чего «geoip:telegram»
  /// выглядел рабочим и вопрос «почему ТГ не учитывается» был без ответа.
  Widget _unknownGeoWarning(
    BuildContext context,
    AppLocalizations l10n,
    List<String> tokens,
  ) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.orange(context).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppTheme.orange(context).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 16, color: AppTheme.orange(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.settingsRoutingGeoUnknownTitle,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.orange(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tokens.join(', '),
            style: TextStyle(
              fontSize: 11.5,
              fontFamily: 'monospace',
              color: AppTheme.text(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.settingsRoutingGeoUnknownHint,
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: AppTheme.textLight(context),
            ),
          ),
        ],
      ),
    );
  }

  /// Пикер кодов из реальных баз: 1500+ geosite и 260+ geoip кодов руками не
  /// вспомнишь, а опечатка молча ломает правило.
  Future<void> _showGeoCodePicker(
    RoutingField field,
    GeoAssetIndex index,
  ) async {
    final token = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card(context),
      showDragHandle: true,
      builder: (_) => _GeoCodePickerSheet(index: index),
    );
    if (token == null || token.isEmpty) return;
    final ctrl = _controllerFor(field);
    ctrl.text = RoutingPresets.mergeValues(ctrl.text, [token]);
    await _persist();
    if (!mounted) return;
    setState(() {});
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.settingsRoutingPresetApplied(token))),
    );
  }
}

/// Список доступных geo-кодов с поиском. Возвращает через `Navigator.pop`
/// готовый токен (`geosite:telegram` / `geoip:ru`).
class _GeoCodePickerSheet extends StatefulWidget {
  const _GeoCodePickerSheet({required this.index});

  final GeoAssetIndex index;

  @override
  State<_GeoCodePickerSheet> createState() => _GeoCodePickerSheetState();
}

class _GeoCodePickerSheetState extends State<_GeoCodePickerSheet> {
  final _search = TextEditingController();
  String _query = '';
  bool _geosite = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<String> get _codes {
    final source =
        _geosite ? widget.index.geositeCodes : widget.index.geoipCodes;
    final needle = _query.trim().toLowerCase();
    final list = source
        .where((c) => needle.isEmpty || c.contains(needle))
        .toList()
      ..sort();
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final codes = _codes;
    final prefix = _geosite ? 'geosite:' : 'geoip:';

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.travel_explore,
                      size: 18, color: AppTheme.accent(context)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.settingsRoutingGeoPickerTitle,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.text(context),
                      ),
                    ),
                  ),
                  Text(
                    l10n.settingsRoutingItemCount(codes.length),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textLight(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _typeTab(
                      context,
                      label: l10n.settingsRoutingGeoPickerGeosite,
                      selected: _geosite,
                      onTap: () => setState(() => _geosite = true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _typeTab(
                      context,
                      label: l10n.settingsRoutingGeoPickerGeoip,
                      selected: !_geosite,
                      onTap: () => setState(() => _geosite = false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _search,
                autofocus: true,
                style: TextStyle(fontSize: 13, color: AppTheme.text(context)),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: l10n.settingsRoutingGeoPickerSearchHint,
                  hintStyle: TextStyle(color: AppTheme.textLight(context)),
                  filled: true,
                  fillColor: AppTheme.inset(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.divider(context)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.divider(context)),
                  ),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: codes.isEmpty
                    ? Center(
                        child: Text(
                          l10n.settingsRoutingGeoPickerEmpty,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.textLight(context),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: codes.length,
                        itemBuilder: (_, i) {
                          final code = codes[i];
                          return ListTile(
                            dense: true,
                            title: Text(
                              '$prefix$code',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontFamily: 'monospace',
                                color: AppTheme.text(context),
                              ),
                            ),
                            trailing: Icon(Icons.add,
                                size: 16, color: AppTheme.accent(context)),
                            onTap: () =>
                                Navigator.of(context).pop('$prefix$code'),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeTab(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final color = AppTheme.accent(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : AppTheme.bg(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : AppTheme.divider(context),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? color : AppTheme.text(context),
          ),
        ),
      ),
    );
  }
}

/// Результат редактора правила: сохранить или удалить (null — отмена, из pop).
sealed class _RuleEditorResult {
  const _RuleEditorResult();
}

class _RuleSave extends _RuleEditorResult {
  final RoutingRule rule;
  const _RuleSave(this.rule);
}

class _RuleDelete extends _RuleEditorResult {
  const _RuleDelete();
}

/// Диалог создания/редактирования одного [RoutingRule]: имя, значения, тип
/// сопоставления и действие. Возвращает [_RuleEditorResult] через Navigator.pop.
class _RuleEditorDialog extends StatefulWidget {
  final RoutingRule? existing;
  const _RuleEditorDialog({this.existing});

  @override
  State<_RuleEditorDialog> createState() => _RuleEditorDialogState();
}

class _RuleEditorDialogState extends State<_RuleEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _values;
  late RuleType _type;
  late RuleAction _action;

  static const _types = [
    RuleType.domain,
    RuleType.ipCidr,
    RuleType.geoip,
    RuleType.geosite,
  ];
  static const _actions = [
    RuleAction.proxy,
    RuleAction.direct,
    RuleAction.block,
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _values = TextEditingController(text: e?.values.join('\n') ?? '');
    // processName в этом редакторе не предлагается — на всякий случай схлопываем
    // на domain, чтобы сегмент типа гарантированно имел выбранное значение.
    _type = (e != null && _types.contains(e.type)) ? e.type : RuleType.domain;
    _action = e?.action ?? RuleAction.proxy;
  }

  @override
  void dispose() {
    _name.dispose();
    _values.dispose();
    super.dispose();
  }

  List<String> _parseValues() => _values.text
      .split(RegExp(r'[\r\n,]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  String _typeLabel(AppLocalizations l10n, RuleType t) => switch (t) {
        RuleType.domain => l10n.settingsRoutingRuleTypeDomain,
        RuleType.ipCidr => l10n.settingsRoutingRuleTypeIp,
        RuleType.geoip => l10n.settingsRoutingRuleTypeGeoip,
        RuleType.geosite => l10n.settingsRoutingRuleTypeGeosite,
        RuleType.processName => l10n.settingsRoutingRuleTypeDomain,
      };

  String _actionLabel(AppLocalizations l10n, RuleAction a) => switch (a) {
        RuleAction.direct => l10n.settingsRoutingFinalDirect,
        RuleAction.proxy => l10n.settingsRoutingFinalProxy,
        RuleAction.block => l10n.settingsRoutingFinalBlock,
      };

  Color _actionColor(BuildContext context, RuleAction a) => switch (a) {
        RuleAction.direct => AppTheme.green(context),
        RuleAction.proxy => AppTheme.accent(context),
        RuleAction.block => AppTheme.red(context),
      };

  void _save() {
    final values = _parseValues();
    if (values.isEmpty) return;
    final e = widget.existing;
    final rule = e == null
        ? RoutingRule.create(
            name: _name.text.trim(),
            type: _type,
            values: values,
            action: _action,
          )
        : e.copyWith(
            name: _name.text.trim(),
            type: _type,
            values: values,
            action: _action,
          );
    Navigator.pop<_RuleEditorResult>(context, _RuleSave(rule));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final accent = AppTheme.accent(context);
    final isEdit = widget.existing != null;
    return AlertDialog(
      backgroundColor: AppTheme.card(context),
      title: Text(
        isEdit
            ? l10n.settingsRoutingRuleEditTitle
            : l10n.settingsRoutingRuleNewTitle,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              style: TextStyle(color: AppTheme.text(context)),
              decoration: InputDecoration(
                isDense: true,
                labelText: l10n.settingsRoutingRuleName,
                hintText: l10n.settingsRoutingRuleNameHint,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _values,
              minLines: 2,
              maxLines: 5,
              style: TextStyle(color: AppTheme.text(context), fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                labelText: l10n.settingsRoutingRuleValues,
                hintText: l10n.settingsRoutingRuleValuesHint,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.settingsRoutingRuleMatchBy,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textLight(context)),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _types)
                  ChoiceChip(
                    label: Text(_typeLabel(l10n, t)),
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                    selectedColor: accent.withValues(alpha: 0.18),
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      color: _type == t ? accent : AppTheme.text(context),
                      fontWeight:
                          _type == t ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              l10n.settingsRoutingRuleAction,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textLight(context)),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in _actions)
                  ChoiceChip(
                    label: Text(_actionLabel(l10n, a)),
                    selected: _action == a,
                    onSelected: (_) => setState(() => _action = a),
                    selectedColor:
                        _actionColor(context, a).withValues(alpha: 0.18),
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      color: _action == a
                          ? _actionColor(context, a)
                          : AppTheme.text(context),
                      fontWeight:
                          _action == a ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (isEdit)
          TextButton(
            onPressed: () => Navigator.pop<_RuleEditorResult>(
                context, const _RuleDelete()),
            child: Text(
              l10n.subscriptionsDelete,
              style: TextStyle(color: AppTheme.red(context)),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.subscriptionsCancel),
        ),
        FilledButton(
          onPressed: _parseValues().isEmpty ? null : _save,
          child: Text(l10n.settingsRoutingRuleSave),
        ),
      ],
    );
  }
}
