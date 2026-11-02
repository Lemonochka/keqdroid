part of '../subscriptions_tab.dart';

Future<void> _showCardLookSheet(BuildContext context, Subscription sub) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _CardLookSheet(subscriptionId: sub.id, fallback: sub),
  );
}

// на кадр после удаления шторка ещё жива, а записи уже нет
Subscription _subscriptionOr(WidgetRef ref, String id, Subscription fallback) {
  final list = ref.watch(subscriptionsProvider).value;
  if (list == null) return fallback;
  for (final sub in list) {
    if (sub.id == id) return sub;
  }
  return fallback;
}

class _CardLookSheet extends ConsumerWidget {
  final String subscriptionId;
  final Subscription fallback;

  const _CardLookSheet({required this.subscriptionId, required this.fallback});

  void _apply(
    WidgetRef ref, {
    String? cardThemeId,
    bool? cardThemeInServers,
    bool? autoSelectVisible,
    Set<SubscriptionCardElement>? hidden,
    CardVeil? veil,
  }) {
    unawaited(
      ref
          .read(subscriptionsProvider.notifier)
          .editMeta(
            subscriptionId,
            cardThemeId: cardThemeId,
            cardThemeInServers: cardThemeInServers,
            autoSelectVisible: autoSelectVisible,
            hiddenCardElements: hidden,
            cardVeil: veil,
          ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final sub = _subscriptionOr(ref, subscriptionId, fallback);
    final cardTheme = resolveCardTheme(sub.cardThemeId);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      l10n.subscriptionCardLookTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme
                          .emphasized(theme.textTheme.titleLarge)
                          ?.copyWith(color: AppTheme.text(context)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _CardPreview(sub: sub),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
              _CardThemePicker(
                currentId: sub.cardThemeId,
                subscriptionId: sub.id,
                veil: sub.cardVeil,
                onSelect: (id) => _apply(ref, cardThemeId: id),
                inServers: sub.cardThemeInServers,
                onInServersChanged: (v) => _apply(ref, cardThemeInServers: v),
              ),
              if (cardTheme.hasImage) ...[
                const SizedBox(height: 16),
                _SheetSectionTitle(l10n.subscriptionCardVeilTitle),
                ExpressiveConnectedButtons<CardVeil>(
                  segments: [
                    for (final veil in CardVeil.values)
                      ExpressiveSegment(
                        value: veil,
                        label: _veilLabel(l10n, veil),
                      ),
                  ],
                  selected: sub.cardVeil,
                  onChanged: (veil) => _apply(ref, veil: veil),
                ),
              ],
              const SizedBox(height: 16),
              _SheetSectionTitle(l10n.subscriptionCardContentTitle),
              ExpressiveConnectedButtons<SubscriptionCardPreset>(
                segments: [
                  for (final preset in SubscriptionCardPreset.selectable)
                    ExpressiveSegment(
                      value: preset,
                      label: _presetLabel(l10n, preset),
                    ),
                ],
                selected: sub.cardPreset,
                onChanged: (preset) => _apply(ref, hidden: preset.hidden),
              ),
              const SizedBox(height: 4),
              for (final element in SubscriptionCardElement.values)
                SwitchListTile(
                  contentPadding: const EdgeInsets.only(left: 4, right: 0),
                  dense: true,
                  value: sub.showsCard(element),
                  title: Text(
                    _elementLabel(l10n, element),
                    style: theme.textTheme.bodyMedium,
                  ),
                  onChanged: (shown) {
                    final hidden = {...sub.hiddenCardElements};
                    if (shown) {
                      hidden.remove(element);
                    } else {
                      hidden.add(element);
                    }
                    _apply(ref, hidden: hidden);
                  },
                ),
              const SizedBox(height: 4),
              _SheetHint(l10n.subscriptionCardContentHint),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: const EdgeInsets.only(left: 4, right: 0),
                dense: true,
                value: sub.autoSelectVisible,
                title: Text(
                  l10n.subscriptionCardAutoSelect,
                  style: theme.textTheme.bodyMedium,
                ),
                subtitle: Text(
                  l10n.subscriptionCardAutoSelectHint,
                  style: theme.textTheme.bodySmall,
                ),
                onChanged: (v) => _apply(ref, autoSelectVisible: v),
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

// своя ProviderScope: в списке карточка может быть свёрнута и прятать то, что тут переключают
class _CardPreview extends StatelessWidget {
  final Subscription sub;

  const _CardPreview({required this.sub});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        collapsedSubscriptionCardsProvider.overrideWith(_ExpandedCards.new),
      ],
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: _SubItem(
            sub: sub,
            listIndex: 0,
            onDelete: () {},
            onRefresh: () async {},
          ),
        ),
      ),
    );
  }
}

class _ExpandedCards extends CollapsedSubscriptionCardsNotifier {
  @override
  Map<String, bool> build() => const <String, bool>{};
}

class _SheetSectionTitle extends StatelessWidget {
  final String text;

  const _SheetSectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppTheme.textLight(context),
            ),
      ),
    );
  }
}

class _SheetHint extends StatelessWidget {
  final String text;

  const _SheetHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.textLight(context),
            ),
      ),
    );
  }
}

String _veilLabel(AppLocalizations l10n, CardVeil veil) => switch (veil) {
      CardVeil.none => l10n.subscriptionCardVeilNone,
      CardVeil.light => l10n.subscriptionCardVeilLight,
      CardVeil.medium => l10n.subscriptionCardVeilMedium,
      CardVeil.strong => l10n.subscriptionCardVeilStrong,
    };

String _presetLabel(AppLocalizations l10n, SubscriptionCardPreset preset) =>
    switch (preset) {
      SubscriptionCardPreset.full => l10n.subscriptionCardPresetFull,
      SubscriptionCardPreset.compact => l10n.subscriptionCardPresetCompact,
      SubscriptionCardPreset.minimal => l10n.subscriptionCardPresetMinimal,
      SubscriptionCardPreset.custom => l10n.subscriptionCardPresetCustom,
    };

String _elementLabel(AppLocalizations l10n, SubscriptionCardElement element) =>
    switch (element) {
      SubscriptionCardElement.announce => l10n.subscriptionCardElementAnnounce,
      SubscriptionCardElement.usage => l10n.subscriptionCardElementUsage,
      SubscriptionCardElement.meta => l10n.subscriptionCardElementMeta,
      SubscriptionCardElement.actions => l10n.subscriptionCardElementActions,
    };
