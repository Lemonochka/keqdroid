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
      icon: isDesktop ? Icons.desktop_windows_outlined : Icons.palette_outlined,
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.bg(context),
        appBar: AppBar(
          backgroundColor: AppTheme.bg(context),
          elevation: 0,
          title: Text(l10n.themeCustomizationTitle),
          bottom: TabBar(
            labelColor: controlsAccent,
            unselectedLabelColor: AppTheme.textLight(context),
            indicatorColor: controlsAccent,
            dividerColor: AppTheme.divider(context),
            tabs: [
              Tab(text: l10n.appearanceTabGeneral),
              Tab(text: l10n.appearanceTabThemes),
            ],
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
    final controlsAccent = AppTheme.accent(context);
    return SmoothScroll(
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(16),
        children: [
          _FontPicker(
            currentFontId: current.fontId,
            onSelect: (id) => onSave(current.copyWith(fontId: id)),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            value: current.serversTwoColumns,
            onChanged: (v) => onSave(current.copyWith(serversTwoColumns: v)),
            activeThumbColor: controlsAccent,
            activeTrackColor: controlsAccent.withValues(alpha: 0.32),
            secondary: Icon(Icons.view_column_outlined, color: controlsAccent),
            title: Text(l10n.serversTwoColumnsTitle),
            subtitle: Text(l10n.serversTwoColumnsSubtitle),
          ),
          SwitchListTile(
            value: current.amoledBlack,
            onChanged: current.darkTheme
                ? (v) => onSave(current.copyWith(amoledBlack: v))
                : null,
            activeThumbColor: controlsAccent,
            activeTrackColor: controlsAccent.withValues(alpha: 0.32),
            secondary: Icon(Icons.contrast, color: controlsAccent),
            title: Text(l10n.appearanceAmoled),
            // Переключатель гасим на светлой теме, а не прячем: иначе он
            // «пропадает» и его ищут.
            subtitle: Text(
              current.darkTheme
                  ? l10n.appearanceAmoledSubtitle
                  : l10n.appearanceAmoledNeedsDark,
            ),
          ),
          if (!PlatformBootstrap.isDesktop)
            SwitchListTile(
              value: current.hapticFeedback,
              onChanged: (v) => onSave(current.copyWith(hapticFeedback: v)),
              activeThumbColor: controlsAccent,
              activeTrackColor: controlsAccent.withValues(alpha: 0.32),
              secondary: Icon(Icons.vibration, color: controlsAccent),
              title: Text(l10n.appearanceHaptics),
              subtitle: Text(l10n.appearanceHapticsSubtitle),
            ),
          SwitchListTile(
            value: current.showTrafficStats,
            onChanged: (v) => onSave(current.copyWith(showTrafficStats: v)),
            activeThumbColor: controlsAccent,
            activeTrackColor: controlsAccent.withValues(alpha: 0.32),
            secondary: Icon(Icons.swap_vert, color: controlsAccent),
            title: Text(l10n.appearanceShowTraffic),
            subtitle: Text(l10n.appearanceShowTrafficSubtitle),
          ),
          SwitchListTile(
            value: current.showConnectionTime,
            onChanged: (v) => onSave(current.copyWith(showConnectionTime: v)),
            activeThumbColor: controlsAccent,
            activeTrackColor: controlsAccent.withValues(alpha: 0.32),
            secondary: Icon(Icons.timer_outlined, color: controlsAccent),
            title: Text(l10n.appearanceShowTime),
            subtitle: Text(l10n.appearanceShowTimeSubtitle),
          ),
          const SizedBox(height: 8),
          Divider(color: AppTheme.divider(context)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: Text(
              l10n.appearanceNotifSectionTitle,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppTheme.textLight(context)),
            ),
          ),
          SwitchListTile(
            value: current.showSpeedInNotification,
            onChanged: (v) =>
                onSave(current.copyWith(showSpeedInNotification: v)),
            activeThumbColor: controlsAccent,
            activeTrackColor: controlsAccent.withValues(alpha: 0.32),
            secondary: Icon(Icons.speed_outlined, color: controlsAccent),
            title: Text(l10n.appearanceNotifSpeedTitle),
            subtitle: Text(l10n.appearanceNotifSpeedSubtitle),
          ),
          SwitchListTile(
            value: current.showUptimeInNotification,
            onChanged: (v) =>
                onSave(current.copyWith(showUptimeInNotification: v)),
            activeThumbColor: controlsAccent,
            activeTrackColor: controlsAccent.withValues(alpha: 0.32),
            secondary: Icon(Icons.timer_outlined, color: controlsAccent),
            title: Text(l10n.appearanceNotifUptimeTitle),
            subtitle: Text(l10n.appearanceNotifUptimeSubtitle),
          ),
          SwitchListTile(
            value: current.notifySubscriptionUpdates,
            onChanged: (v) =>
                onSave(current.copyWith(notifySubscriptionUpdates: v)),
            activeThumbColor: controlsAccent,
            activeTrackColor: controlsAccent.withValues(alpha: 0.32),
            secondary: Icon(Icons.sync_outlined, color: controlsAccent),
            title: Text(l10n.appearanceNotifSubUpdatesTitle),
            subtitle: Text(l10n.appearanceNotifSubUpdatesSubtitle),
          ),
        ],
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
        Row(
          children: [
            Icon(Icons.text_fields, size: 20, color: accent),
            const SizedBox(width: 8),
            Text(
              l10n.appearanceFontTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.text(context)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kAppFonts.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final font = kAppFonts[i];
              return _FontCard(
                label: font.id == kDefaultFontId
                    ? l10n.appearanceFontSystem
                    : font.label,
                fontFamily: font.family,
                selected: font.id == currentFontId,
                accent: accent,
                onTap: () => onSelect(font.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FontCard extends StatelessWidget {
  final String label;
  final String? fontFamily;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  const _FontCard({
    required this.label,
    required this.fontFamily,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 110,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.12)
              : AppTheme.inset(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? accent : AppTheme.divider(context),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Aa Яя',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontFamily: fontFamily, color: AppTheme.text(context)),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontFamily: fontFamily, color: selected ? accent : AppTheme.textLight(context), fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
                  ),
                ),
                if (selected) Icon(Icons.check_circle, size: 16, color: accent),
              ],
            ),
          ],
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
              isDesktop ? Icons.desktop_windows_outlined : Icons.android,
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
        borderRadius: BorderRadius.circular(28),
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
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  _sliderItem(
                    context,
                    active: !isDark,
                    icon: Icons.light_mode,
                    label: AppLocalizations.of(context)!.themeModeLight,
                    onTap: () => onChanged(false),
                  ),
                  _sliderItem(
                    context,
                    active: isDark,
                    icon: Icons.dark_mode,
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
        borderRadius: BorderRadius.circular(24),
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
          borderRadius: BorderRadius.circular(12),
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
                  selected ? Icons.check_circle : Icons.palette_outlined,
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
                  child: Icon(Icons.play_arrow, size: 16, color: scheme.onPrimaryContainer),
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
        borderRadius: BorderRadius.circular(14),
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
              child: Icon(Icons.play_arrow, size: 23, color: scheme.onSurface),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Container(
              width: 84,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Container(
            height: 2,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
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
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Icon(Icons.hub, size: 10, color: scheme.onSurface),
                Icon(Icons.public, size: 10, color: scheme.onSurfaceVariant),
                Icon(Icons.settings, size: 10, color: scheme.onSurfaceVariant),
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
                selected ? Icons.check : Icons.palette,
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
          borderRadius: BorderRadius.circular(6),
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
                  borderRadius: BorderRadius.circular(99),
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
          borderRadius: BorderRadius.circular(8),
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
                      borderRadius: BorderRadius.circular(99),
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
                borderRadius: BorderRadius.circular(4),
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
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Container(
                    width: 11,
                    height: 1.8,
                    decoration: BoxDecoration(
                      color: subText.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right, size: 8, color: subText),
                  const SizedBox(width: 2),
                ],
              ),
            ),
          ],
        ),
      );
  }
}
