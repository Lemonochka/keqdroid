part of '../settings_tab.dart';

@visibleForTesting
Widget appLogScreenForTest() => const _AppLogScreen();

class _AppLogScreen extends StatefulWidget {
  const _AppLogScreen();

  @override
  State<_AppLogScreen> createState() => _AppLogScreenState();
}

class _AppLogScreenState extends State<_AppLogScreen> {
  final _problems = <AppLogSource, int>{};
  List<ProcessExit> _exits = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final source in AppLogService.sources) {
      final entries = await AppLogService.read(source);
      if (!mounted) return;
      setState(() => _problems[source] = entries.where((e) => e.isProblem).length);
    }
    final exits = await AppLogService.processExits();
    if (mounted) setState(() => _exits = exits);
  }

  Future<void> _copyAll(AppLocalizations l10n) async {
    final text = await AppLogService.bundle();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    AppSnack.of(context).showSnackBar(
      SnackBar(content: Text(l10n.serversCopiedToClipboard)),
    );
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ExpressivePage(
      title: l10n.appLogTitle,
      physics: const ClampingScrollPhysics(),
      actions: [
        IconButton(
          tooltip: l10n.appLogCopyAll,
          icon: const Icon(Icons.copy_all_rounded),
          onPressed: () => _copyAll(l10n),
        ),
      ],
      children: [
        ExpressiveGroup(
          children: [
            for (final source in AppLogService.sources)
              _AppLogSourceTile(
                icon: _sourceIcon(source),
                title: _sourceTitle(l10n, source),
                subtitle: _sourceDescription(l10n, source),
                problems: _problems[source],
                onTap: () => _open(_AppLogSourceScreen(source: source)),
              ),
            if (_exits.isNotEmpty)
              _AppLogSourceTile(
                icon: Icons.history_rounded,
                title: l10n.settingsInternalsExits,
                subtitle: l10n.appLogSourceExitsDesc,
                onTap: () => _open(_ProcessExitsScreen(exits: _exits)),
              ),
          ],
        ),
      ],
    );
  }

  static IconData _sourceIcon(AppLogSource source) => switch (source) {
        AppLogSource.app => Icons.widgets_rounded,
        AppLogSource.native => Icons.android_rounded,
      };
}

String _sourceTitle(AppLocalizations l10n, AppLogSource source) =>
    switch (source) {
      AppLogSource.app => l10n.appLogSourceApp,
      AppLogSource.native => l10n.appLogSourceNative,
    };

String _sourceDescription(AppLocalizations l10n, AppLogSource source) =>
    switch (source) {
      AppLogSource.app => l10n.appLogSourceAppDesc,
      AppLogSource.native => l10n.appLogSourceNativeDesc,
    };

class _AppLogSourceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final int? problems;
  final VoidCallback onTap;

  const _AppLogSourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.problems,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final count = problems;
    return ExpressiveGroupTile(
      onTap: onTap,
      child: Row(
        children: [
          ExpressiveIconBadge(icon: icon),
          const SizedBox(width: ExpressiveSpacing.large),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.titleMedium?.copyWith(color: AppTheme.text(context)),
                ),
                Text(
                  subtitle,
                  style: textTheme.bodyMedium?.copyWith(color: AppTheme.textLight(context)),
                ),
                if (count != null)
                  Text(
                    l10n.appLogProblems(count),
                    style: textTheme.labelLarge?.copyWith(
                      color: count > 0 ? AppTheme.red(context) : AppTheme.green(context),
                    ),
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: AppTheme.textLight(context)),
        ],
      ),
    );
  }
}

class _AppLogSourceScreen extends StatefulWidget {
  final AppLogSource source;
  const _AppLogSourceScreen({required this.source});

  @override
  State<_AppLogSourceScreen> createState() => _AppLogSourceScreenState();
}

class _AppLogSourceScreenState extends State<_AppLogSourceScreen> {
  List<LogEntry>? _entries;
  bool _problemsOnly = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final entries = await AppLogService.read(widget.source);
    if (mounted) setState(() => _entries = entries);
  }

  List<LogEntry> get _shown {
    final all = _entries ?? const <LogEntry>[];
    return _problemsOnly ? all.where((e) => e.isProblem).toList() : all;
  }

  Future<void> _copy(AppLocalizations l10n, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    AppSnack.of(context).showSnackBar(
      SnackBar(content: Text(l10n.serversCopiedToClipboard)),
    );
  }

  Color _levelColor(LogLevel level) => switch (level) {
        LogLevel.error => AppTheme.red(context),
        LogLevel.warn => AppTheme.orange(context),
        LogLevel.debug => AppTheme.textLight(context),
        LogLevel.info => AppTheme.text(context),
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final shown = _shown;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          height: 1.35,
        );
    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: ExpressiveScrolledUnderBar(
        builder: (context, background) => AppBar(
          backgroundColor: background,
          title: Text(_sourceTitle(l10n, widget.source)),
          actions: [
            IconButton(
              tooltip: l10n.settingsCopyLogs,
              onPressed: shown.isEmpty
                  ? null
                  : () => _copy(l10n, shown.map((e) => e.text).join('\n')),
              icon: const Icon(Icons.copy_all_rounded),
            ),
            IconButton(
              tooltip: l10n.settingsRefresh,
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilterChip(
                label: Text(l10n.appLogOnlyProblems),
                selected: _problemsOnly,
                onSelected: (value) => setState(() => _problemsOnly = value),
              ),
            ),
          ),
          Expanded(
            child: _entries == null
                ? const Center(child: ShapeLoadingIndicator())
                : shown.isEmpty
                    ? Center(
                        child: Text(
                          l10n.appLogEmpty,
                          style: TextStyle(color: AppTheme.textLight(context)),
                        ),
                      )
                    : Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          margin: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.inset(context),
                            borderRadius:
                                BorderRadius.circular(ExpressiveShape.large),
                            border: Border.all(color: AppTheme.divider(context)),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ListView.builder(
                            shrinkWrap: true,
                            reverse: true,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: shown.length,
                            itemBuilder: (context, index) {
                              final entry = shown[shown.length - 1 - index];
                              return InkWell(
                                onLongPress: () => _copy(l10n, entry.text),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 3,
                                  ),
                                  child: Text(
                                    entry.text,
                                    textDirection: TextDirection.ltr,
                                    style: style?.copyWith(
                                      color: _levelColor(entry.level),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _ProcessExitsScreen extends StatelessWidget {
  final List<ProcessExit> exits;
  const _ProcessExitsScreen({required this.exits});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ExpressivePage(
      title: l10n.settingsInternalsExits,
      physics: const ClampingScrollPhysics(),
      actions: [
        IconButton(
          tooltip: l10n.settingsCopyLogs,
          icon: const Icon(Icons.copy_all_rounded),
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: AppInternalsService.exitLines(exits)),
            );
            if (!context.mounted) return;
            AppSnack.of(context).showSnackBar(
              SnackBar(content: Text(l10n.serversCopiedToClipboard)),
            );
          },
        ),
      ],
      children: [
        ExpressiveGroup(
          children: [for (final exit in exits) _ProcessExitRow(exit: exit)],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            l10n.settingsInternalsExitsHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textLight(context),
                ),
          ),
        ),
      ],
    );
  }
}
