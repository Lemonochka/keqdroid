part of '../settings_tab.dart';

sealed class _ContentChoice {
  const _ContentChoice();
}

class _ContentKind extends _ContentChoice {
  const _ContentKind(this.content);
  final RouteContent content;
}

class _ContentPreset extends _ContentChoice {
  const _ContentPreset(this.preset);
  final RoutingPreset preset;
}

// сохраняет сам, без кнопки. новый маршрут появляется в списке, только когда начал что-то забирать
class _RouteEditorScreen extends ConsumerStatefulWidget {
  const _RouteEditorScreen({this.initial, this.profileId});

  final TrafficRoute? initial;
  final String? profileId;

  @override
  ConsumerState<_RouteEditorScreen> createState() => _RouteEditorScreenState();
}

class _RouteEditorScreenState extends ConsumerState<_RouteEditorScreen> {
  late TrafficRoute _route;
  late final TextEditingController _sites;
  late bool _stored;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _route = widget.initial ?? TrafficRoute.create();
    _stored = widget.initial != null;
    _sites = TextEditingController(text: _route.sites);
  }

  @override
  void dispose() {
    // ref тут нельзя: несохранённое дописывает PopScope на уходе
    _debounce?.cancel();
    _sites.dispose();
    super.dispose();
  }

  // все приложения и весь трафик это и есть всё остальное
  bool get _savable =>
      !(_route.allApps && _route.content == RouteContent.allTraffic) &&
      (_stored || !routeIsEmpty(_route));

  void _change(TrafficRoute next, {bool typing = false}) {
    setState(() => _route = next);
    _debounce?.cancel();
    if (typing) {
      _debounce = Timer(const Duration(milliseconds: 500), _persist);
    } else {
      unawaited(_persist());
    }
  }

  Future<void> _persist() async {
    _debounce?.cancel();
    if (!_savable) return;
    _stored = true;
    await _upsertRoute(ref, widget.profileId, _route);
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l10n.routeDeleteConfirm),
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
    if (ok != true || !mounted) return;
    _debounce?.cancel();
    _stored = false;
    await _removeRoute(ref, widget.profileId, _route.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final caps = ref.watch(routeCapabilitiesProvider);
    final servers = ref.watch(serversProvider.select((s) => s.servers));
    final split = ref.watch(splitTunnelingProvider);
    final issue = _routeIssue(
      l10n,
      _route,
      caps,
      servers,
      split,
      _installedForLabels(ref, [_route]),
    );
    return PopScope(
      // здесь, а не в dispose: там ref уже нельзя трогать
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && (_debounce?.isActive ?? false)) unawaited(_persist());
      },
      child: ExpressivePage(
        title: widget.initial == null && !_stored
            ? l10n.routeNew
            : l10n.routeEditorTitle,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          ExpressiveSpacing.large,
          ExpressiveSpacing.none,
          ExpressiveSpacing.large,
          ExpressiveSpacing.extraLargeIncreased,
        ),
        actions: [
          if (_stored)
            IconButton(
              tooltip: l10n.subscriptionsDelete,
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _delete,
            ),
        ],
        children: [
          if (issue != null) ...[
            ExpressiveNotice(
              color: Theme.of(context).colorScheme.error,
              icon: Icons.error_outline_rounded,
              text: issue,
            ),
            const SizedBox(height: ExpressiveSpacing.medium),
          ],
          ExpressiveGroup(
            children: [
              if (caps.appsOffered || !_route.allApps) _whoTile(l10n),
              _whatTile(l10n),
              _whereTile(l10n, servers),
            ],
          ),
          const SizedBox(height: ExpressiveSpacing.large),
          ExpressiveGroup(
            children: [
              ExpressiveGroupTile(
                onTap: () => _change(_route.copyWith(enabled: !_route.enabled)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.routeEnabled,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: AppTheme.text(context)),
                      ),
                    ),
                    Switch(
                      value: _route.enabled,
                      onChanged: (v) => _change(_route.copyWith(enabled: v)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _whoTile(AppLocalizations l10n) {
    final installed = _installedForLabels(ref, [_route]);
    return ExpressiveGroupTile(
      onTap: () => unawaited(_pickWho()),
      child: _RouteRowContent(
        badge: _route.allApps
            ? const ExpressiveIconBadge(icon: Icons.apps_rounded)
            : _appsBadge(
                _route.apps,
                ref.read(appIconCacheProvider),
                installed,
              ),
        title: Text(l10n.routeWho),
        subtitle: Text(
          _route.allApps
              ? l10n.routesSectionAllApps
              : _route.apps.map((a) => _appLabel(a, installed)).join(', '),
        ),
      ),
    );
  }

  Future<void> _pickWho() async {
    final apps = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _WhoPickerSheet(initial: _route.apps),
    );
    if (apps == null || !mounted) return;
    _change(_route.copyWith(
      apps: apps,
      content: apps.isEmpty && _route.content == RouteContent.allTraffic
          ? RouteContent.sites
          : _route.content,
    ));
  }

  Widget _whatTile(AppLocalizations l10n) {
    final header = _RouteRowContent(
      badge: ExpressiveIconBadge(icon: _contentIcon(_route)),
      title: Text(l10n.routeWhat),
      subtitle: Text(switch (_route.content) {
        RouteContent.allTraffic => l10n.routeWhatAll,
        RouteContent.preset => l10n.routeWhatPresetValue(
            _presetName(l10n, _route.presetId),
          ),
        RouteContent.sites => l10n.routeWhatSitesValue(_sitesCount(l10n)),
      }),
    );
    if (_route.content != RouteContent.sites) {
      return ExpressiveGroupTile(
        onTap: () => unawaited(_pickWhat(l10n)),
        child: header,
      );
    }
    return ExpressiveGroupTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: ExpressiveShape.radius(ExpressiveShape.medium),
            onTap: () => unawaited(_pickWhat(l10n)),
            child: header,
          ),
          const SizedBox(height: ExpressiveSpacing.medium),
          ..._sitesEditor(l10n),
        ],
      ),
    );
  }

  Future<void> _pickWhat(AppLocalizations l10n) async {
    final choice = await _showChoiceSheet<_ContentChoice>(
      context,
      title: l10n.routeWhat,
      children: (ctx) => [
        ExpressiveGroup(
          children: [
            if (!_route.allApps)
              ExpressiveActionTile(
                icon: Icons.all_inclusive_rounded,
                title: l10n.routeWhatAll,
                subtitle: l10n.routeWhatAllSubtitle,
                selected: _route.content == RouteContent.allTraffic,
                onTap: () => Navigator.pop(
                  ctx,
                  const _ContentKind(RouteContent.allTraffic),
                ),
              ),
            ExpressiveActionTile(
              icon: Icons.language_rounded,
              title: l10n.routeWhatSites,
              subtitle: l10n.routeWhatSitesSubtitle,
              selected: _route.content == RouteContent.sites,
              onTap: () =>
                  Navigator.pop(ctx, const _ContentKind(RouteContent.sites)),
            ),
          ],
        ),
        ExpressiveSectionHeader(l10n.settingsRoutingPresetsTitle),
        ExpressiveGroup(
          children: [
            for (final preset in RoutingPresets.all)
              ExpressiveActionTile(
                icon: _presetIcon(preset.id),
                title: _presetName(l10n, preset.id),
                selected: _route.content == RouteContent.preset &&
                    _route.presetId == preset.id,
                onTap: () => Navigator.pop(ctx, _ContentPreset(preset)),
              ),
          ],
        ),
      ],
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case _ContentKind(:final content):
        _change(_route.copyWith(content: content));
      case _ContentPreset(:final preset):
        setState(() => _route = _route.copyWith(
              content: RouteContent.preset,
              presetId: preset.id,
              target: switch (preset.field) {
                RoutingField.direct => RouteTarget.direct,
                RoutingField.proxy => RouteTarget.vpn,
                RoutingField.blocked => RouteTarget.block,
              },
            ));
        // дождаться записи: соседние маршруты ниже перезаписали бы список, прочитанный до неё
        await _persist();
        if (!mounted) return;
        if (preset.offRunetDirect) await _offRunetDirect();
        if (!mounted) return;
        await _applyPresetUnmatched(l10n, preset);
    }
  }

  Future<void> _offRunetDirect() async {
    for (final r in await _routesFor(ref, widget.profileId)) {
      if (!mounted) return;
      if (r.id == _route.id || !r.enabled || !routeSendsRunetDirect(r)) {
        continue;
      }
      await _upsertRoute(ref, widget.profileId, r.copyWith(enabled: false));
    }
  }

  // Re-filter заодно ставит всё остальное напрямую: ради этого пресет и берут
  Future<void> _applyPresetUnmatched(
    AppLocalizations l10n,
    RoutingPreset preset,
  ) async {
    final unmatched = preset.unmatched;
    if (unmatched == null) return;
    final value = switch (unmatched) {
      RoutingField.direct => AppSettings.finalOutboundDirect,
      RoutingField.proxy => AppSettings.finalOutboundProxy,
      RoutingField.blocked => AppSettings.finalOutboundBlock,
    };
    if (_finalOutboundFor(ref, widget.profileId) == value) return;
    await _saveFinalOutbound(ref, widget.profileId, value);
    if (!mounted || unmatched != RoutingField.direct) return;
    AppSnack.of(context).showSnackBar(
      SnackBar(content: Text(l10n.routeRefilterUnmatched)),
    );
  }

  Widget _whereTile(AppLocalizations l10n, List<ServerItem> servers) {
    final color = _targetColor(context, _route.target);
    final server = _route.target == RouteTarget.server
        ? _routeServer(_route, servers)
        : null;
    return ExpressiveGroupTile(
      onTap: () => unawaited(_pickWhere(l10n)),
      child: _RouteRowContent(
        badge: server != null
            ? ServerAvatar(flag: server.flag, protocol: server.protocol)
            : ExpressiveIconBadge(
                icon: _targetIcon(_route.target),
                background: color.withValues(alpha: 0.16),
                foreground: color,
              ),
        title: Text(l10n.routeWhere),
        subtitle: Text(switch (_route.target) {
          RouteTarget.vpn => l10n.settingsRoutingProxyTitle,
          RouteTarget.direct => l10n.settingsRoutingDirectTitle,
          RouteTarget.block => l10n.settingsRoutingBlockTitle,
          RouteTarget.server => _targetLabel(l10n, _route, servers),
        }),
      ),
    );
  }

  Future<void> _pickWhere(AppLocalizations l10n) async {
    final caps = ref.read(routeCapabilitiesProvider);
    final servers = ref.read(serversProvider).servers;
    final current = _routeServer(_route, servers);
    final target = await _showTargetSheet(
      context,
      title: l10n.routeWhere,
      current: _route.target,
      serverTile: caps.servers
          ? (ctx) => ExpressiveActionTile(
                icon: _targetIcon(RouteTarget.server),
                title: current == null
                    ? l10n.chainPickNode
                    : ServerNameUtils.cleanDisplayName(current.displayName),
                selected: current != null,
                onTap: () => Navigator.pop(ctx, RouteTarget.server),
              )
          : null,
    );
    if (target == null || !mounted) return;
    if (target != RouteTarget.server) {
      _change(_route.copyWith(target: target, serverId: ''));
      return;
    }
    // только то, что ядро возьмёт отдельным выходом, остальное ушло бы через VPN
    final candidates = [
      for (final s in servers)
        if (routeServerSupported(s.config, caps.core)) s,
    ];
    final picked = await showModalBottomSheet<ServerItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ServerPickerSheet(
        title: l10n.routeWhereServers,
        searchHint: l10n.chainPickSearch,
        emptyText: l10n.routePickEmpty,
        candidates: candidates,
        selectedId: current?.id,
      ),
    );
    if (picked == null || !mounted) return;
    _change(_route.copyWith(target: RouteTarget.server, serverId: picked.id));
  }

  String _sitesCount(AppLocalizations l10n) {
    final entries = routingEntries(_sites.text);
    final statuses = ref.watch(ruleListsProvider);
    final linked = [
      for (final url in ruleListUrls(_sites.text)) ?statuses[url],
    ].fold(0, (sum, s) => sum + s.domains);
    if (linked == 0) return l10n.settingsRoutingItemCount(entries.length);
    final plain = entries.where((e) => !isRuleListUrl(e)).length;
    final links =
        l10n.settingsRoutingLinkDomains(linked, _groupedCount(linked));
    if (plain == 0) return links;
    return l10n.settingsRoutingCountWithLinks(
      l10n.settingsRoutingItemCount(plain),
      links,
    );
  }

  // цифры латинские и в фарси: остальные числа в приложении печатает код
  String _groupedCount(int n) {
    final lang = Localizations.localeOf(context).languageCode;
    return NumberFormat.decimalPattern(lang == 'fa' ? 'en' : lang).format(n);
  }

  List<Widget> _sitesEditor(AppLocalizations l10n) {
    final geoIndex =
        ref.watch(geoAssetIndexProvider).value ?? GeoAssetIndex.empty;
    final unknown = unknownGeoTokens(_sites.text, geoIndex);
    final statuses = ref.watch(ruleListsProvider);
    final lists = [
      for (final url in ruleListUrls(_sites.text)) ?statuses[url],
    ];
    final linkedDomains = lists.fold(0, (sum, s) => sum + s.domains);
    return [
      _sitesField(l10n, geoIndex),
      if (lists.isNotEmpty) ...[
        const SizedBox(height: ExpressiveSpacing.small),
        for (final status in lists) _ruleListLine(l10n, status),
      ],
      if (Platform.isAndroid &&
          linkedDomains > ruleListPhoneDomainBudget &&
          ref.watch(activeVpnBackendProvider) == VpnBackend.xray) ...[
        const SizedBox(height: ExpressiveSpacing.small),
        ExpressiveNotice(
          color: AppTheme.orange(context),
          icon: Icons.memory_rounded,
          text: l10n.ruleListMemoryWarning(
            _groupedCount(ruleListPhoneDomainBudget),
          ),
        ),
      ],
      if (unknown.isNotEmpty) ...[
        const SizedBox(height: ExpressiveSpacing.small),
        _unknownGeoWarning(l10n, unknown),
      ],
    ];
  }

  Widget _sitesField(AppLocalizations l10n, GeoAssetIndex geoIndex) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = ExpressiveShape.radius(ExpressiveShape.large);
    final withPicker = !geoIndex.isEmpty;
    return Stack(
      children: [
        TextField(
          controller: _sites,
          textDirection: technicalInputDirection,
          minLines: 2,
          maxLines: 8,
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
          decoration: InputDecoration(
            hintText: 'youtube.com, 1.1.1.1, geosite:google',
            filled: true,
            fillColor: scheme.surfaceContainerLowest,
            border: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(color: scheme.primary, width: 2),
            ),
            contentPadding: EdgeInsetsDirectional.fromSTEB(
              16,
              14,
              withPicker ? 48 : 16,
              14,
            ),
          ),
          onChanged: (text) =>
              _change(_route.copyWith(sites: text), typing: true),
        ),
        if (withPicker)
          PositionedDirectional(
            top: 4,
            end: 4,
            child: IconButton(
              tooltip: l10n.settingsRoutingGeoPickerTooltip,
              icon: const Icon(Icons.travel_explore_rounded, size: 20),
              color: scheme.onSurfaceVariant,
              onPressed: () => unawaited(_pickGeoCode(geoIndex)),
            ),
          ),
      ],
    );
  }

  Future<void> _pickGeoCode(GeoAssetIndex index) async {
    final token = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _GeoCodePickerSheet(index: index),
    );
    if (token == null || token.isEmpty || !mounted) return;
    _sites.text = RoutingPresets.mergeValues(_sites.text, [token]);
    _change(_route.copyWith(sites: _sites.text));
  }

  // скачанное раньше при неудаче остаётся в силе, поэтому строка предупреждающая, а не красная
  Widget _ruleListLine(AppLocalizations l10n, RuleListStatus s) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final parsedHost = Uri.tryParse(s.url)?.host ?? '';
    final host = ltrIsolate(parsedHost.isEmpty ? s.url : parsedHost);
    String domains() =>
        l10n.ruleListDomainCount(s.domains, _groupedCount(s.domains));
    String when() => timeAgo(l10n, s.updatedAt!);
    final (IconData icon, Color color, String text) = switch (s) {
      _ when s.loading || (!s.loaded && s.failure == null) => (
          Icons.cloud_sync_outlined,
          scheme.onSurfaceVariant,
          l10n.ruleListLoading(host),
        ),
      _ when s.loaded && s.failure == null => (
          Icons.cloud_done_outlined,
          scheme.onSurfaceVariant,
          l10n.ruleListLoaded(host, domains(), when()),
        ),
      _ when s.loaded => (
          Icons.cloud_off_outlined,
          AppTheme.orange(context),
          l10n.ruleListLoadedStale(host, domains(), when()),
        ),
      _ => (
          Icons.error_outline_rounded,
          scheme.error,
          switch (s.failure) {
            RuleListFailure.insecure => l10n.ruleListFailedInsecure(host),
            RuleListFailure.http =>
              l10n.ruleListFailedHttp(host, s.httpStatus ?? 0),
            RuleListFailure.tooLarge => l10n.ruleListFailedTooLarge(host),
            RuleListFailure.empty => l10n.ruleListFailedEmpty(host),
            RuleListFailure.network || null =>
              l10n.ruleListFailedNetwork(host),
          },
        ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: ExpressiveSpacing.small),
          Expanded(
            child: Text(
              text,
              // оранжевый текст на светлой теме не проходит по контрасту, его несёт иконка
              style: theme.textTheme.bodySmall?.copyWith(
                color: color == scheme.error ? color : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // неизвестный geo-код роняет весь конфиг, такие записи выкидываются перед подключением, и видеть это надо здесь
  Widget _unknownGeoWarning(AppLocalizations l10n, List<String> tokens) {
    final orange = AppTheme.orange(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ExpressiveShape.medium),
        border: Border.all(color: orange.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.settingsRoutingGeoUnknownTitle,
                  style: textTheme
                      .emphasized(textTheme.labelMedium)
                      ?.copyWith(color: orange),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tokens.join(', '),
            style: textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: AppTheme.text(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.settingsRoutingGeoUnknownHint,
            style: textTheme.bodySmall?.copyWith(
              height: 1.35,
              color: AppTheme.textLight(context),
            ),
          ),
        ],
      ),
    );
  }
}
