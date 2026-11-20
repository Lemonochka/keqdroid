part of '../subscriptions_tab.dart';

// подписка, не обновлявшаяся с этой версии, счёта не хранит: берём то, что лежит в списке.
// watch, а не read: шторка открывается и до того, как список загрузился
Map<String, int> _protocolCountsOf(Subscription sub, WidgetRef ref) {
  if (sub.protocolCounts.isNotEmpty) return sub.protocolCounts;
  final counts = <String, int>{};
  for (final server in ref.watch(serversProvider).servers) {
    if (server.subscriptionId != sub.id) continue;
    final key = protocolFilterKey(server.protocol);
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

List<MapEntry<String, int>> _protocolsByCount(Map<String, int> counts) =>
    counts.entries.toList()..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });

class _ProtocolsTile extends StatelessWidget {
  final Map<String, int> counts;
  final Set<String> excluded;
  final VoidCallback onTap;

  const _ProtocolsTile({
    required this.counts,
    required this.excluded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final order = _protocolsByCount(counts);
    final on = [
      for (final e in order)
        if (!excluded.contains(e.key)) e,
    ];
    final total = order.fold(0, (sum, e) => sum + e.value);
    final kept = on.fold(0, (sum, e) => sum + e.value);
    // выключено всё пришедшее: обновление тогда берёт всё, и строка говорит то же
    final active = kept > 0 && kept < total;
    // без изоляции в фарси число из второй половины прилипало к латинским именам
    final value = active
        ? '${ltrIsolate(on.map((e) => e.key.toUpperCase()).join(', '))} · '
              '${l10n.subscriptionProtocolsKept(kept, total)}'
        : l10n.subscriptionProtocolsAll(total);
    final accent = active
        ? ExpressiveAccent.tertiary
        : ExpressiveAccent.secondary;

    return ExpressiveGroupTile(
      onTap: onTap,
      radius: ExpressiveShape.radius(ExpressiveShape.large),
      child: Row(
        children: [
          ExpressiveIconBadge(icon: Icons.filter_alt_rounded, accent: accent),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.subscriptionProtocolsTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
                Text(
                  value,
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

Future<Set<String>?> _showProtocolsSheet(
  BuildContext context, {
  required Map<String, int> counts,
  required Set<String> excluded,
}) {
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: _sheetConstraints(context),
    builder: (ctx) => _ProtocolsSheet(counts: counts, initial: excluded),
  );
}

class _ProtocolsSheet extends StatefulWidget {
  final Map<String, int> counts;
  final Set<String> initial;

  const _ProtocolsSheet({required this.counts, required this.initial});

  @override
  State<_ProtocolsSheet> createState() => _ProtocolsSheetState();
}

class _ProtocolsSheetState extends State<_ProtocolsSheet> {
  late final Set<String> _off = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final order = _protocolsByCount(widget.counts);
    final onCount = order.where((e) => !_off.contains(e.key)).length;

    Widget row(MapEntry<String, int> entry) {
      final on = !_off.contains(entry.key);
      final canToggle = !on || onCount > 1;
      void toggle() => setState(() {
        if (!_off.remove(entry.key)) _off.add(entry.key);
      });
      return ExpressiveGroupTile(
        onTap: canToggle ? toggle : null,
        child: Row(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 104),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: 1,
                child: _ProtocolBadge(protocol: entry.key, on: on),
              ),
            ),
            const SizedBox(width: ExpressiveSpacing.small),
            Expanded(
              child: Text(
                l10n.subscriptionProtocolsServerCount(entry.value),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: on ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
            ),
            Switch(value: on, onChanged: canToggle ? (_) => toggle() : null),
          ],
        ),
      );
    }

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
            _SheetHeader(l10n.subscriptionProtocolsTitle),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Text(
                l10n.subscriptionProtocolsHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
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
                    ExpressiveGroup(children: [for (final e in order) row(e)]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, <String>{}),
                    child: Text(
                      l10n.subscriptionProtocolsTakeAll,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, {..._off}),
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
}

// та же метка, что у сервера в списке, чтобы протокол узнавался по цвету
class _ProtocolBadge extends StatelessWidget {
  final String protocol;
  final bool on;

  const _ProtocolBadge({required this.protocol, required this.on});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final color = serverProtocolColor(context, protocol);
    final fg = on ? color : scheme.onSurfaceVariant.withValues(alpha: 0.55);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ExpressiveSpacing.small,
        vertical: ExpressiveSpacing.extraSmall,
      ),
      decoration: BoxDecoration(
        color: on ? color.withValues(alpha: 0.15) : null,
        border: on ? null : Border.all(color: scheme.outlineVariant),
        borderRadius: ExpressiveShape.radius(ExpressiveShape.extraSmall),
      ),
      child: Text(
        protocol.toUpperCase(),
        style: textTheme
            .emphasized(textTheme.labelLarge)
            ?.copyWith(
              color: fg,
              decoration: on ? null : TextDecoration.lineThrough,
              decorationColor: fg,
            ),
      ),
    );
  }
}
