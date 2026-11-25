part of '../settings_tab.dart';

class _ConnectionsScreen extends ConsumerStatefulWidget {
  const _ConnectionsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<_ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends ConsumerState<_ConnectionsScreen> {
  ConnectionsSnapshot _snapshot = ConnectionsSnapshot.empty;
  bool _loading = true;
  bool _paused = false;
  String _filter = '';
  Timer? _pollTimer;

  bool _refreshing = false;
  final _filterCtrl = TextEditingController();

  ValueNotifier<ConnectionEntry>? _opened;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_refresh()),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _filterCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_paused || _refreshing) return;
    _refreshing = true;
    try {
      final snapshot = await ConnectionsService.snapshot();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
      _syncOpened(snapshot);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _snapshot = ConnectionsSnapshot(
          entries: const [],
          source: ConnectionsSource.unavailable,
          note: '$e',
        );
        _loading = false;
      });
    } finally {
      _refreshing = false;
    }
  }

  List<ConnectionEntry> get _visible {
    final needle = _filter.trim().toLowerCase();
    if (needle.isEmpty) return _snapshot.entries;
    return _snapshot.entries
        .where((e) => e.searchHaystack.contains(needle))
        .toList();
  }

  Future<void> _enableInfoLogs() async {
    final settings = ref.read(settingsNotifierProvider).value;
    if (settings == null) return;
    await ref
        .read(settingsNotifierProvider.notifier)
        .save(
          settings.copyWith(
            xrayCore: settings.xrayCore.copyWith(logLevel: 'info'),
          ),
        );
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    AppSnack.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.connectionsRuleHintApplied)));
  }

  void _togglePause() => setState(() => _paused = !_paused);

  void _refreshAndResume() {
    setState(() => _paused = false);
    unawaited(_refresh());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    ref.listen(vpnStateProvider.select((s) => s.value?.status), (_, _) {
      ConnectionsService.resetTracker();
    });
    final entries = _visible;
    final logLevel = ref.watch(
      settingsNotifierProvider.select(
        (a) => a.value?.xrayCore.logLevel ?? 'warning',
      ),
    );
    final showLogLevelHint =
        !_snapshot.ruleInfoAvailable &&
        _snapshot.source != ConnectionsSource.unavailable &&
        logLevel != 'info' &&
        logLevel != 'debug';
    final showAppNamesHint = Platform.isAndroid && !_snapshot.appNamesAvailable;
    final split = ref.watch(splitTunnelingProvider);
    final showSplitNote =
        Platform.isAndroid &&
        (split.excludePackages.isNotEmpty || split.includePackages.isNotEmpty);

    final scaffold = Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: ExpressiveScrolledUnderBar(
        builder: (context, background) => AppBar(
          backgroundColor: background,
          title: Text(l10n.settingsConnectionsTitle),
          actions: [
            IconButton(
              tooltip: _paused ? l10n.connectionsResume : l10n.connectionsPause,
              icon: Icon(
                _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              ),
              onPressed: _togglePause,
            ),
            IconButton(
              tooltip: l10n.settingsRefresh,
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _refreshAndResume,
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: ShapeLoadingIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: Column(
                    children: [
                      _statusBar(context, l10n, entries.length),
                      if (showLogLevelHint) ...[
                        const SizedBox(height: 10),
                        _logLevelHint(context, l10n),
                      ],
                      if (showAppNamesHint) ...[
                        const SizedBox(height: 10),
                        _noticeBox(
                          context,
                          Icons.apps_rounded,
                          l10n.connectionsAppNamesHint,
                        ),
                      ],
                      if (showSplitNote) ...[
                        const SizedBox(height: 10),
                        _noticeBox(
                          context,
                          Icons.call_split_rounded,
                          l10n.connectionsSplitTunnelNote,
                          color: AppTheme.textLight(context),
                        ),
                      ],
                      const SizedBox(height: 10),
                      TextField(
                        controller: _filterCtrl,
                        textDirection: technicalInputDirection,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.text(context),
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 18,
                          ),
                          hintText: l10n.connectionsFilterHint,
                          hintStyle: TextStyle(
                            color: AppTheme.textLight(context),
                          ),
                          filled: true,
                          fillColor: AppTheme.inset(context),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              ExpressiveShape.medium,
                            ),
                            borderSide: BorderSide(
                              color: AppTheme.divider(context),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              ExpressiveShape.medium,
                            ),
                            borderSide: BorderSide(
                              color: AppTheme.divider(context),
                            ),
                          ),
                          suffixIcon: _filter.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(
                                    Icons.clear_rounded,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    _filterCtrl.clear();
                                    setState(() => _filter = '');
                                  },
                                ),
                        ),
                        onChanged: (v) => setState(() => _filter = v),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: entries.isEmpty
                      ? _emptyState(context, l10n)
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                          itemCount: entries.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => ConnectionTile(
                            entry: entries[i],
                            showProcess:
                                ConnectionsService.supportsProcessNames,
                            ruleInfoAvailable: _snapshot.ruleInfoAvailable,
                            onTap: () => _openDetails(entries[i]),
                          ),
                        ),
                ),
              ],
            ),
    );
    if (widget.embedded) {
      return ColoredBox(
        color: AppTheme.bg(context),
        child: scaffold.body ?? const SizedBox.shrink(),
      );
    }
    return scaffold;
  }

  // строка живёт под ключом группы: одиночная, обзаведясь соседом, меняет id на group:
  void _syncOpened(ConnectionsSnapshot snapshot) {
    final opened = _opened;
    if (opened == null) return;
    final key = opened.value.groupKey;
    final fresh = snapshot.entries.where((e) => e.groupKey == key).firstOrNull;
    if (fresh != null) opened.value = fresh;
  }

  void _openDetails(ConnectionEntry entry) {
    final l10n = AppLocalizations.of(context)!;
    final opened = ValueNotifier(entry);
    _opened = opened;
    final snapshot = _snapshot;
    final servers = ref.read(serversProvider);
    final active = servers.activeServer;
    final profiles =
        ref.read(routingProfilesProvider).value ?? const <RoutingProfile>[];
    // те же маршруты, что взяло подключение
    final routes =
        (active == null ? null : profileForServer(profiles, active)?.routes) ??
        ref.read(routesProvider).value ??
        const <TrafficRoute>[];
    final iconCache = ref.read(appIconCacheProvider);
    final installed = Platform.isAndroid && entry.process.isNotEmpty
        ? ref.read(installedAppsProvider(true).future)
        : Future.value(const <AppInfo>[]);
    final showProcess = ConnectionsService.supportsProcessNames;
    final app = showProcess ? _appField(entry, const [], iconCache) : null;

    final insight = _insight(
      l10n,
      entry,
      routes: routes,
      servers: servers,
      installed: installed,
      iconCache: iconCache,
      showProcess: showProcess,
      ruleInfoAvailable: snapshot.ruleInfoAvailable,
    );

    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => ConnectionDetailsSheet(
          entry: opened,
          live: snapshot.source == ConnectionsSource.coreApi,
          livenessKnown: snapshot.ruleInfoAvailable,
          insight: insight,
          pendingLists: [
            for (final preset in RoutingPresets.all)
              _presetName(l10n, preset.id),
          ],
          app: app,
          rule: _ruleField(
            l10n,
            entry,
            null,
            ruleInfoAvailable: snapshot.ruleInfoAvailable,
          ),
          exit: _exitField(l10n, entry, servers, null),
        ),
      ).whenComplete(() {
        if (identical(_opened, opened)) _opened = null;
      }),
    );
  }

  Future<ConnectionInsightView> _insight(
    AppLocalizations l10n,
    ConnectionEntry entry, {
    required List<TrafficRoute> routes,
    required ServersState servers,
    required Future<List<AppInfo>> installed,
    required AppIconCache iconCache,
    required bool showProcess,
    required bool ruleInfoAvailable,
  }) async {
    final appsLoad = installed.catchError((Object e) {
      AppLogger.instance.warn('Connection details: installed apps: $e');
      return const <AppInfo>[];
    });
    Future<ConnectionInsight?> inspect(List<AppInfo> apps) async {
      // на Android владелец приходит названием, а маршрут хранит пакет
      final packages = {
        for (final a in apps)
          if (a.appName == entry.process) a.packageName,
      };
      try {
        return await inspectConnection(
          entry: entry,
          routes: routes,
          ruleInfoAvailable: ruleInfoAvailable,
          geoDir: await GeoAssetService.geoDir(),
          appMatch: {
            for (final r in routes)
              if (!r.allApps)
                r.id: routeAppsMatch(
                  r.apps,
                  process: entry.process,
                  packages: packages,
                ),
          },
        );
      } catch (e) {
        AppLogger.instance.warn('Connection details: $e');
        return null;
      }
    }

    final List<AppInfo> apps;
    final ConnectionInsight? result;
    if (routes.any((r) => r.enabled && !r.allApps)) {
      apps = await appsLoad;
      result = await inspect(apps);
    } else {
      (apps, result) = await (appsLoad, inspect(const [])).wait;
    }
    final explanation = result?.route ?? const Unexplained();
    final lists = result?.lists ?? const <String, ListMatch>{};
    final presetRoutes = {
      for (final r in routes)
        if (r.enabled && r.content == RouteContent.preset) r.presetId,
    };
    return ConnectionInsightView(
      app: showProcess ? _appField(entry, apps, iconCache) : null,
      rule: _ruleField(
        l10n,
        entry,
        explanation,
        ruleInfoAvailable: ruleInfoAvailable,
        installed: apps,
      ),
      exit: _exitField(l10n, entry, servers, explanation),
      lists: [
        for (final preset in RoutingPresets.all)
          ConnectionListLine(
            _presetName(l10n, preset.id),
            lists[preset.id] ?? ListMatch.unknown,
            note: switch (lists[preset.id]) {
              ListMatch.hit when presetRoutes.contains(preset.id) =>
                l10n.connectionsDetailsListRouteOn,
              ListMatch.unknown || null => l10n.connectionsDetailsListUnknown,
              _ => null,
            },
          ),
      ],
    );
  }

  ConnectionField? _appField(
    ConnectionEntry entry,
    List<AppInfo> installed,
    AppIconCache iconCache,
  ) {
    final name = ConnectionTile.processName(entry.process);
    if (name.isEmpty) return null;
    final app = installed.where((a) => a.appName == entry.process).firstOrNull;
    final path = isProcessPathEntry(entry.process) ? entry.process : null;
    if (Platform.isAndroid && app == null) return ConnectionField(name);
    return ConnectionField(
      name,
      note: app?.packageName ?? (path == name ? null : path),
      leading: SizedBox.square(
        dimension: 16,
        child: FittedBox(
          child: AppIconView(
            iconBase64: app?.iconBase64,
            appName: name,
            iconPath: path,
            cache: iconCache,
          ),
        ),
      ),
    );
  }

  ConnectionField? _ruleField(
    AppLocalizations l10n,
    ConnectionEntry entry,
    RouteExplanation? explanation, {
    required bool ruleInfoAvailable,
    List<AppInfo> installed = const [],
  }) {
    switch (explanation) {
      case ByFinal():
        return ConnectionField(
          l10n.settingsRoutingFinalTitle,
          note: l10n.connectionsDetailsRouteFinal,
        );
      case ByRoute(:final route) when entry.rule.isNotEmpty:
        final content = _contentLabel(l10n, route);
        final name = route.allApps
            ? content
            : '${route.apps.map((a) => _appLabel(a, installed)).join(', ')} · $content';
        return ConnectionField(
          entry.rule,
          mono: true,
          note: l10n.connectionsDetailsRouteNamed(name),
        );
      default:
        final label = ConnectionTile.ruleLabel(
          l10n,
          entry,
          ruleInfoAvailable: ruleInfoAvailable,
        );
        if (label.isEmpty) return null;
        return ConnectionField(label, mono: label == entry.rule);
    }
  }

  ConnectionField? _exitField(
    AppLocalizations l10n,
    ConnectionEntry entry,
    ServersState servers,
    RouteExplanation? explanation,
  ) {
    final out = entry.outbound;
    switch (entry.verdict) {
      case ConnectionVerdict.direct:
        return ConnectionField(
          out,
          mono: true,
          note: l10n.connectionsDetailsExitDirect,
        );
      case ConnectionVerdict.blocked:
        return ConnectionField(
          out,
          mono: true,
          note: l10n.connectionsDetailsExitBlock,
        );
      case ConnectionVerdict.proxied:
        // proxy у обоих ядер ведёт на сервер подключения, а keq-srv-N на свой сервер маршрута (routeServerOutbounds)
        final routeServer = switch (explanation) {
          ByRoute(:final route)
              when route.target == RouteTarget.server &&
                  out.startsWith('keq-srv-') =>
            servers.byId[route.serverId],
          _ => null,
        };
        final server =
            routeServer ??
            (out == MihomoConfigGen.proxyName ? servers.activeServer : null);
        if (server == null) {
          return out.isEmpty ? null : ConnectionField(out, mono: true);
        }
        final protocol = server.protocol.toUpperCase();
        return ConnectionField(
          ServerNameUtils.cleanDisplayName(server.displayName),
          leading: ServerAvatar(
            flag: server.flag,
            protocol: server.protocol,
            size: 16,
          ),
          note: routeServer != null
              ? l10n.connectionsDetailsExitRoute(protocol)
              : l10n.connectionsDetailsExitActive(protocol),
        );
      case ConnectionVerdict.viaCore:
      case ConnectionVerdict.unknown:
        return out.isEmpty ? null : ConnectionField(out, mono: true);
    }
  }

  Widget _statusBar(BuildContext context, AppLocalizations l10n, int shown) {
    final (label, color) = switch (_snapshot.source) {
      ConnectionsSource.coreApi => (
        l10n.connectionsSourceApi,
        AppTheme.green(context),
      ),
      ConnectionsSource.coreLog => (
        l10n.connectionsSourceLog,
        AppTheme.accent(context),
      ),
      ConnectionsSource.unavailable => (
        l10n.connectionsSourceUnavailable,
        AppTheme.textLight(context),
      ),
    };
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(ExpressiveShape.small),
          ),
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: color),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.connectionsCount(shown),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppTheme.textLight(context)),
          ),
        ),
        if (_paused)
          Text(
            l10n.connectionsPaused,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppTheme.orange(context)),
          ),
      ],
    );
  }

  Widget _logLevelHint(BuildContext context, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.orange(context).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ExpressiveShape.medium),
      ),
      child: Row(
        children: [
          Icon(Icons.rule_rounded, size: 16, color: AppTheme.orange(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.connectionsRuleHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                height: 1.35,
                color: AppTheme.text(context),
              ),
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: _enableInfoLogs,
            child: Text(l10n.connectionsRuleHintAction),
          ),
        ],
      ),
    );
  }

  Widget _noticeBox(
    BuildContext context,
    IconData icon,
    String text, {
    Color? color,
  }) {
    final tint = color ?? AppTheme.orange(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ExpressiveShape.medium),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: tint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
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

  Widget _emptyState(BuildContext context, AppLocalizations l10n) {
    final note = _snapshot.note;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lan_rounded,
              size: 40,
              color: AppTheme.textLight(context),
            ),
            const SizedBox(height: 12),
            Text(
              _snapshot.source == ConnectionsSource.unavailable
                  ? l10n.connectionsUnavailable
                  : l10n.connectionsEmpty,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppTheme.text(context)),
            ),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                note,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: AppTheme.textLight(context),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
