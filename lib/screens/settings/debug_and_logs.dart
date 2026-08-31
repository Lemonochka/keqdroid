part of '../settings_tab.dart';

class _DebugModeCard extends ConsumerWidget {
  final AsyncValue<AppSettings> settingsAsync;
  const _DebugModeCard({required this.settingsAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = settingsAsync.value ?? const AppSettings();
    final enabled = settings.debugMode;

    Future<void> save(bool value) async {
      await ref.read(settingsNotifierProvider.notifier).save(settings.copyWith(debugMode: value));
    }

    final textTheme = Theme.of(context).textTheme;

    return ExpressiveGroupTile(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExpressiveIconBadge(
                icon: Icons.bug_report_rounded,
                background: AppTheme.orange(context).withValues(alpha: 0.2),
                foreground: AppTheme.orange(context),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.settingsDebugMode,
                      style: textTheme.titleMedium?.copyWith(
                        color: AppTheme.text(context),
                      ),
                    ),
                    Text(
                      enabled ? l10n.settingsDebugModeOn : l10n.settingsDebugModeOff,
                      style: textTheme.bodyMedium?.copyWith(color: enabled ? AppTheme.orange(context) : AppTheme.textLight(context)),
                    ),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                activeThumbColor: AppTheme.orange(context),
                onChanged: save,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            PlatformBootstrap.isDesktop
                ? l10n.settingsDebugHintDesktop
                : l10n.settingsDebugHintMobile,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textLight(context), height: 1.35),
          ),
          if (enabled) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _XrayLogsScreen()),
              ),
              icon: const Icon(Icons.terminal_rounded),
              label: Text(l10n.settingsOpenXrayLogs),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _ConnectionsScreen()),
              ),
              icon: const Icon(Icons.lan_rounded),
              label: Text(l10n.settingsOpenConnections),
            ),
          ],
        ],
      ),
    );
  }
}

class _XrayLogsScreen extends ConsumerStatefulWidget {
  const _XrayLogsScreen();

  @override
  ConsumerState<_XrayLogsScreen> createState() => _XrayLogsScreenState();
}

class _XrayLogsScreenState extends ConsumerState<_XrayLogsScreen> {
  String _logs = '';
  bool _loading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _refreshLogs();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshLogs());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshLogs() async {
    try {
      final text = await DebugLogService.getXrayLogs(maxLines: 400);
      if (!mounted) return;
      setState(() {
        _logs = text.trim().isEmpty ? 'No Xray logs yet.' : text;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _logs = 'Failed to read logs: $e';
        _loading = false;
      });
    }
  }

  /// Лог целиком в буфер: выделять руками несколько сотен строк на телефоне
  /// невозможно, а именно они и нужны, когда разбираешься, что решило ядро.
  Future<void> _copyLogs(AppLocalizations l10n) async {
    await Clipboard.setData(ClipboardData(text: _logs));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.serversCopiedToClipboard)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: ExpressiveScrolledUnderBar(
        builder: (context, background) => AppBar(
          backgroundColor: background,
          title: Text(l10n.settingsXrayCoreLogs),
          actions: [
            IconButton(
              tooltip: l10n.settingsCopyLogs,
              onPressed: _logs.isEmpty ? null : () => _copyLogs(l10n),
              icon: const Icon(Icons.copy_all_rounded),
            ),
            IconButton(
              tooltip: l10n.settingsRefresh,
              onPressed: _refreshLogs,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: ShapeLoadingIndicator())
          : Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.inset(context),
            borderRadius: BorderRadius.circular(ExpressiveShape.large),
            border: Border.all(color: AppTheme.divider(context)),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              _logs,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace', color: AppTheme.text(context), height: 1.35),
            ),
          ),
        ),
      ),
    );
  }
}

