part of '../settings_tab.dart';

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
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshLogs(),
    );
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

  Future<void> _copyLogs(AppLocalizations l10n) async {
    await Clipboard.setData(ClipboardData(text: _logs));
    if (!mounted) return;
    AppSnack.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.serversCopiedToClipboard)));
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
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: AppTheme.text(context),
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
