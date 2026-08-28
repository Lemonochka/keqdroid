part of '../subscriptions_tab.dart';

/// Редактор оформления карточки подписки.
///
/// Отдельная шторка, а не ещё один блок в редакторе подписки: там правят, ЧТО
/// за подписка (имя, адрес, чем клиент представляется панели), здесь — КАК она
/// выглядит. Смешанные в одной форме, эти две вещи давали шторку, где половина
/// полей про сеть, а половина про картинки.
///
/// Правки применяются сразу и без кнопки «Сохранить»: оформление оценивают
/// глазами на самой карточке, а не подтверждают. Отсюда же и `ConsumerWidget` с
/// `watch` — шторка показывает то же состояние, что уже уехало в хранилище, а
/// не свою локальную копию, которая разошлась бы с карточкой под ней.
Future<void> _showCardLookSheet(BuildContext context, Subscription sub) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _CardLookSheet(subscriptionId: sub.id, fallback: sub),
  );
}

/// Подписка по id из провайдера. Fallback нужен на один кадр после удаления:
/// шторка ещё жива, а записи уже нет.
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              // Образец только у картинок: у палитры затемнения нет, а
              // оценивать по образцу больше нечего — цвета видно в слайдере.
              if (cardTheme.hasImage) ...[
                _CardVeilPreview(theme: cardTheme, sub: sub),
                const SizedBox(height: 16),
              ],
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
                Wrap(
                  spacing: 8,
                  children: [
                    for (final veil in CardVeil.values)
                      ChoiceChip(
                        label: Text(_veilLabel(l10n, veil)),
                        selected: sub.cardVeil == veil,
                        onSelected: (_) => _apply(ref, veil: veil),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                _SheetHint(l10n.subscriptionCardVeilHint),
              ],
              const SizedBox(height: 16),
              _SheetSectionTitle(l10n.subscriptionCardContentTitle),
              Wrap(
                spacing: 8,
                children: [
                  for (final preset in SubscriptionCardPreset.selectable)
                    ChoiceChip(
                      label: Text(_presetLabel(l10n, preset)),
                      selected: sub.cardPreset == preset,
                      // Пресет — это набор целиком, поэтому и повторный тап по
                      // выбранному его просто переставляет: снимать тут нечего.
                      onSelected: (_) => _apply(ref, hidden: preset.hidden),
                    ),
                ],
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Образец подложки: та же картинка с тем же затемнением и текст поверх неё.
///
/// Затемнение — единственная настройка карточки, которую нельзя оценить по
/// названию: «лёгкое» на тёмной фотографии и на светлой читается по-разному, а
/// проверять его, закрывая шторку и открывая заново, — это и есть «настройка
/// вслепую». Поэтому образец рисует НАСТОЯЩУЮ подложку (`background`), а не
/// свою копию: нарисованная отдельно, она разошлась бы с карточкой.
class _CardVeilPreview extends StatelessWidget {
  final SubscriptionCardTheme theme;
  final Subscription sub;

  const _CardVeilPreview({required this.theme, required this.sub});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ClipRRect(
      borderRadius: ExpressiveShape.radius(ExpressiveShape.large),
      child: SizedBox(
        height: 96,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            theme.background(context, veil: sub.cardVeil),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    sub.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium?.copyWith(
                      color: AppTheme.text(context),
                    ),
                  ),
                  // Тот же кегль, что у якоря карточки: судить о читаемости
                  // надо по тому тексту, который на карточке и стоит.
                  Text(
                    sub.usedDisplay ?? sub.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme
                        .emphasized(textTheme.headlineSmall)
                        ?.copyWith(color: AppTheme.text(context)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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

/// Строка «Оформление карточки» в редакторе подписки.
///
/// Читает подписку из провайдера, а не получает её сверху: редактор оформления
/// применяет правки сразу, и строка обязана показывать их же — иначе она
/// описывала бы карточку, какой та была при открытии шторки.
class _CardLookTile extends ConsumerWidget {
  final Subscription fallback;
  final VoidCallback onTap;

  const _CardLookTile({required this.fallback, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final sub = _subscriptionOr(ref, fallback.id, fallback);
    final cardTheme = resolveCardTheme(sub.cardThemeId);
    final preset = sub.cardPreset;

    final parts = <String>[
      if (!cardTheme.isPlain) l10n.subscriptionCardLookThemeOn,
      if (preset != SubscriptionCardPreset.full) _presetLabel(l10n, preset),
      if (cardTheme.hasImage && sub.cardVeil != CardVeil.medium)
        _veilLabel(l10n, sub.cardVeil),
    ];
    final changed = parts.isNotEmpty;

    return ExpressiveGroupTile(
      onTap: onTap,
      radius: ExpressiveShape.radius(ExpressiveShape.large),
      child: Row(
        children: [
          ExpressiveIconBadge(
            icon: Icons.style_rounded,
            accent: changed
                ? ExpressiveAccent.tertiary
                : ExpressiveAccent.secondary,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.subscriptionCardLookTitle,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: scheme.onSurface),
                ),
                Text(
                  changed
                      ? parts.join(' · ')
                      : l10n.subscriptionCardLookDefault,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: changed ? scheme.primary : scheme.onSurfaceVariant,
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
