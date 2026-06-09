import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/shared/ui/app_theme.dart';

import '../models/app_info.dart';
import '../providers/providers.dart';
import '../platform/platform_bootstrap.dart';
import '../tunnel/connection_mode.dart';
import '../utils/process_name_utils.dart';

const _kRussianPackagePrefixes = <String>[
  'ru.yandex.', 'com.yandex.',
  'com.vkontakte.', 'com.vk.', 'ru.vk.',
  'com.mailru.', 'ru.mail.',
  'com.odnoklassniki.', 'ru.ok.',
  'ru.sberbank.', 'ru.sbrf.', 'com.sberbank.',
  'com.idamob.tinkoff.', 'ru.tinkoff.',
  'ru.vtb.', 'ru.vtb24.',
  'ru.alfabank.',
  'ru.gazprombank.',
  'com.gosuslugi.', 'ru.gosuslugi.', 'ru.gov.',
  'ru.rostel.',
  'ru.mts.', 'com.mts.', 'ru.megafon.', 'ru.beeline.', 'com.beeline.', 'ru.rt.',
  'ru.dublgis.',
  'ru.avito.', 'com.avito.',
  'ru.hh.',
  'ru.ozon.',
  'ru.wildberries.',
  'ru.lamoda.',
  'ru.delivery.', 'com.delivery.',
  'ru.ivi.',
  'ru.kinopoisk.',
  'ru.start.',
  'ru.okko.', 'tv.more.',
  'ru.raiffeisen.', 'ru.rosbank.', 'ru.open.',
  'ru.psbank.', 'ru.sovcombank.', 'ru.bspb.', 'ru.mkb.', 'ru.akbars.',
  'ru.domclick.',
  'ru.kontur.', 'ru.tensor.', 'ru.taxcom.',
  'ru.nalog.', 'ru.pfr.',
  'ru.rosreestr.',
  'ru.apteki.', 'ru.eapteka.', 'ru.zdravcity.',
  'ru.superjob.', 'ru.cian.',
  'ru.auto.', 'ru.drom.',
  'ru.litres.', 'ru.skyeng.',
  'ru.rambler.', 'ru.rbc.',
  'ru.russianpost.', 'com.gnivc.', 'ru.minsvyaz.', 'ru.mchs.', 'ru.mos.',
  'ru.nspk.',
  'com.kaspersky.', 'com.kms.', 'com.drweb.', 'com.ncloudtech.',
  'ru.beru.', 'ru.tander.', 'ru.x5.', 'ru.vkusvill.', 'ru.bstr.', 'ru.dodopizza.',
  'ru.mvideo.', 'ru.eldorado.', 'ru.dns.shop.', 'ru.sportmaster.', 'ru.detmir.', 'ru.kazanexpress.',
  'ru.rzd.', 'ru.aeroflot.', 'ru.s7.', 'ru.pobeda.',
  'com.whoosh.', 'ru.urent.', 'com.citymobil.', 'com.taximaxim.', 'ru.tutu.',
  'ru.rutube.', 'ru.smotrim.', 'premier.one.', 'ru.tnt.', 'ru.yappy.', 'com.vbc.', 'ru.youla.', 'ru.sports.',
  'ru.tele2.', 'ru.yota.', 'ru.tinkoff.mobile.',
  'com.vk.max', 'ru.vk.max', 'ru.oneme.app', 'ru.max',
];

const _kRussianPackageSegments = <String>[
  'sberbank', 'sberonline', 'sbrf',
  'tinkoff', 'idamob',
  'alfabank',
  'vtb', 'vtb24',
  'gosuslugi', 'goskey',
  'yandex',
  'vkontakte',
  'odnoklassniki',
  'megafon',
  'beeline',
  'ozon',
  'wildberries',
  'kinopoisk',
  'avito',
  'gazprombank',
  'raiffeisen',
  'rosbank',
  'sovcombank',
  'domclick',
  'apteki',
];

// кириллица в названии приложения
final _cyrillicRe = RegExp(r'[а-яёА-ЯЁ]');

bool _isRussianApp(AppInfo app) {
  final pkg = app.packageName.toLowerCase();
  if (_kRussianPackagePrefixes.any((p) => pkg.startsWith(p))) return true;
  if (_kRussianPackageSegments.any((s) => pkg.contains(s))) return true;
  if (_cyrillicRe.hasMatch(app.appName)) return true;
  return false;
}


enum TunnelMode { all, includeOnly, excludeOnly }

extension TunnelModeX on TunnelMode {
  String label(AppLocalizations l10n) => switch (this) {
    TunnelMode.all => l10n.splitModeAllApps,
    TunnelMode.includeOnly => l10n.splitModeSelectedOnly,
    TunnelMode.excludeOnly => l10n.splitModeAllExceptSelected,
  };
  IconData get icon => switch (this) {
    TunnelMode.all         => Icons.public,
    TunnelMode.includeOnly => Icons.shield_outlined,
    TunnelMode.excludeOnly => Icons.alt_route,
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

  List<AppInfo> _allApps = [];
  List<AppInfo> _displayList = [];
  bool get _isDesktop => PlatformBootstrap.isDesktop;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350))
      ..forward();
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

  List<AppInfo> _mergeCustomApps(List<AppInfo> apps) {
    final split = ref.read(splitTunnelingProvider);
    final known = apps.map((a) => a.packageName.toLowerCase()).toSet();
    final customIds = <String>{
      ...split.includePackages,
      ...split.excludePackages,
    }..removeWhere(known.contains);
    if (customIds.isEmpty) return apps;
    final custom = customIds
        .map(
          (id) => AppInfo(
            packageName: normalizeProcessName(id),
            appName: id.contains(r'\') || id.contains('/')
                ? id.split(RegExp(r'[\\/]')).last
                : id,
          ),
        )
        .toList();
    return [...custom, ...apps];
  }

  void _applyInitialSort(List<AppInfo> apps) {
    final split = ref.read(splitTunnelingProvider);
    final checked = _checkedSet(split);
    final merged = _mergeCustomApps(apps);
    _allApps = [
      ...merged.where((a) => checked.contains(a.packageName)),
      ...merged.where((a) => !checked.contains(a.packageName)),
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
    final ctrl = TextEditingController();
    var pickedPath = '';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card(context),
        title: Text(l10n.splitAddAppTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              decoration: InputDecoration(
                hintText: l10n.splitAddAppHint,
              ),
              autofocus: true,
            ),
            if (_isDesktop) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final r = await FilePicker.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: const ['exe'],
                    );
                    if (r != null && r.files.single.path != null) {
                      pickedPath = r.files.single.path!;
                      ctrl.text = pickedPath;
                    }
                  },
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: Text(l10n.splitAddAppPickFile),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.splitAddApp),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;
    final raw = pickedPath.isNotEmpty ? pickedPath : ctrl.text;
    final name = normalizeProcessName(raw);
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.splitAddAppInvalid)),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.splitAddAppAdded(name))),
    );
  }

  Future<void> _addRussianApps() async {
    if (_isDesktop) return;

    final allApps = ref.read(installedAppsProvider(true)).value ?? [];
    final russianPkgs = allApps
        .where((a) => _isRussianApp(a))
        .map((a) => a.packageName)
        .toList();

    if (russianPkgs.isEmpty) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.splitNoRussianAppsFound),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }

    if (_mode != TunnelMode.excludeOnly) {
      setState(() => _mode = TunnelMode.excludeOnly);
    }

    final notifier = ref.read(splitTunnelingProvider.notifier);
    final current = ref.read(splitTunnelingProvider).excludePackages;
    final toAdd = russianPkgs.where((p) => !current.contains(p)).toList();

    await notifier.addAllExcludes(toAdd);

    if (mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          toAdd.isEmpty
              ? l10n.splitRussianAppsAlreadyAdded
              : l10n.splitAddedRussianApps(toAdd.length),
        ),
        duration: const Duration(seconds: 3),
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

  void _toggle(String pkg) {
    if (_mode == TunnelMode.all) return;
    if (_mode == TunnelMode.includeOnly) {
      ref.read(splitTunnelingProvider.notifier).toggleInclude(pkg);
    } else {
      ref.read(splitTunnelingProvider.notifier).toggleExclude(pkg);
    }
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
    final settings = ref.watch(settingsNotifierProvider).value;
    final checked = _checkedCount(includePackages, excludePackages);
    final proxyModeOnDesktop = _isDesktop &&
        settings?.connectionModeEnum == ConnectionMode.proxy;

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: _buildAppBar(checked),
      floatingActionButton: _isDesktop && _mode != TunnelMode.all
          ? FloatingActionButton.extended(
              onPressed: _showAddAppDialog,
              icon: const Icon(Icons.add),
              label: Text(AppLocalizations.of(context)!.splitAddApp),
            )
          : null,
      body: FadeTransition(
        opacity: _fadeCtrl,
        child: Column(
          children: [
            _ModeSelector(current: _mode, onChanged: _setMode),
            if (proxyModeOnDesktop && _mode != TunnelMode.all)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Material(
                  color: AppTheme.orange(context).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      AppLocalizations.of(context)!.splitProxyModeWarning,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: AppTheme.text(context),
                      ),
                    ),
                  ),
                ),
              ),
            _SearchBar(controller: _searchCtrl),
            Expanded(
              child: appsAsync.when(
                loading: () => Center(
                  child: CircularProgressIndicator(color: AppTheme.accent(context), strokeWidth: 2),
                ),
                error: (e, _) => Center(
                  child: Text(AppLocalizations.of(context)!.splitFailedLoadApps(e.toString()),
                      style: TextStyle(color: AppTheme.textLight(context))),
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
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar(int checked) {
    final l10n = AppLocalizations.of(context)!;
    return AppBar(
      backgroundColor: AppTheme.bg(context),
      elevation: 0,
      iconTheme: IconThemeData(color: AppTheme.text(context)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.splitTunnelingTitle,
              style: TextStyle(color: AppTheme.text(context), fontWeight: FontWeight.w700, fontSize: 17)),
          if (checked > 0 && _mode != TunnelMode.all)
            Text(l10n.splitSelectedAppsCount(checked),
                style: TextStyle(color: AppTheme.textLight(context), fontSize: 11)),
        ],
      ),
      actions: [
        IconButton(
          tooltip: _showSystem ? l10n.splitHideSystemApps : l10n.splitShowSystemApps,
          icon: Icon(
            _showSystem
                ? (_isDesktop ? Icons.computer : Icons.android)
                : (_isDesktop ? Icons.computer_outlined : Icons.android_outlined),
            size: 20,
            color: _showSystem ? AppTheme.accent(context) : AppTheme.textLight(context),
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
            onPressed: _allApps.isEmpty ? null : _addRussianApps,
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
            child: Text(l10n.splitClear, style: TextStyle(color: AppTheme.textLight(context), fontSize: 13)),
          ),
      ],
    );
  }
}

// селектор режимов
class _ModeSelector extends StatelessWidget {
  final TunnelMode current;
  final void Function(TunnelMode) onChanged;
  const _ModeSelector({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    final modes = TunnelMode.values;
    final currentIndex = modes.indexOf(current);

    final alignmentX = -1.0 + (currentIndex * (2.0 / (modes.length - 1)));

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.divider(context).withValues(alpha: 0.5),
          width: 1,
        ),
        boxShadow:[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Stack(
          children:[
            AnimatedAlign(
              alignment: Alignment(alignmentX, 0),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              child: FractionallySizedBox(
                widthFactor: 1 / modes.length,
                heightFactor: 1.0,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.accent(context),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow:[
                      BoxShadow(
                        color: AppTheme.accent(context).withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                ),
              ),
            ),

            Row(
              children: modes.map((mode) {
                final active = mode == current;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(mode),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children:[
                          Icon(
                            mode.icon,
                            size: 18,
                            color: active ? onPrimary : AppTheme.textLight(context),
                          ),
                          const SizedBox(height: 3),
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                              color: active ? onPrimary : AppTheme.textLight(context),
                            ),
                            child: Text(
                              mode.label(l10n),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}


// поиск
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  const _SearchBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow:[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          controller: controller,
          style: TextStyle(color: AppTheme.text(context), fontSize: 14),
          decoration: InputDecoration(
            hintText: l10n.splitSearchHint,
            hintStyle: TextStyle(color: AppTheme.textLight(context).withValues(alpha: 0.6), fontSize: 14),
            prefixIcon: Icon(Icons.search, color: AppTheme.textLight(context), size: 20),
            suffixIcon: controller.text.isNotEmpty
                ? IconButton(
              icon: Icon(Icons.close, color: AppTheme.textLight(context), size: 18),
              onPressed: controller.clear,
              padding: EdgeInsets.zero,
            )
                : null,
            filled: true,
            fillColor: AppTheme.card(context),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppTheme.divider(context).withValues(alpha: 0.5), width: 1),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppTheme.divider(context).withValues(alpha: 0.5), width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppTheme.accent(context), width: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}

// список приложений
class _AppList extends StatelessWidget {
  final List<AppInfo> apps;
  final TunnelMode mode;
  final Set<String> includePackages;
  final Set<String> excludePackages;
  final void Function(String) onToggle;

  const _AppList({
    required this.apps,
    required this.mode,
    required this.includePackages,
    required this.excludePackages,
    required this.onToggle,
  });

  bool _isChecked(String pkg) => switch (mode) {
        TunnelMode.all => false,
        TunnelMode.includeOnly => includePackages.contains(pkg),
        TunnelMode.excludeOnly => excludePackages.contains(pkg),
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (apps.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children:[
            Icon(Icons.search_off, size: 40, color: AppTheme.accent(context).withValues(alpha: 0.4)),
            const SizedBox(height: 10),
            Text(l10n.splitNoAppsFound,
                style: TextStyle(color: AppTheme.textLight(context), fontSize: 14)),
          ],
        ),
      );
    }


    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: apps.length,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final app = apps[i];
        final checked = _isChecked(app.packageName);

        return _AppTile(
          key: ValueKey(app.packageName),
          app: app,
          checked: checked,
          mode: mode,
          onTap: mode == TunnelMode.all ? null : () => onToggle(app.packageName),
        );
      },
    );
  }
}

// строка приложения
class _AppTile extends StatelessWidget {
  final AppInfo app;
  final bool checked;
  final TunnelMode mode;
  final VoidCallback? onTap;

  const _AppTile({
    super.key,
    required this.app,
    required this.checked,
    required this.mode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);

    return Material(
      color: checked ? AppTheme.accent(context).withValues(alpha: 0.1) : AppTheme.card(context),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: checked
              ? AppTheme.accent(context)
              : AppTheme.divider(context).withValues(alpha: 0.5),
          width: checked ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        splashColor: AppTheme.accent(context).withValues(alpha: 0.2),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children:[
              // РРєРѕРЅРєР° РїСЂРёР»РѕР¶РµРЅРёСЏ
              _AppIcon(
                iconBase64: app.iconBase64,
                appName: app.appName,
                iconPath: app.installPath,
              ),
              const SizedBox(width: 14),
              // название и package
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children:[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            app.appName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight:
                                  checked ? FontWeight.w700 : FontWeight.w600,
                              color: AppTheme.text(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (app.isRunning) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.green(context)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '●',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppTheme.green(context),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      app.installPath ?? app.packageName,
                      style: TextStyle(fontSize: 12, color: AppTheme.textLight(context)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (mode != TunnelMode.all)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return ScaleTransition(scale: animation, child: child);
                  },
                  child: checked
                      ? Container(
                    key: const ValueKey('checked'),
                    width: 26, height: 26,
                    decoration: BoxDecoration(
                      color: mode == TunnelMode.includeOnly
                          ? AppTheme.green(context)
                          : AppTheme.orange(context),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check, size: 16, color: Colors.white),
                  )
                      : Container(
                    key: const ValueKey('unchecked'),
                    width: 26, height: 26,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppTheme.divider(context).withValues(alpha: 0.8),
                        width: 2,
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// иконка приложения, exe-иконки на windows подгружаем лениво, вне горячего пути списка
class _AppIcon extends ConsumerStatefulWidget {
  final String? iconBase64;
  final String appName;
  final String? iconPath;
  const _AppIcon({
    required this.iconBase64,
    required this.appName,
    this.iconPath,
  });

  @override
  ConsumerState<_AppIcon> createState() => _AppIconState();
}

class _AppIconState extends ConsumerState<_AppIcon> {
  Uint8List? _bytes;
  bool _loadingIcon = false;

  @override
  void initState() {
    super.initState();
    _applyIcon(widget.iconBase64);
    if (_bytes == null && widget.iconPath != null && widget.iconPath!.isNotEmpty) {
      _loadIconLazy();
    }
  }

  @override
  void didUpdateWidget(_AppIcon old) {
    super.didUpdateWidget(old);
    if (old.iconBase64 != widget.iconBase64) {
      _applyIcon(widget.iconBase64);
    }
    if (_bytes == null &&
        old.iconPath != widget.iconPath &&
        widget.iconPath != null &&
        widget.iconPath!.isNotEmpty) {
      _loadIconLazy();
    }
  }

  void _applyIcon(String? src) {
    if (src != null && src.isNotEmpty) {
      try {
        _bytes = base64Decode(src);
      } catch (_) {
        _bytes = null;
      }
    } else {
      _bytes = null;
    }
  }

  Future<void> _loadIconLazy() async {
    if (_loadingIcon || !mounted) return;
    _loadingIcon = true;
    final path = widget.iconPath!;
    try {
      final b64 = await ref.read(vpnEngineProvider).getAppIcon(path);
      if (!mounted || b64 == null || b64.isEmpty) return;
      setState(() => _applyIcon(b64));
    } finally {
      _loadingIcon = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          _bytes!,
          width: 42, height: 42,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => _fallback(context),
        ),
      );
    }
    return _fallback(context);
  }

  Widget _fallback(BuildContext context) => Container(
    width: 42, height: 42,
    decoration: BoxDecoration(
      color: AppTheme.accent(context).withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Center(
      child: Text(
        widget.appName.isNotEmpty ? widget.appName[0].toUpperCase() : '?',
        style: TextStyle(
            color: AppTheme.text(context), fontSize: 18, fontWeight: FontWeight.bold),
      ),
    ),
  );
}
// флаг ru в круге (иконка в appbar)
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
            Expanded(child: Container(color: const Color(0xFFFFFFFF))), // Р±РµР»С‹Р№
            Expanded(child: Container(color: const Color(0xFF0039A6))), // СЃРёРЅРёР№
            Expanded(child: Container(color: const Color(0xFFD52B1E))), // РєСЂР°СЃРЅС‹Р№
          ],
        ),
      ),
    );
  }
}

