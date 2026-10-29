import 'dart:io' show Platform;
import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:keqdroid/shared/ui/expressive_elements.dart';
import 'package:keqdroid/shared/ui/expressive_group.dart';
import 'package:keqdroid/shared/ui/haptics.dart';
import 'package:keqdroid/shared/ui/scrolled_under.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/shared/ui/add_process_dialog.dart';
import 'package:keqdroid/shared/ui/app_list_tile.dart';
import 'package:keqdroid/shared/ui/app_theme.dart';
import 'package:keqdroid/shared/ui/shape_loading_indicator.dart';
import 'package:keqdroid/shared/ui/smooth_scroll.dart';
import 'package:keqdroid/shared/ui/tv_focus.dart';

import '../models/app_info.dart';
import '../providers/providers.dart';
import '../platform/platform_bootstrap.dart';
import '../tunnel/connection_mode.dart';
import '../tunnel/tunnel_state.dart';
import '../utils/process_name_utils.dart';
import '../utils/russian_apps.dart';
import '../utils/split_tunneling_entries.dart';
import 'package:keqdroid/shared/ui/liquid_toast.dart';

enum TunnelMode { all, includeOnly, excludeOnly }

extension TunnelModeX on TunnelMode {
  String label(AppLocalizations l10n) => switch (this) {
    TunnelMode.all => l10n.splitModeAllApps,
    TunnelMode.includeOnly => l10n.splitModeSelectedOnly,
    TunnelMode.excludeOnly => l10n.splitModeAllExceptSelected,
  };
  IconData get icon => switch (this) {
    TunnelMode.all         => Icons.public_rounded,
    TunnelMode.includeOnly => Icons.shield_rounded,
    TunnelMode.excludeOnly => Icons.alt_route_rounded,
  };
}

class SplitTunnelingScreen extends ConsumerStatefulWidget {
  const SplitTunnelingScreen({super.key});
  @override
  ConsumerState<SplitTunnelingScreen> createState() => _SplitTunnelingScreenState();
}

class _SplitTunnelingScreenState extends ConsumerState<SplitTunnelingScreen>
    with SingleTickerProviderStateMixin {

  final _searchCtrl = TextEditingController();
  String _query = '';
  TunnelMode _mode = TunnelMode.excludeOnly;
  bool _showSystem = false;
  late final AnimationController _fadeCtrl;

  static const double _largeTitleMinHeight = 600;

  List<AppInfo> _allApps = [];
  List<AppInfo> _displayList = [];
  bool get _isDesktop => PlatformBootstrap.isDesktop;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: ExpressiveMotion.durationDefault,
    )..forward();
    _searchCtrl.addListener(_onSearch);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMode());
  }

  void _onSearch() {
    setState(() {
      _query = _searchCtrl.text.toLowerCase();
      if (_query.isEmpty) {
        _displayList = List.of(_allApps);
      } else {
        _displayList = _allApps.where((a) =>
        a.appName.toLowerCase().contains(_query) ||
            a.packageName.toLowerCase().contains(_query) ||
            (a.installPath?.toLowerCase().contains(_query) ?? false)).toList();
      }
    });
  }

  void _loadMode() {
    final split = ref.read(splitTunnelingProvider);
    TunnelMode mode;
    if (split.includePackages.isNotEmpty) {
      mode = TunnelMode.includeOnly;
    } else if (split.excludePackages.isNotEmpty) {
      mode = TunnelMode.excludeOnly;
    } else {
      mode = TunnelMode.all;
    }
    setState(() { _mode = mode; });
  }

  // через splitEntryMatches: сырой строкой discord.exe не находил Discord.exe
  List<AppInfo> _mergeCustomApps(List<AppInfo> apps) {
    final split = ref.read(splitTunnelingProvider);
    final custom = <AppInfo>[];
    for (final entry in {...split.includePackages, ...split.excludePackages}) {
      if (entry.trim().isEmpty) continue;
      if (apps.any((app) => splitEntryMatches(entry, app))) continue;
      custom.add(splitStubForEntry(entry));
    }
    if (custom.isEmpty) return apps;
    return [...custom, ...apps];
  }

  void _applyInitialSort(List<AppInfo> apps) {
    final split = ref.read(splitTunnelingProvider);
    final selection = SplitSelection(_checkedSet(split));
    final merged = dedupeSplitEntries(_mergeCustomApps(apps));
    bool isChecked(AppInfo a) => selection.covers(a);
    _allApps = [
      ...merged.where(isChecked),
      ...merged.where((a) => !isChecked(a)),
    ];
    if (_query.isEmpty) {
      _displayList = List.of(_allApps);
    } else {
      _displayList = _allApps.where((a) =>
      a.appName.toLowerCase().contains(_query) ||
          a.packageName.toLowerCase().contains(_query)).toList();
    }
  }

  Set<String> _checkedSet(SplitTunnelingState split) => switch (_mode) {
    TunnelMode.all         => {},
    TunnelMode.includeOnly => split.includePackages,
    TunnelMode.excludeOnly => split.excludePackages,
  };

  Future<void> _showAddAppDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final raw = await showAddProcessDialog(context);
    if (raw == null || !mounted) return;
    final name = normalizeProcessName(raw);
    if (name.isEmpty) {
      AppSnack.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Platform.isLinux
                ? l10n.splitAddAppInvalidLinux
                : l10n.splitAddAppInvalid,
          ),
        ),
      );
      return;
    }

    final asInclude = _mode == TunnelMode.includeOnly;
    await ref
        .read(splitTunnelingProvider.notifier)
        .addCustomProcess(raw, asInclude: asInclude);

    if (!mounted) return;
    setState(() {
      _allApps = _mergeCustomApps(_allApps);
      _onSearch();
    });
    AppSnack.of(context).showSnackBar(
      SnackBar(content: Text(l10n.splitAddAppAdded(name))),
    );
  }

  Future<void> _addRussianApps() async {
    if (_isDesktop) return;

    final l10n = AppLocalizations.of(context)!;
    final messenger = AppSnack.of(context);
    final notifier = ref.read(splitTunnelingProvider.notifier);

    if (_mode != TunnelMode.excludeOnly) {
      setState(() => _mode = TunnelMode.excludeOnly);
    }

    final visibleApps =
        ref.read(installedAppsProvider(_showSystem)).value ?? const <AppInfo>[];
    final quickRussian = visibleApps
        .where((a) => isRussianApp(a.packageName, isSystem: a.isSystem))
        .map((a) => a.packageName)
        .toList();
    var addedTotal = await notifier.addAllExcludes(quickRussian);

    // до проверки mounted: провайдер keepAlive, доскан доживёт и без экрана
    final fullScan = ref.read(installedAppsProvider(true).future);

    if (mounted) {
      setState(() {
        if (_allApps.isNotEmpty) _applyInitialSort(_allApps);
      });
      if (addedTotal > 0) {
        messenger.showSnackBar(SnackBar(
          content: Text(l10n.splitAddedRussianApps(addedTotal)),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ));
      } else if (quickRussian.isNotEmpty) {
        messenger.showSnackBar(SnackBar(
          content: Text(l10n.splitRussianAppsAlreadyAdded),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }

    List<AppInfo> allApps;
    try {
      allApps = await fullScan;
    } catch (_) {
      allApps = const [];
    }
    final extraAdded = await notifier.addAllExcludes([
      for (final a in allApps)
        if (isRussianApp(a.packageName, isSystem: a.isSystem)) a.packageName,
    ]);
    addedTotal += extraAdded;

    if (!mounted) return;
    if (!_showSystem) ref.invalidate(installedAppsProvider(true));
    if (extraAdded > 0) {
      setState(() {
        if (_allApps.isNotEmpty) _applyInitialSort(_allApps);
      });
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.splitAddedRussianApps(addedTotal)),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ));
    } else if (addedTotal == 0 && quickRussian.isEmpty) {
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.splitNoRussianAppsFound),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearch);
    _searchCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _setMode(TunnelMode mode) {
    setState(() {
      _mode = mode;
      _applyInitialSort(_allApps);
    });
    if (mode == TunnelMode.all) {
      ref.read(splitTunnelingProvider.notifier).clearAll();
    }
  }

  void _toggle(AppInfo app) {
    if (_mode == TunnelMode.all) return;
    ref
        .read(splitTunnelingProvider.notifier)
        .toggleApp(app, include: _mode == TunnelMode.includeOnly);
  }

  int _checkedCount(
    Set<String> includePackages,
    Set<String> excludePackages,
  ) =>
      switch (_mode) {
        TunnelMode.all => 0,
        TunnelMode.includeOnly => includePackages.length,
        TunnelMode.excludeOnly => excludePackages.length,
      };

  @override
  Widget build(BuildContext context) {
    final appsAsync = ref.watch(installedAppsProvider(_showSystem));
    final includePackages = ref.watch(
      splitTunnelingProvider.select((s) => s.includePackages),
    );
    final excludePackages = ref.watch(
      splitTunnelingProvider.select((s) => s.excludePackages),
    );
    ref.listen<Set<String>>(
      splitTunnelingProvider.select((s) => s.excludePackages),
      (prev, next) {
        if (!mounted || _allApps.isEmpty || prev == next) return;
        setState(() => _applyInitialSort(_allApps));
      },
    );
    ref.listen<Set<String>>(
      splitTunnelingProvider.select((s) => s.includePackages),
      (prev, next) {
        if (!mounted || _allApps.isEmpty || prev == next) return;
        setState(() => _applyInitialSort(_allApps));
      },
    );
    final settings = ref.watch(settingsNotifierProvider).value;
    final checked = _checkedCount(includePackages, excludePackages);
    final proxyModeOnDesktop = _isDesktop &&
        settings?.connectionModeEnum == ConnectionMode.proxy;
    final appsLoaded = appsAsync.hasValue;
    final vpnStatus = ref.watch(
      vpnStateProvider.select((a) => a.value?.status),
    );
    final tunnelActive = vpnStatus == VpnStatus.connected ||
        vpnStatus == VpnStatus.connecting;

    final l10n = AppLocalizations.of(context)!;

    final showFab = _isDesktop && _mode != TunnelMode.all;

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      floatingActionButton: showFab
          ? TvFocus.fab(
              (_) => FloatingActionButton.extended(
                onPressed: _showAddAppDialog,
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.splitAddApp),
              ),
            )
          : null,
      body: FadeTransition(
        opacity: _fadeCtrl,
        child: SmoothScroll(
          builder: (context, controller) => CustomScrollView(
            controller: controller,
            slivers: [
              ExpressiveScrolledUnderBuilder(
                builder: (context, background) {
                  final actions =
                      _appBarActions(l10n, checked, appsLoaded: appsLoaded);
                  return MediaQuery.sizeOf(context).height >= _largeTitleMinHeight
                      ? SliverAppBar.large(
                          title: Text(l10n.splitTunnelingTitle),
                          backgroundColor: background,
                          actions: actions,
                        )
                      : SliverAppBar(
                          title: Text(l10n.splitTunnelingTitle),
                          pinned: true,
                          backgroundColor: background,
                          actions: actions,
                        );
                },
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  ExpressiveSpacing.large,
                  ExpressiveSpacing.none,
                  ExpressiveSpacing.large,
                  ExpressiveSpacing.small,
                ),
                sliver: SliverList.list(
                  children: [
                    _ModeSelector(current: _mode, onChanged: _setMode),
                    if (tunnelActive) ...[
                      const SizedBox(height: ExpressiveSpacing.medium),
                      ExpressiveNotice(
                        color: AppTheme.orange(context),
                        icon: Icons.info_outline_rounded,
                        text: l10n.splitTunnelingReconnectHint,
                      ),
                    ],
                    if (proxyModeOnDesktop && _mode != TunnelMode.all) ...[
                      const SizedBox(height: ExpressiveSpacing.medium),
                      ExpressiveNotice(
                        color: AppTheme.orange(context),
                        text: l10n.splitProxyModeWarning,
                      ),
                    ],
                  ],
                ),
              ),
              ExpressiveScrolledUnderBuilder(
                builder: (context, background) => SliverPersistentHeader(
                  pinned: true,
                  delegate: _SearchHeaderDelegate(
                    controller: _searchCtrl,
                    hintText: l10n.splitSearchHint,
                    background: background,
                  ),
                ),
              ),
              if (checked > 0 && _mode != TunnelMode.all)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ExpressiveSpacing.large,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: ExpressiveSectionHeader(
                      l10n.splitSelectedAppsCount(checked),
                    ),
                  ),
                ),
              appsAsync.when(
                loading: () => const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: ShapeLoadingIndicator()),
                ),
                error: (e, _) => SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(ExpressiveSpacing.extraLarge),
                      child: Text(
                        l10n.splitFailedLoadApps(e.toString()),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.textLight(context),
                            ),
                      ),
                    ),
                  ),
                ),
                data: (apps) {
                  final filteredApps = _showSystem
                      ? apps
                      : apps.where((a) => !a.isSystem).toList();

                  if (_allApps.isEmpty && filteredApps.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() => _applyInitialSort(filteredApps));
                    });
                  }
                  final list = _allApps.isEmpty ? filteredApps : _displayList;
                  return _AppList(
                    apps: list,
                    mode: _mode,
                    includePackages: includePackages,
                    excludePackages: excludePackages,
                    onToggle: _toggle,
                    hasFab: showFab,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _appBarActions(
    AppLocalizations l10n,
    int checked, {
    required bool appsLoaded,
  }) {
    return [
      IconButton(
        tooltip:
            _showSystem ? l10n.splitHideSystemApps : l10n.splitShowSystemApps,
        isSelected: _showSystem,
        icon: Icon(
          _isDesktop ? Icons.computer_outlined : Icons.android_outlined,
        ),
        selectedIcon: Icon(
          _isDesktop ? Icons.computer_rounded : Icons.android_rounded,
        ),
        onPressed: () {
          setState(() {
            _showSystem = !_showSystem;
            _allApps = [];
          });
        },
      ),
      if (!_isDesktop &&
          (_mode == TunnelMode.excludeOnly || _mode == TunnelMode.all))
        IconButton(
          tooltip: l10n.splitAddRussianAppsBypass,
          icon: const _RuFlagIcon(),
          onPressed: appsLoaded ? _addRussianApps : null,
        ),
      if (_mode != TunnelMode.all && checked > 0)
        TextButton(
          onPressed: () {
            if (_mode == TunnelMode.includeOnly) {
              ref.read(splitTunnelingProvider.notifier).clearIncludes();
            } else {
              ref.read(splitTunnelingProvider.notifier).clearExcludes();
            }
          },
          child: Text(l10n.splitClear),
        ),
    ];
  }
}

class _ModeSelector extends StatelessWidget {
  final TunnelMode current;
  final void Function(TunnelMode) onChanged;
  const _ModeSelector({required this.current, required this.onChanged});

  static const double _height = 78;

  @override
  Widget build(BuildContext context) {
    final modes = TunnelMode.values;
    // две строки подписи при крупном шрифте Windows в 78 не влезали, низ обрезался
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _height),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < modes.length; i++)
              Expanded(child: _segment(context, modes, i)),
          ],
        ),
      ),
    );
  }

  Widget _segment(BuildContext context, List<TunnelMode> modes, int index) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mode = modes[index];
    final selected = mode == current;
    final foreground =
        selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;

    return Padding(
      padding: ExpressiveListSegment.segmentMargin(
        index: index,
        columns: modes.length,
      ),
      child: ExpressiveListSegment(
        radius: ExpressiveListSegment.segmentRadius(
          index: index,
          count: modes.length,
          columns: modes.length,
        ).resolve(Directionality.of(context)),
        selected: selected,
        color: scheme.surfaceContainerHigh,
        selectedColor: scheme.secondaryContainer,
        splashColor: scheme.primary.withValues(alpha: 0.2),
        highlightColor: scheme.primary.withValues(alpha: 0.08),
        onTap: () {
          if (selected) return;
          AppHaptics.selection();
          onChanged(mode);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ExpressiveSpacing.small,
            vertical: ExpressiveSpacing.small,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                mode.icon,
                size: ExpressiveIconSize.medium,
                color: foreground,
              ),
              const SizedBox(height: ExpressiveSpacing.extraSmall),
              Text(
                mode.label(l10n),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: (selected
                        ? theme.textTheme.emphasized(theme.textTheme.labelMedium)
                        : theme.textTheme.labelMedium)
                    ?.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchHeaderDelegate extends SliverPersistentHeaderDelegate {
  final TextEditingController controller;
  final String hintText;

  final Color background;

  const _SearchHeaderDelegate({
    required this.controller,
    required this.hintText,
    required this.background,
  });

  static const double _barHeight = 56;
  static const double _verticalPadding = ExpressiveSpacing.small;

  @override
  double get minExtent => _barHeight + _verticalPadding * 2;

  @override
  double get maxExtent => minExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: background,
      padding: const EdgeInsets.symmetric(
        horizontal: ExpressiveSpacing.large,
        vertical: _verticalPadding,
      ),
      child: _SearchField(controller: controller, hintText: hintText),
    );
  }

  @override
  bool shouldRebuild(covariant _SearchHeaderDelegate old) =>
      old.controller != controller ||
      old.hintText != hintText ||
      old.background != background;
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  const _SearchField({required this.controller, required this.hintText});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // крестик по самому полю: делегат прилипшей шапки пересобирается только при смене своих полей
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => SearchBar(
        controller: controller,
        hintText: hintText,
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        overlayColor: WidgetStatePropertyAll(
          scheme.onSurface.withValues(alpha: 0.08),
        ),
        shape: WidgetStatePropertyAll(
          ExpressiveShape.border(ExpressiveShape.full),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: ExpressiveSpacing.large),
        ),
        textStyle: WidgetStatePropertyAll(
          theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurface),
        ),
        hintStyle: WidgetStatePropertyAll(
          theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        leading: Icon(
          Icons.search_rounded,
          size: ExpressiveIconSize.large,
          color: scheme.onSurfaceVariant,
        ),
        trailing: [
          if (value.text.isNotEmpty)
            IconButton(
              tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
              icon: const Icon(Icons.close_rounded),
              iconSize: ExpressiveIconSize.medium,
              color: scheme.onSurfaceVariant,
              onPressed: controller.clear,
            ),
        ],
      ),
    );
  }
}

class _AppList extends StatelessWidget {
  final List<AppInfo> apps;
  final TunnelMode mode;
  final Set<String> includePackages;
  final Set<String> excludePackages;
  final void Function(AppInfo) onToggle;

  final bool hasFab;

  const _AppList({
    required this.apps,
    required this.mode,
    required this.includePackages,
    required this.excludePackages,
    required this.onToggle,
    required this.hasFab,
  });

  SplitSelection _selection() => SplitSelection(switch (mode) {
        TunnelMode.all => const <String>{},
        TunnelMode.includeOnly => includePackages,
        TunnelMode.excludeOnly => excludePackages,
      });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    if (apps.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: ExpressiveIconSize.extraLarge,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: ExpressiveSpacing.medium),
              Text(
                l10n.splitNoAppsFound,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        ExpressiveSpacing.large,
        ExpressiveSpacing.none,
        ExpressiveSpacing.large,
        hasFab ? 88 : ExpressiveSpacing.extraLarge,
      ),
      sliver: _AppListBody(
        apps: apps,
        mode: mode,
        selection: _selection(),
        onToggle: onToggle,
      ),
    );
  }
}

class _AppListBody extends ConsumerWidget {
  final List<AppInfo> apps;
  final TunnelMode mode;
  final SplitSelection selection;
  final void Function(AppInfo) onToggle;

  const _AppListBody({
    required this.apps,
    required this.mode,
    required this.selection,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iconCache = ref.read(appIconCacheProvider);
    // цвет отметки смысловой: в одном режиме строка идёт в туннель, в другом мимо, и перепутать их дорого
    final markColor = switch (mode) {
      TunnelMode.all => null,
      TunnelMode.includeOnly => AppTheme.green(context),
      TunnelMode.excludeOnly => AppTheme.orange(context),
    };
    return SliverFixedExtentList.builder(
      itemExtent: AppListTile.height,
      itemCount: apps.length,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: false,
      itemBuilder: (context, i) {
        final app = apps[i];
        return AppListTile(
          key: ValueKey(app.installPath ?? app.packageName),
          app: app,
          iconCache: iconCache,
          checked: selection.covers(app),
          markColor: markColor,
          radius: ExpressiveListSegment.segmentRadius(
            index: i,
            count: apps.length,
          ).resolve(Directionality.of(context)),
          margin: ExpressiveListSegment.segmentMargin(index: i)
              .resolve(Directionality.of(context)),
          onTap:
              mode == TunnelMode.all ? null : () => onToggle(app),
        );
      },
    );
  }
}

class _RuFlagIcon extends StatelessWidget {
  const _RuFlagIcon();

  @override
  Widget build(BuildContext context) {
    const double size = 22;
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: Column(
          children: [
            Expanded(child: Container(color: const Color(0xFFFFFFFF))),
            Expanded(child: Container(color: const Color(0xFF0039A6))),
            Expanded(child: Container(color: const Color(0xFFD52B1E))),
          ],
        ),
      ),
    );
  }
}
