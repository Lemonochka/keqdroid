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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: enabled ? AppTheme.orange(context).withValues(alpha: 0.55) : AppTheme.divider(context),
          width: enabled ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.orange(context).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.bug_report_outlined, size: 20, color: AppTheme.orange(context)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.settingsDebugMode,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.text(context),
                      ),
                    ),
                    Text(
                      enabled ? l10n.settingsDebugModeOn : l10n.settingsDebugModeOff,
                      style: TextStyle(
                        fontSize: 12,
                        color: enabled ? AppTheme.orange(context) : AppTheme.textLight(context),
                      ),
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
            style: TextStyle(fontSize: 12, color: AppTheme.textLight(context), height: 1.35),
          ),
          if (enabled) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _XrayLogsScreen()),
              ),
              icon: const Icon(Icons.terminal),
              label: Text(l10n.settingsOpenXrayLogs),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.bg(context),
        title: Text(l10n.settingsXrayCoreLogs),
        actions: [
          IconButton(
            tooltip: l10n.settingsRefresh,
            onPressed: _refreshLogs,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppTheme.accent(context)))
          : Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.inset(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.divider(context)),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              _logs,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
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

