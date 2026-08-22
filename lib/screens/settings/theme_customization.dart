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
            ],
          ),
          ExpressiveSectionHeader(l10n.appearanceSectionFeel),
          ExpressiveGroup(
            children: [
              _AppearanceSwitchTile(
                icon: Icons.contrast_rounded,
                title: l10n.appearanceAmoled,
                // Переключатель гасим на светлой теме, а не прячем: иначе он
                // «пропадает» и его ищут.
                subtitle: current.darkTheme
                    ? l10n.appearanceAmoledSubtitle
                    : l10n.appearanceAmoledNeedsDark,
                value: current.amoledBlack,
                onChanged: current.darkTheme
                    ? (v) => onSave(current.copyWith(amoledBlack: v))
                    : null,
              ),
              if (!PlatformBootstrap.isDesktop)
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
class _IconShapePicker extends StatelessWidget {
  final String currentShapeId;
  final ValueChanged<String> onSelect;
  const _IconShapePicker({
    required this.currentShapeId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final accent = AppTheme.accent(context);
    final current = IconShape.fromId(currentShapeId);
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
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: IconShape.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final shape = IconShape.values[i];
              return _ShapeSwatch(
                shape: shape,
                label: _shapeLabel(l10n, shape),
                selected: shape == current,
                onTap: () => onSelect(shape.id),
              );
            },
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
    final controlsAccent = AppTheme.accent(context);
    final previewDark = current.darkTheme;
    final isDesktop = PlatformBootstrap.isDesktop;
    return SmoothScroll(
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            value: current.followSystemTheme,
            onChanged: (v) => onSave(current.copyWith(followSystemTheme: v)),
            activeThumbColor: controlsAccent,
            activeTrackColor: controlsAccent.withValues(alpha: 0.32),
            secondary: Icon(
              isDesktop ? Icons.desktop_windows_rounded : Icons.android_rounded,
              color: controlsAccent,
            ),
            title: Text(
              isDesktop ? l10n.themeUseSystemColors : l10n.themeUseDynamicColors,
            ),
            subtitle: Text(
              isDesktop
                  ? l10n.themeUseSystemColorsSubtitle
                  : l10n.themeUseDynamicColorsSubtitle,
            ),
          ),
          const SizedBox(height: 12),
          _LightDarkThemeSlider(
            isDark: current.darkTheme,
            accentColor: controlsAccent,
            onChanged: (isDark) => onSave(current.copyWith(darkTheme: isDark)),
          ),
          const SizedBox(height: 6),
          Text(
            current.followSystemTheme
                ? (isDesktop ? l10n.themeSystemPaletteHint : l10n.themeDynamicPaletteHint)
                : l10n.themeCustomPaletteHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textLight(context)),
          ),
          const SizedBox(height: 14),
          Text(l10n.themeColorThemesTitle,
              style: TextStyle(color: AppTheme.text(context), fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              final crossCount = isDesktop
                  ? (maxW >= 820 ? 4 : maxW >= 560 ? 3 : 2)
                  : 2;
              final aspectRatio = isDesktop ? 1.35 : 0.72;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: kThemePresets.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossCount,
                  mainAxisSpacing: isDesktop ? 10 : 12,
                  crossAxisSpacing: isDesktop ? 10 : 12,
                  childAspectRatio: aspectRatio,
                ),
                itemBuilder: (context, i) {
                  final p = kThemePresets[i];
                  final selected =
                      !current.followSystemTheme && p.id == current.themePresetId;
                  final scheme = buildPresetScheme(
                    p,
                    previewDark ? Brightness.dark : Brightness.light,
                  );
                  return GestureDetector(
                    // Выбор пресета отключает системные цвета: пока
                    // followSystemTheme включён, пресет не применяется и
                    // галочка не рисуется — тап выглядел бы «ничего не делает».
                    onTap: () => onSave(current.copyWith(
                      themePresetId: p.id,
                      followSystemTheme: false,
                    )),
                    child: _ThemePreviewCard(
                      name: p.name,
                      scheme: scheme,
                      darkPreview: previewDark,
                      selected: selected,
                      compact: isDesktop,
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LightDarkThemeSlider extends StatelessWidget {
  final bool isDark;
  final Color accentColor;
  final ValueChanged<bool> onChanged;
  const _LightDarkThemeSlider({
    required this.isDark,
    required this.accentColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final bg = AppTheme.inset(context);
    final border = AppTheme.divider(context);
    final thumb = accentColor;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(ExpressiveShape.extraLarge),
        border: Border.all(color: border),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final thumbW = (c.maxWidth - 8) / 2;
          return Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                // Directional: подписи «светлая/тёмная» зеркалятся в RTL, и
                // бегунок должен ехать вместе с ними, а не по физическим
                // сторонам экрана.
                alignment: isDark
                    ? AlignmentDirectional.centerEnd
                    : AlignmentDirectional.centerStart,
                child: RepaintBoundary(
                  child: Container(
                    width: thumbW,
                    height: 44,
                    decoration: BoxDecoration(
                      color: thumb,
                      borderRadius: BorderRadius.circular(ExpressiveShape.extraLarge),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  _sliderItem(
                    context,
                    active: !isDark,
                    icon: Icons.light_mode_rounded,
                    label: AppLocalizations.of(context)!.themeModeLight,
                    onTap: () => onChanged(false),
                  ),
                  _sliderItem(
                    context,
                    active: isDark,
                    icon: Icons.dark_mode_rounded,
                    label: AppLocalizations.of(context)!.themeModeDark,
                    onTap: () => onChanged(true),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sliderItem(
      BuildContext context, {
        required bool active,
        required IconData icon,
        required String label,
        required VoidCallback onTap,
      }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(ExpressiveShape.extraLarge),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: active ? AppTheme.bg(context) : AppTheme.textLight(context),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: active ? AppTheme.bg(context) : AppTheme.text(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemePreviewCard extends StatelessWidget {
  final String name;
  final ColorScheme scheme;
  final bool darkPreview;
  final bool selected;
  final bool compact;
  const _ThemePreviewCard({
    required this.name,
    required this.scheme,
    required this.darkPreview,
    required this.selected,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = scheme.surface;
    final card = darkPreview ? scheme.surfaceContainer : scheme.surfaceContainerHigh;
    final cardBorder = scheme.outlineVariant.withValues(alpha: darkPreview ? 0.45 : 0.65);
    if (compact) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(ExpressiveShape.medium),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurface),
                  ),
                ),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.palette_rounded,
                  size: 16,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    shape: BoxShape.circle,
                    border: Border.all(color: cardBorder),
                  ),
                  child: Icon(Icons.play_arrow_rounded, size: 16, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _miniSubscriptionCard(
                    bg: card,
                    border: cardBorder,
                    text: scheme.onSurface,
                    subText: scheme.onSurfaceVariant,
                    accent: scheme.primary,
                    height: 24,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(ExpressiveShape.large),
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Center(
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: card,
                shape: BoxShape.circle,
                border: Border.all(color: cardBorder),
              ),
              child: Icon(Icons.play_arrow_rounded, size: 23, color: scheme.onSurface),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Container(
              width: 84,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(ExpressiveShape.full),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Container(
            height: 2,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ExpressiveShape.full),
              gradient: LinearGradient(
                colors: [
                  scheme.secondary.withValues(alpha: 0.0),
                  scheme.secondary,
                  scheme.secondary.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          _miniSubscriptionCard(
            bg: card,
            border: cardBorder,
            text: scheme.onSurface,
            subText: scheme.onSurfaceVariant,
            accent: scheme.primary,
          ),
          const SizedBox(height: 4),
          _miniSubscriptionCard(
            bg: card,
            border: cardBorder,
            text: scheme.onSurface,
            subText: scheme.onSurfaceVariant,
            accent: scheme.secondary,
          ),
          const Spacer(),
          Container(
            height: 18,
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(ExpressiveShape.full),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Icon(Icons.hub_rounded, size: 10, color: scheme.onSurface),
                Icon(Icons.public_rounded, size: 10, color: scheme.onSurfaceVariant),
                Icon(Icons.settings_rounded, size: 10, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                selected ? Icons.check_rounded : Icons.palette_rounded,
                size: 16,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniSubscriptionCard({
    required Color bg,
    required Color border,
    required Color text,
    required Color subText,
    required Color accent,
    double height = 29,
  }) {
    if (height <= 26) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(ExpressiveShape.small),
          border: Border.all(color: border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        child: Row(
          children: [
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.85),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  color: text.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(ExpressiveShape.full),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                color: subText.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
        height: height,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(ExpressiveShape.small),
          border: Border.all(color: border),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 3, 4, 2),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 3,
                    decoration: BoxDecoration(color: text.withValues(alpha: 0.8), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 3),
                  Container(
                    width: 26,
                    height: 2,
                    decoration: BoxDecoration(
                      color: text.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(ExpressiveShape.full),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(4, 0, 4, 4),
              height: 13,
              decoration: BoxDecoration(
                color: subText.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(ExpressiveShape.extraSmall),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: accent.withValues(alpha: 0.85), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 20,
                    height: 2,
                    decoration: BoxDecoration(
                      color: text.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(ExpressiveShape.full),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Container(
                    width: 11,
                    height: 1.8,
                    decoration: BoxDecoration(
                      color: subText.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(ExpressiveShape.full),
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right_rounded, size: 8, color: subText),
                  const SizedBox(width: 2),
                ],
              ),
            ),
          ],
        ),
      );
  }
}
