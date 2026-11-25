part of '../settings_tab.dart';

@visibleForTesting
Widget connectionsLogsScreenForTest() => const _ConnectionsLogsScreen();

class _ConnectionsLogsScreen extends StatefulWidget {
  const _ConnectionsLogsScreen();

  @override
  State<_ConnectionsLogsScreen> createState() => _ConnectionsLogsScreenState();
}

class _ConnectionsLogsScreenState extends State<_ConnectionsLogsScreen>
    with SingleTickerProviderStateMixin {
  final _connectionsKey = GlobalKey<_ConnectionsScreenState>();
  final _logsKey = GlobalKey<_AppLogScreenState>();
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)..addListener(_syncActions);
  }

  void _syncActions() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final connections = _connectionsKey.currentState;
    final paused = connections?._paused ?? false;
    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: ExpressiveScrolledUnderBar(
        preferredSize: const Size.fromHeight(kToolbarHeight + 48),
        builder: (context, background) => AppBar(
          backgroundColor: background,
          title: Text(l10n.settingsConnectionsLogsTitle),
          actions: [
            if (_tabs.index == 0) ...[
              IconButton(
                tooltip: paused
                    ? l10n.connectionsResume
                    : l10n.connectionsPause,
                icon: Icon(
                  paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                ),
                onPressed: () {
                  _connectionsKey.currentState?._togglePause();
                  setState(() {});
                },
              ),
              IconButton(
                tooltip: l10n.settingsRefresh,
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () {
                  _connectionsKey.currentState?._refreshAndResume();
                  setState(() {});
                },
              ),
            ] else if (Platform.isAndroid)
              IconButton(
                tooltip: l10n.appLogShareFile,
                icon: const Icon(Icons.share_rounded),
                onPressed: () => _logsKey.currentState?._shareFile(l10n),
              )
            else
              IconButton(
                tooltip: l10n.appLogCopyAll,
                icon: const Icon(Icons.copy_all_rounded),
                onPressed: () => _logsKey.currentState?._copyAll(l10n),
              ),
          ],
          bottom: TabBar(
            controller: _tabs,
            tabs: [
              Tab(text: l10n.settingsConnectionsTitle),
              Tab(text: l10n.settingsLogsTab),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _ConnectionsScreen(key: _connectionsKey, embedded: true),
          _AppLogScreen(key: _logsKey, embedded: true),
        ],
      ),
    );
  }
}
