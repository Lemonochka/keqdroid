import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/server_group.dart';
import '../../models/subscription_card_theme.dart';
import '../../providers/providers.dart';
import '../../services/subscription_accent_service.dart';
import '../../shared/ui/expressive.dart';
import '../../shared/ui/server_group_anchors.dart';

/// Быстрый переход по группам серверов в боковой панели десктопа.
///
/// Под тремя кнопками разделов остаётся полэкрана пустоты, а список серверов у
/// человека с четырьмя подписками листается долго. Здесь — те же группы, что и
/// в списке ([buildServerGroups]), в том же порядке: клик переключает на
/// вкладку серверов и прокручивает список к нужной группе.
///
/// Прижато к НИЗУ колонки, а не к верху свободного места: разделы вверху,
/// переход внизу — две группы кнопок, а не одна разъехавшаяся. Разделителя над
/// списком нет намеренно: в M3 секции навигации разделяет заголовок и воздух,
/// а линия поперёк панели читается как шов.
///
/// Цвет точки берётся у темы карточки подписки — то же связывание «карточка ↔
/// группа ↔ кнопка», что уже сделано в шапке группы: узнавание идёт по цвету, а
/// не по чтению названий.
class SidebarGroupNav extends ConsumerWidget {
  /// Узкий сайдбар (окно < 900): только значки с подсказками.
  final bool compact;

  /// Переключение на вкладку серверов. Прыжок без неё бессмысленен: список
  /// может быть не на экране.
  final VoidCallback onOpenServers;

  const SidebarGroupNav({
    super.key,
    required this.compact,
    required this.onOpenServers,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider.select((s) => s.servers));
    final subs = ref.watch(subscriptionsProvider).value ?? const [];

    final groups = buildServerGroups(servers: servers, subscriptions: subs);
    // Одна группа — это весь список: прыгать некуда, а строка занимала бы место
    // и обещала навигацию, которой нет.
    if (groups.length < 2) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Expanded(
      // Expanded + Align: забираем всю свободную высоту, но содержимое жмём
      // вниз. Список внутри остаётся ограниченным — на десятке подписок он
      // прокручивается, а не выдавливает разделы за край окна.
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!compact)
              Padding(
                // 28 слева — это 10 внешнего поля пилюли плюс 18 её
                // собственного: заголовок встаёт ровно над текстом пунктов.
                padding: const EdgeInsets.fromLTRB(28, 14, 16, 6),
                child: Text(
                  l10n.sidebarJumpTitle,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              )
            else
              const SizedBox(height: 12),
            Flexible(
              // Подсветка идёт за ПОЛОЖЕНИЕМ списка, а не за активным сервером:
              // активный сервер не двигается, и метка навсегда оставалась бы на
              // своей группе, сколько бы ты ни прыгала. ValueListenableBuilder,
              // чтобы прокрутка перестраивала только эти пункты, а не сайдбар.
              child: ValueListenableBuilder<String?>(
                valueListenable: ServerGroupAnchors.instance.currentGroup,
                builder: (context, currentKey, _) => ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    return _GroupJumpTile(
                      group: group,
                      compact: compact,
                      selected: group.key == currentKey,
                      title: _titleFor(group, l10n),
                      onTap: () {
                        onOpenServers();
                        // Список мог не строиться ни разу (первый заход с
                        // другой вкладки) — прыгаем после кадра, когда якоря
                        // уже на месте.
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          unawaited(
                            ServerGroupAnchors.instance.jumpTo(group.key),
                          );
                        });
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _titleFor(ServerGroupRef group, AppLocalizations l10n) =>
      switch (group.kind) {
        ServerGroupKind.chains => l10n.chainGroupTitle,
        ServerGroupKind.manual => l10n.serversManualGroup,
        ServerGroupKind.subscription => group.subscriptionName.isEmpty
            ? l10n.serversManualGroup
            : group.subscriptionName,
      };
}

/// Пункт перехода — та же пилюля, что у разделов выше, только рангом ниже:
/// меньше рост, роль текста `labelMedium`, вместо иконки раздела — точка цвета
/// подписки. Выбранный красится в `secondaryContainer`, как и раздел.
///
/// Цвет достаётся из синхронного кэша, а при промахе досчитывается в фоне —
/// ровно как в шапке группы ([SubscriptionAccentService]): сайдбар
/// перестраивается на каждую прокрутку списка, и `FutureBuilder` здесь гонял бы
/// квантование картинки постоянно.
class _GroupJumpTile extends StatefulWidget {
  final ServerGroupRef group;
  final String title;
  final bool compact;
  final bool selected;
  final VoidCallback onTap;

  const _GroupJumpTile({
    required this.group,
    required this.title,
    required this.compact,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_GroupJumpTile> createState() => _GroupJumpTileState();
}

class _GroupJumpTileState extends State<_GroupJumpTile> {
  Color? _seed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAccent();
  }

  @override
  void didUpdateWidget(_GroupJumpTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group.subscription?.cardThemeId !=
        widget.group.subscription?.cardThemeId) {
      _syncAccent();
    }
  }

  void _syncAccent() {
    final themeId = widget.group.subscription?.cardThemeId ?? '';
    if (themeId.isEmpty || resolveCardTheme(themeId).isPlain) {
      if (_seed != null) setState(() => _seed = null);
      return;
    }
    final scheme = Theme.of(context).colorScheme;
    final cached = SubscriptionAccentService.cached(
      themeId: themeId,
      scheme: scheme,
    );
    if (cached != null) {
      if (cached.seed != _seed) setState(() => _seed = cached.seed);
      return;
    }
    unawaited(() async {
      final accent = await SubscriptionAccentService.resolve(
        themeId: themeId,
        scheme: scheme,
      );
      if (!mounted) return;
      if ((widget.group.subscription?.cardThemeId ?? '') != themeId) return;
      if (accent?.seed != _seed) setState(() => _seed = accent?.seed);
    }());
  }

  IconData get _icon => switch (widget.group.kind) {
        ServerGroupKind.chains => Icons.link_rounded,
        ServerGroupKind.manual => Icons.edit_rounded,
        ServerGroupKind.subscription => Icons.cloud_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final shape = BorderRadius.circular(ExpressiveShape.full);
    final accent = _seed ?? scheme.primary;
    final fg =
        widget.selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    final count = widget.group.servers.length;

    final pill = Material(
      color: widget.selected ? scheme.secondaryContainer : Colors.transparent,
      borderRadius: shape,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: shape,
        child: widget.compact
            ? SizedBox(height: 40, child: Icon(_icon, size: 20, color: accent))
            : Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: (widget.selected
                                ? textTheme.emphasized(textTheme.labelMedium)
                                : textTheme.labelMedium)
                            ?.copyWith(color: fg),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$count',
                      style: textTheme.labelSmall?.copyWith(
                        color: fg.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );

    return Padding(
      // Внешнее поле как у разделов выше — пилюли обеих групп стоят на одной
      // вертикали.
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: widget.compact
          ? Tooltip(
              message: '${widget.title}  ($count)',
              waitDuration: const Duration(milliseconds: 400),
              child: pill,
            )
          : pill,
    );
  }
}
