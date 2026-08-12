part of '../servers_tab.dart';

class _ServerTile extends ConsumerWidget {
  final ServerItem server;
  final bool isActive;
  final bool isFirst;
  final bool isLast;
  /// Скругление углов тайла. По умолчанию — нижние углы у последнего тайла
  /// (одноколоночный список); сетка в две колонки передаёт своё (у нижнего
  /// ряда скругляется только внешний угол каждой колонки).
  final BorderRadius? radius;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final Future<void> Function() onPing;

  const _ServerTile({
    super.key,
    required this.server,
    required this.isActive,
    required this.isFirst,
    required this.isLast,
    this.radius,
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

    final radius = this.radius ??
        BorderRadius.vertical(
          bottom: isLast
              ? const Radius.circular(ExpressiveShape.extraLarge)
              : Radius.zero,
        );

    // кэшируем цвета, чтобы не дёргать Theme.of() на каждый вложенный виджет
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textColor = AppTheme.text(context);
    final accentColor = AppTheme.accent(context);
    final textLightColor = AppTheme.textLight(context);
    final textTheme = theme.textTheme;

    // Активный сервер «поднимается» из группы отдельным сегментом: свои
    // скругления, отступ от краёв и заливка secondaryContainer.
    //
    // Это подход M3E к выбранному пункту списка — форма плюс цветной
    // контейнер. Прежняя подсветка (accent на 13% альфы) отличала активный
    // сервер только чуть более светлым фоном, а на AMOLED-чёрном не читалась
    // почти никак. В две колонки приём не работает — там подсветка обязана
    // растворяться к середине карточки, поэтому режим остаётся градиентным.
    // Активный сервер «поднимается» из группы отдельным сегментом — и в одну
    // колонку, и в сетке.
    //
    // В сетке раньше стоял градиент, растворявший подсветку к середине
    // карточки: сплошная заливка на всю ширину плитки давала жёсткую
    // вертикальную линию на стыке колонок. Поднятый сегмент отступает от краёв
    // со всех сторон, поэтому стыка нет вовсе — приём решает исходную задачу
    // прямее, чем обходной градиент.
    final isLifted = isActive;
    final liftedRadius = ExpressiveShape.radius(ExpressiveShape.largeIncreased);
    const liftedInset = EdgeInsets.symmetric(horizontal: 6, vertical: 3);
    final onSegment = isLifted ? scheme.onSecondaryContainer : textColor;

    final activeDecoration = BoxDecoration(color: scheme.secondaryContainer);
    final restDecoration = BoxDecoration(color: AppTheme.card(context));
    // Цвет протокола — идентичность сервера, и на выбранной строке его терять
    // нельзя. Но полупрозрачная подложка поверх secondaryContainer сводит тон
    // бейджа с тоном контейнера, и надпись проваливается по контрасту. Поэтому
    // на поднятом сегменте бейдж встаёт на собственную непрозрачную подложку —
    // ту же, на которой живут бейджи остальных строк, так что выглядит он
    // ровно как у соседей.
    final protocolColor = _protocolColor(server.protocol, context);
    final badgeBg = isLifted
        ? AppTheme.card(context)
        : protocolColor.withValues(alpha: 0.15);

    final titleText = ServerNameUtils.formatForDisplay(
      ServerNameUtils.cleanDisplayName(server.displayName),
    );

    final rowBody = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _countryFlagCircle(
            countryCode: server.countryCode,
            protocolColor: protocolColor,
            protocol: server.protocol,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (server.isPinned)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 4),
                        child: Transform.rotate(
                          // слегка наклонённая канцелярская кнопка — как
                          // «приколотый» пин в мессенджерах
                          angle: 45 * pi / 180,
                          child: Icon(
                            Icons.push_pin,
                            size: 13,
                            color: isLifted ? onSegment : accentColor,
                          ),
                        ),
                      ),
                    Flexible(
                      child: Text(
                        titleText,
                        // Активный сервер отличается ВЕСОМ, а не размером: у
                        // M3E это и есть роль усиленного варианта.
                        style:
                            (isActive
                                    ? textTheme.emphasized(textTheme.titleSmall)
                                    : textTheme.titleSmall)
                                ?.copyWith(color: onSegment),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: ExpressiveShape.radius(
                            ExpressiveShape.extraSmall,
                          ),
                        ),
                        child: Text(
                          server.protocol.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme
                              .emphasized(textTheme.labelSmall)
                              ?.copyWith(color: protocolColor),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        ltrIsolate(
                          pingMs != null
                              ? PingService.formatPingValue(
                                  pingMs, pingColorType)
                              : (lastTestedAt != null ? 'N/A' : '- ms'),
                        ),
                        // Пинг — числовой показатель, у M3 это роль label, а
                        // не body: плотнее и заметнее при том же кегле.
                        style: textTheme.labelMedium?.copyWith(
                          color: pingMs != null
                              ? _pingColor(pingMs, context, pingColorType)
                              : (isLifted
                                  ? onSegment.withValues(alpha: 0.7)
                                  : textLightColor),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildTrailing(
            context,
            isConnected,
            isConnecting,
            isActive,
            isPinging,
            accentColor,
            textLightColor,
          ),
        ],
      ),
    );

    // Один семантический узел на тайл (имя + протокол + пинг + tap). Сервис
    // доступности/autofill включает семантику реально, а её геометрия
    // пересчитывается на каждом кадре свайпа — чем меньше узлов, тем дешевле.
    //
    // Высота строки задаётся снаружи отступа сегмента: у поднятого тайла
    // отступ съедает часть высоты, а шаг списка обязан остаться прежним —
    // иначе сетка в две колонки и `mainAxisExtent` разъедутся.
    return RepaintBoundary(
      child: MergeSemantics(
        child: SizedBox(
          height: _subCardRowHeight,
          // Отступ, форма и заливка едут от ОДНОГО значения.
          //
          // Раньше это были три независимые implicit-анимации (AnimatedPadding
          // + TweenAnimationBuilder + AnimatedContainer). Каждая при перебивке
          // стартует со своего текущего значения, и на быстром переборе
          // серверов они расходились: радиус успевал дойти до квадрата, пока
          // отступ и подсветка ещё ехали, — отсюда квадратные обводки. Один
          // контроллер такой рассинхрон исключает по построению.
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: isActive ? 1 : 0),
            duration: ExpressiveMotion.durationFast,
            curve: ExpressiveMotion.emphasized,
            builder: (context, t, child) {
              return Padding(
                padding: EdgeInsets.lerp(EdgeInsets.zero, liftedInset, t)!,
                child: ClipRRect(
                  borderRadius: BorderRadius.lerp(radius, liftedRadius, t)!,
                  clipBehavior: Clip.antiAlias,
                  child: DecoratedBox(
                    decoration: BoxDecoration.lerp(
                      restDecoration,
                      activeDecoration,
                      t,
                    )!,
                    child: child,
                  ),
                ),
              );
            },
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
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
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
      );
    } else if (isConnected) {
      bgColor = green.withValues(alpha: 0.25);
      center = Icon(Icons.pause, key: const ValueKey('pause'), size: 18, color: green);
    } else if (isActive) {
      bgColor = accentColor.withValues(alpha: 0.18);
      center =
          Icon(Icons.play_arrow, key: const ValueKey('play'), size: 18, color: accentColor);
    } else {
      bgColor = Colors.transparent;
      center = Icon(Icons.chevron_right, key: const ValueKey('idle'), color: textLightColor);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeInOutCubic,
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
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
                      icon: Icons.network_ping,
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
                              content: Text(_friendlyError(e)),
                              backgroundColor: AppTheme.red(context),
                            ),
                          );
                        }
                      },
                    ),
                    ExpressiveActionTile(
                      icon: server.isPinned
                          ? Icons.push_pin_outlined
                          : Icons.push_pin,
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
                      icon: Icons.drive_file_rename_outline,
                      title: l10n.serversRename,
                      onTap: () {
                        Navigator.pop(context);
                        _showRenameDialog(context, ref);
                      },
                    ),
                    ExpressiveActionTile(
                      icon: Icons.tune,
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
                      icon: Icons.link,
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
                      icon: Icons.delete_outline,
                      title: l10n.serversDeleteServer,
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
            Icon(Icons.drive_file_rename_outline, color: accentColor, size: 26),
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
                l10n.serversDeleteServer,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: textColor),
              ),
            ),
          ],
        ),
        content: Text(
          l10n.serversDeleteConfirm(name),
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
              foregroundColor: Colors.white,
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

  /// Цвет бейджа протокола.
  ///
  /// Оттенки свои (протокол — это идентичность, роль схемы её не выражает), но
  /// гармонизированные: на динамической теме сырой `0xFF4A90D9` выпадал из
  /// палитры, потому что не имел к сиду никакого отношения.
  Color _protocolColor(String p, BuildContext ctx) => switch (p) {
    'vless' => AppTheme.harmonize(ctx, const Color(0xFF4A90D9)),
    'awg' => AppTheme.harmonize(ctx, const Color(0xFF2E7D32)),
    'vmess' => AppTheme.harmonize(ctx, const Color(0xFF7B68EE)),
    'trojan' => AppTheme.harmonize(ctx, const Color(0xFFE53935)),
    'ss' => AppTheme.harmonize(ctx, const Color(0xFF43A047)),
    'hysteria' => AppTheme.harmonize(ctx, const Color(0xFF00897B)),
    'hysteria2' => AppTheme.harmonize(ctx, const Color(0xFF00695C)),
    'hy2' => AppTheme.harmonize(ctx, const Color(0xFF004D40)),
    // Готовый конфиг ядра: протокол внутри может быть любым, поэтому цвет
    // отдельный — «это конфиг целиком, со своим роутингом».
    'custom' => AppTheme.harmonize(ctx, const Color(0xFFF9A825)),
    _ => AppTheme.textLight(ctx),
  };

  Color _pingColor(int ms, BuildContext ctx, PingType type) {
    return switch (PingService.pingLatencyQuality(ms, type)) {
      PingLatencyQuality.good => AppTheme.green(ctx),
      PingLatencyQuality.fair => AppTheme.orange(ctx),
      PingLatencyQuality.poor => AppTheme.red(ctx),
    };
  }
}

String _friendlyError(Object e, [BuildContext? context]) {
  if (context == null) return explainError(e).short;
  final localized = explainErrorLocalized(e, AppLocalizations.of(context)!);
  return '${localized.title}: ${localized.message}';
}

String _friendlyErrorDetailed(Object e, [BuildContext? context]) {
  if (context == null) return explainError(e).full;
  final l10n = AppLocalizations.of(context)!;
  final localized = explainErrorLocalized(e, l10n);
  return '${localized.title}\n${localized.message}\n${l10n.errorActionLabel(localized.action)}';
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
                child: Text(
                  text,
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

