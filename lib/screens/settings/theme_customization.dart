part of '../settings_tab.dart';

Widget appearanceGeneralTabForTest(
  AppSettings current, {
  Future<void> Function(AppSettings)? onSave,
}) =>
    _AppearanceGeneralTab(current: current, onSave: onSave ?? (_) async {});

class _ThemeCustomizationCard extends ConsumerWidget {
  final AsyncValue<AppSettings> settingsAsync;
  const _ThemeCustomizationCard({required this.settingsAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = settingsAsync.value ?? const AppSettings();
    // themePresetFor: своей темы в списке нет, и resolveThemePreset дал бы Ocean
    final preset = themePresetFor(settings);
    final modeLabel = settings.darkTheme ? l10n.themeModeDark : l10n.themeModeLight;
    final isDesktop = PlatformBootstrap.isDesktop;
    final subtitle = settings.followSystemTheme
        ? (isDesktop
            ? l10n.settingsSystemColorsSubtitle(modeLabel)
            : l10n.settingsAndroidColorsSubtitle(modeLabel))
        // без изоляции в фарси решётка уезжает в конец
        : '${ltrIsolate(preset.name)} · $modeLabel';
    return _SettingsCard(
      title: AppLocalizations.of(context)!.settingsThemeTitle,
      subtitle: subtitle,
      icon: isDesktop ? Icons.desktop_windows_rounded : Icons.palette_rounded,
      accent: ExpressiveAccent.primary,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => _ThemeCustomizationScreen(settings: settings)),
      ),
    );
  }
}

class _ThemeCustomizationScreen extends ConsumerWidget {
  final AppSettings settings;
  const _ThemeCustomizationScreen({required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final current = ref.watch(settingsNotifierProvider).value ?? settings;
    final controlsAccent = AppTheme.accent(context);

    Future<void> save(AppSettings next) async {
      await ref.read(settingsNotifierProvider.notifier).save(next);
    }

    final tabBar = TabBar(
      labelColor: controlsAccent,
      unselectedLabelColor: AppTheme.textLight(context),
      indicatorColor: controlsAccent,
      dividerColor: AppTheme.divider(context),
      tabs: [
        Tab(text: l10n.appearanceTabGeneral),
        Tab(text: l10n.appearanceTabThemes),
      ],
    );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.bg(context),
        appBar: ExpressiveScrolledUnderBar(
          preferredSize: Size.fromHeight(
            kToolbarHeight + tabBar.preferredSize.height,
          ),
          builder: (context, background) => AppBar(
            backgroundColor: background,
            title: Text(l10n.themeCustomizationTitle),
            bottom: tabBar,
          ),
        ),
        // без TabBarView: его PageView зовёт jumpToPage в didChangeDependencies,
        // и смена темы отсюда же даёт setState() called during build
        body: Builder(
          builder: (context) {
            final tabController = DefaultTabController.of(context);
            return ListenableBuilder(
              listenable: tabController,
              builder: (context, _) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: KeyedSubtree(
                  key: ValueKey(tabController.index),
                  child: tabController.index == 0
                      ? _AppearanceGeneralTab(current: current, onSave: save)
                      : _AppearanceThemesTab(current: current, onSave: save),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AppearanceGeneralTab extends ConsumerWidget {
  final AppSettings current;
  final Future<void> Function(AppSettings) onSave;
  const _AppearanceGeneralTab({required this.current, required this.onSave});

  // по ширине экрана: на телефоне список серверов во всю ширину
  String? _columnsNote(BuildContext context, AppLocalizations l10n) {
    if (!current.serversTwoColumns) return null;
    final wanted = ServerRow.wantedColumns(current);
    final fit = ServerRow.fittingColumns(
      MediaQuery.sizeOf(context).width,
      MediaQuery.textScalerOf(context),
      wanted,
    );
    if (fit == 1) return l10n.serversColumnsNoRoom;
    return fit < wanted ? l10n.serversColumnsOnlyFit(fit) : null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return SmoothScroll(
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(16),
        children: [
          _FontPicker(
            currentFontId: current.fontId,
            onSelect: (id) => onSave(current.copyWith(fontId: id)),
          ),
          const SizedBox(height: 8),
          _UiScalePicker(
            value: current.uiScale,
            onChanged: (v) => onSave(current.copyWith(uiScale: v)),
          ),
          const SizedBox(height: 8),
          _IconShapePicker(
            currentShapeId: current.iconShapeId,
            onSelect: (id) => onSave(current.copyWith(iconShapeId: id)),
          ),
          const SizedBox(height: 8),
          ExpressiveSectionHeader(l10n.appearanceSectionServers),
          ExpressiveGroup(
            children: [
              _AppearanceSwitchTile(
                icon: Icons.view_column_rounded,
                title: l10n.serversColumnsTitle,
                subtitle: _columnsNote(context, l10n),
                value: current.serversTwoColumns,
                onChanged: (v) =>
                    onSave(current.copyWith(serversTwoColumns: v)),
              ),
              if (current.serversTwoColumns)
                ExpressiveGroupTile(
                  padding: const EdgeInsets.all(12),
                  child: ExpressiveConnectedButtons<int>(
                    segments: const [
                      ExpressiveSegment(value: 2, label: '2'),
                      ExpressiveSegment(value: 3, label: '3'),
                    ],
                    selected: current.serversColumns,
                    onChanged: (v) =>
                        onSave(current.copyWith(serversColumns: v)),
                    height: 48,
                  ),
                ),
              _AppearanceSwitchTile(
                icon: Icons.palette_outlined,
                title: l10n.appearanceServerIconThemeColors,
                value: current.serverIconThemeColors,
                onChanged: (v) =>
                    onSave(current.copyWith(serverIconThemeColors: v)),
              ),
            ],
          ),
          ExpressiveSectionHeader(l10n.appearanceSectionConnectPanel),
          ExpressiveGroup(
            children: [
              _ScreenPartTile(
                icon: Icons.vertical_align_top_rounded,
                label: l10n.appearancePartTop,
                child: ExpressiveConnectedButtons<bool>(
                  segments: [
                    ExpressiveSegment(
                      value: false,
                      label: l10n.appearanceConnectPanelLegacy,
                    ),
                    ExpressiveSegment(
                      value: true,
                      label: l10n.appearanceConnectPanelModern,
                    ),
                  ],
                  selected: current.modernConnectPanel,
                  onChanged: (v) =>
                      onSave(current.copyWith(modernConnectPanel: v)),
                  height: 48,
                ),
              ),
              // нижняя панель на ПК своя
              if (!PlatformBootstrap.isDesktop) ...[
                _ScreenPartTile(
                  icon: Icons.vertical_align_bottom_rounded,
                  label: l10n.appearancePartBottom,
                  child: ExpressiveConnectedButtons<bool>(
                    segments: [
                      ExpressiveSegment(
                        value: false,
                        label: l10n.appearanceConnectPanelLegacy,
                      ),
                      ExpressiveSegment(
                        value: true,
                        label: l10n.appearanceConnectPanelModern,
                      ),
                    ],
                    selected: LiquidBarStyle.tryParse(current.bottomBarStyle) != null,
                    onChanged: (v) => onSave(current.copyWith(
                      bottomBarStyle: v
                          ? LiquidBarStyle.mainland.name
                          : AppSettings.bottomBarLegacy,
                    )),
                    height: 48,
                  ),
                ),
                if (LiquidBarStyle.tryParse(current.bottomBarStyle) != null)
                  _ScreenPartTile(
                    child: ExpressiveConnectedButtons<String>(
                      segments: [
                        ExpressiveSegment(
                          value: LiquidBarStyle.mainland.name,
                          label: l10n.appearanceBarMainland,
                        ),
                        ExpressiveSegment(
                          value: LiquidBarStyle.islands.name,
                          label: l10n.appearanceBarIslands,
                        ),
                      ],
                      selected: LiquidBarStyle.fromId(current.bottomBarStyle).name,
                      onChanged: (v) =>
                          onSave(current.copyWith(bottomBarStyle: v)),
                      height: 48,
                    ),
                  ),
              ],
            ],
          ),
          ExpressiveSectionHeader(l10n.appearanceSectionUnderButton),
          ExpressiveGroup(
            children: [
              _AppearanceSwitchTile(
                icon: Icons.swap_vert_rounded,
                title: l10n.appearanceShowTraffic,
                value: current.showTrafficStats,
                onChanged: (v) => onSave(current.withTrafficStats(v)),
              ),
              if (ref.watch(activeVpnBackendProvider) == VpnBackend.mihomo)
                _AppearanceSwitchTile(
                  icon: Icons.alt_route_rounded,
                  title: l10n.appearanceShowTrafficSplit,
                  value: current.showTrafficSplit,
                  onChanged: (v) => onSave(current.withTrafficSplit(v)),
                ),
              _AppearanceSwitchTile(
                icon: Icons.timer_rounded,
                title: l10n.appearanceShowTime,
                value: current.showConnectionTime,
                onChanged: (v) =>
                    onSave(current.copyWith(showConnectionTime: v)),
              ),
              _AppearanceSwitchTile(
                icon: Icons.palette_rounded,
                title: l10n.appearanceWaveLatencyColor,
                value: current.waveLatencyColor,
                onChanged: (v) => onSave(current.copyWith(waveLatencyColor: v)),
              ),
            ],
          ),
          if (!PlatformBootstrap.isDesktop) ...[
            ExpressiveSectionHeader(l10n.appearanceSectionFeel),
            ExpressiveGroup(
              children: [
                _AppearanceSwitchTile(
                  icon: Icons.vibration_rounded,
                  title: l10n.appearanceHaptics,
                  value: current.hapticFeedback,
                  onChanged: (v) =>
                      onSave(current.copyWith(hapticFeedback: v)),
                ),
              ],
            ),
          ],
          ExpressiveSectionHeader(l10n.appearanceNotifSectionTitle),
          ExpressiveGroup(
            children: [
              _AppearanceSwitchTile(
                icon: Icons.speed_rounded,
                title: l10n.appearanceNotifSpeedTitle,
                value: current.showSpeedInNotification,
                onChanged: (v) =>
                    onSave(current.copyWith(showSpeedInNotification: v)),
              ),
              _AppearanceSwitchTile(
                icon: Icons.timer_outlined,
                title: l10n.appearanceNotifUptimeTitle,
                value: current.showUptimeInNotification,
                onChanged: (v) =>
                    onSave(current.copyWith(showUptimeInNotification: v)),
              ),
              _AppearanceSwitchTile(
                icon: Icons.sync_rounded,
                title: l10n.appearanceNotifSubUpdatesTitle,
                value: current.notifySubscriptionUpdates,
                onChanged: (v) =>
                    onSave(current.copyWith(notifySubscriptionUpdates: v)),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _AppearanceSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;

  final String? subtitle;
  final bool value;

  final ValueChanged<bool>? onChanged;

  const _AppearanceSwitchTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final enabled = onChanged != null;
    final accent = AppTheme.accent(context);

    return ExpressiveGroupTile(
      padding: const EdgeInsets.all(16),
      onTap: enabled ? () => onChanged!(!value) : null,
      child: Row(
        children: [
          ExpressiveIconBadge(
            icon: icon,
            accent: value && enabled
                ? ExpressiveAccent.tertiary
                : ExpressiveAccent.secondary,
          ),
          const SizedBox(width: ExpressiveSpacing.large),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.titleMedium?.copyWith(
                    color: enabled
                        ? AppTheme.text(context)
                        : AppTheme.textLight(context),
                  ),
                ),
                if (subtitle case final subtitle?)
                  Text(
                    subtitle,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppTheme.textLight(context),
                      height: 1.3,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: ExpressiveSpacing.small),
          Switch(
            value: value,
            activeThumbColor: accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _IconShapePicker extends StatefulWidget {
  final String currentShapeId;
  final ValueChanged<String> onSelect;
  const _IconShapePicker({
    required this.currentShapeId,
    required this.onSelect,
  });

  @override
  State<_IconShapePicker> createState() => _IconShapePickerState();
}

class _IconShapePickerState extends State<_IconShapePicker> {
  final ScrollController _shapes = ScrollController();

  @override
  void dispose() {
    _shapes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final accent = AppTheme.accent(context);
    final current = IconShape.fromId(widget.currentShapeId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExpressiveSectionHeader(
          l10n.appearanceIconShapeTitle,
          icon: Icons.category_rounded,
        ),
        SizedBox(
          height: 60,
          child: HorizontalMouseScroll(
            controller: _shapes,
            child: ListView.separated(
              controller: _shapes,
              scrollDirection: Axis.horizontal,
              itemCount: IconShape.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final shape = IconShape.values[i];
                return _ShapeSwatch(
                  shape: shape,
                  label: _shapeLabel(l10n, shape),
                  selected: shape == current,
                  onTap: () => widget.onSelect(shape.id),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            _shapeLabel(l10n, current),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }

  static String _shapeLabel(AppLocalizations l10n, IconShape shape) =>
      switch (shape) {
        IconShape.circle => l10n.appearanceIconShapeCircle,
        IconShape.square => l10n.appearanceIconShapeSquare,
        IconShape.slanted => l10n.appearanceIconShapeSlanted,
        IconShape.arch => l10n.appearanceIconShapeArch,
        IconShape.pill => l10n.appearanceIconShapePill,
        IconShape.gem => l10n.appearanceIconShapeGem,
        IconShape.sunny => l10n.appearanceIconShapeSunny,
        IconShape.cookie => l10n.appearanceIconShapeCookie,
        IconShape.clover => l10n.appearanceIconShapeClover,
        IconShape.flower => l10n.appearanceIconShapeFlower,
        IconShape.puffy => l10n.appearanceIconShapePuffy,
        IconShape.pebble => l10n.appearanceIconShapePebble,
      };
}

class _ShapeSwatch extends StatelessWidget {
  final IconShape shape;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ShapeSwatch({
    required this.shape,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  static const _size = 56.0;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        selected: selected,
        button: true,
        child: TvTappable(
          onTap: onTap,
          shape: shape.border(_size),
          child: GestureDetector(
            onTap: onTap,
            child: Builder(builder: (context) {
              final scheme = Theme.of(context).colorScheme;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: _size,
                height: _size,
                decoration: ShapeDecoration(
                  color: TvFocusHighlight.containerOf(context) ??
                      (selected
                          ? scheme.primary
                          : scheme.surfaceContainerHighest),
                  shape: shape.border(_size),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _FontPicker extends StatelessWidget {
  final String currentFontId;
  final ValueChanged<String> onSelect;
  const _FontPicker({required this.currentFontId, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final accent = AppTheme.accent(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExpressiveSectionHeader(
          l10n.appearanceFontTitle,
          icon: Icons.text_fields_rounded,
        ),
        SizedBox(
          height: 60,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kAppFonts.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final font = kAppFonts[i];
              return _FontSwatch(
                label: _fontLabel(l10n, font),
                fontFamily: font.family,
                selected: font.id == currentFontId,
                onTap: () => onSelect(font.id),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            _fontLabel(
              l10n,
              kAppFonts.firstWhere(
                (f) => f.id == currentFontId,
                orElse: () => kAppFonts.first,
              ),
            ),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }

  static String _fontLabel(AppLocalizations l10n, AppFont font) =>
      font.id == kDefaultFontId ? l10n.appearanceFontSystem : font.label;
}

class _FontSwatch extends StatelessWidget {
  final String label;
  final String? fontFamily;
  final bool selected;
  final VoidCallback onTap;

  const _FontSwatch({
    required this.label,
    required this.fontFamily,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        selected: selected,
        button: true,
        child: TvTappable(
          onTap: onTap,
          radius: BorderRadius.circular(ExpressiveShape.large),
          child: GestureDetector(
            onTap: onTap,
            child: Builder(builder: (context) {
              final scheme = Theme.of(context).colorScheme;
              final focusFill = TvFocusHighlight.containerOf(context);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                height: 56,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: focusFill ??
                      (selected
                          ? scheme.primary
                          : scheme.surfaceContainerHighest),
                  borderRadius: BorderRadius.circular(ExpressiveShape.large),
                ),
                child: Text(
                  'Aa Яя',
                  maxLines: 1,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFamily: fontFamily,
                        color: selected && focusFill == null
                            ? scheme.onPrimary
                            : scheme.onSurface,
                      ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _AppearanceThemesTab extends StatelessWidget {
  final AppSettings current;
  final Future<void> Function(AppSettings) onSave;
  const _AppearanceThemesTab({required this.current, required this.onSave});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDesktop = PlatformBootstrap.isDesktop;
    // отдельным сливером: GridView(shrinkWrap) раскладывал все плитки на каждом кадре смены темы
    return SmoothScroll(
      builder: (context, controller) => CustomScrollView(
        controller: controller,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList.list(children: _controls(context, l10n, isDesktop)),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: _ThemePresetGrid(current: current, onSave: onSave),
          ),
        ],
      ),
    );
  }

  List<Widget> _controls(
    BuildContext context,
    AppLocalizations l10n,
    bool isDesktop,
  ) {
    return [
          ExpressiveConnectedButtons<bool>(
            segments: [
              ExpressiveSegment(
                value: false,
                label: l10n.themeModeLight,
                icon: Icons.light_mode_rounded,
              ),
              ExpressiveSegment(
                value: true,
                label: l10n.themeModeDark,
                icon: Icons.dark_mode_rounded,
              ),
            ],
            selected: current.darkTheme,
            onChanged: (v) => onSave(current.copyWith(darkTheme: v)),
            height: 56,
          ),
          const SizedBox(height: ExpressiveSpacing.large),
          ExpressiveGroup(
            children: [
              _AppearanceSwitchTile(
                icon: Icons.contrast_rounded,
                title: l10n.appearanceAmoled,
                subtitle: current.darkTheme ? null : l10n.appearanceAmoledNeedsDark,
                value: current.amoledBlack,
                onChanged: current.darkTheme
                    ? (v) => onSave(current.copyWith(amoledBlack: v))
                    : null,
              ),
              // вне окна праздника переключатель ничего не делает, поэтому скрыт;
              // выше системных цветов, чтобы подпись под группой оставалась про них
              if (HalloweenSeason.isNow)
                _AppearanceSwitchTile(
                  icon: Icons.celebration_rounded,
                  title: l10n.appearanceHalloween,
                  subtitle: l10n.appearanceHalloweenUntil,
                  value: current.seasonalDecor,
                  onChanged: (v) => onSave(current.copyWith(seasonalDecor: v)),
                ),
              _AppearanceSwitchTile(
                icon: isDesktop
                    ? Icons.desktop_windows_rounded
                    : Icons.android_rounded,
                title: isDesktop
                    ? l10n.themeUseSystemColors
                    : l10n.themeUseDynamicColors,
                value: current.followSystemTheme,
                onChanged: (v) =>
                    onSave(current.copyWith(followSystemTheme: v)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              l10n.themePaletteHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textLight(context),
                    height: 1.35,
                  ),
            ),
          ),
          ExpressiveSectionHeader(
            l10n.themeColorThemesTitle,
            icon: Icons.palette_rounded,
          ),
        ];
  }
}

class _UiScalePicker extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _UiScalePicker({required this.value, required this.onChanged});

  @override
  State<_UiScalePicker> createState() => _UiScalePickerState();
}

class _UiScalePickerState extends State<_UiScalePicker> {
  static const _step = 0.05;

  // масштаб применяется по отпусканию: иначе экран сжимается под пальцем и ползунок уезжает
  double? _dragging;

  @override
  void didUpdateWidget(_UiScalePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) _dragging = null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final accent = AppTheme.accent(context);
    final value = _dragging ?? widget.value;
    final percent = (value * 100).round();
    final divisions =
        ((AppSettings.maxUiScale - AppSettings.minUiScale) / _step).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExpressiveSectionHeader(
          l10n.appearanceUiScaleTitle,
          icon: Icons.format_size_rounded,
        ),
        Row(
          children: [
            Expanded(
              child: TvFocus.slider(
                Slider(
                  value: value.clamp(
                    AppSettings.minUiScale,
                    AppSettings.maxUiScale,
                  ),
                  min: AppSettings.minUiScale,
                  max: AppSettings.maxUiScale,
                  divisions: divisions,
                  activeColor: accent,
                  label: '$percent%',
                  onChanged: (v) => setState(() => _dragging = v),
                  onChangeEnd: widget.onChanged,
                ),
              ),
            ),
            SizedBox(
              width: 56,
              child: Text(
                '$percent%',
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppTheme.text(context),
                    ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
          child: Text(
            l10n.appearanceUiScaleSubtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textLight(context),
                  height: 1.35,
                ),
          ),
        ),
      ],
    );
  }
}

class _ThemePresetGrid extends StatelessWidget {
  final AppSettings current;
  final Future<void> Function(AppSettings) onSave;
  const _ThemePresetGrid({required this.current, required this.onSave});

  static const double _padding = 10;

  static const double _targetTileWidth = 190;

  ColorScheme _previewScheme(ThemePreset preset) {
    final scheme = buildPresetScheme(
      preset,
      current.darkTheme ? Brightness.dark : Brightness.light,
    );
    return current.amoledBlack ? applyAmoledBlack(scheme) : scheme;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final iconShape = ExpressiveIconShapeTheme.of(context);

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.crossAxisExtent / _targetTileWidth)
            .floor()
            .clamp(2, 6);
        final tileWidth = constraints.crossAxisExtent / columns;
        final mockWidth =
            tileWidth - ExpressiveListSegment.gap * 2 - _padding * 2;
        final labelHeight = MediaQuery.textScalerOf(context)
                .scale(theme.textTheme.labelLarge?.fontSize ?? 14) *
            1.4;
        final tileHeight = _padding * 2 +
            mockWidth / _ThemeScreenMock.aspectRatio +
            ExpressiveSpacing.small +
            labelHeight +
            ExpressiveListSegment.gap;

        final l10n = AppLocalizations.of(context)!;
        final customSeed = parseThemeSeed(current.customThemeSeed);
        final customSelected = !current.followSystemTheme &&
            current.themePresetId == kCustomThemePresetId;
        final count = kThemePresets.length + 1;

        return SliverGrid.builder(
          itemCount: count,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 0,
            crossAxisSpacing: 0,
            mainAxisExtent: tileHeight,
          ),
          itemBuilder: (context, i) {
            if (i == kThemePresets.length) {
              final preset = customThemePreset(
                customSeed ?? kCustomThemeDefaultSeed,
                variant: parseThemeVariant(current.customThemeVariant),
              );
              return Padding(
                padding: ExpressiveListSegment.segmentMargin(
                  index: i,
                  columns: columns,
                ),
                child: ExpressiveListSegment(
                  radius: ExpressiveListSegment.segmentRadius(
                    index: i,
                    count: count,
                    columns: columns,
                  ).resolve(Directionality.of(context)),
                  selected: customSelected,
                  color: scheme.surfaceContainerHigh,
                  selectedColor: scheme.secondaryContainer,
                  onTap: () => _showCustomColorSheet(
                    context,
                    current: current,
                    onSave: onSave,
                  ),
                  child: _ThemePresetTile(
                    name: l10n.appearanceCustomColorTitle,
                    scheme: _previewScheme(preset),
                    iconShape: iconShape,
                    selected: customSelected,
                    padding: _padding,
                  ),
                ),
              );
            }
            final preset = kThemePresets[i];
            // с разрешённым id: у тех, кто сидел на удалённой теме, в настройках лежит forest
            final selected = !current.followSystemTheme &&
                !customSelected &&
                preset.id == resolveThemePreset(current.themePresetId).id;
            return Padding(
              padding: ExpressiveListSegment.segmentMargin(
                index: i,
                columns: columns,
              ),
              child: ExpressiveListSegment(
                radius: ExpressiveListSegment.segmentRadius(
                  index: i,
                  count: count,
                  columns: columns,
                ).resolve(Directionality.of(context)),
                selected: selected,
                color: scheme.surfaceContainerHigh,
                selectedColor: scheme.secondaryContainer,
                onTap: () => onSave(current.copyWith(
                  themePresetId: preset.id,
                  followSystemTheme: false,
                )),
                child: _ThemePresetTile(
                  name: preset.name,
                  scheme: _previewScheme(preset),
                  iconShape: iconShape,
                  selected: selected,
                  padding: _padding,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ThemePresetTile extends StatelessWidget {
  final String name;
  final ColorScheme scheme;
  final IconShape iconShape;
  final bool selected;
  final double padding;

  const _ThemePresetTile({
    required this.name,
    required this.scheme,
    required this.iconShape,
    required this.selected,
    required this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final labelColor =
        selected ? appScheme.onSecondaryContainer : appScheme.onSurface;

    return Padding(
      padding: EdgeInsets.all(padding),
      child: Column(
        children: [
          Expanded(
            child: FittedBox(
              child: _ThemeScreenMock(scheme: scheme, iconShape: iconShape),
            ),
          ),
          const SizedBox(height: ExpressiveSpacing.small),
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (selected
                          ? textTheme.emphasized(textTheme.labelLarge)
                          : textTheme.labelLarge)
                      ?.copyWith(color: labelColor),
                ),
              ),
              SizedBox(
                width: ExpressiveIconSize.inline,
                height: ExpressiveIconSize.inline,
                child: selected
                    ? Icon(
                        Icons.check_rounded,
                        size: ExpressiveIconSize.inline,
                        color: appScheme.onSecondaryContainer,
                      )
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeScreenMock extends StatelessWidget {
  final ColorScheme scheme;
  final IconShape iconShape;

  const _ThemeScreenMock({required this.scheme, required this.iconShape});

  static const double width = 120;
  static const double height = 160;
  static const double aspectRatio = width / height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
            width: 0.8,
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 9),
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: scheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Icon(
              Icons.pause_rounded,
              size: 16,
              color: scheme.onPrimary,
            ),
          ),
          const SizedBox(height: 7),
          _bar(52, 4, scheme.onSurface.withValues(alpha: 0.9)),
          const SizedBox(height: 3),
          _bar(30, 3, scheme.onSurfaceVariant.withValues(alpha: 0.75)),
          const SizedBox(height: 7),
          SizedBox(
            width: 96,
            height: 8,
            child: CustomPaint(
              painter: _MockWavePainter(
                color: scheme.primary,
                track: scheme.secondaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _serverRow(selected: true),
          const SizedBox(height: 2),
          _serverRow(selected: false),
          const Spacer(),
          _bottomNav(),
          const SizedBox(height: 7),
        ],
      ),
    );
  }

  static Widget _bar(double width, double height, Color color) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      );

  static Widget _dot(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  Widget _serverRow({required bool selected}) {
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurface;
    final muted = selected
        ? scheme.onSecondaryContainer.withValues(alpha: 0.7)
        : scheme.onSurfaceVariant;
    return Container(
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color:
            selected ? scheme.secondaryContainer : scheme.surfaceContainerHigh,
        borderRadius: selected
            ? BorderRadius.circular(5)
            : const BorderRadius.vertical(
                top: Radius.circular(1.5),
                bottom: Radius.circular(5),
              ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: selected
                    ? scheme.tertiaryContainer
                    : scheme.primaryContainer,
                shape: iconShape.border(13),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bar(28, 3, fg.withValues(alpha: 0.85)),
              const SizedBox(height: 3),
              Row(
                children: [
                  _bar(11, 2.5, selected ? fg : scheme.secondary),
                  const SizedBox(width: 3),
                  _bar(8, 2.5, muted),
                ],
              ),
            ],
          ),
          const Spacer(),
          _dot(
            9,
            selected
                ? scheme.onSecondaryContainer.withValues(alpha: 0.2)
                : scheme.primary.withValues(alpha: 0.15),
          ),
        ],
      ),
    );
  }

  Widget _bottomNav() => SizedBox(
        height: 14,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dot(5, scheme.onSecondaryContainer),
                  const SizedBox(width: 3),
                  _bar(
                    12,
                    2.5,
                    scheme.onSecondaryContainer.withValues(alpha: 0.9),
                  ),
                ],
              ),
            ),
            _dot(5.5, scheme.onSurfaceVariant),
            _dot(5.5, scheme.onSurfaceVariant),
          ],
        ),
      );
}

class _MockWavePainter extends CustomPainter {
  final Color color;
  final Color track;

  const _MockWavePainter({required this.color, required this.track});

  static const double _thickness = 3;
  static const double _amplitude = 1.5;
  static const double _wavelength = 13;

  static const double _tail = 13;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final cap = _thickness / 2;
    final left = cap;
    final right = size.width - cap;
    if (right <= left) return;
    final activeRight = math.max(left, right - _tail);

    double waveY(double x) =>
        mid + _amplitude * math.sin(2 * math.pi * x / _wavelength);

    final path = Path()..moveTo(left, waveY(left));
    for (var x = left + 1; x < activeRight; x += 1) {
      path.lineTo(x, waveY(x));
    }
    path.lineTo(activeRight, waveY(activeRight));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _thickness
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final trackStart = activeRight + _thickness + 2;
    if (trackStart < right) {
      canvas.drawLine(
        Offset(trackStart, mid),
        Offset(right, mid),
        Paint()
          ..color = track
          ..style = PaintingStyle.stroke
          ..strokeWidth = _thickness
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawCircle(
      Offset(right, mid),
      _thickness / 2,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_MockWavePainter old) =>
      old.color != color || old.track != track;
}

// ряд выбора одной части главного экрана: значок слева говорит, верх это или низ
class _ScreenPartTile extends StatelessWidget {
  const _ScreenPartTile({this.icon, this.label, required this.child});

  final IconData? icon;
  final String? label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    return ExpressiveGroupTile(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: icon == null
                ? null
                : Icon(
                    icon,
                    size: 22,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    semanticLabel: label,
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}
