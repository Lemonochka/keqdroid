part of '../settings_tab.dart';

// Подписи и цвета структурированных правил нужны и списку на экране, и диалогу
// редактирования. Держим их здесь, а не в каждом State по копии.

String _ruleTypeLabel(AppLocalizations l10n, RuleType t) => switch (t) {
      RuleType.domain => l10n.settingsRoutingRuleTypeDomain,
      RuleType.ipCidr => l10n.settingsRoutingRuleTypeIp,
      RuleType.geoip => l10n.settingsRoutingRuleTypeGeoip,
      RuleType.geosite => l10n.settingsRoutingRuleTypeGeosite,
      RuleType.processName => l10n.settingsRoutingRuleTypeDomain,
    };

String _ruleActionLabel(AppLocalizations l10n, RuleAction a) => switch (a) {
      RuleAction.direct => l10n.settingsRoutingFinalDirect,
      RuleAction.proxy => l10n.settingsRoutingFinalProxy,
      RuleAction.block => l10n.settingsRoutingFinalBlock,
    };

Color _ruleActionColor(BuildContext context, RuleAction a) => switch (a) {
      RuleAction.direct => AppTheme.green(context),
      RuleAction.proxy => AppTheme.accent(context),
      RuleAction.block => AppTheme.red(context),
    };

IconData _ruleActionIcon(RuleAction a) => switch (a) {
      RuleAction.direct => Icons.call_made_rounded,
      RuleAction.proxy => Icons.public_rounded,
      RuleAction.block => Icons.block_rounded,
    };

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
        'ru' => Icons.flag_rounded,
        'ru_geoip' => Icons.public_rounded,
        'ru_geosite' => Icons.travel_explore_rounded,
        'banks' => Icons.account_balance_rounded,
        'lan_ips' => Icons.lan_rounded,
        'ads' => Icons.block_rounded,
        'ads_geosite' => Icons.block_rounded,
        'streaming' => Icons.play_circle_outline_rounded,
        'messengers' => Icons.chat_bubble_outline_rounded,
        'telegram_geo' => Icons.send_rounded,
        'refilter' => Icons.shield_rounded,
        _ => Icons.tune_rounded,
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
    return ExpressivePage(
      title: l10n.settingsRoutingTitle,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        ExpressiveSpacing.large,
        ExpressiveSpacing.none,
        ExpressiveSpacing.large,
        ExpressiveSpacing.extraLargeIncreased,
      ),
      actions: [
        IconButton(
          tooltip: l10n.routingCheatSheetTitle,
          icon: const Icon(Icons.help_outline_rounded),
          onPressed: () => _showCheatSheet(context, l10n),
        ),
        IconButton(
          tooltip: l10n.settingsResetRoutingTitle,
          icon: const Icon(Icons.restore_rounded),
          onPressed: _resetToDefaults,
        ),
      ],
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
            icon: Icons.call_made_rounded,
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
            icon: Icons.vpn_lock_rounded,
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
            icon: Icons.block_rounded,
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
    );
  }

  Widget _reconnectHintBanner(BuildContext context, AppLocalizations l10n) {
    return ExpressiveNotice(
      color: AppTheme.orange(context),
      icon: Icons.info_outline_rounded,
      text: l10n.splitTunnelingReconnectHint,
    );
  }

  // ── Финальное действие (глобал-прокси / обход / блок) ──────────────────────

  String _finalLabel(AppLocalizations l10n, String value) => switch (value) {
        AppSettings.finalOutboundDirect => l10n.settingsRoutingFinalDirect,
        AppSettings.finalOutboundBlock => l10n.settingsRoutingFinalBlock,
        _ => l10n.settingsRoutingFinalProxy,
      };

  IconData _finalIcon(String value) => switch (value) {
        AppSettings.finalOutboundDirect => Icons.call_made_rounded,
        AppSettings.finalOutboundBlock => Icons.block_rounded,
        _ => Icons.vpn_lock_rounded,
      };

  Color _finalColor(BuildContext context, String value) => switch (value) {
        AppSettings.finalOutboundDirect => AppTheme.green(context),
        AppSettings.finalOutboundBlock => AppTheme.red(context),
        _ => AppTheme.accent(context),
      };

  Widget _finalOutboundCard(
      BuildContext context, AppLocalizations l10n, String current) {
    return ExpressiveCard(
      child:Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.alt_route_rounded, size: 18, color: AppTheme.accent(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.settingsRoutingFinalTitle,
                  style: Theme.of(context)
                      .textTheme
                      .emphasized(Theme.of(context).textTheme.titleMedium)
                      ?.copyWith(color: AppTheme.text(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            l10n.settingsRoutingFinalDesc,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppTheme.textLight(context)),
          ),
          const SizedBox(height: 12),
          // Связанная группа кнопок вместо трёх самодельных плиток с рамкой в
          // 2px и заливкой на 14% альфы: выбор одного из взаимоисключающих
          // вариантов — ровно её работа, а прежний вид был кнопкой-переключателем
          // из M2. Смысловой цвет остаётся на иконках невыбранных.
          ExpressiveConnectedButtons<String>(
            segments: [
              for (final value in AppSettings.finalOutbounds)
                ExpressiveSegment(
                  value: value,
                  label: _finalLabel(l10n, value),
                  icon: _finalIcon(value),
                  iconColor: _finalColor(context, value),
                ),
            ],
            selected: current,
            onChanged: _saveFinalOutbound,
          ),
        ],
      ),
    );
  }


  // ── Структурированные правила (RoutingRule) ────────────────────────────────

  Widget _advancedRulesCard(BuildContext context, AppLocalizations l10n) {
    final rulesAsync = ref.watch(routingRulesProvider);
    // processName-правила не поддержаны в этом редакторе (пер-аппный роутинг —
    // отдельный экран split tunneling); прячем их, чтобы не путать.
    final rules = (rulesAsync.value ?? const <RoutingRule>[])
        .where((r) => r.type != RuleType.processName)
        .toList();
    return ExpressiveCard(
      child:Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, size: 18, color: AppTheme.accent(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.settingsRoutingAdvancedTitle,
                  style: Theme.of(context)
                      .textTheme
                      .emphasized(Theme.of(context).textTheme.titleMedium)
                      ?.copyWith(color: AppTheme.text(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            l10n.settingsRoutingAdvancedHint,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppTheme.textLight(context)),
          ),
          const SizedBox(height: 12),
          if (rules.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: Text(
                  l10n.settingsRoutingAdvancedEmpty,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppTheme.textLight(context)),
                ),
              ),
            )
          else
            for (final rule in rules) _ruleTile(context, l10n, rule),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.tonalIcon(
              onPressed: () => _openRuleEditor(l10n, null),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(l10n.settingsRoutingAdvancedAdd),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ruleTile(
      BuildContext context, AppLocalizations l10n, RoutingRule rule) {
    final color = _ruleActionColor(context, rule.action);
    final valuesPreview = rule.values.join(', ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppTheme.bg(context),
        borderRadius: BorderRadius.circular(ExpressiveShape.medium),
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
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: rule.enabled
                                  ? AppTheme.text(context)
                                  : AppTheme.textLight(context),
                            ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _pill(_ruleTypeLabel(l10n, rule.type),
                        AppTheme.textLight(context)),
                    const SizedBox(width: 4),
                    _pill(_ruleActionLabel(l10n, rule.action), color),
                  ],
                ),
                if (rule.name.trim().isNotEmpty && valuesPreview.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    valuesPreview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppTheme.textLight(context)),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: l10n.settingsRoutingRuleEditTitle,
            icon: Icon(Icons.edit_rounded,
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
          borderRadius: BorderRadius.circular(ExpressiveShape.small),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
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
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: AppTheme.text(context)),
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
              ? Theme.of(context)
                  .textTheme
                  .emphasized(Theme.of(context).textTheme.labelLarge)
                  ?.copyWith(
                    letterSpacing: 0.3,
                    color: AppTheme.accent(context),
                  )
              : Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.45,
                    color: AppTheme.text(context),
                  ),
        ),
      ));
    }
    return out;
  }

  Widget _syntaxLegend(BuildContext context, AppLocalizations l10n) {
    return ExpressiveCard(
      child:Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.help_outline_rounded, size: 18, color: AppTheme.textLight(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.settingsRoutingSyntaxHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
        borderRadius: BorderRadius.circular(ExpressiveShape.large),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.alt_route_rounded, size: 20, color: AppTheme.accent(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.settingsRoutingHeaderDesc,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
    return ExpressiveCard(
      child:Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settingsRoutingPresetsTitle,
            style: Theme.of(context)
                .textTheme
                .emphasized(Theme.of(context).textTheme.titleMedium)
                ?.copyWith(color: AppTheme.text(context)),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.settingsRoutingPresetsHint,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppTheme.textLight(context)),
          ),
          const SizedBox(height: 12),
          _presetPicker(context, l10n),
        ],
      ),
    );
  }

  RoutingPreset? _selectedPreset() {
    for (final preset in RoutingPresets.all) {
      if (preset.id == _selectedPresetId) return preset;
    }
    return null;
  }

  /// Выбор пресета шторкой, а не `DropdownButton`.
  ///
  /// `DropdownButton` — компонент M2: своя рамка, своя стрелка, а выбранное он
  /// никак не помечает, просто прокручивает к нему список. Шторка со строками
  /// [ExpressiveActionTile] — тот же способ выбора, что уже стоит у сортировки
  /// серверов и интервала обновления подписки, и в неё помещается описание
  /// пресета, которому в закрытом списке места не было вовсе.
  Widget _presetPicker(BuildContext context, AppLocalizations l10n) {
    final selected = _selectedPreset();
    // Одной строкой: выбор и кнопка рядом, а не друг под другом.
    //
    // Описание пресета сюда не выводим — оно есть в шторке, ровно там, где по
    // нему и принимают решение. Здесь оно занимало третью строку и повторяло
    // то, что человек только что прочитал при выборе.
    return Row(
      children: [
        Expanded(
          child: ExpressiveGroup(
            children: [
              ExpressiveActionTile(
                icon: selected == null
                    ? Icons.tune_rounded
                    : _presetIcon(selected.id),
                title: selected == null
                    ? l10n.settingsRoutingPresetChoose
                    : _presetTitle(l10n, selected.id),
                onTap: () => unawaited(_showPresetSheet(context, l10n)),
              ),
            ],
          ),
        ),
        const SizedBox(width: ExpressiveSpacing.medium),
        FilledButton.icon(
          onPressed: selected == null
              ? null
              : () => _applyPreset(selected, _presetTitle(l10n, selected.id)),
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.settingsRoutingPresetAdd),
        ),
      ],
    );
  }

  Future<void> _showPresetSheet(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final theme = Theme.of(context);
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.8,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  child: Text(
                    l10n.settingsRoutingPresetsTitle,
                    style: theme.textTheme
                        .emphasized(theme.textTheme.titleMedium)
                        ?.copyWith(color: AppTheme.text(context)),
                  ),
                ),
                ExpressiveGroup(
                  children: [
                    for (final preset in RoutingPresets.all)
                      ExpressiveActionTile(
                        icon: _presetIcon(preset.id),
                        title: _presetTitle(l10n, preset.id),
                        subtitle: _presetDesc(l10n, preset.id),
                        selected: preset.id == _selectedPresetId,
                        onTap: () => Navigator.pop(ctx, preset.id),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => _selectedPresetId = chosen);
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
    return ExpressiveCard(
      child:Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(ExpressiveShape.medium),
                ),
                child: Icon(icon, size: 17, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .emphasized(Theme.of(context).textTheme.titleSmall)
                      ?.copyWith(color: AppTheme.text(context)),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(ExpressiveShape.small),
                ),
                child: Text(
                  l10n.settingsRoutingItemCount(count),
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: color),
                ),
              ),
              if (!geoIndex.isEmpty)
                IconButton(
                  tooltip: l10n.settingsRoutingGeoPickerTooltip,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(Icons.travel_explore_rounded, size: 18, color: color),
                  onPressed: () => _showGeoCodePicker(field, geoIndex),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            desc,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppTheme.textLight(context)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 8,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppTheme.text(context)),
            // Форма, рамка, цвета фокуса и стили подсказок — из темы
            // (`buildExpressiveComponentThemes.inputDecoration`). Здесь остаётся
            // только то, что относится к этому конкретному полю: сам текст
            // подсказки и пояснение под ним.
            decoration: InputDecoration(
              hintText: hint,
              helperText: l10n.settingsRoutingValuesHint,
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
        borderRadius: BorderRadius.circular(ExpressiveShape.medium),
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
                  style: Theme.of(context)
                      .textTheme
                      .emphasized(Theme.of(context).textTheme.labelMedium)
                      ?.copyWith(color: AppTheme.orange(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tokens.join(', '),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: AppTheme.text(context),
                ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.settingsRoutingGeoUnknownHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
