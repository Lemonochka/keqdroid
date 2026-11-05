part of '../servers_tab.dart';

class _SubscriptionTabsRow extends ConsumerWidget {
  const _SubscriptionTabsRow({
    required this.subscription,
    required this.groups,
    this.autoKey,
  });

  final Subscription subscription;
  final int groups;
  final Key? autoKey;

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
              _AutoSelectButton(
                subscription: subscription,
                buttonKey: autoKey,
              ),
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

// флагов стран в эмодзи-шрифте Windows нет, он печатает буквы: флаг рисуется картинкой слева, как у серверов
String _plainName(String name) {
  final plain = stripFlags(name).trim();
  return plain.isEmpty ? name : plain;
}

// флаг сервера, через который группа идёт сейчас; без подключения флаг из её имени
ServerFlag? _groupFlag(
  ClashTemplate template,
  String group,
  Map<String, ServerItem> byNode,
  Map<String, MihomoGroupState>? live,
) {
  var at = group;
  for (var hop = 0; hop < 8; hop++) {
    final now = live?[at]?.now;
    if (now == null) break;
    final server = byNode[now];
    if (server != null) return server.flag;
    at = now;
  }
  if (const {ClashMemberKind.direct, ClashMemberKind.block}
      .contains(template.kindOf(at))) {
    return null;
  }
  return firstFlagIn(at) ?? firstFlagIn(group);
}

// через что идёт всё остальное, если в главной группе выбрали не сервер
({String label, ServerFlag? flag})? _mainGroupRoute(
  BuildContext context,
  WidgetRef ref,
  ServerItem server,
) {
  final subId = server.subscriptionId;
  if (subId == null) return null;
  final template = ref.watch(subscriptionTemplateProvider(subId));
  if (template == null || template.nodeFor(server) == null) return null;
  final choices = ref.watch(subscriptionsProvider.select((a) => a.value
      ?.where((s) => s.id == subId)
      .firstOrNull
      ?.groupChoices));
  final chosen = template.mainChoice(choices ?? const {});
  if (chosen == null) return null;
  final live = ref.watch(liveTemplateGroupsProvider(subId)).value;
  final byNode = _serversByNode(template, [
    for (final s in ref.read(serversProvider).servers)
      if (s.subscriptionId == subId) s,
  ]);
  return (
    label: template.kindOf(chosen) == ClashMemberKind.direct
        ? context.l10n.settingsRoutingDirectTitle
        : _plainName(chosen),
    flag: _groupFlag(template, chosen, byNode, live),
  );
}

String? _groupNow(
  ClashTemplate template,
  ClashTemplateGroup group,
  Subscription subscription,
  Map<String, MihomoGroupState>? live, {
  String? activeNode,
}) =>
    live?[group.name]?.now ??
    (group.name == template.mainGroup
        ? template.mainChoice(subscription.groupChoices) ?? activeNode
        : template.currentOf(group, subscription.groupChoices));

// список узлов внутри есть только у запущенного ядра: proxy-providers качает оно
bool _drillable(
  ClashTemplate template,
  String member,
  Map<String, MihomoGroupState>? live,
) =>
    template.pinnable(member) && (live?[member]?.all.length ?? 0) > 1;

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
  Map<String, ServerItem> byNode,
  Map<String, MihomoGroupState>? live,
) {
  final scheme = Theme.of(context).colorScheme;
  final server = byNode[member];
  if (server != null) {
    return ServerAvatar(flag: server.flag, protocol: server.protocol);
  }
  final kind = template.kindOf(member);
  final flag = switch (kind) {
    ClashMemberKind.group => _groupFlag(template, member, byNode, live),
    ClashMemberKind.node || ClashMemberKind.other => firstFlagIn(member),
    _ => null,
  };
  if (flag != null) return ServerAvatar(flag: flag, protocol: '');
  return switch (kind) {
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

String _nodeName(String member, Map<String, ServerItem> byNode) {
  final server = byNode[member];
  return server == null
      ? _plainName(member)
      : ServerNameUtils.formatForDisplay(
          ServerNameUtils.cleanDisplayName(server.displayName),
        );
}

String _memberLabel(
  BuildContext context,
  ClashTemplate template,
  String member,
  Map<String, ServerItem> byNode,
  Map<String, MihomoGroupState>? live, {
  Map<String, String> choices = const {},
  bool withName = true,
}) {
  final l10n = context.l10n;
  final server = byNode[member];
  if (server != null) {
    final ping = server.pingMs;
    return [
      if (withName) _nodeName(member, byNode),
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
      // упавший закреплённый узел ядро обходит молча: тогда показываем, куда идёт на деле
      final pin = live == null
          ? (template.pinnable(member) ? choices[member] : null)
          : live[member]?.fixed;
      final detail = pin != null && (live == null || pin == now)
          ? l10n.serverGroupPinned(_nodeName(pin, byNode))
          : now == null
              ? (template.groupType(member) == 'select'
                  ? null
                  : l10n.serverGroupAuto)
              : l10n.serverGroupNow(_nodeName(now, byNode));
      return [if (withName) _plainName(member), ?detail].join(' · ');
    case ClashMemberKind.node || ClashMemberKind.other:
      return withName ? _plainName(member) : '';
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
    required this.onSelectServer,
  });

  final Subscription subscription;
  final ClashTemplate template;
  final List<ServerItem> servers;
  final double rowExtent;
  final double gap;
  final SubscriptionAccent? accent;
  final void Function(ServerItem) onSelectServer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(liveTemplateGroupsProvider(subscription.id)).value;
    final active = ref.watch(serversProvider.select((s) => s.activeServer));
    final activeHere = active?.subscriptionId == subscription.id;
    final activeNode = activeHere ? template.nodeFor(active!) : null;
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
      final now = _groupNow(
        template,
        group,
        subscription,
        live,
        activeNode: activeNode,
      );
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
            onTap: () => _showGroupPickSheet(
              context,
              subscription,
              group,
              onSelectServer,
            ),
            child: Opacity(
              opacity: activeHere ? 1 : 0.45,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ExpressiveSpacing.large,
                ),
                child: Row(
                  children: [
                    if (now != null)
                      _memberAvatar(context, template, now, byNode, live),
                    const SizedBox(width: ExpressiveSpacing.medium),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _plainName(group.name),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyLarge
                                ?.copyWith(color: AppTheme.text(context)),
                          ),
                          if (now != null) ...[
                            const SizedBox(height: ExpressiveSpacing.hairline),
                            Text(
                              _memberLabel(
                                context,
                                template,
                                now,
                                byNode,
                                live,
                                choices: subscription.groupChoices,
                              ),
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
  void Function(ServerItem) onSelectServer,
) {
  AppHaptics.selection();
  unawaited(showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _GroupPickSheet(
      subscriptionId: subscription.id,
      group: group,
      onSelectServer: onSelectServer,
    ),
  ));
}

Widget _groupSheetHeader(BuildContext context, String title, String hint) {
  final textTheme = Theme.of(context).textTheme;
  return Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
    child: Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: textTheme
              .emphasized(textTheme.titleLarge)
              ?.copyWith(color: AppTheme.text(context)),
        ),
        const SizedBox(height: 4),
        Text(
          hint,
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium
              ?.copyWith(color: AppTheme.textLight(context)),
        ),
      ],
    ),
  );
}

Widget _groupMemberTile(
  BuildContext context, {
  required Widget avatar,
  required String title,
  String subtitle = '',
  Widget? trailing,
  required bool selected,
  bool drill = false,
  required VoidCallback onTap,
}) {
  final scheme = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;
  final fg = selected ? scheme.onSecondaryContainer : scheme.onSurface;
  return ExpressiveGroupTile(
    onTap: onTap,
    color: selected ? scheme.secondaryContainer : null,
    child: Row(
      children: [
        avatar,
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
        ?trailing,
        if (selected) ...[
          const SizedBox(width: ExpressiveSpacing.medium),
          Icon(Icons.check_rounded, color: fg),
        ],
        if (drill) ...[
          const SizedBox(width: ExpressiveSpacing.small),
          Icon(
            Icons.chevron_right_rounded,
            size: ExpressiveIconSize.medium,
            color: selected ? fg : AppTheme.textLight(context),
          ),
        ],
      ],
    ),
  );
}

class _GroupPickSheet extends ConsumerWidget {
  const _GroupPickSheet({
    required this.subscriptionId,
    required this.group,
    required this.onSelectServer,
  });

  final String subscriptionId;
  final ClashTemplateGroup group;
  final void Function(ServerItem) onSelectServer;

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
    final active = ref.watch(serversProvider.select((s) => s.activeServer));
    final byNode = _serversByNode(template, servers);
    final isMain = group.name == template.mainGroup;
    final now = _groupNow(
      template,
      group,
      subscription,
      live,
      activeNode: active?.subscriptionId == subscriptionId
          ? template.nodeFor(active!)
          : null,
    );
    // выбор, поставленный первым в группу с include-all, ядро отдаёт в all дважды
    final members = [...{...(live?[group.name]?.all ?? group.members)}];
    final scheme = Theme.of(context).colorScheme;
    final direction = Directionality.of(context);
    final l10n = context.l10n;

    // ref закрытой шторки уже мёртв: notifier берём до pop
    Future<void> choose(String member) async {
      AppHaptics.selection();
      final subs = ref.read(subscriptionsProvider.notifier);
      Navigator.pop(context);
      await subs.chooseInGroup(subscriptionId, group.name, member);
    }

    // сервер в главной это то же, что нажать его в списке: туда и переподключаемся
    void chooseNode(String member) {
      if (!isMain) {
        unawaited(choose(member));
        return;
      }
      AppHaptics.selection();
      Navigator.pop(context);
      onSelectServer(byNode[member]!);
    }

    final parent = template.parentOf(group.name);
    final hint = isMain
        ? l10n.serverGroupMainHint
        : template.isRuleTarget(group.name) || parent == null
            ? l10n.serverGroupPickHint
            : l10n.serverGroupViaHint(_plainName(parent));

    final others = [for (final m in members) if (byNode[m] == null) m];
    final nodes = [for (final m in members) if (byNode[m] != null) m];

    Widget otherTile(String member) {
      final detail = _memberLabel(
        context,
        template,
        member,
        byNode,
        live,
        choices: subscription.groupChoices,
        withName: false,
      );
      final title = switch (template.kindOf(member)) {
        ClashMemberKind.direct || ClashMemberKind.block => detail,
        _ => _plainName(member),
      };
      final drill = _drillable(template, member, live);
      return _groupMemberTile(
        context,
        avatar: _memberAvatar(context, template, member, byNode, live),
        title: title,
        subtitle: title == detail ? '' : detail,
        selected: member == now,
        drill: drill,
        onTap: drill
            ? () => _showGroupServersSheet(
                  context,
                  subscriptionId: subscriptionId,
                  parent: group.name,
                  group: member,
                )
            : () => unawaited(choose(member)),
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
            _groupSheetHeader(context, _plainName(group.name), hint),
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
                                    onTap: () => chooseNode(nodes[i]),
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

void _showGroupServersSheet(
  BuildContext context, {
  required String subscriptionId,
  required String parent,
  required String group,
}) {
  AppHaptics.selection();
  unawaited(showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _GroupServersSheet(
      subscriptionId: subscriptionId,
      parent: parent,
      group: group,
    ),
  ));
}

// узлы url-test или fallback: самый быстрый сам или закреплённый руками
class _GroupServersSheet extends ConsumerWidget {
  const _GroupServersSheet({
    required this.subscriptionId,
    required this.parent,
    required this.group,
  });

  final String subscriptionId;
  final String parent;
  final String group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final template = ref.watch(subscriptionTemplateProvider(subscriptionId));
    final live = ref.watch(liveTemplateGroupsProvider(subscriptionId)).value;
    final state = live?[group];
    if (template == null || state == null) return const SizedBox.shrink();
    final delays =
        ref.watch(liveTemplateDelaysProvider(subscriptionId)).value ?? const {};
    final servers = ref.watch(serversProvider.select((s) => [
          for (final server in s.servers)
            if (server.subscriptionId == subscriptionId) server,
        ]));
    final byNode = _serversByNode(template, servers);
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final pinned = state.fixed;
    final now = state.now;
    final members = [...{...state.all}];
    final order = {for (var i = 0; i < members.length; i++) members[i]: i};
    // без замера в конце, порядок ядра внутри одинаковых
    members.sort((a, b) {
      final da = delays[a];
      final db = delays[b];
      if (da != null && db != null && da != db) return da.compareTo(db);
      if ((da == null) != (db == null)) return da == null ? 1 : -1;
      return order[a]!.compareTo(order[b]!);
    });

    // ref закрытой шторки уже мёртв: notifier берём до pop
    Future<void> pick(String? member) async {
      AppHaptics.selection();
      final subs = ref.read(subscriptionsProvider.notifier);
      Navigator.pop(context);
      await subs.chooseInGroup(subscriptionId, parent, group);
      if (member == null) {
        await subs.unpinGroup(subscriptionId, group);
      } else {
        await subs.chooseInGroup(subscriptionId, group, member);
      }
    }

    Widget delay(String member) {
      final ms = delays[member];
      return Text(
        ltrIsolate(ms == null ? '—' : '$ms ms'),
        style: textTheme.emphasized(textTheme.labelMedium)?.copyWith(
          color: ms == null
              ? AppTheme.textLight(context)
              : pingQualityColor(context, ms, PingType.url),
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
            _groupSheetHeader(
              context,
              _plainName(group),
              l10n.serverGroupServersHint,
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Column(
                  children: [
                    ExpressiveGroup(
                      children: [
                        _groupMemberTile(
                          context,
                          avatar: _GroupBadge(
                            icon: Icons.bolt_rounded,
                            background: scheme.tertiaryContainer,
                            foreground: scheme.onTertiaryContainer,
                          ),
                          title: l10n.serverGroupAutomatically,
                          subtitle: pinned == null && now != null
                              ? l10n.serverGroupNow(_nodeName(now, byNode))
                              : l10n.serverGroupAuto,
                          selected: pinned == null,
                          onTap: () => unawaited(pick(null)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ExpressiveGroup(
                      children: [
                        for (final member in members)
                          _groupMemberTile(
                            context,
                            avatar: _memberAvatar(
                              context,
                              template,
                              member,
                              byNode,
                              live,
                            ),
                            title: _nodeName(member, byNode),
                            trailing: delay(member),
                            selected: member == pinned,
                            onTap: () => unawaited(pick(member)),
                          ),
                      ],
                    ),
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
