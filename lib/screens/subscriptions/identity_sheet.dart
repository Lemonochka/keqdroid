part of '../subscriptions_tab.dart';

class _IdentityTile extends StatelessWidget {
  final SubscriptionFetchIdentity identity;
  final VoidCallback onTap;

  const _IdentityTile({required this.identity, required this.onTap});

  static String? summary(SubscriptionFetchIdentity identity) {
    if (!identity.isActive) return null;
    final parts = [
      identity.userAgent,
      identity.deviceModel,
      identity.osVersion,
      identity.deviceOs,
      identity.hwid,
    ].whereType<String>();
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final value = summary(identity);
    final active = value != null;
    final accent = active
        ? ExpressiveAccent.tertiary
        : ExpressiveAccent.secondary;

    return ExpressiveGroupTile(
      onTap: onTap,
      radius: ExpressiveShape.radius(ExpressiveShape.large),
      child: Row(
        children: [
          ExpressiveIconBadge(icon: Icons.badge_rounded, accent: accent),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.subscriptionIdentityTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
                Text(
                  value ?? l10n.subscriptionIdentityAppDefault,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: active ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 22,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

// isScrollControlled снимает потолок высоты, и на десктопе ручка уезжала под край экрана
BoxConstraints _sheetConstraints(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return BoxConstraints(
    maxWidth: 560,
    maxHeight: math.min(640, size.height * 0.9),
  );
}

Future<SubscriptionFetchIdentity?> _showIdentitySheet(
  BuildContext context, {
  required SubscriptionFetchIdentity initial,
}) {
  return showModalBottomSheet<SubscriptionFetchIdentity>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: _sheetConstraints(context),
    builder: (ctx) => _IdentitySheet(initial: initial),
  );
}

class _SheetHeader extends StatelessWidget {
  final String title;

  const _SheetHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 4, 8),
      child: Row(
        children: [
          const SizedBox(width: 48),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme
                  .emphasized(theme.textTheme.titleLarge)
                  ?.copyWith(color: theme.colorScheme.onSurface),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          ),
        ],
      ),
    );
  }
}

class _IdentitySheet extends ConsumerStatefulWidget {
  final SubscriptionFetchIdentity initial;

  const _IdentitySheet({required this.initial});

  @override
  ConsumerState<_IdentitySheet> createState() => _IdentitySheetState();
}

class _IdentitySheetState extends ConsumerState<_IdentitySheet> {
  late bool _enabled = widget.initial.enabled;
  late String? _hwid = widget.initial.hwid;
  late String? _userAgent = widget.initial.userAgent;
  late String? _deviceOs = widget.initial.deviceOs;
  late String? _deviceModel = widget.initial.deviceModel;
  late String? _osVersion = widget.initial.osVersion;

  SubscriptionFetchIdentity get _identity => SubscriptionFetchIdentity(
    enabled: _enabled,
    hwid: _hwid,
    userAgent: _userAgent,
    deviceOs: _deviceOs,
    deviceModel: _deviceModel,
    osVersion: _osVersion,
  );

  List<String> _used(String? Function(SubscriptionFetchIdentity) pick) {
    final subs =
        ref.read(subscriptionsProvider).value ?? const <Subscription>[];
    final out = <String>[];
    for (final sub in subs) {
      final value = pick(sub.fetchIdentity);
      if (value != null && !out.contains(value)) out.add(value);
    }
    return out;
  }

  List<_IdentitySection> _sections(
    List<_IdentitySection> presets,
    String? Function(SubscriptionFetchIdentity) pick, {
    List<String> extra = const [],
  }) {
    final known = presets.expand((s) => s.items).toSet();
    final used = [
      ...extra,
      ..._used(pick),
    ].where((v) => !known.contains(v)).toSet().toList();
    return [
      if (used.isNotEmpty)
        _IdentitySection(
          title: AppLocalizations.of(context)!.subscriptionIdentitySectionUsed,
          icon: Icons.history_rounded,
          items: used,
        ),
      ...presets,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    // watch: настройки грузятся асинхронно, и read на первом экране отдал бы пустоту
    final shareHwid =
        ref.watch(settingsNotifierProvider).value?.shareDeviceHwid ?? true;
    final deviceHwid = ref.read(storageProvider).getHwid();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetHeader(l10n.subscriptionIdentityTitle),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Text(
                l10n.subscriptionIdentityHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            ExpressiveGroup(
              children: [
                ExpressiveGroupTile(
                  onTap: () => setState(() => _enabled = !_enabled),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.subscriptionIdentityEnable,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      Switch(
                        value: _enabled,
                        onChanged: (v) => setState(() => _enabled = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_enabled) ...[
              const SizedBox(height: 12),
              if (!shareHwid)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _IdentityWarning(
                    text: l10n.subscriptionIdentityHwidOff,
                  ),
                ),
              Flexible(
                child: SmoothScroll(
                  builder: (context, controller) => ListView(
                    controller: controller,
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    physics: const ClampingScrollPhysics(),
                    children: [
                      ExpressiveGroup(
                        children: [
                          _IdentityOptionRow(
                            label: l10n.subscriptionIdentityHwid,
                            icon: Icons.fingerprint_rounded,
                            value: _hwid,
                            lowercaseCustom: true,
                            sections: _sections(
                              const [],
                              (i) => i.hwid,
                              extra: [
                                if (deviceHwid?.isNotEmpty ?? false)
                                  deviceHwid!,
                              ],
                            ),
                            onChanged: (v) => setState(() => _hwid = v),
                          ),
                          _IdentityOptionRow(
                            label: l10n.subscriptionIdentityUserAgent,
                            icon: Icons.http_rounded,
                            value: _userAgent,
                            sections: _sections(
                              _uaPresets(l10n),
                              (i) => i.userAgent,
                            ),
                            onChanged: (v) => setState(() => _userAgent = v),
                          ),
                          _IdentityOptionRow(
                            label: l10n.subscriptionIdentityDeviceOs,
                            icon: Icons.phone_android_rounded,
                            value: _deviceOs,
                            sections: _sections(
                              _osPresets(l10n),
                              (i) => i.deviceOs,
                            ),
                            onChanged: (v) => setState(() => _deviceOs = v),
                          ),
                          _IdentityOptionRow(
                            label: l10n.subscriptionIdentityDeviceModel,
                            icon: Icons.smartphone_rounded,
                            value: _deviceModel,
                            sections: _sections(
                              _modelPresets(l10n),
                              (i) => i.deviceModel,
                            ),
                            onChanged: (v) => setState(() => _deviceModel = v),
                          ),
                          _IdentityOptionRow(
                            label: l10n.subscriptionIdentityOsVersion,
                            icon: Icons.system_update_alt_rounded,
                            value: _osVersion,
                            sections: _sections(
                              _osVersionPresets(l10n),
                              (i) => i.osVersion,
                            ),
                            onChanged: (v) => setState(() => _osVersion = v),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.pop(context, SubscriptionFetchIdentity.empty),
                    child: Text(
                      l10n.subscriptionIdentityReset,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _identity),
                    child: Text(
                      l10n.subscriptionIdentityApply,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static List<_IdentitySection> _uaPresets(AppLocalizations l10n) => [
    _IdentitySection(
      title: l10n.subscriptionIdentitySectionUaAndroid,
      icon: Icons.android_rounded,
      items: ClientUaPresets.android,
    ),
    _IdentitySection(
      title: l10n.subscriptionIdentitySectionUaApple,
      icon: Icons.phone_iphone_rounded,
      items: ClientUaPresets.ios,
    ),
    _IdentitySection(
      title: l10n.subscriptionIdentitySectionUaDesktop,
      icon: Icons.computer_rounded,
      items: ClientUaPresets.desktop,
    ),
    _IdentitySection(
      title: l10n.subscriptionIdentitySectionUaCores,
      icon: Icons.terminal_rounded,
      items: ClientUaPresets.cores,
    ),
  ];

  static List<_IdentitySection> _osPresets(AppLocalizations l10n) => [
    _IdentitySection(
      title: l10n.subscriptionIdentitySectionOs,
      icon: Icons.devices_rounded,
      items: DeviceOsPresets.all,
    ),
  ];

  static List<_IdentitySection> _modelPresets(AppLocalizations l10n) => [
    const _IdentitySection(
      title: 'Android',
      icon: Icons.android_rounded,
      items: DeviceModelPresets.android,
    ),
    _IdentitySection(
      title: l10n.subscriptionIdentitySectionApple,
      icon: Icons.phone_iphone_rounded,
      items: DeviceModelPresets.ios,
    ),
    _IdentitySection(
      title: l10n.subscriptionIdentitySectionDesktop,
      icon: Icons.computer_rounded,
      items: DeviceModelPresets.desktop,
    ),
  ];

  static List<_IdentitySection> _osVersionPresets(AppLocalizations l10n) => [
    _IdentitySection(
      title: l10n.subscriptionIdentitySectionAndroidRelease,
      icon: Icons.android_rounded,
      items: OsVersionPresets.androidRelease,
    ),
    _IdentitySection(
      title: l10n.subscriptionIdentitySectionAndroidBuild,
      icon: Icons.build_circle_rounded,
      items: OsVersionPresets.androidBuilds,
    ),
    _IdentitySection(
      title: l10n.subscriptionIdentitySectionIosRelease,
      icon: Icons.phone_iphone_rounded,
      items: OsVersionPresets.iosRelease,
    ),
    _IdentitySection(
      title: l10n.subscriptionIdentitySectionIosBuild,
      icon: Icons.numbers_rounded,
      items: OsVersionPresets.iosBuilds,
    ),
    _IdentitySection(
      title: l10n.subscriptionIdentitySectionDesktop,
      icon: Icons.computer_rounded,
      items: OsVersionPresets.desktop,
    ),
  ];
}

class _IdentityWarning extends StatelessWidget {
  final String text;
  const _IdentityWarning({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ExpressiveCard(
      color: scheme.errorContainer,
      corner: ExpressiveShape.large,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentitySection {
  final String title;
  final IconData icon;
  final List<String> items;

  const _IdentitySection({
    required this.title,
    required this.icon,
    required this.items,
  });
}

class _IdentityOptionRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? value;
  final List<_IdentitySection> sections;

  // HWID и уходит в нижнем регистре, у остальных полей регистр значим
  final bool lowercaseCustom;

  final ValueChanged<String?> onChanged;

  const _IdentityOptionRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.sections,
    required this.onChanged,
    this.lowercaseCustom = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final set = value != null;

    return ExpressiveGroupTile(
      onTap: () async {
        final picked = await showModalBottomSheet<({String? value})>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          constraints: _sheetConstraints(context),
          builder: (ctx) => _IdentityOptionPicker(
            title: label,
            icon: icon,
            selected: value,
            sections: sections,
            lowercaseCustom: lowercaseCustom,
          ),
        );
        if (picked != null) onChanged(picked.value);
      },
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: set
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              borderRadius: ExpressiveShape.radius(ExpressiveShape.medium),
            ),
            child: Icon(
              icon,
              size: 20,
              color: set ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  set
                      ? ltrIsolate(value!)
                      : l10n.subscriptionIdentityAppDefault,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: set ? scheme.onSurface : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.unfold_more_rounded,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _IdentityOptionPicker extends StatefulWidget {
  final String title;
  final IconData icon;
  final String? selected;
  final List<_IdentitySection> sections;
  final bool lowercaseCustom;

  const _IdentityOptionPicker({
    required this.title,
    required this.icon,
    required this.selected,
    required this.sections,
    required this.lowercaseCustom,
  });

  @override
  State<_IdentityOptionPicker> createState() => _IdentityOptionPickerState();
}

class _IdentityOptionPickerState extends State<_IdentityOptionPicker> {
  late final _queryCtrl = TextEditingController(
    text: _isKnown(widget.selected) ? '' : (widget.selected ?? ''),
  );
  late String _query = _queryCtrl.text;

  bool _isKnown(String? value) =>
      value != null && widget.sections.any((s) => s.items.contains(value));

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  bool _matches(String value) =>
      _query.isEmpty || value.toLowerCase().contains(_query.toLowerCase());

  String? get _typedValue {
    final typed = _query.trim();
    if (typed.isEmpty) return null;
    if (widget.sections.any((s) => s.items.contains(typed))) return null;
    return widget.lowercaseCustom ? typed.toLowerCase() : typed;
  }

  void _pick(String? value) => Navigator.pop(context, (value: value));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final typed = _typedValue;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetHeader(widget.title),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TvTextField(
                radius: BorderRadius.circular(ExpressiveShape.full),
                builder: (ctx, canRequestFocus) {
                  final barScheme = Theme.of(ctx).colorScheme;
                  return ExcludeFocus(
                    excluding: !canRequestFocus,
                    child: SearchBar(
                      controller: _queryCtrl,
                      hintText: l10n.subscriptionIdentitySearchOrEnter,
                      autoFocus: false,
                      leading: Icon(
                        Icons.search_rounded,
                        color: barScheme.onSurfaceVariant,
                      ),
                      onChanged: (q) => setState(() => _query = q),
                      onSubmitted: (_) {
                        if (_typedValue != null) _pick(_typedValue);
                      },
                    ),
                  );
                },
              ),
            ),
            Flexible(
              child: SmoothScroll(
                builder: (context, controller) => ListView(
                  controller: controller,
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    ExpressiveGroup(
                      children: [
                        if (typed != null)
                          ExpressiveActionTile(
                            icon: Icons.edit_rounded,
                            title: typed,
                            subtitle: l10n.subscriptionIdentityUseTyped,
                            accent: ExpressiveAccent.tertiary,
                            selected: widget.selected == typed,
                            onTap: () => _pick(typed),
                          ),
                        ExpressiveActionTile(
                          icon: Icons.home_rounded,
                          title: l10n.subscriptionIdentityAppDefault,
                          subtitle: l10n.subscriptionIdentityAppDefaultHint,
                          selected: widget.selected == null,
                          onTap: () => _pick(null),
                        ),
                      ],
                    ),
                    for (final section in widget.sections) ..._section(section),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _section(_IdentitySection section) {
    final items = section.items.where(_matches).toList();
    if (items.isEmpty) return const [];
    return [
      ExpressiveSectionHeader(section.title, icon: section.icon),
      ExpressiveGroup(
        children: [
          for (final item in items)
            ExpressiveActionTile(
              icon: section.icon,
              title: item,
              selected: widget.selected == item,
              onTap: () => _pick(item),
            ),
        ],
      ),
    ];
  }
}
