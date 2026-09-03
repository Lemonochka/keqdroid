import 'dart:convert';
import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:keqdroid/shared/ui/expressive_elements.dart';
import 'package:keqdroid/shared/ui/expressive_group.dart';
import 'package:keqdroid/shared/ui/haptics.dart';
import 'package:keqdroid/shared/ui/scrolled_under.dart';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/shared/ui/app_theme.dart';
import 'package:keqdroid/shared/ui/shape_loading_indicator.dart';
import 'package:keqdroid/shared/ui/smooth_scroll.dart';

import '../models/app_info.dart';
import '../providers/providers.dart';
import '../platform/platform_bootstrap.dart';
import '../services/app_icon_cache.dart';
import '../services/file_dialog_service.dart';
import '../tunnel/connection_mode.dart';
import '../tunnel/tunnel_state.dart';
import '../utils/error_messages.dart';
import '../utils/process_name_utils.dart';
import '../utils/split_tunneling_entries.dart';

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

// Русскость определяется ТОЛЬКО по имени пакета (курируемые списки ниже).
// Язык отображаемого имени (кириллица в app.appName) НЕ используется: на
// ru-locale системные приложения MIUI/HyperOS и сторонние (клавиатура FUTO
// и т.п.) локализованы кириллицей и ошибочно попадали в bypass-список.
bool _isRussianApp(AppInfo app) {
  final pkg = app.packageName.toLowerCase();
  if (_kRussianPackagePrefixes.any((p) => pkg.startsWith(p))) return true;
  if (_kRussianPackageSegments.any((s) => pkg.contains(s))) return true;
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

  /// Ниже этой высоты окна крупный заголовок не показываем — значение и повод
  /// те же, что у `ExpressivePage._largeTitleMinHeight`.
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

  /// Записи, которых нет в списке процессов, — добавленные руками exe.
  ///
  /// Сравнение идёт по ключу [splitEntryKey], а не по сырой строке. Раньше
  /// `known` собирался в нижнем регистре, а сохранённые имена — нет: Windows
  /// отдаёт `Discord.exe`, в списках оседает `Discord.exe`, и проверка
  /// `known.contains('Discord.exe')` не находила `discord.exe`. Каждое
  /// выбранное приложение считалось «добавленным руками» и приписывалось в
  /// начало списка ВТОРОЙ строкой — без пути и без иконки.
  ///
  /// Хуже того, слияние повторялось поверх уже слитого списка на каждое
  /// изменение выбора, и лишняя строка прибавлялась к каждой галочке снова и
  /// снова: отсюда и три-четыре одинаковых Discord.exe подряд.
  List<AppInfo> _mergeCustomApps(List<AppInfo> apps) {
    final split = ref.read(splitTunnelingProvider);
    final seen = apps.map((a) => splitEntryKey(a.packageName)).toSet();
    final custom = <AppInfo>[];
    for (final id in {...split.includePackages, ...split.excludePackages}) {
      final key = splitEntryKey(id);
      // `add` возвращает false и на «уже есть в списке», и на второй вариант
      // того же имени в самих списках (`Telegram.exe` рядом с `telegram.exe`).
      if (key.isEmpty || !seen.add(key)) continue;
      custom.add(
        AppInfo(
          packageName: normalizeProcessName(id),
          appName: id.contains(r'\') || id.contains('/')
              ? id.split(RegExp(r'[\\/]')).last
              : id,
        ),
      );
    }
    if (custom.isEmpty) return apps;
    return [...custom, ...apps];
  }

  void _applyInitialSort(List<AppInfo> apps) {
    final split = ref.read(splitTunnelingProvider);
    final checkedKeys = _checkedSet(split).map(splitEntryKey).toSet();
    // Схлопывание — страховка на случай, если дубли придут откуда-то ещё
    // (список процессов, накопленное состояние прошлых версий): экран не
    // должен показывать одно приложение дважды ни при каких входных данных.
    final merged = dedupeSplitEntries(_mergeCustomApps(apps));
    bool isChecked(AppInfo a) => checkedKeys.contains(splitEntryKey(a.packageName));
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
    final ctrl = TextEditingController();
    var pickedPath = '';

    // Почему не открылся выбор файла — прямо в диалоге: снекбар Scaffold
    // рисует под ним, и объяснение осталось бы за модальным барьером.
    String? pickError;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        // Заливка и форма — из `dialogTheme`: локальный `backgroundColor`
        // повторял тот же `surfaceContainerHigh`, но мимо темы, и в flair-темах
        // диалог не получал их усиленных скруглений.
        builder: (ctx, setDialogState) => AlertDialog(
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
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () async {
                    try {
                      final r = await AppFileDialogs.pickFile(
                        dialogTitle: l10n.splitAddAppPickFile,
                        type: FileType.custom,
                        allowedExtensions: const ['exe'],
                      );
                      if (r?.path != null) {
                        pickedPath = r!.path!;
                        ctrl.text = pickedPath;
                      }
                    } catch (e) {
                      // Путь всё ещё можно вписать руками в поле выше —
                      // поэтому только объясняем, а диалог не закрываем.
                      setDialogState(
                        () => pickError = friendlyErrorDetailed(e, ctx),
                      );
                    }
                  },
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: Text(l10n.splitAddAppPickFile),
                ),
              ),
              if (pickError != null) ...[
                const SizedBox(height: 8),
                Text(
                  pickError!,
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: AppTheme.red(ctx),
                      ),
                ),
              ],
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

    // Всё, что нужно после await, захватываем заранее: экран могут закрыть,
    // пока идёт долгий скан, и ref/context станут недоступны.
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(splitTunnelingProvider.notifier);

    if (_mode != TunnelMode.excludeOnly) {
      setState(() => _mode = TunnelMode.excludeOnly);
    }

    // 1) Мгновенный проход по уже загруженному списку — галочки и снекбар
    //    появляются сразу. Полный список (includeSystem=true, с иконками
    //    каждого пакета) телефон собирает 5–30 секунд — всё это время без
    //    быстрого прохода не было бы никакой реакции на кнопку.
    final visibleApps =
        ref.read(installedAppsProvider(_showSystem)).value ?? const <AppInfo>[];
    final quickRussian = visibleApps
        .where(_isRussianApp)
        .map((a) => a.packageName)
        .toList();
    var addedTotal = await notifier.addAllExcludes(quickRussian);

    // Полный скан запускаем до проверки mounted: провайдер keepAlive, а
    // добавляет notifier уровня приложения — доскан доживёт и без экрана.
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

    // 2) Доскан по полному списку (включая системные/предустановленные).
    List<AppInfo> allApps;
    try {
      allApps = await fullScan;
    } catch (_) {
      allApps = const [];
    }
    final extraAdded = await notifier.addAllExcludes(
      allApps.where(_isRussianApp).map((a) => a.packageName).toList(),
    );
    addedTotal += extraAdded;

    if (!mounted) return;
    // Полный список (includeSystem=true, иконки всех пакетов — мегабайты)
    // нужен был только ради packageName'ов. Если экран его сейчас не
    // показывает — освобождаем, не дожидаясь таймера autoDispose.
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

    // Экран собран одной прокруткой, а не шапкой поверх `Column` с `Expanded`.
    // Так он начинается крупным заголовком, как остальные подэкраны настроек
    // (см. `ExpressivePage`), режим и предупреждения уезжают вместе с
    // содержимым, а поиск остаётся прилипшим под шапкой — он нужен на любой
    // позиции списка в пару сотен строк.
    final showFab = _isDesktop && _mode != TunnelMode.all;

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      floatingActionButton: showFab
          ? FloatingActionButton.extended(
              onPressed: _showAddAppDialog,
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.splitAddApp),
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
                  // Правило крупного заголовка — то же, что у `ExpressivePage`:
                  // на невысоком вьюпорте (окно из трея) 152dp шапки съели бы
                  // половину экрана, а длинный заголовок в узком окне ещё и
                  // разъехался бы на три строки.
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
                    // Списки include/exclude читаются только в момент connect() —
                    // при активном туннеле изменения вступят в силу лишь после
                    // переподключения, и без подсказки это выглядит как «не работает».
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
              // Поиск красится тем же цветом, что и шапка над ним: прилипшая
              // полоса обязана быть с ней одной поверхностью, иначе под шапкой
              // едет вторая, другого тона.
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
      // Показ системных — переключаемая иконка-кнопка M3: включённое состояние
      // несёт её собственный контейнер, а не подмена цвета иконки вручную.
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

/// Селектор режимов: три сегмента списка M3E.
///
/// Был самодельный переключатель из M2 — общая рамка, две тени и подсветка,
/// ездящая под подписями через `AnimatedAlign`. Теперь выбор несут ровно те же
/// средства, что у строк серверов и плиток тем: заливка `secondaryContainer` и
/// морф формы (внутренние углы 4dp → 16dp у выбранного), причём пружинами из
/// спеки движения, а не кривой с длительностью.
///
/// Почему не [ExpressiveConnectedButtons], штатная замена сегментированной
/// кнопки: её подписи живут в одну строку с многоточием, а «Все кроме
/// выбранных» и «Только выбранные» в треть ширины телефона не влезают — от
/// режима осталось бы «Все кр…». Сегменты списка дают ту же анатомию выбора и
/// две строки под подпись.
class _ModeSelector extends StatelessWidget {
  final TunnelMode current;
  final void Function(TunnelMode) onChanged;
  const _ModeSelector({required this.current, required this.onChanged});

  /// Высота сегмента: иконка, зазор и две строки подписи `labelMedium`.
  static const double _height = 78;

  @override
  Widget build(BuildContext context) {
    final modes = TunnelMode.values;
    return SizedBox(
      height: _height,
      child: Row(
        children: [
          for (var i = 0; i < modes.length; i++)
            Expanded(child: _segment(context, modes, i)),
        ],
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
        ),
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

/// Прилипшая полоса поиска.
///
/// Живёт слайвером, а не строкой в `Column`: список длиной в пару сотен строк
/// без прилипшего поиска заставлял бы прокручивать вверх ради каждого запроса.
class _SearchHeaderDelegate extends SliverPersistentHeaderDelegate {
  final TextEditingController controller;
  final String hintText;

  /// Цвет шапки над полосой. Прилипшая полоса обязана быть с ней ОДНОЙ
  /// поверхностью, иначе под шапкой едет вторая, другого тона.
  final Color background;

  const _SearchHeaderDelegate({
    required this.controller,
    required this.hintText,
    required this.background,
  });

  /// Контейнер поиска по спеке — 56dp; поля сверху и снизу держат его на
  /// расстоянии от шапки и первой строки списка.
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

/// Поиск на штатном `SearchBar` M3.
///
/// Было текстовое поле с собственной тенью, рамкой в полупрозрачный
/// `outlineVariant` и радиусом 16 — ни filled, ни outlined, а помесь. У M3
/// поиск — отдельный компонент со своей анатомией: пилюля, заливка контейнера
/// и никакой тени.
class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  const _SearchField({required this.controller, required this.hintText});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Кнопку очистки показываем по СОДЕРЖИМОМУ поля, а не по перестройке
    // экрана: делегат прилипшей шапки пересобирается только при смене своих
    // полей, и без этой подписки крестик появлялся бы через раз.
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

// список приложений
class _AppList extends StatelessWidget {
  final List<AppInfo> apps;
  final TunnelMode mode;
  final Set<String> includePackages;
  final Set<String> excludePackages;
  final void Function(String) onToggle;

  /// Есть ли над списком расширенный FAB. Если есть — последняя строка должна
  /// уезжать из-под него, иначе до неё не дотянуться.
  final bool hasFab;

  const _AppList({
    required this.apps,
    required this.mode,
    required this.includePackages,
    required this.excludePackages,
    required this.onToggle,
    required this.hasFab,
  });

  /// Отмеченные — ключами, а не сырыми строками: сохранённый `telegram.exe` и
  /// пришедший из системы `Telegram.exe` — одна и та же строка списка, и
  /// галочка обязана стоять в обоих случаях. Считаем один раз на построение
  /// списка, а не на каждую из сотен строк.
  Set<String> _checkedKeys() => switch (mode) {
        TunnelMode.all => const <String>{},
        TunnelMode.includeOnly => includePackages.map(splitEntryKey).toSet(),
        TunnelMode.excludeOnly => excludePackages.map(splitEntryKey).toSet(),
      };

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

    // Строки — сегменты одного списка, а не отдельные карточки с зазором в
    // 10px: зазор набирается полями САМОГО сегмента, поэтому шаг списка
    // остаётся постоянным и его можно отдать `SliverFixedExtentList` — тот не
    // раскладывает каждую строку ради высоты. На списке в пару сотен
    // приложений это и есть разница между рывками и ровной прокруткой.
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        ExpressiveSpacing.large,
        ExpressiveSpacing.none,
        ExpressiveSpacing.large,
        // 88 — высота расширенного FAB с его полями: ровно столько нужно, чтобы
        // последняя строка не пряталась под кнопкой.
        hasFab ? 88 : ExpressiveSpacing.extraLarge,
      ),
      sliver: _AppListBody(
        apps: apps,
        mode: mode,
        checkedKeys: _checkedKeys(),
        onToggle: onToggle,
      ),
    );
  }
}

/// Тело списка вынесено отдельным виджетом: набор отмеченных считается один
/// раз на построение, а не в каждом `itemBuilder`.
class _AppListBody extends ConsumerWidget {
  final List<AppInfo> apps;
  final TunnelMode mode;
  final Set<String> checkedKeys;
  final void Function(String) onToggle;

  const _AppListBody({
    required this.apps,
    required this.mode,
    required this.checkedKeys,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Кэш иконок берём ОДИН раз на список, а не в каждой строке: строка с
    // собственным `ConsumerStatefulWidget` тащила бы за собой ещё и область
    // зависимостей Riverpod — на сотнях строк это не бесплатно.
    final iconCache = ref.read(appIconCacheProvider);
    return SliverFixedExtentList.builder(
      itemExtent: _AppTile.height,
      itemCount: apps.length,
      // Строка и так завёрнута в свой `RepaintBoundary`, а держать её живой
      // после ухода с экрана незачем: обе обёртки — это по два лишних виджета
      // на КАЖДУЮ строку, а их тут пара сотен.
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: false,
      itemBuilder: (context, i) {
        final app = apps[i];
        return _AppTile(
          key: ValueKey(app.packageName),
          app: app,
          iconCache: iconCache,
          checked: checkedKeys.contains(splitEntryKey(app.packageName)),
          mode: mode,
          radius: ExpressiveListSegment.segmentRadius(
            index: i,
            count: apps.length,
          ),
          margin: ExpressiveListSegment.segmentMargin(index: i),
          onTap:
              mode == TunnelMode.all ? null : () => onToggle(app.packageName),
        );
      },
    );
  }
}

/// Строка приложения — сегмент списка M3E.
///
/// Была карточка с собственной рамкой: невыбранная в полупрозрачный
/// `outlineVariant`, выбранная — в акцент толщиной 1.5px поверх заливки на 10%
/// альфы. Рамка на КАЖДОЙ строке и есть тот самый шум, от которого у M3E
/// уходят к контейнерам: теперь строку отделяет заливка, а выбор несут морф
/// формы и `secondaryContainer` — ровно как у строк серверов.
class _AppTile extends StatelessWidget {
  final AppInfo app;
  final bool checked;
  final TunnelMode mode;

  /// Форма сегмента: считает её список — только он знает, где у строки сосед,
  /// а где край группы.
  final BorderRadius radius;

  /// Поля сегмента внутри шага списка; из них набирается зазор между строками.
  final EdgeInsets margin;

  final VoidCallback? onTap;

  /// Кэш иконок приходит сверху — см. комментарий в [_AppListBody].
  final AppIconCache iconCache;

  /// ШАГ списка вместе с зазором — от него живёт `SliverFixedExtentList`.
  /// 40dp иконки и две строки текста укладываются в 72 с полями по 8.
  static const double height = 72;

  /// Размер индикатора выбора: XSmall-контейнер иконки M3E.
  static const double _markSize = 24;

  const _AppTile({
    super.key,
    required this.app,
    required this.checked,
    required this.mode,
    required this.radius,
    required this.margin,
    required this.onTap,
    required this.iconCache,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground =
        checked ? scheme.onSecondaryContainer : scheme.onSurface;
    final muted = checked
        ? scheme.onSecondaryContainer.withValues(alpha: 0.7)
        : scheme.onSurfaceVariant;
    final titleStyle = checked
        ? theme.textTheme.emphasized(theme.textTheme.bodyLarge)
        : theme.textTheme.bodyLarge;

    return RepaintBoundary(
      child: MergeSemantics(
        child: Padding(
          padding: margin,
          child: ExpressiveListSegment(
            radius: radius,
            selected: checked,
            color: scheme.surfaceContainerHigh,
            selectedColor: scheme.secondaryContainer,
            onTap: onTap == null
                ? null
                : () {
                    AppHaptics.selection();
                    onTap!();
                  },
            splashColor: scheme.primary.withValues(alpha: 0.2),
            highlightColor: scheme.primary.withValues(alpha: 0.08),
            child: Padding(
              // Отступ leading-слота по спеке списка — 16dp от края контейнера.
              padding: const EdgeInsets.symmetric(
                horizontal: ExpressiveSpacing.large,
              ),
              child: Row(
                children: [
                  _AppIcon(
                    iconBase64: app.iconBase64,
                    appName: app.appName,
                    iconPath: app.installPath,
                    cache: iconCache,
                  ),
                  const SizedBox(width: ExpressiveSpacing.medium),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                app.appName,
                                style: titleStyle?.copyWith(color: foreground),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Процесс запущен — точка, а не «●» в плашке:
                            // символ жил на своей типографике и прыгал по
                            // базовой линии между шрифтами тем.
                            if (app.isRunning) ...[
                              const SizedBox(width: ExpressiveSpacing.small),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: AppTheme.green(context),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          app.installPath ?? app.packageName,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (mode != TunnelMode.all) ...[
                    const SizedBox(width: ExpressiveSpacing.medium),
                    _SelectionMark(checked: checked, mode: mode),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Отметка выбора: зелёная у «только выбранные», оранжевая у «кроме выбранных».
///
/// Смысловой цвет здесь остаётся сознательно: строка одинаково «выбрана» в
/// обоих режимах, но в одном она идёт В туннель, а в другом мимо него, и
/// перепутать их дорого.
class _SelectionMark extends StatelessWidget {
  final bool checked;
  final TunnelMode mode;
  const _SelectionMark({required this.checked, required this.mode});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final markColor = mode == TunnelMode.includeOnly
        ? AppTheme.green(context)
        : AppTheme.orange(context);

    return AnimatedSwitcher(
      duration: ExpressiveMotion.durationFast,
      switchInCurve: ExpressiveMotion.emphasized,
      transitionBuilder: (child, animation) =>
          ScaleTransition(scale: animation, child: child),
      child: checked
          ? Container(
              key: const ValueKey('checked'),
              width: _AppTile._markSize,
              height: _AppTile._markSize,
              decoration: BoxDecoration(color: markColor, shape: BoxShape.circle),
              child: Icon(
                Icons.check_rounded,
                size: ExpressiveIconSize.inline,
                color: scheme.surface,
              ),
            )
          : Container(
              key: const ValueKey('unchecked'),
              width: _AppTile._markSize,
              height: _AppTile._markSize,
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outline, width: 2),
                shape: BoxShape.circle,
              ),
            ),
    );
  }
}

// иконка приложения, exe-иконки на windows подгружаем лениво, вне горячего пути списка
class _AppIcon extends StatefulWidget {
  final String? iconBase64;
  final String appName;
  final String? iconPath;

  /// Кэш приходит сверху, а не берётся из провайдера здесь: строка списка не
  /// должна тащить за собой область зависимостей Riverpod ради одного чтения.
  final AppIconCache cache;

  const _AppIcon({
    required this.iconBase64,
    required this.appName,
    required this.cache,
    this.iconPath,
  });

  @override
  State<_AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<_AppIcon> {
  Uint8List? _bytes;

  AppIconCache get _cache => widget.cache;

  /// Путь, по которому мы сейчас числимся в очереди кэша: по нему же и
  /// отписываемся. Хранить отдельно от `widget.iconPath` обязательно — в
  /// `dispose` виджет может уже нести другой путь.
  String? _pendingPath;

  @override
  void initState() {
    super.initState();
    _applyIcon(widget.iconBase64);
    if (_bytes == null) _loadIcon();
  }

  @override
  void didUpdateWidget(_AppIcon old) {
    super.didUpdateWidget(old);
    if (old.iconBase64 != widget.iconBase64) {
      _applyIcon(widget.iconBase64);
    }
    if (old.iconPath != widget.iconPath) {
      _releasePending();
      if (_bytes == null) _loadIcon();
    }
  }

  @override
  void dispose() {
    _releasePending();
    super.dispose();
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

  void _releasePending() {
    final path = _pendingPath;
    if (path == null) return;
    _pendingPath = null;
    _cache.release(path);
  }

  /// Иконка через общий кэш.
  ///
  /// Раньше каждая строка при появлении дёргала нативную выемку сама, без
  /// кэша: на быстрой прокрутке поток платформы разбирал десятки таких
  /// вызовов подряд, и список рвало. Уже добытая иконка теперь ставится
  /// СРАЗУ, без кадра с буквой-заглушкой, а строка, улетевшая с экрана до
  /// своей очереди, запрос забирает.
  void _loadIcon() {
    final path = widget.iconPath;
    if (path == null || path.isEmpty) return;
    if (_cache.has(path)) {
      _bytes = _cache.peek(path);
      return;
    }
    _pendingPath = path;
    _cache.request(path).then((bytes) {
      if (!mounted || bytes == null) return;
      setState(() => _bytes = bytes);
    });
  }

  /// Leading-слот строки по спеке списка M3E.
  static const double _size = 40;

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return ClipRRect(
        borderRadius: ExpressiveShape.radius(ExpressiveShape.medium),
        child: Image.memory(
          _bytes!,
          width: _size,
          height: _size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          // Иконка приезжает крупнее слота (нативная часть просит 128 и
          // спускается вниз), поэтому здесь она УМЕНЬШАЕТСЯ — а на уменьшении
          // качество фильтра как раз и видно.
          filterQuality: FilterQuality.medium,
          // Декодируем под фактический размер слота: исходные иконки бывают до
          // 512×512, полноразмерный декод раздувал image cache в разы.
          cacheWidth: (_size * MediaQuery.devicePixelRatioOf(context)).round(),
          errorBuilder: (context, error, stackTrace) => _fallback(context),
        ),
      );
    }
    return _fallback(context);
  }

  /// Приложение без иконки — буква в контейнере роли, а не акцент на 30%
  /// альфы: полупрозрачность сводилась с заливкой строки, и на выбранной
  /// кружок съезжал в другой оттенок.
  Widget _fallback(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: ExpressiveShape.radius(ExpressiveShape.medium),
      ),
      child: Center(
        child: Text(
          widget.appName.isNotEmpty ? widget.appName[0].toUpperCase() : '?',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
        ),
      ),
    );
  }
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
            Expanded(child: Container(color: const Color(0xFFFFFFFF))), // белый
            Expanded(child: Container(color: const Color(0xFF0039A6))), // синий
            Expanded(child: Container(color: const Color(0xFFD52B1E))), // красный
          ],
        ),
      ),
    );
  }
}

