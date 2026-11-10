part of '../settings_tab.dart';

Widget routingScreen({String? focusProfileId}) =>
    _RoutingScreen(focusProfileId: focusProfileId);

Color _targetColor(BuildContext context, RouteTarget target) =>
    switch (target) {
      RouteTarget.direct => AppTheme.green(context),
      RouteTarget.block => AppTheme.red(context),
      RouteTarget.vpn || RouteTarget.server => AppTheme.accent(context),
    };

IconData _targetIcon(RouteTarget target) => switch (target) {
      RouteTarget.direct => Icons.call_made_rounded,
      RouteTarget.block => Icons.block_rounded,
      RouteTarget.vpn => Icons.vpn_lock_rounded,
      RouteTarget.server => Icons.dns_rounded,
    };

RouteTarget _finalTarget(String finalOutbound) => switch (finalOutbound) {
      AppSettings.finalOutboundDirect => RouteTarget.direct,
      AppSettings.finalOutboundBlock => RouteTarget.block,
      _ => RouteTarget.vpn,
    };

String _finalOutboundOf(RouteTarget target) => switch (target) {
      RouteTarget.direct => AppSettings.finalOutboundDirect,
      RouteTarget.block => AppSettings.finalOutboundBlock,
      _ => AppSettings.finalOutboundProxy,
    };

String _presetName(AppLocalizations l10n, String id) => switch (id) {
      'ru' => l10n.settingsRoutingPresetRuTitle,
      'ir' => l10n.settingsRoutingPresetIrTitle,
      'ads' => l10n.settingsRoutingPresetAdsTitle,
      'refilter' => l10n.settingsRoutingPresetRefilterTitle,
      'whitelist' => l10n.settingsRoutingPresetWhitelistTitle,
      _ => id,
    };

IconData _presetIcon(String id) => switch (id) {
      'ru' || 'ir' => Icons.flag_rounded,
      'ads' => Icons.block_rounded,
      'refilter' => Icons.shield_rounded,
      'whitelist' => Icons.signal_cellular_alt_rounded,
      _ =>Icons.playlist_add_check_rounded,
    };

IconData _contentIcon(TrafficRoute route) => switch (route.content) {
      RouteContent.allTraffic => Icons.all_inclusive_rounded,
      RouteContent.sites => Icons.language_rounded,
      RouteContent.preset => _presetIcon(route.presetId),
    };

String _appLabel(String entry, [List<AppInfo> installed = const []]) {
  final app = _installedApp(entry, installed);
  if (app != null && app.appName.isNotEmpty) return app.appName;
  var name = normalizeProcessName(entry);
  if (name.toLowerCase().endsWith('.exe')) {
    name = name.substring(0, name.length - 4);
  }
  return name;
}

AppInfo? _installedApp(String entry, List<AppInfo> installed) =>
    installed.where((app) => splitEntryMatches(entry, app)).firstOrNull;

// на Android запись маршрута это имя пакета, название и иконку даёт само
// приложение; на ПК подпись и есть имя программы
List<AppInfo> _installedForLabels(WidgetRef ref, List<TrafficRoute> routes) {
  if (!Platform.isAndroid || routes.every((r) => r.allApps)) return const [];
  return ref.watch(installedAppsProvider(true)).value ?? const [];
}

Widget _appsBadge(
  List<String> apps,
  AppIconCache cache, [
  List<AppInfo> installed = const [],
]) =>
    AppIconView(
      iconBase64: _installedApp(apps.first, installed)?.iconBase64,
      appName: _appLabel(apps.first, installed),
      iconPath: isProcessPathEntry(apps.first) ? apps.first : null,
      cache: cache,
    );

String? _routeIssue(
  AppLocalizations l10n,
  TrafficRoute route,
  RouteCapabilities caps,
  List<ServerItem> servers,
  SplitTunnelingState split,
  List<AppInfo> installed,
) {
  if (routePortRanges(route.ports) == null) return l10n.routePortsInvalid;
  if (route.allApps &&
      route.content == RouteContent.allTraffic &&
      !routeHasProtocol(route)) {
    return l10n.routeAllTrafficNeedsProtocol;
  }
  if (!route.allApps) {
    if (!caps.apps) {
      if (!caps.appsNeedTun) return l10n.routeAppsUnsupported;
      return Platform.isAndroid ? l10n.routeAppsNeedVpn : l10n.routeAppsNeedTun;
    }
    final outside = appsOutsideSplit(
      route.apps,
      include: split.includePackages,
      exclude: split.excludePackages,
    );
    if (outside.isNotEmpty) {
      return l10n.routeSplitExcluded(
        ltrIsolate(outside.map((a) => _appLabel(a, installed)).join(', ')),
      );
    }
  }
  if (route.target == RouteTarget.server) {
    final server = servers.where((s) => s.id == route.serverId).firstOrNull;
    if (server == null) return l10n.routeServerMissing;
    if (!caps.servers || !routeServerSupported(server.config, caps.core)) {
      return l10n.routeServerUnsupported;
    }
  }
  return null;
}

String? _networkName(RouteNetwork network) => switch (network) {
      RouteNetwork.any => null,
      RouteNetwork.tcp => 'TCP',
      RouteNetwork.udp => 'UDP',
    };

// неверные порты показываем как набраны: ошибку рядом называет _routeIssue
String? _portsText(TrafficRoute route) {
  final raw = route.ports.trim();
  if (raw.isEmpty) return null;
  final ranges = routePortRanges(raw);
  if (ranges == null) return raw;
  return [for (final (from, to) in ranges) from == to ? '$from' : '$from-$to']
      .join(', ');
}

// не plural: gen-l10n сводит =1 и русское one в один вариант, и диапазон из 21 порта стал бы «порт»
String _portsLabel(AppLocalizations l10n, TrafficRoute route, String ports) {
  final count = (routePortRanges(route.ports) ?? const [])
      .fold(0, (sum, r) => sum + r.$2 - r.$1 + 1);
  return count == 1
      ? l10n.routePortValue(ltrIsolate(ports))
      : l10n.routePortsValue(ltrIsolate(ports));
}

String _protocolValue(AppLocalizations l10n, TrafficRoute route) {
  final ports = _portsText(route);
  final network = _networkName(route.network) ??
      (ports == null ? null : l10n.routeProtocolAnySubtitle);
  if (network == null) return l10n.routeProtocolAny;
  return '$network · ${ports == null ? l10n.routePortsAll : _portsLabel(l10n, route, ports)}';
}

String? _protocolShort(AppLocalizations l10n, TrafficRoute route) {
  final ports = _portsText(route);
  final network = _networkName(route.network);
  if (ports == null) return network;
  if (network == null) return _portsLabel(l10n, route, ports);
  return ltrIsolate('$network $ports');
}

ServerItem? _routeServer(TrafficRoute route, List<ServerItem> servers) =>
    route.target == RouteTarget.server
        ? servers.where((s) => s.id == route.serverId).firstOrNull
        : null;

String _targetLabel(
  AppLocalizations l10n,
  TrafficRoute route,
  List<ServerItem> servers,
) =>
    switch (route.target) {
      RouteTarget.vpn => l10n.routeToVpn,
      RouteTarget.direct => l10n.routeToDirect,
      RouteTarget.block => l10n.routeToBlock,
      // флаг рисуется значком рядом, а в имени он часто стоит эмодзи
      RouteTarget.server => switch (_routeServer(route, servers)) {
          final server? => ServerNameUtils.cleanDisplayName(server.displayName),
          null => l10n.routeToVpn,
        },
    };

// ссылку показываем именем хоста: полный адрес съел бы строку
String _contentLabel(AppLocalizations l10n, TrafficRoute route) {
  switch (route.content) {
    case RouteContent.allTraffic:
      return l10n.routeAllTrafficShort;
    case RouteContent.preset:
      return _presetName(l10n, route.presetId);
    case RouteContent.sites:
      final entries = routingEntries(route.sites);
      if (entries.isEmpty) return l10n.settingsRoutingItemCount(0);
      return [
        for (final e in entries)
          if (isRuleListUrl(e))
            ltrIsolate(Uri.tryParse(e)?.host.nonEmptyOr(e) ?? e)
          else
            e,
      ].join(', ');
  }
}

extension on String {
  String nonEmptyOr(String fallback) => isEmpty ? fallback : this;
}

// под кнопкой «Новый профиль» не должна прятаться последняя строка
const _fabClearance = 96.0;

class _RoutingScreen extends ConsumerStatefulWidget {
  const _RoutingScreen({this.focusProfileId});

  final String? focusProfileId;

  @override
  ConsumerState<_RoutingScreen> createState() => _RoutingScreenState();
}

class _RoutingScreenState extends ConsumerState<_RoutingScreen> {
  final _mainKey = GlobalKey();
  final _focusKey = GlobalKey();
  late var _focusPending = widget.focusProfileId != null;

  // строки ленивые: под длинным «Основным» карточки ещё нет, до неё листаем экранами
  Future<void> _revealFocused() async {
    final mainContext = _mainKey.currentContext;
    if (mainContext == null) return;
    final position = Scrollable.of(mainContext).position;
    for (var i = 0; i < 20 && _focusKey.currentContext == null; i++) {
      if (position.pixels >= position.maxScrollExtent) return;
      position.jumpTo(math.min(
        position.pixels + position.viewportDimension,
        position.maxScrollExtent,
      ));
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    final card = _focusKey.currentContext?.findRenderObject();
    if (card == null) return;
    final viewport = RenderAbstractViewport.of(card);
    final top = viewport.getOffsetToReveal(card, 0).offset;
    final bottom = viewport.getOffsetToReveal(card, 1).offset + _fabClearance;
    if (position.pixels >= bottom && position.pixels <= top) return;
    // сдвиг поменьше: влезающую карточку поднимаем только до кнопки внизу, а не к верху
    final target = position.pixels < bottom && bottom <= top ? bottom : top;
    position.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // маршруты читаются только в connect(), при живом туннеле правка вступит после переподключения
    final vpnStatus = ref.watch(
      vpnStateProvider.select((a) => a.value?.status),
    );
    final tunnelActive = vpnStatus == VpnStatus.connected ||
        vpnStatus == VpnStatus.connecting;
    final routesAsync = ref.watch(routesProvider);
    final profilesAsync = ref.watch(routingProfilesProvider);
    // до загрузки карточек нет: «Основной» вырастал из пустого анимацией, и прокрутка к профилю промахивалась
    final loaded = routesAsync.hasValue && profilesAsync.hasValue;
    final routes = routesAsync.value ?? const <TrafficRoute>[];
    final profiles = profilesAsync.value ?? const <RoutingProfile>[];
    if (_focusPending &&
        loaded &&
        profiles.any((p) => p.id == widget.focusProfileId)) {
      _focusPending = false;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_revealFocused()),
      );
    }
    final subs = ref.watch(subscriptionsProvider).value ?? const [];
    final expanded = ref.watch(expandedRoutingProfilesProvider);
    final hint = ref.watch(routesHintProvider);
    final caps = ref.watch(routeCapabilitiesProvider);
    final servers = ref.watch(serversProvider.select((s) => s.servers));
    final split = ref.watch(splitTunnelingProvider);
    final iconCache = ref.read(appIconCacheProvider);
    final installed = _installedForLabels(
      ref,
      [...routes, for (final p in profiles) ...p.routes],
    );
    final mainFinal = ref.watch(
      settingsNotifierProvider.select(
        (a) => a.value?.finalOutbound ?? AppSettings.finalOutboundProxy,
      ),
    );
    final ignoreProviderRules = ref.watch(
      settingsNotifierProvider.select((a) => a.value?.ignoreProviderRules ?? false),
    );
    final ignoreProviderDns = ref.watch(
      settingsNotifierProvider.select((a) => a.value?.ignoreProviderDns ?? false),
    );
    final templates = [
      for (final s in subs) ?ref.watch(subscriptionTemplateProvider(s.id)),
    ];
    // выключать нечего, пока ни один сервер не принёс своего; включённую кнопку не прячем
    final showProviderRules = ignoreProviderRules ||
        templates.isNotEmpty ||
        profiles.any((p) => p.providerSubscriptionId != null) ||
        servers.any((s) =>
            (s.customConfig?.hasProviderRules ?? false) ||
            (s.clashConfig?.hasProviderRules ?? false));
    final showProviderDns = ignoreProviderDns ||
        templates.any((t) => t.config.hasProviderDns) ||
        servers.any((s) =>
            (s.customConfig?.hasProviderDns ?? false) ||
            (s.clashConfig?.hasProviderDns ?? false));
    // профиль провайдера только смотрят, пока его правила слушают
    bool locked(RoutingProfile p) =>
        p.providerSubscriptionId != null && !ignoreProviderRules;
    final rowColor = Theme.of(context).colorScheme.surfaceContainer;

    List<Widget> routeRows(
      String? profileId,
      List<TrafficRoute> list,
      String finalOutbound, {
      bool locked = false,
    }) {
      Widget tile(TrafficRoute route) => _RouteTile(
            route: route,
            servers: servers,
            iconCache: iconCache,
            installed: installed,
            background: rowColor,
            issue: _routeIssue(l10n, route, caps, servers, split, installed),
            onTap: locked
                ? () => _showRouteEntries(context, route)
                : () => _openRouteEditor(context, route, profileId),
          );
      final block = routesIn(RouteSection.block, list);
      final apps = routesIn(RouteSection.apps, list);
      final allApps = routesIn(RouteSection.allApps, list);
      final target = _finalTarget(finalOutbound);
      final fixed = [
        _FinalRouteTile(
          target: target,
          background: rowColor,
          onTap: locked
              ? null
              : () => _pickFinalTarget(context, ref, profileId, target),
        ),
        if (!locked)
          ExpressiveGroupTile(
            onTap: () => _openRouteEditor(context, null, profileId),
            color: rowColor,
            child: _RouteRowContent(
              badge: const ExpressiveIconBadge(icon: Icons.add_rounded),
              title: Text(l10n.routeNew),
              subtitle: Text(
                caps.appsOffered
                    ? l10n.routeNewSubtitle
                    : l10n.routeNewSubtitleSites,
              ),
              chevron: false,
            ),
          ),
      ];
      return [
        if (block.isNotEmpty) ...[
          _ProfileSectionLabel(l10n.routesSectionBlock),
          ExpressiveGroup(children: [for (final r in block) tile(r)]),
        ],
        if (apps.isNotEmpty) ...[
          _ProfileSectionLabel(l10n.routesSectionApps),
          ExpressiveGroup(children: [for (final r in apps) tile(r)]),
        ],
        _ProfileSectionLabel(l10n.routesSectionAllApps),
        // переставлять одну строку некуда, а профиль провайдера под замком только смотрят
        if (locked || allApps.length < 2)
          ExpressiveGroup(children: [for (final r in allApps) tile(r), ...fixed])
        else
          _ReorderableRouteGroup(
            routes: allApps,
            tile: tile,
            fixed: fixed,
            onMove: (from, to) => unawaited(
              profileId == null
                  ? ref.read(routesProvider.notifier).moveInAllApps(from, to)
                  : ref
                      .read(routingProfilesProvider.notifier)
                      .moveRouteInAllApps(profileId, from, to),
            ),
          ),
      ];
    }

    final subNames = {for (final s in subs) s.id: s.name};
    final mainExpanded = _profileExpanded(expanded, _mainProfileKey);
    final mainScope = profiles.any(
      (p) => p.enabled && p.subscriptionIds.any(subNames.containsKey),
    )
        ? l10n.routingProfileScopeRest
        : l10n.routingProfileScopeAll;

    Widget profileCard(RoutingProfile p) {
      final isLocked = locked(p);
      final summary = !p.enabled
          ? l10n.routingProfileOff
          : !p.subscriptionIds.any(subNames.containsKey)
              ? l10n.routingProfileNoSubscriptions
              : '${l10n.routingProfileRouteCount(p.routes.length)} · '
                  '${l10n.routingProfileFinal(_finalLabel(l10n, p.finalOutbound))}';
      return _ProfileCard(
        key: ValueKey('routing-profile-${p.id}'),
        title: p.name,
        summary: isLocked
            ? '${l10n.routingProfileFromProvider} · $summary'
            : summary,
        chips: [for (final id in p.subscriptionIds) ?subNames[id]],
        enabled: isLocked ? null : p.enabled,
        onEnabled: (v) => unawaited(
          ref.read(routingProfilesProvider.notifier).setEnabled(p.id, v),
        ),
        menu: !isLocked
            ? IconButton(
                tooltip: MaterialLocalizations.of(context).showMenuTooltip,
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 20,
                  color: AppTheme.textLight(context),
                ),
                onPressed: () => _showProfileMenu(context, ref, p),
              )
            : IconButton(
                tooltip: l10n.routingProfileFromProvider,
                icon: Icon(
                  Icons.lock_rounded,
                  size: 20,
                  color: AppTheme.textLight(context),
                ),
                onPressed: () => AppSnack.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      l10n.routingProfileLockedHint(
                        '${l10n.routingIgnoreFromProvider}: '
                        '${l10n.routingIgnoreProviderRulesChip}',
                      ),
                    ),
                    backgroundColor: AppTheme.accent(context),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(ExpressiveShape.medium),
                    ),
                  ),
                ),
              ),
        expanded: _profileExpanded(expanded, p.id),
        onToggle: () => _toggleProfile(ref, p.id),
        body: routeRows(p.id, p.routes, p.finalOutbound, locked: isLocked),
      );
    }

    return ExpressivePage(
      title: l10n.settingsRoutingTitle,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        ExpressiveSpacing.large,
        ExpressiveSpacing.none,
        ExpressiveSpacing.large,
        _fabClearance,
      ),
      floatingActionButton: TvFocus.fab(
        (_) => FloatingActionButton.extended(
          onPressed: () => unawaited(_showProfileSheet(context, ref)),
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.routingProfileNew),
        ),
      ),
      actions: [
        IconButton(
          tooltip: l10n.routingCheatSheetTitle,
          icon: const Icon(Icons.help_outline_rounded),
          onPressed: () => _showRoutingCheatSheet(context, l10n),
        ),
      ],
      children: [
        if (tunnelActive)
          ExpressiveNotice(
            color: AppTheme.orange(context),
            icon: Icons.info_outline_rounded,
            text: l10n.splitTunnelingReconnectHint,
            action: TextButton(
              onPressed: vpnStatus == VpnStatus.connected
                  ? () => unawaited(_reconnect(ref))
                  : null,
              child: Text(l10n.settingsRoutingReconnect),
            ),
          ),
        if (tunnelActive && hint)
          const SizedBox(height: ExpressiveSpacing.medium),
        if (hint)
          ExpressiveNotice(
            color: Theme.of(context).colorScheme.primary,
            icon: Icons.info_outline_rounded,
            text: l10n.routesHint,
            action: TextButton(
              onPressed: () =>
                  unawaited(ref.read(routesHintProvider.notifier).dismiss()),
              child: Text(l10n.routesHintDismiss),
            ),
          ),
        if (tunnelActive || hint)
          const SizedBox(height: ExpressiveSpacing.large),
        if (loaded) ...[
          if (showProviderRules || showProviderDns) ...[
            ExpressiveGroup(children: [
              _ProviderOverridesTile(
                rules: showProviderRules ? ignoreProviderRules : null,
                dns: showProviderDns ? ignoreProviderDns : null,
                onRules: (v) => unawaited(_saveProviderOverrides(ref, rules: v)),
                onDns: (v) => unawaited(_saveProviderOverrides(ref, dns: v)),
              ),
            ]),
            const SizedBox(height: ExpressiveSpacing.large),
          ],
          KeyedSubtree(
            key: _mainKey,
            child: _ProfileCard(
              key: const ValueKey('routing-profile-main'),
              title: l10n.routingProfileMain,
              // счёт своей строкой: «Все» и «Остальные» разной длины, и переключатель
              // чужого профиля перекидывал хвост строки туда-обратно
              summary: mainExpanded
                  ? mainScope
                  : '$mainScope\n${l10n.routingProfileRouteCount(routes.length)}',
              expanded: mainExpanded,
              onToggle: () => _toggleProfile(ref, _mainProfileKey),
              menu: IconButton(
                tooltip: l10n.subscriptionsShareButton,
                icon: Icon(
                  Icons.qr_code_2_rounded,
                  size: 20,
                  color: AppTheme.textLight(context),
                ),
                onPressed: () => _showRoutingShareSheet(
                  context,
                  name: l10n.routingProfileMain,
                  finalOutbound: mainFinal,
                  routes: routes,
                ),
              ),
              body: routeRows(null, routes, mainFinal),
            ),
          ),
          for (final p in profiles)
            if (p.id == widget.focusProfileId)
              KeyedSubtree(key: _focusKey, child: profileCard(p))
            else
              profileCard(p),
        ],
      ],
    );
  }

  static Future<void> _saveProviderOverrides(
    WidgetRef ref, {
    bool? rules,
    bool? dns,
  }) async {
    final notifier = ref.read(settingsNotifierProvider.notifier);
    final settings = ref.read(settingsNotifierProvider).value ?? const AppSettings();
    await notifier.save(
      settings.copyWith(ignoreProviderRules: rules, ignoreProviderDns: dns),
    );
  }

  static Future<void> _reconnect(WidgetRef ref) async {
    try {
      await ref.read(vpnStateProvider.notifier).reconnectToActiveServer();
    } catch (_) {}
  }

  static void _openRouteEditor(
    BuildContext context,
    TrafficRoute? route,
    String? profileId,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _RouteEditorScreen(initial: route, profileId: profileId),
      ),
    );
  }

  static void _showRouteEntries(BuildContext context, TrafficRoute route) {
    final l10n = AppLocalizations.of(context)!;
    unawaited(_showChoiceSheet<void>(
      context,
      title: switch (route.target) {
        RouteTarget.direct => l10n.routeToDirect,
        RouteTarget.block => l10n.routeToBlock,
        _ => l10n.routeToVpn,
      },
      children: (ctx) => [
        ExpressiveGroup(children: [
          for (final e in routingEntries(route.sites))
            ExpressiveGroupTile(
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  ltrIsolate(e),
                  style: Theme.of(ctx)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: AppTheme.text(ctx)),
                ),
              ),
            ),
        ]),
      ],
    ));
  }

  static Future<void> _pickFinalTarget(
    BuildContext context,
    WidgetRef ref,
    String? profileId,
    RouteTarget current,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final picked = await _showTargetSheet(
      context,
      title: l10n.settingsRoutingFinalTitle,
      current: current,
    );
    if (picked == null) return;
    await _saveFinalOutbound(ref, profileId, _finalOutboundOf(picked));
  }
}

class _RouteRowContent extends StatelessWidget {
  const _RouteRowContent({
    required this.badge,
    required this.title,
    required this.subtitle,
    this.chevron = true,
    this.dimmed = false,
    this.note,
  });

  final Widget badge;
  final Widget title;
  final Widget subtitle;
  final bool chevron;

  // своей строкой: в хвосте подписи её обрезал бы длинный список сайтов
  final Widget? note;

  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final row = Row(
      children: [
        badge,
        const SizedBox(width: ExpressiveSpacing.large),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              DefaultTextStyle.merge(
                style: textTheme.titleMedium
                    ?.copyWith(color: AppTheme.text(context)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: title,
              ),
              DefaultTextStyle.merge(
                style: textTheme.bodyMedium
                    ?.copyWith(color: AppTheme.textLight(context)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                child: subtitle,
              ),
              if (note != null)
                DefaultTextStyle.merge(
                  style: textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  child: note!,
                ),
            ],
          ),
        ),
        if (chevron)
          Icon(Icons.chevron_right_rounded, color: AppTheme.textLight(context)),
      ],
    );
    return dimmed ? Opacity(opacity: 0.5, child: row) : row;
  }
}

// куда стоит первым, чтобы при нехватке места обрезался список сайтов, а не сервер
class _RouteTile extends StatelessWidget {
  const _RouteTile({
    required this.route,
    required this.servers,
    required this.iconCache,
    required this.installed,
    required this.issue,
    required this.onTap,
    this.background,
  });

  final TrafficRoute route;
  final List<ServerItem> servers;
  final AppIconCache iconCache;
  final List<AppInfo> installed;
  final String? issue;
  final VoidCallback onTap;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = _targetColor(context, route.target);
    final title = route.allApps
        ? _contentLabel(l10n, route)
        : route.apps.map((a) => _appLabel(a, installed)).join(', ');
    final details = [
      if (!route.allApps) _contentLabel(l10n, route),
      ?_protocolShort(l10n, route),
      if (!route.enabled) l10n.routeDisabledShort,
    ];
    return ExpressiveGroupTile(
      onTap: onTap,
      color: background,
      child: _RouteRowContent(
        dimmed: !route.enabled,
        badge: route.allApps
            ? ExpressiveIconBadge(icon: _contentIcon(route))
            : _appsBadge(route.apps, iconCache, installed),
        title: Text(title),
        note: issue == null ? null : Text(issue!),
        subtitle: Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: '→ '),
              // флаг нужен: имя Германия у трёх провайдеров одинаковое
              if (_routeServer(route, servers) case final server?)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 4),
                    child: ServerAvatar(
                      flag: server.flag,
                      protocol: server.protocol,
                      size: 18,
                    ),
                  ),
                ),
              TextSpan(
                text: _targetLabel(l10n, route, servers),
                style: TextStyle(color: color),
              ),
              for (final d in details) TextSpan(text: ' · $d'),
            ],
          ),
        ),
      ),
    );
  }
}

// маршруты всех приложений с переносом: зажать и тащить. своего Scrollable у списка нет нарочно,
// SliverReorderableList берёт прокрутку страницы и листает её у края экрана
class _ReorderableRouteGroup extends StatefulWidget {
  const _ReorderableRouteGroup({
    required this.routes,
    required this.tile,
    required this.fixed,
    required this.onMove,
  });

  final List<TrafficRoute> routes;
  final Widget Function(TrafficRoute route) tile;

  // «Всё остальное» и «Новый маршрут»: стоят под списком и не переносятся
  final List<Widget> fixed;

  final void Function(int from, int to) onMove;

  @override
  State<_ReorderableRouteGroup> createState() => _ReorderableRouteGroupState();
}

class _ReorderableRouteGroupState extends State<_ReorderableRouteGroup> {
  static const _spacing = 2.0;

  // поднятая строка выбывает из группы до конца переноса: иначе вставшая наверх оставалась с мелкими верхними углами
  int? _dragging;

  void _endDrag() {
    if (_dragging != null) setState(() => _dragging = null);
  }

  @override
  Widget build(BuildContext context) {
    final routes = widget.routes;
    final fixed = widget.fixed;
    final tile = widget.tile;
    final dragging = _dragging;
    final count = routes.length + fixed.length - (dragging == null ? 0 : 1);
    int place(int i) => dragging != null && i > dragging ? i - 1 : i;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ReorderZoomFix(
          builder: (context, fix) => ShrinkWrappingViewport(
            offset: ViewportOffset.zero(),
            slivers: [
              SliverReorderableList(
                itemCount: routes.length,
                onReorderStart: (i) => setState(() => _dragging = i),
                // onReorderItem зовётся только при смене места, а без неё строка просто ложится обратно
                onReorderEnd: (insert) {
                  final from = _dragging;
                  if (from == null || insert == from || insert == from + 1) {
                    _endDrag();
                  }
                },
                onReorderItem: (from, to) {
                  _endDrag();
                  widget.onMove(from, to);
                },
                // поднятая строка собирается заново: у неё скруглены все углы, а не как у места в группе
                proxyDecorator: (child, index, animation) => fix(
                  AnimatedBuilder(
                    animation: animation,
                    builder: (context, child) => Transform.scale(
                      scale: 1 + 0.02 * Curves.easeOut.transform(animation.value),
                      child: child,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: _spacing),
                      child: Material(
                        color: Colors.transparent,
                        elevation: 8,
                        shadowColor: Colors.black26,
                        borderRadius:
                            ExpressiveShape.radius(ExpressiveShape.extraLarge),
                        child: ExpressiveGroupSegment(
                          index: 0,
                          count: 1,
                          child: tile(routes[index]),
                        ),
                      ),
                    ),
                  ),
                  animation,
                ),
                itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
                  key: ValueKey('route-row-${routes[i].id}'),
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: _spacing),
                    child: ExpressiveGroupSegment(
                      index: place(i),
                      count: count,
                      child: tile(routes[i]),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < fixed.length; i++) ...[
          if (i > 0) const SizedBox(height: _spacing),
          ExpressiveGroupSegment(
            index: place(routes.length + i),
            count: count,
            child: fixed[i],
          ),
        ],
      ],
    );
  }
}

class _FinalRouteTile extends StatelessWidget {
  const _FinalRouteTile({
    required this.target,
    required this.onTap,
    this.background,
  });

  final RouteTarget target;
  final VoidCallback? onTap;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return ExpressiveGroupTile(
      onTap: onTap,
      color: background,
      child: _RouteRowContent(
        badge: ExpressiveIconBadge(
          icon: Icons.alt_route_rounded,
          background: scheme.surfaceContainerHighest,
          foreground: scheme.onSurfaceVariant,
        ),
        title: Text(l10n.settingsRoutingFinalTitle),
        chevron: onTap != null,
        subtitle: Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: '→ '),
              TextSpan(
                text: switch (target) {
                  RouteTarget.direct => l10n.routeToDirect,
                  RouteTarget.block => l10n.routeToBlock,
                  _ => l10n.routeToVpn,
                },
                style: TextStyle(color: _targetColor(context, target)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<T?> _showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<Widget> Function(BuildContext sheetContext) children,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  child: Text(
                    title,
                    style: theme.textTheme
                        .emphasized(theme.textTheme.titleMedium)
                        ?.copyWith(color: AppTheme.text(ctx)),
                  ),
                ),
                ...children(ctx),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Future<RouteTarget?> _showTargetSheet(
  BuildContext context, {
  required String title,
  required RouteTarget current,
  Widget Function(BuildContext sheetContext)? serverTile,
}) {
  final l10n = AppLocalizations.of(context)!;
  return _showChoiceSheet<RouteTarget>(
    context,
    title: title,
    children: (ctx) => [
      ExpressiveGroup(
        children: [
          for (final (target, name, subtitle) in [
            (RouteTarget.vpn, l10n.settingsRoutingProxyTitle,
                l10n.routeWhereVpnSubtitle),
            (RouteTarget.direct, l10n.settingsRoutingDirectTitle,
                l10n.routeWhereDirectSubtitle),
            (RouteTarget.block, l10n.settingsRoutingBlockTitle,
                l10n.routeWhereBlockSubtitle),
          ])
            ExpressiveActionTile(
              icon: _targetIcon(target),
              title: name,
              subtitle: subtitle,
              selected: current == target,
              onTap: () => Navigator.pop(ctx, target),
            ),
        ],
      ),
      if (serverTile != null) ...[
        ExpressiveSectionHeader(l10n.routeWhereServers),
        ExpressiveGroup(children: [serverTile(ctx)]),
      ],
    ],
  );
}

void _showRoutingCheatSheet(BuildContext context, AppLocalizations l10n) {
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
              style: Theme.of(ctx)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: AppTheme.text(ctx)),
            ),
            const SizedBox(height: 10),
            ..._cheatLines(ctx, l10n.routingCheatSheetBody),
          ],
        ),
      ),
    ),
  );
}

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

// одна плитка на всё, что можно не брать у провайдера: две строки с подписями занимали пол экрана
class _ProviderOverridesTile extends StatelessWidget {
  const _ProviderOverridesTile({
    required this.rules,
    required this.dns,
    required this.onRules,
    required this.onDns,
  });

  final bool? rules;
  final bool? dns;
  final ValueChanged<bool> onRules;
  final ValueChanged<bool> onDns;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final on = (rules ?? false) || (dns ?? false);
    return ExpressiveGroupTile(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          ExpressiveIconBadge(
            icon: Icons.playlist_remove_rounded,
            accent: on ? ExpressiveAccent.tertiary : ExpressiveAccent.secondary,
          ),
          const SizedBox(width: ExpressiveSpacing.large),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.routingIgnoreFromProvider,
                  style: textTheme.titleMedium
                      ?.copyWith(color: AppTheme.text(context)),
                ),
                const SizedBox(height: ExpressiveSpacing.small),
                Wrap(
                  spacing: ExpressiveSpacing.small,
                  runSpacing: ExpressiveSpacing.small,
                  children: [
                    if (rules case final value?)
                      Tooltip(
                        message: l10n.routingIgnoreProviderRulesHint,
                        child: ExpressiveToggleButton(
                          selected: value,
                          label: l10n.routingIgnoreProviderRulesChip,
                          onPressed: () => onRules(!value),
                        ),
                      ),
                    if (dns case final value?)
                      Tooltip(
                        message: l10n.routingIgnoreProviderDnsHint,
                        child: ExpressiveToggleButton(
                          selected: value,
                          label: l10n.routingIgnoreProviderDnsChip,
                          onPressed: () => onDns(!value),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
