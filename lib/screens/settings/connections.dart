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
    // Подсказка про уровень логов актуальна только там, где правило берётся из
    // лога (Android) и уровень ниже Info.
    final showLogLevelHint = !_snapshot.ruleInfoAvailable &&
        _snapshot.source == ConnectionsSource.coreLog &&
        logLevel != 'info' &&
        logLevel != 'debug';

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
                      const SizedBox(height: 10),
                      TextField(
                        controller: _filterCtrl,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.text(context),
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          prefixIcon: const Icon(Icons.search, size: 18),
                          hintText: l10n.connectionsFilterHint,
                          hintStyle:
                              TextStyle(color: AppTheme.textLight(context)),
                          filled: true,
                          fillColor: AppTheme.inset(context),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide(color: AppTheme.divider(context)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
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
                          itemBuilder: (_, i) => _ConnectionTile(
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
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.connectionsCount(shown),
            style: TextStyle(
              fontSize: 11.5,
              color: AppTheme.textLight(context),
            ),
          ),
        ),
        if (_paused)
          Text(
            l10n.connectionsPaused,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.orange(context),
            ),
          ),
      ],
    );
  }

  Widget _logLevelHint(BuildContext context, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.orange(context).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.rule, size: 16, color: AppTheme.orange(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.connectionsRuleHint,
              style: TextStyle(
                fontSize: 11.5,
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
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.text(context),
              ),
            ),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                note,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
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

class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({
    required this.entry,
    required this.showProcess,
    required this.ruleInfoAvailable,
  });

  final ConnectionEntry entry;
  final bool showProcess;

  /// false — источник вообще не знает правил (access-лог ниже уровня Info):
  /// пустое правило тогда значит «неизвестно», а не «сработал catch-all».
  final bool ruleInfoAvailable;

  Color _verdictColor(BuildContext context) => switch (entry.verdict) {
        ConnectionVerdict.proxied => AppTheme.accent(context),
        ConnectionVerdict.direct => AppTheme.green(context),
        ConnectionVerdict.blocked => AppTheme.red(context),
        ConnectionVerdict.unknown => AppTheme.textLight(context),
      };

  String _verdictLabel(AppLocalizations l10n) => switch (entry.verdict) {
        ConnectionVerdict.proxied => l10n.connectionsVerdictProxy,
        ConnectionVerdict.direct => l10n.connectionsVerdictDirect,
        ConnectionVerdict.blocked => l10n.connectionsVerdictBlock,
        ConnectionVerdict.unknown => '—',
      };

  static String _bytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    if (value < 1024 * 1024 * 1024) {
      return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Только имя исполняемого файла: полный путь съедает всю строку.
  static String _processName(String raw) {
    if (raw.isEmpty) return '';
    final normalized = raw.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    return slash >= 0 ? normalized.substring(slash + 1) : normalized;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = _verdictColor(context);
    final process = _processName(entry.process);
    final rule = switch (entry.rule) {
      '' => ruleInfoAvailable && entry.outbound.isNotEmpty
          ? l10n.connectionsRuleDefault
          : '',
      final r when XrayAccessLogParser.isDefaultRoute(r) =>
        l10n.connectionsRuleDefault,
      final r => r,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: color, width: 3),
          top: BorderSide(color: AppTheme.divider(context)),
          right: BorderSide(color: AppTheme.divider(context)),
          bottom: BorderSide(color: AppTheme.divider(context)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  entry.target,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.text(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _chip(context, entry.network.toUpperCase(),
                  AppTheme.textLight(context)),
              const SizedBox(width: 6),
              _chip(context, _verdictLabel(l10n), color),
            ],
          ),
          if (entry.destIp.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              entry.destIp,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: AppTheme.textLight(context),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (showProcess && process.isNotEmpty)
                _meta(context, Icons.apps, process),
              if (rule.isNotEmpty) _meta(context, Icons.rule, rule),
              if (entry.outbound.isNotEmpty)
                _meta(context, Icons.call_split, entry.outbound),
              if (entry.inbound.isNotEmpty)
                _meta(context, Icons.login, entry.inbound),
              if (entry.source.isNotEmpty)
                _meta(context, Icons.computer, entry.source),
              if (entry.download != null || entry.upload != null)
                _meta(
                  context,
                  Icons.swap_vert,
                  '↓ ${_bytes(entry.download ?? 0)}  ↑ ${_bytes(entry.upload ?? 0)}',
                ),
              if (entry.startedAt != null)
                _meta(
                  context,
                  Icons.schedule,
                  _formatTime(entry.startedAt!),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  Widget _chip(BuildContext context, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      );

  Widget _meta(BuildContext context, IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppTheme.textLight(context)),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textLight(context),
              ),
            ),
          ),
        ],
      );
}
