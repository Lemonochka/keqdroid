part of '../settings_tab.dart';

/// Дебаг-экран «Соединения»: что, куда и по какому правилу идёт прямо сейчас.
///
/// Данные берёт [ConnectionsService]; полнота зависит от платформы — на десктопе
/// это живой снимок из clash_api ядра (с процессом и байтами), на Android —
/// разбор access-лога xray (без процесса и байт).
class _ConnectionsScreen extends ConsumerStatefulWidget {
  const _ConnectionsScreen();

  @override
  ConsumerState<_ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends ConsumerState<_ConnectionsScreen> {
  ConnectionsSnapshot _snapshot = ConnectionsSnapshot.empty;
  bool _loading = true;
  bool _paused = false;
  String _filter = '';
  Timer? _pollTimer;
  final _filterCtrl = TextEditingController();

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
    if (_paused) return;
    try {
      final snapshot = await ConnectionsService.snapshot();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
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
    }
  }

  List<ConnectionEntry> get _visible {
    final needle = _filter.trim().toLowerCase();
    if (needle.isEmpty) return _snapshot.entries;
    return _snapshot.entries
        .where((e) => e.searchHaystack.contains(needle))
        .toList();
  }

  /// Уровень логов ядра на Info — без него xray не печатает, какое правило
  /// сработало, и колонка «правило» на Android остаётся пустой.
  Future<void> _enableInfoLogs() async {
    final settings = ref.read(settingsNotifierProvider).value;
    if (settings == null) return;
    await ref.read(settingsNotifierProvider.notifier).save(
          settings.copyWith(
            xrayCore: settings.xrayCore.copyWith(logLevel: 'info'),
          ),
        );
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.connectionsRuleHintApplied)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final entries = _visible;
    final logLevel = ref.watch(
      settingsNotifierProvider.select(
        (a) => a.value?.xrayCore.logLevel ?? 'warning',
      ),
    );
    // Правило ядро печатает только на уровне Info — и когда оно само инбаунд
    // (Android), и когда работает встроенным движком за sing-box (десктоп):
    // там clash_api знает лишь «отдал движку».
    final showLogLevelHint = !_snapshot.ruleInfoAvailable &&
        _snapshot.source != ConnectionsSource.unavailable &&
        logLevel != 'info' &&
        logLevel != 'debug';
    // Владельца соединения на Android ищем по логу tun2socks, а он включается
    // при старте туннеля. Дебаг включили после подключения — колонка будет
    // пустой до переподключения, и молчать об этом нельзя: выглядит поломкой.
    final showAppNamesHint =
        Platform.isAndroid && !_snapshot.appNamesAvailable;
    // Сплит-туннель на Android делает система: исключённые приложения идут
    // мимо TUN, их трафик не видит ни tun2socks, ни ядро. В списке их поэтому
    // не бывает никогда — и это не пропажа, а как раз то, о чём просили.
    final split = ref.watch(splitTunnelingProvider);
    final showSplitNote = Platform.isAndroid &&
        (split.excludePackages.isNotEmpty || split.includePackages.isNotEmpty);

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.bg(context),
        title: Text(l10n.settingsConnectionsTitle),
        actions: [
          IconButton(
            tooltip: _paused ? l10n.connectionsResume : l10n.connectionsPause,
            icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
            onPressed: () => setState(() => _paused = !_paused),
          ),
          IconButton(
            tooltip: l10n.settingsRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _paused = false);
              unawaited(_refresh());
            },
          ),
        ],
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: AppTheme.accent(context)),
            )
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
                          Icons.apps,
                          l10n.connectionsAppNamesHint,
                        ),
                      ],
                      if (showSplitNote) ...[
                        const SizedBox(height: 10),
                        _noticeBox(
                          context,
                          Icons.call_split,
                          l10n.connectionsSplitTunnelNote,
                          color: AppTheme.textLight(context),
                        ),
                      ],
                      const SizedBox(height: 10),
                      TextField(
                        controller: _filterCtrl,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppTheme.text(context)),
                        decoration: InputDecoration(
                          isDense: true,
                          prefixIcon: const Icon(Icons.search, size: 18),
                          hintText: l10n.connectionsFilterHint,
                          hintStyle:
                              TextStyle(color: AppTheme.textLight(context)),
                          filled: true,
                          fillColor: AppTheme.inset(context),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(ExpressiveShape.medium),
                            borderSide:
                                BorderSide(color: AppTheme.divider(context)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(ExpressiveShape.medium),
                            borderSide:
                                BorderSide(color: AppTheme.divider(context)),
                          ),
                          suffixIcon: _filter.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
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
                            showProcess: ConnectionsService.supportsProcessNames,
                            ruleInfoAvailable: _snapshot.ruleInfoAvailable,
                          ),
                        ),
                ),
              ],
            ),
    );
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
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: color),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.connectionsCount(shown),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppTheme.textLight(context)),
          ),
        ),
        if (_paused)
          Text(
            l10n.connectionsPaused,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: AppTheme.orange(context)),
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
          Icon(Icons.rule, size: 16, color: AppTheme.orange(context)),
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

  /// Плашка-объяснение без действия: сделать за пользователя тут нечего.
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
              Icons.lan_outlined,
              size: 40,
              color: AppTheme.textLight(context),
            ),
            const SizedBox(height: 12),
            Text(
              _snapshot.source == ConnectionsSource.unavailable
                  ? l10n.connectionsUnavailable
                  : l10n.connectionsEmpty,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppTheme.text(context)),
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
