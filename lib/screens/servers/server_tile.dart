part of '../servers_tab.dart';

/// Trailing-слот строки сервера: контейнер XSmall-иконки M3E.
const _trailingSlotSize = 32.0;

class _ServerTile extends ConsumerWidget {
  final ServerItem server;
  final bool isActive;

  /// Форма сегмента. Считает её список ([ExpressiveListSegment.segmentRadius]):
  /// только он знает, где у тайла сосед, а где край группы.
  final BorderRadius radius;

  /// Поля сегмента внутри шага списка — из них и набирается зазор между
  /// строками (см. [ExpressiveListSegment.segmentMargin]).
  final EdgeInsets margin;

  /// Цвета, выведенные из картинки подписки. null — у подписки нет своей
  /// подложки (или сервер добавлен руками), тогда тайл живёт на ролях темы,
  /// как и раньше.
  final SubscriptionAccent? accent;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final Future<void> Function() onPing;

  const _ServerTile({
    super.key,
    required this.server,
    required this.isActive,
    required this.radius,
    required this.margin,
    this.accent,
    required this.onTap,
    required this.onDelete,
    required this.onPing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPinging = ref.watch(
      pingingServerIdsProvider.select((ids) => ids.contains(server.id)),
    );
    final (pingMs, lastTestedAt, lastPingType) = ref.watch(
      serversProvider.select((s) {
        final item = s.byId[server.id];
        if (item != null) {
          return (item.pingMs, item.lastTestedAt, item.lastPingType);
        }
        return (server.pingMs, server.lastTestedAt, server.lastPingType);
      }),
    );
    final settings = ref.watch(
      settingsNotifierProvider.select(
        (async) => async.value ?? const AppSettings(),
      ),
    );
    final pingColorType = PingService.pingColorTypeForServer(
      server.copyWith(
        pingMs: pingMs,
        lastTestedAt: lastTestedAt,
        lastPingType: lastPingType,
      ),
      settings,
    );

    final vpnStatus = ref.watch(
      vpnStateProvider.select((a) {
        if (!isActive) return VpnStatus.disconnected;
        return a.value?.status ?? VpnStatus.disconnected;
      }),
    );

    // Во время смены сервера движок на миг проходит через `disconnected`;
    // для активного (целевого) тайла держим «подключается», чтобы кружок не
    // мелькал spinner → play → spinner, а плавно дошёл до паузы.
    final switching = ref.watch(vpnServerSwitchInProgressProvider);
    final isConnected =
        isActive && vpnStatus == VpnStatus.connected && !switching;
    final isConnecting =
        isActive &&
        (switching ||
            vpnStatus == VpnStatus.connecting ||
            vpnStatus == VpnStatus.disconnecting);

    // кэшируем цвета, чтобы не дёргать Theme.of() на каждый вложенный виджет
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Акцент подписки подменяет РОЛЬ, а не отдельный цвет: и заливка выбранного
    // сегмента, и текст на нём берутся из одной тональной схемы, поэтому
    // контраст остаётся выверенным при любой картинке. Подписи «серверов
    // вообще» (пинг, протокол) остаются на ролях темы — иначе список стал бы
    // пёстрым, а не связанным.
    final accent = this.accent;
    final accentColor = accent?.seed ?? AppTheme.accent(context);
    final textLightColor = AppTheme.textLight(context);

    // Активный сервер — ВЫБРАННЫЙ СЕГМЕНТ списка, по спеке expressive-списка:
    // форма морфится к 16dp по кругу, заливка уходит в цветной контейнер. Ни
    // подъёма, ни отступа, ни подсветки поверх — выделение несут контейнер и
    // его форма, и больше ничего.
    //
    // Прежде тайл «поднимался» из группы (свой inset 6×3 и радиус 20). Приём
    // понадобился ровно потому, что строки стояли встык и отличить одну из них
    // было нечем; в сегментированном списке зазор уже есть у всех, и выбранной
    // строке достаточно перестать быть квадратной.
    final tileColor =
        accent?.surface(AppTheme.card(context)) ?? AppTheme.card(context);
    final selectedColor = accent?.container ?? scheme.secondaryContainer;

    // Сам ряд — общий с выбором узлов цепочки (shared/ui/server_row.dart).
    // Плитка добавляет к нему только состояние выбора, форму и жесты.
    //
    // Цвет протокола — идентичность сервера, и на выбранной строке его терять
    // нельзя. Но полупрозрачная подложка поверх secondaryContainer сводит тон
    // бейджа с тоном контейнера, и надпись проваливается по контрасту. Поэтому
    // на выбранном сегменте бейдж встаёт на собственную непрозрачную подложку —
    // ту же, на которой живут бейджи остальных строк.
    final rowBody = ServerRow(
      server: server,
      pingMs: pingMs,
      lastTestedAt: lastTestedAt,
      pingColorType: pingColorType,
      foreground: isActive
          ? (accent?.onContainer ?? scheme.onSecondaryContainer)
          : null,
      opaqueBadge: isActive,
      // Активный сервер отличается ВЕСОМ, а не размером: у M3E это и есть
      // роль усиленного варианта.
      emphasizeTitle: isActive,
      trailing: _buildTrailing(
        context,
        isConnected,
        isConnecting,
        isActive,
        isPinging,
        accentColor,
        textLightColor,
      ),
    );

    // Один семантический узел на тайл (имя + протокол + пинг + tap). Сервис
    // доступности/autofill включает семантику реально, а её геометрия
    // пересчитывается на каждом кадре свайпа — чем меньше узлов, тем дешевле.
    //
    // Внешний SizedBox — ШАГ списка, а не высота сегмента: зазор набирается
    // полями внутри него. От шага считаются `mainAxisExtent` сетки и смещение
    // якоря активного сервера, и он обязан остаться прежним.
    return RepaintBoundary(
      child: MergeSemantics(
        child: SizedBox(
          height: _subCardRowHeight,
          child: Padding(
            padding: margin,
            child: ExpressiveListSegment(
              radius: radius,
              selected: isActive,
              color: tileColor,
              selectedColor: selectedColor,
              onTap: () {
                AppHaptics.selection();
                onTap();
              },
              onLongPress: () => _showOptions(context, ref),
              // на десктопе правый клик открывает то же меню
              onSecondaryTap: () => _showOptions(context, ref),
              splashColor: accentColor.withValues(alpha: 0.2),
              highlightColor: accentColor.withValues(alpha: 0.08),
              child: rowBody,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrailing(
    BuildContext context,
    bool isConnected,
    bool isConnecting,
    bool isActive,
    bool isPinging,
    Color accentColor,
    Color textLightColor,
  ) {
    // «Морфинг-кружок»: сам кружок стоит на месте и плавно перетекает цветом
    // (прозрачный → accent → зелёный) через AnimatedContainer, а внутри мягко
    // (fade + scale) сменяется только центр — иконка/спиннер — через
    // AnimatedSwitcher. Это заметно плавнее, чем кросс-фейд двух разных кружков.
    // Особенно на смене активного сервера при подключённом VPN: у старого тайла
    // зелёная пауза утекает в шеврон, у нового — шеврон → спиннер → пауза.
    final green = AppTheme.green(context);

    // Пинг/подключение имеют приоритет над паузой: иначе у активного сервера
    // крутилка была бы перекрыта значком паузы.
    final Color bgColor;
    final Widget center;
    if (isPinging || isConnecting) {
      bgColor = accentColor.withValues(alpha: 0.18);
      center = SizedBox(
        // один ключ для обоих спиннеров — крутилка не мигает при ping↔connect.
        key: const ValueKey('spinner'),
        width: ExpressiveIconSize.medium,
        height: ExpressiveIconSize.medium,
        child: ShapeLoadingIndicator(
          size: ExpressiveIconSize.medium,
          color: accentColor,
        ),
      );
    } else if (isConnected) {
      bgColor = green.withValues(alpha: 0.25);
      center = Icon(
        Icons.pause_rounded,
        key: const ValueKey('pause'),
        size: ExpressiveIconSize.medium,
        color: green,
      );
    } else if (isActive) {
      bgColor = accentColor.withValues(alpha: 0.18);
      // Тот же глиф, что в главной кнопке подключения: outlined, пока не
      // подключено, и filled `pause_rounded`, когда подключено. Кружок в строке
      // сервера — тот же переключатель, только маленький, и разные треугольники
      // в двух местах читались как недосмотр.
      center = Icon(
        Icons.play_arrow_outlined,
        key: const ValueKey('play'),
        size: ExpressiveIconSize.medium,
        color: accentColor,
      );
    } else {
      bgColor = Colors.transparent;
      center = Icon(
        Icons.chevron_right_rounded,
        key: const ValueKey('idle'),
        size: ExpressiveIconSize.medium,
        color: textLightColor,
      );
    }

    // Кружок ровно с XSmall-иконкой M3E (32dp контейнер, 20dp глиф): у списка
    // это trailing-слот, а не отдельная кнопка — вся строка и есть одна цель
    // нажатия, поэтому 48dp здесь набирать нечем и незачем.
    return AnimatedContainer(
      duration: ExpressiveMotion.durationDefault,
      curve: ExpressiveMotion.emphasized,
      width: _trailingSlotSize,
      height: _trailingSlotSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
      child: AnimatedSwitcher(
        duration: ExpressiveMotion.durationFast,
        switchInCurve: ExpressiveMotion.emphasizedDecelerate,
        switchOutCurve: ExpressiveMotion.emphasizedAccelerate,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.7, end: 1.0).animate(animation),
            child: child,
          ),
        ),
        child: center,
      ),
    );
  }

  void _showOptions(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      // Цвет НЕ задаём: из темы шторка берёт surfaceContainerLow. Здесь стоял
      // AppTheme.bg — ровно фон страницы, поэтому шторка не отделялась от неё
      // ничем, кроме затемнения, и читалась плоской.
      // Настоящая ручка вместо нарисованной. Прежняя была просто Container
      // внутри прокручиваемого содержимого: выглядела как ручка, но тянуть за
      // неё было нельзя — жест уходил в скролл, и шторка не закрывалась.
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ServerNameUtils.formatForDisplay(
                  ServerNameUtils.cleanDisplayName(server.displayName),
                ),
                style: Theme.of(context).textTheme
                    .emphasized(Theme.of(context).textTheme.titleMedium)
                    ?.copyWith(color: AppTheme.text(context)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              // У цепочки на месте адреса — её маршрут: адрес входного узла
              // тут не главное, а копировать его незачем.
              if (server.protocol == 'chain')
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ChainRouteStrip(
                        hops: server.chainHopItems,
                        arrowColor: AppTheme.textLight(context),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.chainNodesCount(server.chainConfig!.hops.length),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.textLight(context),
                            ),
                      ),
                    ],
                  ),
                )
              else
                // Адрес и есть кнопка копирования: отдельный пункт списка занимал
                // целую строку меню ради того, что уже написано здесь.
                _CopyableAddress(
                  text: '${server.address}:${server.port}',
                  onCopied: () => Navigator.pop(context),
                ),
              const SizedBox(height: 16),
              // Пункты собраны в группы: «проверить/закрепить», «править» и
              // отдельно удаление. Прежде это был плоский список ListTile —
              // без границ и без подсказки, куда именно жать.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ExpressiveGroup(
                  children: [
                    ExpressiveActionTile(
                      icon: Icons.network_ping_rounded,
                      title: l10n.serversPingServer,
                      accent: ExpressiveAccent.primary,
                      onTap: () async {
                        Navigator.pop(context);
                        try {
                          await onPing();
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(_shortError(e)),
                              backgroundColor: AppTheme.red(context),
                            ),
                          );
                        }
                      },
                    ),
                    ExpressiveActionTile(
                      icon: server.isPinned
                          ? Icons.push_pin_rounded
                          : Icons.push_pin_rounded,
                      title: server.isPinned
                          ? l10n.serversUnpin
                          : l10n.serversPin,
                      subtitle: server.isPinned ? null : l10n.serversPinDesc,
                      accent: ExpressiveAccent.tertiary,
                      onTap: () {
                        Navigator.pop(context);
                        unawaited(
                          ref
                              .read(serversProvider.notifier)
                              .togglePin(server.id),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ExpressiveGroup(
                  children: [
                    ExpressiveActionTile(
                      icon: Icons.drive_file_rename_outline_rounded,
                      title: l10n.serversRename,
                      onTap: () {
                        Navigator.pop(context);
                        _showRenameDialog(context, ref);
                      },
                    ),
                    if (server.protocol == 'chain')
                      ExpressiveActionTile(
                        icon: Icons.route_rounded,
                        title: l10n.chainEdit,
                        subtitle: l10n.chainRouteLabel,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              fullscreenDialog: true,
                              builder: (_) => ChainEditorScreen(
                                serverId: server.id,
                              ),
                            ),
                          );
                        },
                      )
                    else
                      ExpressiveActionTile(
                        icon: Icons.tune_rounded,
                        title: l10n.serversEditConfig,
                        subtitle: l10n.serversEditConfigDesc,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              fullscreenDialog: true,
                              builder: (_) => ServerConfigEditorScreen(
                                serverId: server.id,
                              ),
                            ),
                          );
                        },
                      ),
                    ExpressiveActionTile(
                      icon: Icons.link_rounded,
                      title: l10n.serversCopyConfig,
                      subtitle: server.protocol.toUpperCase(),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: server.config));
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.serversConfigCopied)),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Удаление — отдельной группой и в роли error: рядом с
              // безобидным «скопировать» по нему промахивались.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ExpressiveGroup(
                  children: [
                    ExpressiveActionTile(
                      icon: Icons.delete_outline_rounded,
                      title: server.protocol == 'chain'
                          ? l10n.chainDelete
                          : l10n.serversDeleteServer,
                      danger: true,
                      onTap: () {
                        Navigator.pop(context);
                        _showDeleteConfirmation(context);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  /// Диалог переименования: пишет customName поверх имени из конфига
  /// (переживает обновление подписки); пустое или исходное имя — сброс.
  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final cardColor = AppTheme.card(context);
    final textColor = AppTheme.text(context);
    final textLightColor = AppTheme.textLight(context);
    final accentColor = AppTheme.accent(context);
    final hasCustomName = server.customName?.trim().isNotEmpty ?? false;
    final ctrl = TextEditingController(text: server.displayName);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardColor,
        title: Row(
          children: [
            Icon(Icons.drive_file_rename_outline_rounded, color: accentColor, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.serversRenameTitle,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: textColor),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 1,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: textColor),
              decoration: InputDecoration(
                hintText: l10n.serversRenameHint,
                hintStyle: TextStyle(
                  color: textLightColor.withValues(alpha: 0.5),
                ),
                filled: true,
                fillColor: AppTheme.bg(ctx),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ExpressiveShape.medium),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ExpressiveShape.medium),
                  borderSide: BorderSide(color: accentColor, width: 2),
                ),
              ),
              onSubmitted: (_) => _applyRename(ctx, ref, ctrl.text),
            ),
            if (hasCustomName) ...[
              const SizedBox(height: 8),
              Text(
                l10n.serversRenameOriginal(
                  ServerNameUtils.formatForDisplay(
                    ServerNameUtils.cleanDisplayName(server.derivedName),
                  ),
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: textLightColor),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        actions: [
          if (hasCustomName)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                unawaited(
                  ref.read(serversProvider.notifier).rename(server.id, null),
                );
              },
              child: Text(
                l10n.serversRenameReset,
                style: TextStyle(color: textLightColor),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              l10n.subscriptionsCancel,
              style: TextStyle(color: textLightColor),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentContainer(ctx),
              foregroundColor: AppTheme.onAccentContainer(ctx),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ExpressiveShape.medium),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: () => _applyRename(ctx, ref, ctrl.text),
            child: Text(
              l10n.subscriptionsSave,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _applyRename(BuildContext dialogCtx, WidgetRef ref, String raw) {
    Navigator.pop(dialogCtx);
    final name = raw.trim();
    // имя, совпавшее с исходным из конфига, — это сброс, а не override
    unawaited(
      ref
          .read(serversProvider.notifier)
          .rename(server.id, name == server.derivedName ? null : name),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cardColor = AppTheme.card(context);
    final textColor = AppTheme.text(context);
    final textLightColor = AppTheme.textLight(context);
    final redColor = AppTheme.red(context);
    final name = ServerNameUtils.formatForDisplay(
      ServerNameUtils.cleanDisplayName(server.displayName),
    );
    final isChain = server.protocol == 'chain';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardColor,
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: redColor, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isChain ? l10n.chainDelete : l10n.serversDeleteServer,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: textColor),
              ),
            ),
          ],
        ),
        content: Text(
          // У цепочки важно сказать, что серверы из неё останутся: иначе
          // удаление маршрута выглядит как удаление всех его узлов.
          isChain
              ? l10n.chainDeleteConfirm(name)
              : l10n.serversDeleteConfirm(name),
          style: TextStyle(color: textLightColor, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              l10n.subscriptionsCancel,
              style: TextStyle(color: textLightColor),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: redColor,
              foregroundColor: AppTheme.onRed(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ExpressiveShape.medium),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              onDelete();
            },
            child: Text(
              l10n.subscriptionsDelete,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

}

String _shortError(Object e, [BuildContext? context]) {
  if (context == null) return explainError(e).short;
  final localized = explainErrorLocalized(e, AppLocalizations.of(context)!);
  return '${localized.title}: ${localized.message}';
}

/// Адрес сервера в шапке меню, он же кнопка копирования.
///
/// Раньше рядом жил отдельный пункт списка «скопировать адрес» — целая строка
/// меню ради значения, которое тут же и написано. Теперь копирует сам адрес:
/// иконка показывает, что он нажимается, state layer подтверждает нажатие.
class _CopyableAddress extends StatelessWidget {
  final String text;

  /// Меню закрывается до снек-бара: он живёт на Scaffold под модальной шторкой
  /// и иначе оказался бы за ней.
  final VoidCallback onCopied;

  const _CopyableAddress({required this.text, required this.onCopied});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textLight = AppTheme.textLight(context);
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: textLight,
        );

    return Tooltip(
      message: l10n.serversCopyAddress,
      child: InkWell(
        onTap: () {
          Clipboard.setData(ClipboardData(text: text));
          final messenger = ScaffoldMessenger.of(context);
          onCopied();
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.serversCopiedToClipboard)),
          );
        },
        customBorder: ExpressiveShape.border(ExpressiveShape.full),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                // Направлением, а не изолятом: эту же строку кладут в буфер
                // обмена, и невидимые U+2066/U+2069 уехали бы туда вместе с
                // адресом. Без фикса `nl.example.com:443` в персидской локали
                // показывается как `443:nl.example.com` — двоеточие между
                // латиницей и цифрами перестаёт быть частью числа.
                child: LtrBlock(
                  child: Text(
                    text,
                    style: style,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.copy_rounded, size: 14, color: textLight),
            ],
          ),
        ),
      ),
    );
  }
}

String _vpnErrorStatusLabel(String? errorMessage, BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  final details = explainErrorLocalized(errorMessage ?? 'unknown', l10n);
  return switch (details.kind) {
    UiErrorKind.permission => l10n.errorConnectionPermission,
    UiErrorKind.network => l10n.errorConnectionNetwork,
    UiErrorKind.config => l10n.errorConnectionConfig,
    UiErrorKind.auth => l10n.errorConnectionAuth,
    UiErrorKind.providerConfig => l10n.errorProviderConfigTitle,
    UiErrorKind.unknown => l10n.errorConnectionGeneric,
  };
}

