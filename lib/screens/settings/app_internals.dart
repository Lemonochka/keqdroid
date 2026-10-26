part of '../settings_tab.dart';

// только статус: в состоянии раз в секунду едет телеметрия, а пересборка перечитывает бинари ядер
final _appInternalsProvider = FutureProvider.autoDispose<AppInternals>((
  ref,
) async {
  final settings = await ref.watch(settingsNotifierProvider.future);
  ref.watch(vpnStateProvider.select((state) => state.value?.status));
  return AppInternalsService.collect(
    settings: settings,
    state: ref.read(vpnStateProvider).value,
  );
});

class _AppInternalsScreen extends ConsumerWidget {
  const _AppInternalsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final internals = ref.watch(_appInternalsProvider);

    return ExpressivePage(
      title: l10n.settingsInternalsTitle,
      physics: const ClampingScrollPhysics(),
      actions: [
        IconButton(
          tooltip: l10n.settingsInternalsCopyAll,
          icon: const Icon(Icons.copy_all_rounded),
          onPressed: internals.value == null
              ? null
              : () => _copyReport(context, l10n, internals.value!),
        ),
      ],
      children: switch (internals) {
        AsyncData(:final value) => _sections(context, ref, l10n, value),
        AsyncError(:final error) => [
            ExpressiveNotice(
              color: Theme.of(context).colorScheme.error,
              icon: Icons.error_outline_rounded,
              text: friendlyError(error, context),
            ),
          ],
        _ => const [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: ShapeLoadingIndicator()),
            ),
          ],
      },
    );
  }

  List<Widget> _sections(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    AppInternals data,
  ) {
    return [
      ExpressiveSectionHeader(l10n.settingsInternalsBuild),
      ExpressiveGroup(children: _buildRows(l10n, data.build)),

      if (Platform.isAndroid) ...[
        ExpressiveSectionHeader(l10n.settingsTunnelModeSection),
        const ExpressiveGroup(
          children: [
            _TunnelModeTile(mode: ConnectionMode.tun),
            _TunnelModeTile(mode: ConnectionMode.proxy),
            _ProxyAuthTile(),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            l10n.settingsTunnelModeHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textLight(context),
                ),
          ),
        ),
      ],

      ExpressiveSectionHeader(l10n.settingsInternalsCores),
      if (data.cores.isEmpty)
        ExpressiveGroup(
          children: [
            _InternalsRow(label: l10n.settingsInternalsNoCores, value: ''),
          ],
        )
      else ...[
        ExpressiveGroup(
          children: [
            for (final core in data.cores)
              if (_selectableCore(core) case final vpnCore?)
                _SelectableCoreTile(core: core, value: vpnCore)
              else
                _CoreTile(core: core),
          ],
        ),
        if (mihomoShipsHere)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              l10n.settingsCoreHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textLight(context),
                  ),
            ),
          ),
        if (_coreMismatch(ref) case final skip?) ...[
          const SizedBox(height: 8),
          ExpressiveNotice(
            color: AppTheme.orange(context),
            icon: Icons.info_outline_rounded,
            text: _coreMismatchText(l10n, skip),
          ),
        ],
      ],

      ExpressiveSectionHeader(l10n.settingsInternalsGeo),
      ExpressiveGroup(
        children: [
          for (final base in data.geoBases) _GeoTile(base: base),
          if (GeoBaseDownloader.isSupported && _geoipIsTrimmed(data.geoBases))
            const _GeoDownloadTile(),
        ],
      ),

      ExpressiveSectionHeader(l10n.settingsInternalsSession),
      ExpressiveGroup(children: _sessionRows(context, l10n, data.session)),

      ExpressiveSectionHeader(l10n.settingsAdvancedGroupDiagnostics),
      ExpressiveGroup(
        children: [
          _SettingsCard(
            title: l10n.appLogTitle,
            subtitle: l10n.appLogSubtitle,
            icon: Icons.receipt_long_rounded,
            accent: ExpressiveAccent.tertiary,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const _AppLogScreen()),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _sessionRows(
    BuildContext context,
    AppLocalizations l10n,
    SessionInfo session,
  ) {
    final dash = l10n.settingsInternalsUnavailable;
    return [
      _InternalsRow(
        label: l10n.settingsInternalsStatus,
        value: _statusLabel(l10n, session.status),
        accent: session.isActive,
      ),
      _InternalsRow(
        label: l10n.settingsInternalsEngine,
        value: session.engine,
      ),
      if (session.mode != null)
        _InternalsRow(
          label: l10n.settingsInternalsMode,
          value: session.mode == ConnectionMode.tun ? 'TUN' : l10n.trayModeProxy,
        ),
      _InternalsRow(
        label: l10n.settingsInternalsPorts,
        value: 'SOCKS ${session.socksPort} · HTTP ${session.httpPort}',
      ),
      if (session.clashApiPort != null)
        _InternalsRow(
          label: l10n.settingsInternalsClashPort,
          value: '${session.clashApiPort}',
        ),
      _InternalsRow(
        label: l10n.settingsInternalsUptime,
        value: session.uptime == null
            ? dash
            : _formatDuration(session.uptime!),
      ),
      _InternalsRow(
        label: l10n.settingsInternalsCorePids,
        value: session.corePids.isEmpty
            ? dash
            : session.corePids.entries
                .map((e) => '${e.key} ${e.value}')
                .join('\n'),
      ),
      if (session.elevated != null)
        _InternalsRow(
          label: l10n.settingsInternalsElevated,
          value: session.elevated!
              ? l10n.settingsInternalsYes
              : l10n.settingsInternalsNo,
        ),
    ];
  }

  List<Widget> _buildRows(AppLocalizations l10n, BuildInfo build) {
    return [
      _VersionRow(
        label: l10n.settingsInternalsAppVersion,
        value: ltrIsolate('${build.appVersion} (${build.buildNumber})'),
      ),
      _InternalsRow(
        label: l10n.settingsInternalsPackage,
        value: build.packageName,
      ),
      _InternalsRow(
        label: l10n.settingsInternalsOs,
        value: build.osVersion,
      ),
      _InternalsRow(label: l10n.settingsInternalsAbi, value: build.abi),
      _InternalsRow(
        label: l10n.settingsInternalsDart,
        value: build.dartVersion,
      ),
      _InternalsRow(
        label: l10n.settingsInternalsBuildMode,
        value: build.releaseMode ? 'release' : 'debug',
      ),
      const _KeqtrisBestRow(),
    ];
  }

  Future<void> _copyReport(
    BuildContext context,
    AppLocalizations l10n,
    AppInternals data,
  ) async {
    await Clipboard.setData(
      ClipboardData(text: AppInternalsService.report(data)),
    );
    if (!context.mounted) return;
    AppSnack.of(context).showSnackBar(
      SnackBar(content: Text(l10n.settingsInternalsCopied)),
    );
  }

  static String _statusLabel(AppLocalizations l10n, VpnStatus status) {
    return switch (status) {
      VpnStatus.connected => l10n.trayStatusConnected,
      VpnStatus.connecting => l10n.vpnConnecting,
      VpnStatus.disconnecting => l10n.vpnDisconnecting,
      VpnStatus.error => l10n.settingsInternalsStatusError,
      VpnStatus.disconnected => l10n.trayStatusDisconnected,
    };
  }
}

class _CoreTile extends StatelessWidget {
  final CoreInfo core;

  final bool? selected;

  final String? subtitle;

  final VoidCallback? onTap;

  const _CoreTile({
    required this.core,
    this.selected,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    final version = core.missing
        ? l10n.settingsInternalsCoreMissing
        : core.version ?? l10n.settingsInternalsVersionFromEngines;

    return ExpressiveGroupTile(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExpressiveIconBadge(
                icon: Icons.memory_rounded,
                accent: core.missing
                    ? ExpressiveAccent.secondary
                    : ExpressiveAccent.primary,
              ),
              const SizedBox(width: ExpressiveSpacing.large),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      core.name,
                      style: textTheme.titleMedium?.copyWith(
                        color: AppTheme.text(context),
                      ),
                    ),
                    Text(
                      subtitle ?? _roleLabel(l10n, core.role),
                      style: textTheme.bodySmall?.copyWith(
                        color: AppTheme.textLight(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected != null) ...[
                const SizedBox(width: ExpressiveSpacing.large),
                Icon(
                  selected!
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected!
                      ? AppTheme.accent(context)
                      : AppTheme.textLight(context),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          SelectableText(
            version,
            style: textTheme.bodyMedium?.copyWith(
              color: core.missing || core.version == null
                  ? AppTheme.textLight(context)
                  : AppTheme.accent(context),
            ),
          ),
          if (core.engines.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final engine in core.engines.entries)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: SelectableText(
                  '${engine.key} ${engine.value}',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppTheme.text(context),
                  ),
                ),
              ),
          ],
          if (!core.missing) ...[
            const SizedBox(height: 10),
            Text(
              _fileLine(l10n, core),
              style: textTheme.bodySmall?.copyWith(
                color: AppTheme.textLight(context),
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _fileLine(AppLocalizations l10n, CoreInfo core) {
    final parts = <String>[
      if (core.sizeBytes != null) formatBytes(core.sizeBytes!),
      if (core.modified != null) formatFileDate(core.modified!),
      if (core.goVersion != null) core.goVersion!,
    ];
    // без изоляции в фарси число отрывалось от MiB
    return ltrIsolate(parts.join(' · '));
  }

  static String _roleLabel(AppLocalizations l10n, CoreRole role) =>
      switch (role) {
        CoreRole.core => l10n.settingsInternalsRoleCore,
        CoreRole.proxy => l10n.settingsInternalsRoleProxy,
        CoreRole.tun => l10n.settingsInternalsRoleTun,
      };
}

bool _geoipIsTrimmed(List<GeoBaseInfo> bases) {
  for (final b in bases) {
    if (b.name != 'geoip.dat') continue;
    return !b.missing && b.codeCount < GeoAssetIndex.fullGeoipCodeThreshold;
  }
  return false;
}

class _GeoDownloadTile extends ConsumerStatefulWidget {
  const _GeoDownloadTile();

  @override
  ConsumerState<_GeoDownloadTile> createState() => _GeoDownloadTileState();
}

class _GeoDownloadTileState extends ConsumerState<_GeoDownloadTile> {
  bool _busy = false;
  double _progress = 0;
  String? _error;

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _progress = 0;
      _error = null;
    });
    try {
      await GeoBaseDownloader.install(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      ref.invalidate(_appInternalsProvider);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ExpressiveActionTile(
      icon: Icons.public_rounded,
      title: l10n.settingsInternalsGeoDownload,
      subtitle: _error != null
          ? l10n.settingsInternalsGeoDownloadFailed(_error!)
          : (_busy
              ? '${(_progress * 100).round()}%'
              : l10n.settingsInternalsGeoTrimmedHint),
      accent: ExpressiveAccent.tertiary,
      danger: _error != null,
      onTap: _busy ? () {} : _download,
    );
  }
}

class _GeoTile extends StatelessWidget {
  final GeoBaseInfo base;
  const _GeoTile({required this.base});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (base.missing) {
      return _InternalsRow(
        label: base.name,
        value: l10n.settingsInternalsCoreMissing,
      );
    }
    return _InternalsRow(
      label: base.name,
      value: l10n.settingsInternalsGeoCodes(base.codeCount),
      detail: ltrIsolate([
        if (base.sizeBytes != null) formatBytes(base.sizeBytes!),
        if (base.modified != null) formatFileDate(base.modified!),
      ].join(' · ')),
    );
  }
}

class _ProcessExitRow extends StatelessWidget {
  final ProcessExit exit;
  const _ProcessExitRow({required this.exit});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = exit.time.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return _InternalsRow(
      label: ltrIsolate('${formatFileDate(t)} ${two(t.hour)}:${two(t.minute)}'),
      value: _causeLabel(l10n, exit.cause),
      accent: exit.vpnWasOn,
      detail: [
        if (exit.vpnWasOn) l10n.settingsInternalsExitVpnOn,
        if (exit.description != null) ltrIsolate(exit.description!),
      ].join(' · '),
    );
  }

  static String _causeLabel(AppLocalizations l10n, ProcessExitCause cause) =>
      switch (cause) {
        ProcessExitCause.system => l10n.settingsInternalsExitSystem,
        ProcessExitCause.memory => l10n.settingsInternalsExitMemory,
        ProcessExitCause.crash => l10n.settingsInternalsExitCrash,
        ProcessExitCause.user => l10n.settingsInternalsExitUser,
        ProcessExitCause.userOrUpdate => l10n.settingsInternalsExitUserOrUpdate,
        ProcessExitCause.update => l10n.settingsInternalsExitUpdate,
        ProcessExitCause.self => l10n.settingsInternalsExitSelf,
      };
}

class _KeqtrisBestRow extends ConsumerWidget {
  const _KeqtrisBestRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final best = ref.read(storageProvider).getKeqtrisBest();
    if (best <= 0) return const SizedBox.shrink();
    return _InternalsRow(
      label: switch (Localizations.localeOf(context).languageCode) {
        'ru' => 'Рекорд',
        'de' => 'Rekord',
        'zh' => '最高分',
        'fa' => 'بهترین امتیاز',
        _ => 'Best score',
      },
      value: '$best',
    );
  }
}

class _VersionRow extends ConsumerStatefulWidget {
  const _VersionRow({required this.label, required this.value});

  final String label;
  final String value;

  static const int tapsToOpen = 5;

  @override
  ConsumerState<_VersionRow> createState() => _VersionRowState();
}

class _VersionRowState extends ConsumerState<_VersionRow> {
  static const _forgetAfter = Duration(seconds: 1);

  int _taps = 0;
  DateTime? _lastTap;

  void _onTap() {
    final now = DateTime.now();
    final last = _lastTap;
    _taps = (last == null || now.difference(last) > _forgetAfter) ? 1 : _taps + 1;
    _lastTap = now;
    if (_taps < _VersionRow.tapsToOpen) return;
    _taps = 0;
    _open();
  }

  Future<void> _open() async {
    final storage = ref.read(storageProvider);
    final haptics =
        ref.read(settingsNotifierProvider).value?.hapticFeedback ?? true;
    if (haptics) AppHaptics.selection();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => KeqtrisScreen(
          bestScore: storage.getKeqtrisBest(),
          haptics: haptics,
          labels: _keqtrisLabels(Localizations.localeOf(context).languageCode),
          onGameOver: (score) {
            if (score > storage.getKeqtrisBest()) {
              unawaited(storage.setKeqtrisBest(score));
            }
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: _InternalsRow(label: widget.label, value: widget.value),
    );
  }
}

KeqtrisLabels _keqtrisLabels(String language) => switch (language) {
  'ru' => const KeqtrisLabels(
    score: 'СЧЁТ',
    best: 'РЕКОРД',
    lines: 'ЛИНИИ',
    hold: 'ЗАПАС',
    next: 'ДАЛЕЕ',
    gameOver: 'Партия окончена',
    restart: 'Ещё раз',
    newBest: 'Новый рекорд',
  ),
  _ => const KeqtrisLabels(),
};

class _InternalsRow extends StatelessWidget {
  final String label;
  final String value;
  final String? detail;
  final bool accent;

  const _InternalsRow({
    required this.label,
    required this.value,
    this.detail,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ExpressiveGroupTile(
      child: SizedBox(
        width: double.infinity,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: AppTheme.textLight(context),
            ),
          ),
          if (value.isNotEmpty) ...[
            const SizedBox(height: 2),
            SelectableText(
              value,
              style: textTheme.bodyMedium?.copyWith(
                color: accent
                    ? AppTheme.accent(context)
                    : AppTheme.text(context),
              ),
            ),
          ],
          if (detail != null && detail!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              detail!,
              style: textTheme.bodySmall?.copyWith(
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

VpnCoreSkip? _coreMismatch(WidgetRef ref) {
  final server = ref.watch(serversProvider).activeServer;
  if (server == null) return null;
  final core = ref.watch(
    settingsNotifierProvider.select(
      (a) => a.value?.vpnCore ?? AppSettings.vpnCoreXray,
    ),
  );
  return resolveVpnBackend(
    config: server.config,
    preference: core,
    mihomoAvailable: mihomoShipsHere,
  ).skip;
}

String _coreMismatchText(AppLocalizations l10n, VpnCoreSkip skip) =>
    switch (skip) {
      VpnCoreSkip.customConfig => l10n.settingsCoreSkipCustom,
      VpnCoreSkip.chainXrayOnly => l10n.settingsCoreSkipChainXrayOnly,
      VpnCoreSkip.chainMihomoOnly => l10n.settingsCoreSkipChainMihomoOnly,
      VpnCoreSkip.amneziaWg => l10n.settingsCoreSkipAwg,
      VpnCoreSkip.clashConfig => l10n.settingsCoreSkipClash,
      VpnCoreSkip.linkXrayOnly => l10n.settingsCoreSkipLinkXrayOnly,
      VpnCoreSkip.linkMihomoOnly => l10n.settingsCoreSkipLinkMihomoOnly,
      VpnCoreSkip.platform => l10n.settingsCoreSkipPlatform,
    };

class _ProxyAuthTile extends ConsumerWidget {
  const _ProxyAuthTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final settings = ref.watch(settingsNotifierProvider.select((a) => a.value));
    final chosen = settings?.connectionModeChosen ?? false;
    final mode = chosen
        ? ConnectionMode.fromStorage(settings?.connectionMode)
        : ConnectionMode.tun;
    if (mode != ConnectionMode.proxy) return const SizedBox.shrink();

    final on = settings?.proxyModeAuth ?? true;
    final user = settings?.proxyModeUser ?? '';
    final pass = settings?.proxyModePass ?? '';

    Future<void> toggle(bool v) async {
      final s = await ref.read(settingsNotifierProvider.future);
      await ref
          .read(settingsNotifierProvider.notifier)
          .save(s.copyWith(proxyModeAuth: v));
    }

    return ExpressiveGroupTile(
      padding: const EdgeInsets.all(16),
      onTap: () => toggle(!on),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExpressiveIconBadge(
                icon: Icons.password_rounded,
                accent: ExpressiveAccent.tertiary,
              ),
              const SizedBox(width: ExpressiveSpacing.large),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.settingsProxyAuthTitle,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: AppTheme.text(context)),
                    ),
                    Text(
                      l10n.settingsProxyAuthSubtitle,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppTheme.textLight(context)),
                    ),
                  ],
                ),
              ),
              Switch(value: on, onChanged: toggle),
            ],
          ),
          if (on && user.isNotEmpty && pass.isNotEmpty) ...[
            const SizedBox(height: 12),
            _InternalsRow(label: l10n.settingsProxyAuthUser, value: user),
            _InternalsRow(label: l10n.settingsProxyAuthPass, value: pass),
          ],
        ],
      ),
    );
  }
}

class _TunnelModeTile extends ConsumerWidget {
  final ConnectionMode mode;

  const _TunnelModeTile({required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final settingsValue = ref.watch(
      settingsNotifierProvider.select((a) => a.value),
    );
    // пока режим не выбирали руками, подключится VPN, его и показываем
    final current = (settingsValue?.connectionModeChosen ?? false)
        ? ConnectionMode.fromStorage(settingsValue?.connectionMode)
        : ConnectionMode.tun;
    final selected = current == mode;
    final isProxy = mode == ConnectionMode.proxy;

    Future<void> select() async {
      if (selected) return;
      final settings = await ref.read(settingsNotifierProvider.future);
      await ref.read(settingsNotifierProvider.notifier).save(
            settings.copyWith(
              connectionMode: mode.storageValue,
              connectionModeChosen: true,
            ),
          );
    }

    return ExpressiveGroupTile(
      padding: const EdgeInsets.all(16),
      onTap: select,
      child: Row(
        children: [
          ExpressiveIconBadge(
            icon: isProxy ? Icons.lan_rounded : Icons.vpn_lock_rounded,
            accent: isProxy
                ? ExpressiveAccent.secondary
                : ExpressiveAccent.primary,
          ),
          const SizedBox(width: ExpressiveSpacing.large),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isProxy ? l10n.settingsTunnelModeProxy : l10n.settingsTunnelModeVpn,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppTheme.text(context),
                  ),
                ),
                Text(
                  isProxy
                      ? l10n.settingsTunnelModeProxySubtitle
                      : l10n.settingsTunnelModeVpnSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.textLight(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: ExpressiveSpacing.large),
          Icon(
            selected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded,
            color: selected
                ? AppTheme.accent(context)
                : AppTheme.textLight(context),
          ),
        ],
      ),
    );
  }
}

const _selectableCores = <String, String>{
  'libxray.so': AppSettings.vpnCoreXray,
  'xray.exe': AppSettings.vpnCoreXray,
  'xray': AppSettings.vpnCoreXray,
  'libmihomo.so': AppSettings.vpnCoreMihomo,
  'mihomo.exe': AppSettings.vpnCoreMihomo,
  'mihomo': AppSettings.vpnCoreMihomo,
};

String? _selectableCore(CoreInfo core) =>
    core.missing ? null : _selectableCores[core.name];

class _SelectableCoreTile extends ConsumerWidget {
  final CoreInfo core;

  final String value;

  const _SelectableCoreTile({required this.core, required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final current = ref.watch(
      settingsNotifierProvider.select(
        (a) => a.value?.vpnCore ?? AppSettings.vpnCoreXray,
      ),
    );

    Future<void> select() async {
      if (value == current) return;
      final settings = await ref.read(settingsNotifierProvider.future);
      await ref
          .read(settingsNotifierProvider.notifier)
          .save(settings.copyWith(vpnCore: value));
    }

    return _CoreTile(
      core: core,
      selected: value == current,
      subtitle: switch (value) {
        AppSettings.vpnCoreMihomo => l10n.settingsCoreMihomoSubtitle,
        _ => l10n.settingsCoreXraySubtitle,
      },
      onTap: select,
    );
  }
}

String _formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
