part of '../settings_tab.dart';

// записи те же, что у сплита, поэтому приложение в сплите и в маршруте хранится одной записью;
// пустой список выбирает все приложения, null приходит, если шторку закрыли
class _WhoPickerSheet extends ConsumerStatefulWidget {
  const _WhoPickerSheet({required this.initial});

  final List<String> initial;

  @override
  ConsumerState<_WhoPickerSheet> createState() => _WhoPickerSheetState();
}

class _WhoPickerSheetState extends ConsumerState<_WhoPickerSheet> {
  late Set<String> _selected = {...widget.initial};
  final _query = TextEditingController();
  bool _showSystem = false;

  // порядок первой загрузки: пересортировка на каждое нажатие уводила бы строку из-под пальца
  List<AppInfo>? _rows;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<AppInfo> _arrange(List<AppInfo> apps) {
    final stubs = [
      for (final entry in _selected)
        if (!apps.any((app) => splitEntryMatches(entry, app)))
          splitStubForEntry(entry),
    ];
    final merged = dedupeSplitEntries([...stubs, ...apps]);
    final selection = SplitSelection(_selected);
    return [
      ...merged.where(selection.covers),
      ...merged.where((app) => !selection.covers(app)),
    ];
  }

  List<AppInfo> _visible(List<AppInfo> rows) {
    final needle = _query.text.trim().toLowerCase();
    if (needle.isEmpty) return rows;
    return [
      for (final app in rows)
        if (app.appName.toLowerCase().contains(needle) ||
            app.packageName.toLowerCase().contains(needle) ||
            (app.installPath?.toLowerCase().contains(needle) ?? false))
          app,
    ];
  }

  void _toggle(AppInfo app) => setState(
    () => _selected = SplitTunnelingNotifier.toggledEntries(_selected, app),
  );

  Future<void> _addByHand() async {
    final raw = await showAddProcessDialog(context);
    if (raw == null || !mounted) return;
    final entry = isProcessPathEntry(raw)
        ? normalizeProcessPath(raw)
        : normalizeProcessName(raw);
    if (entry.isEmpty || normalizeProcessName(entry).isEmpty) return;
    setState(() {
      _selected = {..._selected, entry};
      final rows = _rows ?? const <AppInfo>[];
      if (!rows.any((app) => splitEntryMatches(entry, app))) {
        _rows = [splitStubForEntry(entry), ...rows];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final appsAsync = ref.watch(installedAppsProvider(_showSystem));
    if (_rows == null && appsAsync.hasValue) {
      _rows = _arrange(appsAsync.value!);
    }
    final rows = _visible(_rows ?? const []);
    final selection = SplitSelection(_selected);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Text(
                  l10n.routeWho,
                  style: theme.textTheme
                      .emphasized(theme.textTheme.titleMedium)
                      ?.copyWith(color: AppTheme.text(context)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ExpressiveGroup(
                  children: [
                    ExpressiveActionTile(
                      icon: Icons.apps_rounded,
                      title: l10n.routesSectionAllApps,
                      subtitle: l10n.routeWhoAllSubtitle,
                      selected: widget.initial.isEmpty,
                      onTap: () => Navigator.pop(context, const <String>[]),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ExpressiveSectionHeader(
                  l10n.routeWhoApps,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: _showSystem
                            ? l10n.splitHideSystemApps
                            : l10n.splitShowSystemApps,
                        isSelected: _showSystem,
                        icon: Icon(
                          PlatformBootstrap.isDesktop
                              ? Icons.computer_outlined
                              : Icons.android_outlined,
                        ),
                        selectedIcon: Icon(
                          PlatformBootstrap.isDesktop
                              ? Icons.computer_rounded
                              : Icons.android_rounded,
                        ),
                        onPressed: () => setState(() {
                          _showSystem = !_showSystem;
                          _rows = null;
                        }),
                      ),
                      if (PlatformBootstrap.isDesktop)
                        TextButton.icon(
                          onPressed: () => unawaited(_addByHand()),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: Text(l10n.splitAddApp),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _query,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: l10n.splitSearchHint,
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: AppTheme.inset(context),
                    border: OutlineInputBorder(
                      borderRadius: ExpressiveShape.radius(
                        ExpressiveShape.medium,
                      ),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Flexible(child: _list(l10n, appsAsync, rows, selection)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: FilledButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.pop(context, _selected.toList()),
                  child: Text(l10n.routeWhoDone(_selected.length)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(
    AppLocalizations l10n,
    AsyncValue<List<AppInfo>> appsAsync,
    List<AppInfo> rows,
    SplitSelection selection,
  ) {
    final muted = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: AppTheme.textLight(context));
    Widget message(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 24),
      child: Text(text, textAlign: TextAlign.center, style: muted),
    );
    if (_rows == null) {
      return appsAsync.hasError
          ? message(l10n.splitFailedLoadApps('${appsAsync.error}'))
          : const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: ShapeLoadingIndicator()),
            );
    }
    if (rows.isEmpty) return message(l10n.splitNoAppsFound);
    final iconCache = ref.read(appIconCacheProvider);
    final direction = Directionality.of(context);
    final mark = AppTheme.green(context);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemExtent: AppListTile.height,
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final app = rows[i];
        return AppListTile(
          key: ValueKey(app.installPath ?? app.packageName),
          app: app,
          iconCache: iconCache,
          checked: selection.covers(app),
          markColor: mark,
          radius: ExpressiveListSegment.segmentRadius(
            index: i,
            count: rows.length,
          ).resolve(direction),
          margin: ExpressiveListSegment.segmentMargin(
            index: i,
          ).resolve(direction),
          onTap: () => _toggle(app),
        );
      },
    );
  }
}
