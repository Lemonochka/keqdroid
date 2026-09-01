part of '../settings_tab.dart';

class _ThemeCustomizationCard extends ConsumerWidget {
  final AsyncValue<AppSettings> settingsAsync;
  const _ThemeCustomizationCard({required this.settingsAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = settingsAsync.value ?? const AppSettings();
    final preset = resolveThemePreset(settings.themePresetId);
    final modeLabel = settings.darkTheme ? l10n.themeModeDark : l10n.themeModeLight;
    final isDesktop = PlatformBootstrap.isDesktop;
    final subtitle = settings.followSystemTheme
        ? (isDesktop
            ? l10n.settingsSystemColorsSubtitle(modeLabel)
            : l10n.settingsAndroidColorsSubtitle(modeLabel))
        : '${preset.name} · $modeLabel';
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

    // Две вкладки: «Общие» — как выглядит приложение (колонки, чипы статистики),
    // «Темы» — всё про цвета (динамические/системные, светлая/тёмная, пресеты).
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
        // Высоту считаем от самого TabBar, а не константой: он
        // `PreferredSizeWidget`, и его высота зависит от того, есть ли в
        // вкладках иконки.
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
        // Не TabBarView: его PageView при смене зависимостей (тёмная/светлая
        // тема из этого же экрана, метрики окна) синхронизирует застрявший
        // offset страницы через jumpToPage прямо в didChangeDependencies —
        // «setState() called during build» в консоли. Свайп между двумя
        // вкладками настроек не нужен, переключаем контент сами по index.
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

/// Вкладка «Общие»: раскладка списка серверов и чипы статистики под кнопкой.
class _AppearanceGeneralTab extends StatelessWidget {
  final AppSettings current;
  final Future<void> Function(AppSettings) onSave;
  const _AppearanceGeneralTab({required this.current, required this.onSave});

  @override
  Widget build(BuildContext context) {
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
          // Рядом со шрифтом, а не в группе переключателей ниже: это про то же
          // — каким текст выглядит, — и смотреть на результат удобно прямо
          // здесь, потому что подпись под ползунком меняется вместе с ним.
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
          // Дальше — не сплошная стопка переключателей, а группы по смыслу.
          // Девять одинаковых строк подряд читались как список без иерархии:
          // глазу не за что зацепиться, и найти нужную можно только прочитав
          // все. Заголовки разбивают их на «где что живёт».
          ExpressiveSectionHeader(l10n.appearanceSectionServers),
          ExpressiveGroup(
            children: [
              _AppearanceSwitchTile(
                icon: Icons.view_column_rounded,
                title: l10n.serversTwoColumnsTitle,
                subtitle: l10n.serversTwoColumnsSubtitle,
                value: current.serversTwoColumns,
                onChanged: (v) =>
                    onSave(current.copyWith(serversTwoColumns: v)),
              ),
              _AppearanceSwitchTile(
                icon: Icons.swap_vert_rounded,
                title: l10n.appearanceShowTraffic,
                subtitle: l10n.appearanceShowTrafficSubtitle,
                value: current.showTrafficStats,
                onChanged: (v) => onSave(current.copyWith(showTrafficStats: v)),
              ),
              _AppearanceSwitchTile(
                icon: Icons.timer_rounded,
                title: l10n.appearanceShowTime,
                subtitle: l10n.appearanceShowTimeSubtitle,
                value: current.showConnectionTime,
                onChanged: (v) =>
                    onSave(current.copyWith(showConnectionTime: v)),
              ),
              _AppearanceSwitchTile(
                icon: Icons.palette_rounded,
                title: l10n.appearanceWaveLatencyColor,
                subtitle: l10n.appearanceWaveLatencyColorSubtitle,
                value: current.waveLatencyColor,
                onChanged: (v) => onSave(current.copyWith(waveLatencyColor: v)),
              ),
            ],
          ),
          // AMOLED уехал на вкладку «Темы», к выбору светлой/тёмной: он и есть
          // поправка к тёмной схеме и без неё не работает. Здесь от секции
          // остаётся одна вибрация, которой на десктопе нет вовсе — поэтому
          // прячем секцию целиком, а не оставляем заголовок над пустой группой.
          if (!PlatformBootstrap.isDesktop) ...[
            ExpressiveSectionHeader(l10n.appearanceSectionFeel),
            ExpressiveGroup(
              children: [
                _AppearanceSwitchTile(
                  icon: Icons.vibration_rounded,
                  title: l10n.appearanceHaptics,
                  subtitle: l10n.appearanceHapticsSubtitle,
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
                subtitle: l10n.appearanceNotifSpeedSubtitle,
                value: current.showSpeedInNotification,
                onChanged: (v) =>
                    onSave(current.copyWith(showSpeedInNotification: v)),
              ),
              _AppearanceSwitchTile(
                icon: Icons.timer_outlined,
                title: l10n.appearanceNotifUptimeTitle,
                subtitle: l10n.appearanceNotifUptimeSubtitle,
                value: current.showUptimeInNotification,
                onChanged: (v) =>
                    onSave(current.copyWith(showUptimeInNotification: v)),
              ),
              _AppearanceSwitchTile(
                icon: Icons.sync_rounded,
                title: l10n.appearanceNotifSubUpdatesTitle,
                subtitle: l10n.appearanceNotifSubUpdatesSubtitle,
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

/// Переключатель настройки — сегмент группы, а не `SwitchListTile`.
///
/// `SwitchListTile` тянет за собой чужую анатомию: иконка без контейнера,
/// свои отступы, своя высота строки. Рядом с остальными экранами, которые
/// давно живут на [ExpressiveGroupTile] с кружком-иконкой, это и читалось как
/// «страница из прошлой версии».
///
/// Включённое состояние показывает цвет кружка (`tertiary` — роль «тут
/// что-то изменилось»), как у LAN-прокси и HWID. Нажатие по всей строке, а не
/// только по самому переключателю: попасть в строку проще, чем в тумблер.
class _AppearanceSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;

  /// null — настройка недоступна в текущем состоянии (AMOLED на светлой теме).
  final ValueChanged<bool>? onChanged;

  const _AppearanceSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
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

/// Выбор формы кружков под иконками — то же, что выбор формы иконок в лаунчере
/// Pixel.
///
/// Образцы рисуются настоящим [ExpressiveIconBadge] с явно заданной формой, а
/// не картинкой: превью, нарисованное отдельно, рано или поздно расходится с
/// тем, что видно на экранах.
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
  /// Ради колеса мыши: без своего контроллера ряд форм на десктопе не листается
  /// вовсе, а в узком окне ещё и уезжает за край (см. [HorizontalMouseScroll]).
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
        // Образцы — сами формы, крупно и без обвязки, как в выборе формы
        // иконок на Pixel. Прежние карточки с рамкой и подписью под каждой
        // соревновались с тем единственным, что тут надо разглядеть, — с
        // силуэтом. Название выбранной формы уходит одной строкой под ряд:
        // подпись нужна одна, а не шесть.
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

/// Один силуэт формы. Выбранный залит акцентом — тем же приёмом, что и в
/// системном выборе: не рамкой вокруг, а самим цветом фигуры.
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
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        selected: selected,
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: _size,
            height: _size,
            decoration: ShapeDecoration(
              color: selected
                  ? scheme.primary
                  : scheme.surfaceContainerHighest,
              shape: shape.border(_size),
            ),
          ),
        ),
      ),
    );
  }
}

/// Горизонтальный выбор шрифта интерфейса. Каждая карточка рисует образец своим
/// шрифтом (латиница + кириллица); применяется поверх любой темы.
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
        // Тот же принцип, что у форм: образец шрифта и всё. Рамка с подписью
        // под каждой карточкой мешала сравнивать сами начертания, а сравнивают
        // тут именно их.
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

/// Образец начертания. Выбранный залит акцентом — как и выбранная форма, тем
/// же приёмом, чтобы два ряда подряд читались как один язык.
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
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        selected: selected,
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: 56,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primary
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(ExpressiveShape.large),
            ),
            child: Text(
              // Латиница и кириллица разом: часть шрифтов различается только
              // в одной из них, и по «Aa» выбрать было бы не из чего.
              'Aa Яя',
              maxLines: 1,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontFamily: fontFamily,
                    color: selected ? scheme.onPrimary : scheme.onSurface,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Вкладка «Темы»: динамические/системные цвета, светлая/тёмная, пресеты.
class _AppearanceThemesTab extends StatelessWidget {
  final AppSettings current;
  final Future<void> Function(AppSettings) onSave;
  const _AppearanceThemesTab({required this.current, required this.onSave});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDesktop = PlatformBootstrap.isDesktop;
    // Сетка пресетов — отдельный сливер, а не виджет внутри списка.
    //
    // Раньше она стояла в `ListView` как `GridView(shrinkWrap: true)`, и это
    // стоило дорого: shrinkWrap заставляет сливер разложить ВСЕ элементы, чтобы
    // узнать свою высоту, то есть все двенадцать плиток собирались и
    // раскладывались на каждом кадре — включая девять, которых на экране нет.
    // А кадров таких много: `AnimatedTheme` пересобирает поддерево все 350 мс
    // перехода светлая↔тёмная. В сливере строятся только видимые.
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

  /// Всё, что стоит над сеткой: выбор яркости, источник палитры и заголовок.
  List<Widget> _controls(
    BuildContext context,
    AppLocalizations l10n,
    bool isDesktop,
  ) {
    return [
          // Светлая/тёмная — связанная группа M3E, а не самодельный ползунок с
          // бегунком. Тот держал выбор на одной заливке: форма выбранной
          // половины не менялась вовсе, хотя у связанной группы именно она и
          // есть индикатор. Подпись на бегунке к тому же красилась в
          // `AppTheme.bg` — цвет фона на месте роли `onPrimary`, — и в AMOLED
          // выходила чёрным по акценту.
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
            // Размер M (56): группа стоит первой на экране и отвечает за самый
            // частый выбор на нём.
            height: 56,
          ),
          const SizedBox(height: ExpressiveSpacing.large),
          // Источник палитры — такой же сегмент группы, как переключатели на
          // соседней вкладке. Голый `SwitchListTile` на фоне был последним
          // следом старого экрана: чужая анатомия строки (иконка без
          // контейнера, свои отступы, своя высота) и никакого containment.
          ExpressiveGroup(
            children: [
              // AMOLED стоит первым и сразу под выбором светлой/тёмной: это
              // поправка к тёмной схеме, и на светлой она погашена. Пока он
              // жил на соседней вкладке рядом с вибрацией, «почему выключено»
              // было не ответить, не уходя с экрана.
              _AppearanceSwitchTile(
                icon: Icons.contrast_rounded,
                title: l10n.appearanceAmoled,
                // Гасим, а не прячем: иначе он «пропадает» и его ищут.
                subtitle: current.darkTheme
                    ? l10n.appearanceAmoledSubtitle
                    : l10n.appearanceAmoledNeedsDark,
                value: current.amoledBlack,
                onChanged: current.darkTheme
                    ? (v) => onSave(current.copyWith(amoledBlack: v))
                    : null,
              ),
              _AppearanceSwitchTile(
                icon: isDesktop
                    ? Icons.desktop_windows_rounded
                    : Icons.android_rounded,
                title: isDesktop
                    ? l10n.themeUseSystemColors
                    : l10n.themeUseDynamicColors,
                subtitle: isDesktop
                    ? l10n.themeUseSystemColorsSubtitle
                    : l10n.themeUseDynamicColorsSubtitle,
                value: current.followSystemTheme,
                onChanged: (v) =>
                    onSave(current.copyWith(followSystemTheme: v)),
              ),
            ],
          ),
          // Подпись под группой — тем же приёмом, что и пояснение под ползунком
          // масштаба: отступ 4 слева, роль `bodySmall` на `onSurfaceVariant`.
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              current.followSystemTheme
                  ? (isDesktop
                      ? l10n.themeSystemPaletteHint
                      : l10n.themeDynamicPaletteHint)
                  : l10n.themeCustomPaletteHint,
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

/// Ползунок размера интерфейса: множитель поверх системного масштаба текста.
///
/// Значение пишется в настройки на каждое движение — «Сохранить» тут нет, и
/// правильно: результат виден целиком, всей страницей сразу, и подбирают его
/// глазами. Ради этого же ползунок стоит на экране, который сам под него
/// перерисовывается.
class _UiScalePicker extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _UiScalePicker({required this.value, required this.onChanged});

  /// Шаг 5%: мельче — разницы между соседними положениями не видно, крупнее —
  /// нужного размера можно не найти вовсе.
  static const _step = 0.05;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final accent = AppTheme.accent(context);
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
              child: Slider(
                value: value.clamp(
                  AppSettings.minUiScale,
                  AppSettings.maxUiScale,
                ),
                min: AppSettings.minUiScale,
                max: AppSettings.maxUiScale,
                divisions: divisions,
                activeColor: accent,
                label: '$percent%',
                onChanged: onChanged,
              ),
            ),
            // Ширина под самое длинное значение, иначе ползунок дёргается на
            // каждом переходе через сотню процентов. Процент, а не «как в
            // системе» на 100%: подпись под ползунком и так говорит, что это
            // поправка к системному размеру, а строка переменной длины сдвигала
            // бы ползунок ровно в тот момент, когда его тянут.
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

/// Сетка пресетов.
///
/// Плитки — те же сегменты списка, что и строки серверов
/// ([ExpressiveListSegment]): выбор несут заливка и морф формы. Прежде его
/// показывала рамка в 2 px цветом САМОГО пресета — на светлых палитрах её было
/// не разглядеть, а на тёмных она спорила с картинкой внутри.
///
/// Обвязка плитки живёт в ТЕКУЩЕЙ теме приложения, а миниатюра внутри — в
/// цветах пресета. Это не небрежность: рамка с подписью — орган управления и
/// обязана выглядеть как остальной экран, а картинка внутри показывает чужую
/// палитру. Пока в цвета пресета красилась и обвязка, выбранная плитка на
/// светлой теме и невыбранная на тёмной различались меньше, чем две соседние.
class _ThemePresetGrid extends StatelessWidget {
  final AppSettings current;
  final Future<void> Function(AppSettings) onSave;
  const _ThemePresetGrid({required this.current, required this.onSave});

  /// Поля плитки вокруг миниатюры.
  static const double _padding = 10;

  /// Ширина, к которой стремится плитка. Колонки считаются от неё, а не от
  /// платформы: `isDesktop ? 4 : 2` давал в узком окне десктопа плитки в
  /// пол-экрана, а на планшете — две колонки на 800 px.
  static const double _targetTileWidth = 190;

  /// Палитра пресета в том виде, в каком её увидит пользователь: в текущей
  /// яркости и с учётом AMOLED.
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

    // Ширину берём из сливерных ограничений: обычный LayoutBuilder внутри
    // CustomScrollView не поставить, а `crossAxisExtent` — это ровно та же
    // ширина, уже за вычетом SliverPadding.
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.crossAxisExtent / _targetTileWidth)
            .floor()
            .clamp(2, 6);
        final tileWidth = constraints.crossAxisExtent / columns;
        // Высота плитки СЧИТАЕТСЯ, а не задаётся пропорцией. Пропорций было
        // две — 0.72 на телефоне и 1.35 на десктопе, — и под каждую рисовалась
        // своя раскладка превью. Здесь раскладка одна, а высота ровно такая,
        // какую просит миниатюра в своём масштабе плюс строка с названием.
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

        return SliverGrid.builder(
          itemCount: kThemePresets.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            // Зазор набирается полями самих сегментов (segmentMargin), как в
            // списке серверов, — иначе крайние плитки встали бы уже остальных.
            mainAxisSpacing: 0,
            crossAxisSpacing: 0,
            mainAxisExtent: tileHeight,
          ),
          itemBuilder: (context, i) {
            final preset = kThemePresets[i];
            // Сравниваем с РАЗРЕШЁННЫМ id, а не с сохранённым: у того, кто
            // сидел на удалённом пресете, в настройках так и лежит «forest», и
            // прямое сравнение не отметило бы галочкой ни одну плитку — экран
            // выглядел бы «тема не выбрана».
            final selected = !current.followSystemTheme &&
                preset.id == resolveThemePreset(current.themePresetId).id;
            return Padding(
              padding: ExpressiveListSegment.segmentMargin(
                index: i,
                columns: columns,
              ),
              child: ExpressiveListSegment(
                radius: ExpressiveListSegment.segmentRadius(
                  index: i,
                  count: kThemePresets.length,
                  columns: columns,
                ),
                selected: selected,
                color: scheme.surfaceContainerHigh,
                selectedColor: scheme.secondaryContainer,
                // Выбор пресета отключает системные цвета: пока
                // followSystemTheme включён, пресет не применяется и галочка не
                // рисуется — тап выглядел бы «ничего не делает».
                onTap: () => onSave(current.copyWith(
                  themePresetId: preset.id,
                  followSystemTheme: false,
                )),
                child: _ThemePresetTile(
                  name: preset.name,
                  // AMOLED учитывается: он чернит фон поверх ЛЮБОЙ тёмной
                  // схемы, и без него превью показывало бы не тот экран,
                  // который получится. Лестница контейнеров при этом остаётся
                  // обычной, поэтому список и навигация в миниатюре не
                  // сливаются с фоном — ровно как в приложении.
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

/// Содержимое плитки: миниатюра экрана и строка с названием.
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
            // Миниатюра нарисована в своём масштабе и ужимается сюда целиком:
            // так толщины линий и пропорции одинаковы при любой ширине плитки.
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
                  // Выбранное отличается ВЕСОМ, а не кеглем — как имя активного
                  // сервера в списке.
                  style: (selected
                          ? textTheme.emphasized(textTheme.labelLarge)
                          : textTheme.labelLarge)
                      ?.copyWith(color: labelColor),
                ),
              ),
              // Слот под галочку занят всегда: иначе название пересобиралось бы
              // по ширине в момент выбора и дёргалось.
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

/// Миниатюра главного экрана в цветах пресета.
///
/// Показывает ровно то, что видно в приложении: кнопку подключения (её форму и
/// цвет в состоянии «подключено»), строку статуса, волну-индикатор под ней, два
/// сегмента списка серверов — верхний выбранный — и нижнюю навигацию с
/// пилюлей-индикатором. Прежнее превью осталось от интерфейса, которого давно
/// нет: круг с play, градиентная полоска поперёк карточки, «карточки подписок»
/// с шевронами и три иконки в пилюле снизу.
///
/// Кружок сервера подчиняется выбранной форме иконок — той же, что в списке.
///
/// Масштаб честный, но не буквальный: экран целиком (360×800) в плитку сетки не
/// влезает ни при какой пропорции, поэтому миниатюра сжата по вертикали —
/// элементы узнаваемы, а высоты подобраны под 120×160.
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
          // Волосяная обводка отделяет миниатюру от плитки, когда палитра
          // пресета почти совпадает с текущей темой.
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
            width: 0.8,
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 9),
          // Кнопка «подключено»: заливка primary, иконка паузы, угол в той же
          // доле от размера, что у настоящей (48 из 136).
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

  /// Сегмент списка серверов: кружок страны, имя, бейдж протокола и пинг,
  /// кружок действия справа.
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
        // Углы настоящих сегментов (16 снаружи, 4 на стыке), уменьшенные вместе
        // со строкой: выбранный круглый со всех сторон, у соседа сверху стык.
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
                // Кружки берут контейнерные роли, а не один акцент: превью
                // заодно показывает, какими выйдут иконки и чипы.
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

  /// Нижняя навигация: пилюля-индикатор с иконкой и подписью в один ряд — та
  /// самая горизонтальная раскладка, ради которой в приложении своя реализация
  /// навбара.
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

/// Волна-индикатор миниатюры — уменьшенная копия той, что на главном экране:
/// синусоида штрихом с круглыми торцами, зазор, короткий хвост трека и
/// точка-стоп в его конце.
class _MockWavePainter extends CustomPainter {
  final Color color;
  final Color track;

  const _MockWavePainter({required this.color, required this.track});

  static const double _thickness = 3;
  static const double _amplitude = 1.5;
  static const double _wavelength = 13;

  /// Хвост трека справа: у настоящего индикатора активная часть до края не
  /// доходит — соединение это состояние, а не задача с концом.
  static const double _tail = 13;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    // Круглый торец выходит за конец отрезка на радиус штриха.
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

    // Зазор меряется между ВИДИМЫМИ краями, а drawLine берёт центры торцов.
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
