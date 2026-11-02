part of '../servers_tab.dart';

class _SubscriptionTabsRow extends ConsumerWidget {
  const _SubscriptionTabsRow({required this.subscription, required this.groups});

  final Subscription subscription;
  final int groups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final open = ref.watch(
      serverGroupsTabProvider.select((m) => m[subscription.id] ?? false),
    );
    void show(bool value) => ref
        .read(serverGroupsTabProvider.notifier)
        .update((m) => {...m, subscription.id: value});
    return SizedBox(
      height: _GroupHeaderBackground.autoRowHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 14, 0),
        child: Row(
          children: [
            ExpressiveToggleButton(
              selected: !open,
              label: l10n.serversTabServers,
              onPressed: () => show(false),
            ),
            const SizedBox(width: ExpressiveSpacing.small),
            ExpressiveToggleButton(
              selected: open,
              label: l10n.serversTabGroups(groups),
              onPressed: () => show(true),
            ),
            // Авто справа: пара не прыгает, когда его включают в виде карточки
            if (subscription.autoSelectVisible) ...[
              const Spacer(),
              _AutoSelectButton(subscription: subscription),
            ],
          ],
        ),
      ),
    );
  }
}

Map<String, ServerItem> _serversByNode(
  ClashTemplate template,
  List<ServerItem> servers,
) => {
      for (final s in servers) ?template.nodeFor(s): s,
    };

String? _groupNow(
  ClashTemplate template,
  ClashTemplateGroup group,
  Subscription subscription,
  Map<String, MihomoGroupState>? live,
) =>
    live?[group.name]?.now ?? template.currentOf(group, subscription.groupChoices);

class _GroupBadge extends StatelessWidget {
  const _GroupBadge({
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final Color background;
  final Color foreground;

  static const _size = 40.0;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: _size,
        child: ClipPath(
          clipper: ShapeBorderClipper(
            shape: ExpressiveIconShapeTheme.of(context).border(_size),
          ),
          child: ColoredBox(
            color: background,
            child: Icon(icon, size: _size / 2, color: foreground),
          ),
        ),
      );
}

Widget _memberAvatar(
  BuildContext context,
  ClashTemplate template,
  String member,
  ServerItem? server,
) {
  final scheme = Theme.of(context).colorScheme;
  if (server != null) {
    return ServerAvatar(flag: server.flag, protocol: server.protocol);
  }
  return switch (template.kindOf(member)) {
    ClashMemberKind.direct => _GroupBadge(
        icon: Icons.call_made_rounded,
        background: AppTheme.green(context).withValues(alpha: 0.2),
        foreground: AppTheme.green(context),
      ),
    ClashMemberKind.block => _GroupBadge(
        icon: Icons.block_rounded,
        background: AppTheme.red(context).withValues(alpha: 0.2),
        foreground: AppTheme.red(context),
      ),
    ClashMemberKind.group => _GroupBadge(
        icon: template.groupType(member) == 'select'
            ? Icons.alt_route_rounded
            : Icons.bolt_rounded,
        background: scheme.tertiaryContainer,
        foreground: scheme.onTertiaryContainer,
      ),
    _ => _GroupBadge(
        icon: Icons.public_rounded,
        background: scheme.secondaryContainer,
        foreground: scheme.onSecondaryContainer,
      ),
  };
}

String _memberLabel(
  BuildContext context,
  ClashTemplate template,
  String member,
  Map<String, ServerItem> byNode,
  Map<String, MihomoGroupState>? live, {
  bool withName = true,
}) {
  final l10n = context.l10n;
  final server = byNode[member];
  if (server != null) {
    final ping = server.pingMs;
    return [
      if (withName)
        ServerNameUtils.formatForDisplay(
          ServerNameUtils.cleanDisplayName(server.displayName),
        ),
      if (ping != null) '$ping ms',
    ].join(' · ');
  }
  switch (template.kindOf(member)) {
    case ClashMemberKind.direct:
      return l10n.settingsRoutingDirectTitle;
    case ClashMemberKind.block:
      return l10n.settingsRoutingBlockTitle;
    case ClashMemberKind.group:
      final now = live?[member]?.now;
      final nowServer = now == null ? null : byNode[now];
      final detail = now == null
          ? (template.groupType(member) == 'select' ? null : l10n.serverGroupAuto)
          : l10n.serverGroupNow(
              nowServer == null
                  ? now
                  : ServerNameUtils.formatForDisplay(
                      ServerNameUtils.cleanDisplayName(nowServer.displayName),
                    ),
            );
      return [if (withName) member, ?detail].join(' · ');
    case ClashMemberKind.node || ClashMemberKind.other:
      return withName ? member : '';
  }
}

class _TemplateGroupsSliver extends ConsumerWidget {
  const _TemplateGroupsSliver({
    required this.subscription,
    required this.template,
    required this.servers,
    required this.rowExtent,
    required this.gap,
    required this.accent,
  });

  final Subscription subscription;
  final ClashTemplate template;
  final List<ServerItem> servers;
  final double rowExtent;
  final double gap;
  final SubscriptionAccent? accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(liveTemplateGroupsProvider(subscription.id)).value;
    final activeHere = ref.watch(
      serversProvider.select(
        (s) => s.activeServer?.subscriptionId == subscription.id,
      ),
    );
    final byNode = _serversByNode(template, servers);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final direction = Directionality.of(context);
    final tileColor =
        accent?.surface(AppTheme.card(context)) ?? AppTheme.card(context);
    final selectedColor = accent?.container ?? scheme.secondaryContainer;
    final groups = template.groups;

    Widget tileAt(int index) {
      final group = groups[index];
      final now = _groupNow(template, group, subscription, live);
      return SizedBox(
        height: rowExtent,
        child: Padding(
          padding: ExpressiveListSegment.segmentMargin(index: index, spacing: gap)
              .resolve(direction),
          child: ExpressiveListSegment(
            radius: ExpressiveListSegment.segmentRadius(
              index: index,
              count: groups.length,
              endCorner: ExpressiveShape.extraLarge - ExpressiveListSegment.gap,
            ).resolve(direction),
            color: tileColor,
            selectedColor: selectedColor,
            onTap: () => _showGroupPickSheet(context, subscription, group),
            child: Opacity(
              opacity: activeHere ? 1 : 0.45,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ExpressiveSpacing.large,
                ),
                child: Row(
                  children: [
                    if (now != null)
                      _memberAvatar(context, template, now, byNode[now]),
                    const SizedBox(width: ExpressiveSpacing.medium),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            group.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyLarge
                                ?.copyWith(color: AppTheme.text(context)),
                          ),
                          if (now != null) ...[
                            const SizedBox(height: ExpressiveSpacing.hairline),
                            Text(
                              _memberLabel(context, template, now, byNode, live),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelLarge
                                  ?.copyWith(color: AppTheme.textLight(context)),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: ExpressiveIconSize.medium,
                      color: AppTheme.textLight(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final list = SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => tileAt(index),
        childCount: groups.length,
      ),
    );
    if (activeHere) return list;
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: ExpressiveIconSize.inline,
                  color: AppTheme.textLight(context),
                ),
                const SizedBox(width: ExpressiveSpacing.small),
                Expanded(
                  child: Text(
                    context.l10n.serverGroupsInactive,
                    style: textTheme.bodyMedium
                        ?.copyWith(color: AppTheme.textLight(context)),
                  ),
                ),
              ],
            ),
          ),
        ),
        list,
      ],
    );
  }
}

void _showGroupPickSheet(
  BuildContext context,
  Subscription subscription,
  ClashTemplateGroup group,
) {
  AppHaptics.selection();
  unawaited(showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _GroupPickSheet(subscriptionId: subscription.id, group: group),
  ));
}

class _GroupPickSheet extends ConsumerWidget {
  const _GroupPickSheet({required this.subscriptionId, required this.group});

  final String subscriptionId;
  final ClashTemplateGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final template = ref.watch(subscriptionTemplateProvider(subscriptionId));
    final subscription = ref.watch(subscriptionsProvider.select((a) =>
        a.value?.where((s) => s.id == subscriptionId).firstOrNull));
    if (template == null || subscription == null) return const SizedBox.shrink();
    final live = ref.watch(liveTemplateGroupsProvider(subscriptionId)).value;
    final servers = ref.watch(serversProvider.select((s) => [
          for (final server in s.servers)
            if (server.subscriptionId == subscriptionId) server,
        ]));
    final byNode = _serversByNode(template, servers);
    final now = _groupNow(template, group, subscription, live);
    // выбор, поставленный первым в группу с include-all, ядро отдаёт в all дважды
    final members = [...{...(live?[group.name]?.all ?? group.members)}];
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final direction = Directionality.of(context);

    // ref закрытой шторки уже мёртв: notifier берём до pop
    Future<void> choose(String member) async {
      AppHaptics.selection();
      final subs = ref.read(subscriptionsProvider.notifier);
      Navigator.pop(context);
      await subs.chooseInGroup(subscriptionId, group.name, member);
    }

    final others = [for (final m in members) if (byNode[m] == null) m];
    final nodes = [for (final m in members) if (byNode[m] != null) m];

    Widget otherTile(String member) {
      final selected = member == now;
      final fg = selected ? scheme.onSecondaryContainer : scheme.onSurface;
      final detail = _memberLabel(
        context,
        template,
        member,
        byNode,
        live,
        withName: false,
      );
      final title = switch (template.kindOf(member)) {
        ClashMemberKind.direct || ClashMemberKind.block => detail,
        _ => member,
      };
      final subtitle = title == detail ? '' : detail;
      return ExpressiveGroupTile(
        onTap: () => unawaited(choose(member)),
        color: selected ? scheme.secondaryContainer : null,
        child: Row(
          children: [
            _memberAvatar(context, template, member, null),
            const SizedBox(width: ExpressiveSpacing.large),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyLarge?.copyWith(color: fg),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_rounded, color: fg),
          ],
        ),
      );
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Column(
                children: [
                  Text(
                    group.name,
                    textAlign: TextAlign.center,
                    style: textTheme
                        .emphasized(textTheme.titleLarge)
                        ?.copyWith(color: AppTheme.text(context)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.serverGroupPickHint,
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium
                        ?.copyWith(color: AppTheme.textLight(context)),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                child: Column(
                  children: [
                    if (others.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ExpressiveGroup(
                          children: [for (final m in others) otherTile(m)],
                        ),
                      ),
                    if (others.isNotEmpty && nodes.isNotEmpty)
                      const SizedBox(height: 12),
                    if (nodes.isNotEmpty)
                      LayoutBuilder(builder: (context, box) {
                        final columns = ServerRow.fittingColumns(
                          box.maxWidth + ServerRow.listSideInset * 2,
                          MediaQuery.textScalerOf(context),
                          2,
                        );
                        final height = columns > 1
                            ? ServerRow.cardHeight(context)
                            : ServerRow.height;
                        return Wrap(
                          children: [
                            for (var i = 0; i < nodes.length; i++)
                              SizedBox(
                                width: box.maxWidth / columns,
                                height: height,
                                child: Padding(
                                  padding: ExpressiveListSegment.segmentMargin(
                                    index: i,
                                    columns: columns,
                                  ).resolve(direction),
                                  child: ExpressiveListSegment(
                                    radius: ExpressiveListSegment.segmentRadius(
                                      index: i,
                                      count: nodes.length,
                                      columns: columns,
                                    ).resolve(direction),
                                    selected: nodes[i] == now,
                                    color: scheme.surfaceContainerHigh,
                                    selectedColor: scheme.secondaryContainer,
                                    onTap: () => unawaited(choose(nodes[i])),
                                    child: ServerRow(
                                      server: byNode[nodes[i]]!,
                                      pingMs: byNode[nodes[i]]!.pingMs,
                                      lastTestedAt: byNode[nodes[i]]!.lastTestedAt,
                                      layout: columns > 1
                                          ? ServerRowLayout.card
                                          : ServerRowLayout.inline,
                                      emphasizeTitle: nodes[i] == now,
                                      foreground: nodes[i] == now
                                          ? scheme.onSecondaryContainer
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
