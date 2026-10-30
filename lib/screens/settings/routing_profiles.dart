part of '../settings_tab.dart';

// null это «Основной»: его маршруты в routesProvider, «Всё остальное» в настройках
Future<void> _upsertRoute(
  WidgetRef ref,
  String? profileId,
  TrafficRoute route,
) =>
    profileId == null
        ? ref.read(routesProvider.notifier).upsert(route)
        : ref
            .read(routingProfilesProvider.notifier)
            .upsertRoute(profileId, route);

Future<void> _removeRoute(WidgetRef ref, String? profileId, String routeId) =>
    profileId == null
        ? ref.read(routesProvider.notifier).remove(routeId)
        : ref
            .read(routingProfilesProvider.notifier)
            .removeRoute(profileId, routeId);

Future<List<TrafficRoute>> _routesFor(WidgetRef ref, String? profileId) async {
  if (profileId == null) return ref.read(routesProvider.future);
  final profiles = await ref.read(routingProfilesProvider.future);
  return profiles.where((p) => p.id == profileId).firstOrNull?.routes ??
      const [];
}

String _finalOutboundFor(WidgetRef ref, String? profileId) {
  if (profileId == null) {
    return ref.read(settingsNotifierProvider).value?.finalOutbound ??
        AppSettings.finalOutboundProxy;
  }
  final profile = ref
      .read(routingProfilesProvider)
      .value
      ?.where((p) => p.id == profileId)
      .firstOrNull;
  return profile?.finalOutbound ?? AppSettings.finalOutboundProxy;
}

Future<void> _saveFinalOutbound(
  WidgetRef ref,
  String? profileId,
  String value,
) async {
  if (profileId != null) {
    await ref
        .read(routingProfilesProvider.notifier)
        .setFinalOutbound(profileId, value);
    return;
  }
  final settings = ref.read(settingsNotifierProvider).value;
  if (settings == null) return;
  await ref
      .read(settingsNotifierProvider.notifier)
      .save(settings.copyWith(finalOutbound: value));
}

String _finalLabel(AppLocalizations l10n, String finalOutbound) =>
    switch (finalOutbound) {
      AppSettings.finalOutboundDirect => l10n.routeToDirect,
      AppSettings.finalOutboundBlock => l10n.routeToBlock,
      _ => l10n.routeToVpn,
    };

// «Основной» раскрыт, пока его не свернули, остальные наоборот
const _mainProfileKey = '';

bool _profileExpanded(Map<String, bool> state, String key) =>
    state[key] ?? key == _mainProfileKey;

void _toggleProfile(WidgetRef ref, String key) => ref
    .read(expandedRoutingProfilesProvider.notifier)
    .update((m) => {...m, key: !_profileExpanded(m, key)});

class _ProfileChip extends StatelessWidget {
  const _ProfileChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(ExpressiveShape.small),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: scheme.onPrimaryContainer),
      ),
    );
  }
}

class _ProfileSectionLabel extends StatelessWidget {
  const _ProfileSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 0, 6),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      );
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    super.key,
    required this.title,
    required this.summary,
    required this.expanded,
    required this.onToggle,
    required this.body,
    this.chips = const [],
    this.enabled,
    this.onEnabled,
    this.menu,
  });

  final String title;
  final String summary;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> body;
  final List<String> chips;

  // null у «Основного»: его нельзя выключить
  final bool? enabled;
  final ValueChanged<bool>? onEnabled;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final light = AppTheme.textLight(context);
    final dim = enabled == false ? 0.5 : 1.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(ExpressiveShape.largeIncreased),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggle,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(
                      children: [
                        TvTappable(
                          onTap: onToggle,
                          radius: BorderRadius.circular(11),
                          child: AnimatedRotation(
                            turns: expanded ? 0 : -0.25,
                            duration: const Duration(milliseconds: 200),
                            child: Builder(
                              builder: (context) => Icon(
                                Icons.expand_more_rounded,
                                size: 22,
                                color: TvFocusHighlight.containerOf(context) !=
                                        null
                                    ? Theme.of(context).colorScheme.onSurface
                                    : light,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Opacity(
                            opacity: dim,
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme
                                  .emphasized(theme.textTheme.titleMedium)
                                  ?.copyWith(color: AppTheme.text(context)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (enabled != null) Switch(value: enabled!, onChanged: onEnabled),
              ?menu,
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Opacity(
              opacity: dim,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 8, 0),
                    child: Text(
                      summary,
                      style: theme.textTheme.bodyMedium?.copyWith(color: light),
                    ),
                  ),
                  if (chips.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [for (final c in chips) _ProfileChip(c)],
                    ),
                  ],
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    alignment: Alignment.topCenter,
                    child: expanded
                        ? Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: body,
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _showProfileMenu(BuildContext context, WidgetRef ref, RoutingProfile p) {
  final l10n = AppLocalizations.of(context)!;
  unawaited(showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                p.name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(ctx)
                    .textTheme
                    .emphasized(Theme.of(ctx).textTheme.titleLarge)
                    ?.copyWith(color: AppTheme.text(ctx)),
              ),
            ),
            ExpressiveGroup(
              children: [
                ExpressiveActionTile(
                  icon: Icons.edit_rounded,
                  title: l10n.serversRename,
                  accent: ExpressiveAccent.primary,
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_renameProfile(context, ref, p));
                  },
                ),
                ExpressiveActionTile(
                  icon: Icons.language_rounded,
                  title: l10n.routingProfileSubscriptions,
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_showProfileSheet(context, ref, editing: p));
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            ExpressiveGroup(
              children: [
                ExpressiveActionTile(
                  icon: Icons.delete_outline_rounded,
                  title: l10n.subscriptionsDelete,
                  danger: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_deleteProfile(context, ref, p));
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  ));
}

Future<void> _renameProfile(
  BuildContext context,
  WidgetRef ref,
  RoutingProfile p,
) async {
  final l10n = AppLocalizations.of(context)!;
  // без dispose: поле ещё рисуется, пока диалог уезжает после pop
  final controller = TextEditingController(text: p.name);
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.routingProfileRenameTitle),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.routingProfileName),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.subscriptionsCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: Text(l10n.subscriptionsSave),
        ),
      ],
    ),
  );
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty) return;
  await ref.read(routingProfilesProvider.notifier).rename(p.id, trimmed);
}

Future<void> _deleteProfile(
  BuildContext context,
  WidgetRef ref,
  RoutingProfile p,
) async {
  final l10n = AppLocalizations.of(context)!;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(l10n.routingProfileDeleteConfirm(p.name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.subscriptionsCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.subscriptionsDelete),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await ref.read(routingProfilesProvider.notifier).remove(p.id);
}

Future<void> _showProfileSheet(
  BuildContext context,
  WidgetRef ref, {
  RoutingProfile? editing,
}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _ProfileSheet(editing: editing),
    );

// с editing шторка правит только подписки готового профиля
class _ProfileSheet extends ConsumerStatefulWidget {
  const _ProfileSheet({this.editing});

  final RoutingProfile? editing;

  @override
  ConsumerState<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends ConsumerState<_ProfileSheet> {
  final _name = TextEditingController();
  late final Set<String> _subs = {...?widget.editing?.subscriptionIds};
  bool _copyMain = true;

  bool get _creating => widget.editing == null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _toggle(String subId, bool on) =>
      setState(() => on ? _subs.add(subId) : _subs.remove(subId));

  Future<void> _submit() async {
    final notifier = ref.read(routingProfilesProvider.notifier);
    final picked = _subs.toList();
    if (!_creating) {
      await notifier.setSubscriptions(widget.editing!.id, picked);
    } else {
      final main = await ref.read(routesProvider.future);
      final profile = RoutingProfile.create(
        name: _name.text.trim(),
        subscriptionIds: picked,
        finalOutbound: _copyMain
            ? _finalOutboundFor(ref, null)
            : AppSettings.finalOutboundProxy,
        routes: _copyMain ? main : const [],
      );
      await notifier.add(profile);
      ref
          .read(expandedRoutingProfilesProvider.notifier)
          .update((m) => {...m, profile.id: true});
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final light = AppTheme.textLight(context);
    final subs = ref.watch(subscriptionsProvider).value ?? const [];
    final profiles =
        ref.watch(routingProfilesProvider).value ?? const <RoutingProfile>[];

    // подпись только у занятой другим профилем: отметка здесь заберёт её оттуда
    String? owner(String subId) {
      final other = profiles
          .where((p) =>
              p.id != widget.editing?.id && p.subscriptionIds.contains(subId))
          .firstOrNull;
      return other == null ? null : l10n.routingProfileSubOnOther(other.name);
    }

    final canSubmit = !_creating || _name.text.trim().isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  child: Text(
                    _creating
                        ? l10n.routingProfileNew
                        : l10n.routingProfileSubscriptions,
                    style: theme.textTheme
                        .emphasized(theme.textTheme.titleMedium)
                        ?.copyWith(color: AppTheme.text(context)),
                  ),
                ),
                if (_creating) ...[
                  TextField(
                    controller: _name,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: l10n.routingProfileName,
                    ),
                  ),
                  ExpressiveSectionHeader(l10n.routingProfileForSubscriptions),
                ],
                if (subs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    child: Text(
                      l10n.routingProfileNoSubscriptionsYet,
                      style: theme.textTheme.bodyMedium?.copyWith(color: light),
                    ),
                  )
                else
                  ExpressiveGroup(
                    children: [
                      for (final sub in subs)
                        ExpressiveGroupTile(
                          onTap: () => _toggle(sub.id, !_subs.contains(sub.id)),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      sub.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                        color: AppTheme.text(context),
                                      ),
                                    ),
                                    if (owner(sub.id) case final note?)
                                      Text(
                                        note,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(color: light),
                                      ),
                                  ],
                                ),
                              ),
                              Checkbox(
                                value: _subs.contains(sub.id),
                                onChanged: (v) => _toggle(sub.id, v == true),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                if (_creating) ...[
                  ExpressiveSectionHeader(l10n.routingProfileStartFrom),
                  ExpressiveGroup(
                    children: [
                      ExpressiveActionTile(
                        icon: Icons.content_copy_rounded,
                        title: l10n.routingProfileStartCopy,
                        subtitle: l10n.routingProfileStartCopyHint,
                        selected: _copyMain,
                        onTap: () => setState(() => _copyMain = true),
                      ),
                      ExpressiveActionTile(
                        icon: Icons.note_add_outlined,
                        title: l10n.routingProfileStartEmpty,
                        subtitle: l10n.routingProfileStartEmptyHint,
                        selected: !_copyMain,
                        onTap: () => setState(() => _copyMain = false),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: ExpressiveSpacing.large),
                FilledButton(
                  onPressed: canSubmit ? () => unawaited(_submit()) : null,
                  child: Text(
                    _creating
                        ? l10n.routingProfileCreate
                        : l10n.subscriptionsSave,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
