part of '../settings_tab.dart';

/// Панель «Внутренности»: что за ядра стоят, какой они версии, какие geo-базы,
/// что происходит в текущей сессии и на чём всё запущено.
///
/// Данные собираются на открытие экрана и пересобираются, когда подключение
/// поднялось или упало, — чтобы PID и порты не остались от прошлой жизни.
///
/// Следим ИМЕННО за статусом, а не за всем состоянием: в нём едет телеметрия
/// трафика, и она меняется раз в секунду. Пересборка на каждый тик означала бы
/// перечитывание десятков мегабайт бинарей ядра ежесекундно.
final _appInternalsProvider = FutureProvider.autoDispose<AppInternals>((
  ref,
) async {
  final settings = await ref.watch(settingsNotifierProvider.future);
  ref.watch(vpnStateProvider.select((state) => state.value?.status));
  return AppInternalsService.collect(
    settings: settings,
    state: ref.read(vpnStateProvider).value,
  );
});

class _AppInternalsScreen extends ConsumerWidget {
  const _AppInternalsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final internals = ref.watch(_appInternalsProvider);

    return ExpressivePage(
      title: l10n.settingsInternalsTitle,
      physics: const ClampingScrollPhysics(),
      actions: [
        IconButton(
          tooltip: l10n.settingsInternalsCopyAll,
          icon: const Icon(Icons.copy_all_rounded),
          onPressed: internals.value == null
              ? null
              : () => _copyReport(context, l10n, internals.value!),
        ),
      ],
      children: switch (internals) {
        AsyncData(:final value) => _sections(context, ref, l10n, value),
        AsyncError(:final error) => [
            ExpressiveNotice(
              color: Theme.of(context).colorScheme.error,
              icon: Icons.error_outline_rounded,
              text: friendlyError(error, context),
            ),
          ],
        _ => const [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: ShapeLoadingIndicator()),
            ),
          ],
      },
    );
  }

  List<Widget> _sections(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    AppInternals data,
  ) {
    return [
      // Экран называется «О приложении», и начинаться он должен с того, ради
      // чего его чаще всего и открывают, — версии. Ядра и сессия ниже: это
      // уже подробности для тех, кто пришёл за ними.
      ExpressiveSectionHeader(l10n.settingsInternalsBuild),
      ExpressiveGroup(children: _buildRows(l10n, data.build)),

      // Режим — выше ядер: он отвечает на более крупный вопрос («забирать ли
      // весь трафик устройства»), чем то, каким бинарём исполнять сервер.
      // Только на Android: на десктопе тот же выбор живёт в боковой панели,
      // рядом с кнопкой подключения, и второй его копии тут не нужно.
      if (Platform.isAndroid) ...[
        ExpressiveSectionHeader(l10n.settingsTunnelModeSection),
        const ExpressiveGroup(
          children: [
            _TunnelModeTile(mode: ConnectionMode.tun),
            _TunnelModeTile(mode: ConnectionMode.proxy),
            _ProxyAuthTile(),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            l10n.settingsTunnelModeHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textLight(context),
                ),
          ),
        ),
      ],

      ExpressiveSectionHeader(l10n.settingsInternalsCores),
      if (data.cores.isEmpty)
        ExpressiveGroup(
          children: [
            _InternalsRow(label: l10n.settingsInternalsNoCores, value: ''),
          ],
        )
      else ...[
        ExpressiveGroup(
          children: [
            // «Само» — первым: это умолчание и правильный ответ для почти
            // всех. Ручной выбор ниже нужен ровно для обычных ссылок, всё
            // остальное исполняет то ядро, на языке которого написано.
            if (mihomoShipsHere) const _AutoCoreTile(),
            for (final core in data.cores)
              if (_selectableCore(core) case final vpnCore?)
                _SelectableCoreTile(core: core, value: vpnCore)
              else
                _CoreTile(core: core),
          ],
        ),
        // Подсказка стоит под группой, а не внутри: внутри она была бы
        // сегментом без заливки и рвала бы containment посередине списка.
        if (mihomoShipsHere)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              l10n.settingsCoreHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textLight(context),
                  ),
            ),
          ),
        // Выбранное ядро не исполняет активный сервер — говорим об этом прямо
        // здесь. Без плашки настройка выглядела сломанной: выбран mihomo, а
        // строкой ниже, в «Текущей сессии», честно стоит libxray.
        if (_coreMismatch(ref) case final skip?) ...[
          const SizedBox(height: 8),
          ExpressiveNotice(
            color: AppTheme.orange(context),
            icon: Icons.info_outline_rounded,
            text: _coreMismatchText(l10n, skip),
          ),
        ],
      ],

      ExpressiveSectionHeader(l10n.settingsInternalsGeo),
      ExpressiveGroup(
        children: [
          for (final base in data.geoBases) _GeoTile(base: base),
          // Догрузка полной базы стран — только там, где вшита урезанная.
          // На десктопе рядом с бинарником лежит полная, качать нечего.
          if (GeoBaseDownloader.isSupported && _geoipIsTrimmed(data.geoBases))
            const _GeoDownloadTile(),
        ],
      ),

      ExpressiveSectionHeader(l10n.settingsInternalsSession),
      ExpressiveGroup(children: _sessionRows(context, l10n, data.session)),
    ];
  }

  List<Widget> _sessionRows(
    BuildContext context,
    AppLocalizations l10n,
    SessionInfo session,
  ) {
    final dash = l10n.settingsInternalsUnavailable;
    return [
      _InternalsRow(
        label: l10n.settingsInternalsStatus,
        value: _statusLabel(l10n, session.status),
        accent: session.isActive,
      ),
      _InternalsRow(
        label: l10n.settingsInternalsEngine,
        value: session.engine,
      ),
      if (session.mode != null)
        _InternalsRow(
          label: l10n.settingsInternalsMode,
          value: session.mode == ConnectionMode.tun ? 'TUN' : 'Proxy',
        ),
      _InternalsRow(
        label: l10n.settingsInternalsPorts,
        value: 'SOCKS ${session.socksPort} · HTTP ${session.httpPort}',
      ),
      if (session.clashApiPort != null)
        _InternalsRow(
          label: l10n.settingsInternalsClashPort,
          value: '${session.clashApiPort}',
        ),
      _InternalsRow(
        label: l10n.settingsInternalsUptime,
        value: session.uptime == null
            ? dash
            : _formatDuration(session.uptime!),
      ),
      _InternalsRow(
        label: l10n.settingsInternalsCorePids,
        value: session.corePids.isEmpty
            ? dash
            : session.corePids.entries
                .map((e) => '${e.key} ${e.value}')
                .join('\n'),
      ),
      if (session.elevated != null)
        _InternalsRow(
          label: l10n.settingsInternalsElevated,
          value: session.elevated!
              ? l10n.settingsInternalsYes
              : l10n.settingsInternalsNo,
        ),
    ];
  }

  List<Widget> _buildRows(AppLocalizations l10n, BuildInfo build) {
    return [
      _InternalsRow(
        label: l10n.settingsInternalsAppVersion,
        value: '${build.appVersion} (${build.buildNumber})',
      ),
      _InternalsRow(
        label: l10n.settingsInternalsPackage,
        value: build.packageName,
      ),
      _InternalsRow(
        label: l10n.settingsInternalsOs,
        value: build.osVersion,
      ),
      _InternalsRow(label: l10n.settingsInternalsAbi, value: build.abi),
      _InternalsRow(
        label: l10n.settingsInternalsDart,
        value: build.dartVersion,
      ),
      _InternalsRow(
        label: l10n.settingsInternalsBuildMode,
        value: build.releaseMode ? 'release' : 'debug',
      ),
    ];
  }

  Future<void> _copyReport(
    BuildContext context,
    AppLocalizations l10n,
    AppInternals data,
  ) async {
    await Clipboard.setData(
      ClipboardData(text: AppInternalsService.report(data)),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.settingsInternalsCopied)),
    );
  }

  static String _statusLabel(AppLocalizations l10n, VpnStatus status) {
    return switch (status) {
      VpnStatus.connected => l10n.trayStatusConnected,
      VpnStatus.connecting => l10n.vpnConnecting,
      VpnStatus.disconnecting => l10n.vpnDisconnecting,
      VpnStatus.error => l10n.settingsInternalsStatusError,
      VpnStatus.disconnected => l10n.trayStatusDisconnected,
    };
  }
}

/// Ядро: имя и роль сверху, версия крупно, движки внутри и файл — мелко.
///
/// Если ядро выбирается ([selected] не null), плитка становится и переключателем
/// — с кружком выбора справа от имени. Выбор живёт здесь, а не отдельным
/// списком сверху, потому что решение принимают именно по этим данным: версия,
/// дата сборки, есть ли бинарь вообще.
class _CoreTile extends StatelessWidget {
  final CoreInfo core;

  /// null — ядро не участвует в выборе (tun2socks, wg-go, десктопные бинари).
  final bool? selected;

  /// Заменяет подпись роли: у двух прокси-движков она одинаковая и в момент
  /// выбора бесполезна — важнее, чем они друг от друга отличаются.
  final String? subtitle;

  final VoidCallback? onTap;

  const _CoreTile({
    required this.core,
    this.selected,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    final version = core.missing
        ? l10n.settingsInternalsCoreMissing
        : core.version ?? l10n.settingsInternalsVersionFromEngines;

    return ExpressiveGroupTile(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Иконка у всех ядер одна: они и есть одно и то же — ядро.
              // Разные значки на соседних строках читались как разные сущности
              // и «случайные картинки», хотя различает их подпись роли.
              ExpressiveIconBadge(
                icon: Icons.memory_rounded,
                accent: core.missing
                    ? ExpressiveAccent.secondary
                    : ExpressiveAccent.primary,
              ),
              const SizedBox(width: ExpressiveSpacing.large),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      core.name,
                      style: textTheme.titleMedium?.copyWith(
                        color: AppTheme.text(context),
                      ),
                    ),
                    Text(
                      subtitle ?? _roleLabel(l10n, core.role),
                      style: textTheme.bodySmall?.copyWith(
                        color: AppTheme.textLight(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected != null) ...[
                const SizedBox(width: ExpressiveSpacing.large),
                Icon(
                  selected!
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected!
                      ? AppTheme.accent(context)
                      : AppTheme.textLight(context),
                ),
              ],
            ],
          ),
          // Версия — своей строкой во всю ширину, а не прижатой вправо: у
          // псевдоверсии xray длина такая, что в колонке справа она ломалась
          // пополам, и три плитки подряд выглядели как три разных вёрстки.
          const SizedBox(height: 10),
          SelectableText(
            version,
            style: textTheme.bodyMedium?.copyWith(
              color: core.missing || core.version == null
                  ? AppTheme.textLight(context)
                  : AppTheme.accent(context),
            ),
          ),
          // Для keqrnel это главное: своей версии у него нет, а вопрос
          // «какой внутри xray» задают именно про него.
          if (core.engines.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final engine in core.engines.entries)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: SelectableText(
                  '${engine.key} ${engine.value}',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppTheme.text(context),
                  ),
                ),
              ),
          ],
          if (!core.missing) ...[
            const SizedBox(height: 10),
            Text(
              _fileLine(l10n, core),
              style: textTheme.bodySmall?.copyWith(
                color: AppTheme.textLight(context),
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _fileLine(AppLocalizations l10n, CoreInfo core) {
    final parts = <String>[
      if (core.sizeBytes != null) formatBytes(core.sizeBytes!),
      if (core.modified != null) formatFileDate(core.modified!),
      if (core.goVersion != null) core.goVersion!,
    ];
    return parts.join(' · ');
  }

  static String _roleLabel(AppLocalizations l10n, CoreRole role) =>
      switch (role) {
        CoreRole.core => l10n.settingsInternalsRoleCore,
        CoreRole.proxy => l10n.settingsInternalsRoleProxy,
        CoreRole.tun => l10n.settingsInternalsRoleTun,
        CoreRole.amneziawg => l10n.settingsInternalsRoleAwg,
      };
}

/// Урезана ли база стран — по числу кодов в ней самой, а не по флажку в
/// настройках: флажок разъедется с диском, коды и есть диск.
bool _geoipIsTrimmed(List<GeoBaseInfo> bases) {
  for (final b in bases) {
    if (b.name != 'geoip.dat') continue;
    return !b.missing && b.codeCount < GeoAssetIndex.fullGeoipCodeThreshold;
  }
  return false;
}

/// Кнопка догрузки полной базы стран.
///
/// Стоит прямо под строками гео-баз, потому что решение принимается по ним же:
/// человек видит «кодов: 4» и рядом объяснение с кнопкой, а не ищет настройку
/// в другом месте.
class _GeoDownloadTile extends ConsumerStatefulWidget {
  const _GeoDownloadTile();

  @override
  ConsumerState<_GeoDownloadTile> createState() => _GeoDownloadTileState();
}

class _GeoDownloadTileState extends ConsumerState<_GeoDownloadTile> {
  bool _busy = false;
  double _progress = 0;
  String? _error;

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _progress = 0;
      _error = null;
    });
    try {
      await GeoBaseDownloader.install(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      // Панель читает размеры и число кодов при построении, поэтому после
      // подмены базы её надо перечитать — иначе останется «кодов: 4».
      ref.invalidate(_appInternalsProvider);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ExpressiveActionTile(
      icon: Icons.public_rounded,
      title: l10n.settingsInternalsGeoDownload,
      subtitle: _error != null
          ? l10n.settingsInternalsGeoDownloadFailed(_error!)
          : (_busy
              ? '${(_progress * 100).round()}%'
              : l10n.settingsInternalsGeoTrimmedHint),
      accent: ExpressiveAccent.tertiary,
      danger: _error != null,
      onTap: _busy ? () {} : _download,
    );
  }
}

class _GeoTile extends StatelessWidget {
  final GeoBaseInfo base;
  const _GeoTile({required this.base});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (base.missing) {
      return _InternalsRow(
        label: base.name,
        value: l10n.settingsInternalsCoreMissing,
      );
    }
    return _InternalsRow(
      label: base.name,
      value: l10n.settingsInternalsGeoCodes(base.codeCount),
      detail: [
        if (base.sizeBytes != null) formatBytes(base.sizeBytes!),
        if (base.modified != null) formatFileDate(base.modified!),
      ].join(' · '),
    );
  }
}

/// Строка «подпись — значение», собранная стопкой: подпись сверху мелким,
/// значение под ней во всю ширину.
///
/// Так, а не в две колонки, потому что значения здесь длинные и заранее
/// неизвестной длины — имя пакета, версия ОС, «SOCKS 2080 · HTTP 2081». В две
/// колонки они жались в узкий правый столбец, переносились по слогам и рвали
/// имя пакета посреди слова, а прижатые вправо строки разной длины смотрелись
/// разнобоем. Одна колонка слева — ни переносов, ни рваного края.
///
/// Значение выделяемое: панель существует ровно для того, чтобы её содержимое
/// можно было куда-то отправить.
class _InternalsRow extends StatelessWidget {
  final String label;
  final String value;
  final String? detail;
  final bool accent;

  const _InternalsRow({
    required this.label,
    required this.value,
    this.detail,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ExpressiveGroupTile(
      // Ширину задаём явно: колонка тянется по содержимому, и без этого
      // плитки сжимались каждая под свой текст и вставали лесенкой по центру
      // группы. Раньше ширину держал Expanded внутри Row.
      child: SizedBox(
        width: double.infinity,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: AppTheme.textLight(context),
            ),
          ),
          if (value.isNotEmpty) ...[
            const SizedBox(height: 2),
            SelectableText(
              value,
              style: textTheme.bodyMedium?.copyWith(
                color: accent
                    ? AppTheme.accent(context)
                    : AppTheme.text(context),
              ),
            ),
          ],
          if (detail != null && detail!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              detail!,
              style: textTheme.bodySmall?.copyWith(
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

/// Причина, по которой выбранное ядро не возьмёт активный сервер, или null —
/// возьмёт (либо выбран xray, который умеет всё).
///
/// Считается по активному серверу, а не по всему списку: ядро выбирается для
/// подключения, а подключение идёт к нему одному.
VpnCoreSkip? _coreMismatch(WidgetRef ref) {
  final server = ref.watch(serversProvider).activeServer;
  if (server == null) return null;
  final core = ref.watch(
    settingsNotifierProvider.select(
      (a) => a.value?.vpnCore ?? AppSettings.vpnCoreAuto,
    ),
  );
  return resolveVpnBackend(
    config: server.config,
    preference: core,
    mihomoAvailable: mihomoShipsHere,
  ).skip;
}

String _coreMismatchText(AppLocalizations l10n, VpnCoreSkip skip) =>
    switch (skip) {
      VpnCoreSkip.customConfig => l10n.settingsCoreSkipCustom,
      VpnCoreSkip.chain => l10n.settingsCoreSkipChain,
      VpnCoreSkip.amneziaWg => l10n.settingsCoreSkipAwg,
      VpnCoreSkip.clashConfig => l10n.settingsCoreSkipClash,
      VpnCoreSkip.platform => l10n.settingsCoreSkipPlatform,
    };

/// Пароль локального прокси и сами креды. Видна только в режиме «Прокси»: в
/// режиме VPN в ядро ходит один tun2socks, и креды ему передаются мимо человека.
class _ProxyAuthTile extends ConsumerWidget {
  const _ProxyAuthTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final settings = ref.watch(settingsNotifierProvider.select((a) => a.value));
    final chosen = settings?.connectionModeChosen ?? false;
    final mode = chosen
        ? ConnectionMode.fromStorage(settings?.connectionMode)
        : ConnectionMode.tun;
    if (mode != ConnectionMode.proxy) return const SizedBox.shrink();

    final on = settings?.proxyModeAuth ?? true;
    final user = settings?.proxyModeUser ?? '';
    final pass = settings?.proxyModePass ?? '';

    Future<void> toggle(bool v) async {
      final s = await ref.read(settingsNotifierProvider.future);
      await ref
          .read(settingsNotifierProvider.notifier)
          .save(s.copyWith(proxyModeAuth: v));
    }

    return ExpressiveGroupTile(
      padding: const EdgeInsets.all(16),
      onTap: () => toggle(!on),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExpressiveIconBadge(
                icon: Icons.password_rounded,
                accent: ExpressiveAccent.tertiary,
              ),
              const SizedBox(width: ExpressiveSpacing.large),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.settingsProxyAuthTitle,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: AppTheme.text(context)),
                    ),
                    Text(
                      l10n.settingsProxyAuthSubtitle,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppTheme.textLight(context)),
                    ),
                  ],
                ),
              ),
              Switch(value: on, onChanged: toggle),
            ],
          ),
          // Креды показываем только когда они есть: до первого подключения в
          // этом режиме их ещё не создавали, и пустые строки читались бы как
          // «пароль пустой».
          if (on && user.isNotEmpty && pass.isNotEmpty) ...[
            const SizedBox(height: 12),
            _InternalsRow(label: l10n.settingsProxyAuthUser, value: user),
            _InternalsRow(label: l10n.settingsProxyAuthPass, value: pass),
          ],
        ],
      ),
    );
  }
}

/// Выбор режима: полноценный VPN или только локальный прокси.
///
/// Два слова взяты не наугад. «VPN» — то, чем режим является для системы:
/// именно его показывает ключик в статусбаре и диалог разрешения. «Прокси» —
/// то, чем становится приложение без туннеля: локальный SOCKS/HTTP, к которому
/// приложения подключаются сами. Ни «TUN», ни «tun2socks» тут не звучат — это
/// имена наших внутренностей, а не то, что выбирает человек.
class _TunnelModeTile extends ConsumerWidget {
  final ConnectionMode mode;

  const _TunnelModeTile({required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final settingsValue = ref.watch(
      settingsNotifierProvider.select((a) => a.value),
    );
    // Пока режим не выбирали руками, показываем VPN — ровно то, что и будет
    // подключено (см. TunnelSessionBuilder.resolveMode). Иначе экран показывал
    // бы «Прокси», а подключался VPN.
    final current = (settingsValue?.connectionModeChosen ?? false)
        ? ConnectionMode.fromStorage(settingsValue?.connectionMode)
        : ConnectionMode.tun;
    final selected = current == mode;
    final isProxy = mode == ConnectionMode.proxy;

    Future<void> select() async {
      if (selected) return;
      final settings = await ref.read(settingsNotifierProvider.future);
      await ref.read(settingsNotifierProvider.notifier).save(
            settings.copyWith(
              connectionMode: mode.storageValue,
              connectionModeChosen: true,
            ),
          );
    }

    return ExpressiveGroupTile(
      padding: const EdgeInsets.all(16),
      onTap: select,
      child: Row(
        children: [
          ExpressiveIconBadge(
            icon: isProxy ? Icons.lan_rounded : Icons.vpn_lock_rounded,
            accent: isProxy
                ? ExpressiveAccent.secondary
                : ExpressiveAccent.primary,
          ),
          const SizedBox(width: ExpressiveSpacing.large),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isProxy ? l10n.settingsTunnelModeProxy : l10n.settingsTunnelModeVpn,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppTheme.text(context),
                  ),
                ),
                Text(
                  isProxy
                      ? l10n.settingsTunnelModeProxySubtitle
                      : l10n.settingsTunnelModeVpnSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.textLight(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: ExpressiveSpacing.large),
          Icon(
            selected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded,
            color: selected
                ? AppTheme.accent(context)
                : AppTheme.textLight(context),
          ),
        ],
      ),
    );
  }
}

/// «Само»: ядро выбирает формат сервера, а не пользователь.
///
/// Отдельной плиткой, а не переключателем над списком: выбор здесь один и тот
/// же — из чего исполнять сервер, — и все его варианты должны стоять в одном
/// ряду, иначе «авто» читается как ещё одна настройка поверх выбранного ядра.
class _AutoCoreTile extends ConsumerWidget {
  const _AutoCoreTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final selected = ref.watch(
          settingsNotifierProvider.select((a) => a.value?.vpnCore),
        ) ==
        AppSettings.vpnCoreAuto;

    Future<void> select() async {
      if (selected) return;
      final settings = await ref.read(settingsNotifierProvider.future);
      await ref
          .read(settingsNotifierProvider.notifier)
          .save(settings.copyWith(vpnCore: AppSettings.vpnCoreAuto));
    }

    return ExpressiveGroupTile(
      padding: const EdgeInsets.all(16),
      onTap: select,
      child: Row(
        children: [
          ExpressiveIconBadge(
            icon: Icons.auto_awesome_rounded,
            accent: ExpressiveAccent.primary,
          ),
          const SizedBox(width: ExpressiveSpacing.large),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsCoreAuto,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppTheme.text(context),
                  ),
                ),
                Text(
                  l10n.settingsCoreAutoSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.textLight(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: ExpressiveSpacing.large),
          Icon(
            selected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded,
            color: selected
                ? AppTheme.accent(context)
                : AppTheme.textLight(context),
          ),
        ],
      ),
    );
  }
}

/// Ядра, между которыми пользователь выбирает: имя файла → значение
/// [AppSettings.vpnCore].
///
/// Имена платформенные, но роль одна: слева — то, что исполняет конфиги xray
/// (на десктопе это keqrnel, внутри которого тот же xray), справа — mihomo.
const _selectableCores = <String, String>{
  'libxray.so': AppSettings.vpnCoreXray,
  'keqrnel.exe': AppSettings.vpnCoreXray,
  'keqrnel': AppSettings.vpnCoreXray,
  'libmihomo.so': AppSettings.vpnCoreMihomo,
  'mihomo.exe': AppSettings.vpnCoreMihomo,
  'mihomo': AppSettings.vpnCoreMihomo,
};

/// Значение [AppSettings.vpnCore] для плитки — или null, если это ядро не
/// выбирают. Отсутствующий бинарь выбрать нельзя: выбирать нечего.
String? _selectableCore(CoreInfo core) =>
    core.missing ? null : _selectableCores[core.name];

/// Плитка ядра, которая заодно выбирает его.
///
/// Смена на живом подключении ничего не переподключает — новое ядро поднимется
/// на следующем коннекте, о чём и говорит подпись под группой.
///
/// Цепочки и готовые xray-конфиги остаются на xray независимо от выбора: они
/// описаны в терминах xray, и переводить их в mihomo нечего (см.
/// vpn_state_provider).
class _SelectableCoreTile extends ConsumerWidget {
  final CoreInfo core;

  /// Значение [AppSettings.vpnCore], которое ставит эта плитка.
  final String value;

  const _SelectableCoreTile({required this.core, required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final current = ref.watch(
      settingsNotifierProvider.select(
        (a) => a.value?.vpnCore ?? AppSettings.vpnCoreAuto,
      ),
    );

    Future<void> select() async {
      if (value == current) return;
      final settings = await ref.read(settingsNotifierProvider.future);
      await ref
          .read(settingsNotifierProvider.notifier)
          .save(settings.copyWith(vpnCore: value));
    }

    return _CoreTile(
      core: core,
      selected: value == current,
      subtitle: switch (value) {
        AppSettings.vpnCoreMihomo => l10n.settingsCoreMihomoSubtitle,
        _ => l10n.settingsCoreXraySubtitle,
      },
      onTap: select,
    );
  }
}

String _formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
