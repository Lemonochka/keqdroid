part of '../servers_tab.dart';

/// Внутренний край плитки в сетке из двух колонок — край, обращённый к
/// середине карточки. Подсветка активного сервера мягко растворяется к нему
/// градиентом, чтобы граница между соседями в ряду была плавной, а не резкой
/// вертикальной линией.
enum _TileInnerEdge { left, right }

class _ServerTile extends ConsumerWidget {
  final ServerItem server;
  final bool isActive;
  final bool isFirst;
  final bool isLast;
  /// Скругление углов тайла. По умолчанию — нижние углы у последнего тайла
  /// (одноколоночный список); сетка в две колонки передаёт своё (у нижнего
  /// ряда скругляется только внешний угол каждой колонки).
  final BorderRadius? radius;
  /// Внутренний край плитки в режиме двух колонок; null — одноколоночный
  /// список, подсветка активного сервера сплошная на всю ширину.
  final _TileInnerEdge? innerEdge;
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
    this.innerEdge,
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
          bottom: isLast ? const Radius.circular(22) : Radius.zero,
        );

    // кэшируем цвета, чтобы не дёргать Theme.of() на каждый вложенный виджет
    final textColor = AppTheme.text(context);
    final accentColor = AppTheme.accent(context);
    final textLightColor = AppTheme.textLight(context);
    final textTheme = Theme.of(context).textTheme;

    // Фон плитки. В сетке из двух колонок подсветка активного сервера не
    // обрывается резкой линией по середине карточки, а мягко растворяется
    // градиентом к внутреннему краю плитки (несколько стоп приближают
    // ease-out, чтобы не было видимого излома). Полупрозрачные цвета ложатся
    // на фон DecoratedSliver карточки — так же, как сплошная подсветка.
    final Decoration tileDecoration;
    if (isActive && innerEdge != null) {
      Color glow(double f) => accentColor.withValues(alpha: 0.13 * f);
      final toRight = innerEdge == _TileInnerEdge.right;
      tileDecoration = BoxDecoration(
        gradient: LinearGradient(
          begin: toRight ? Alignment.centerLeft : Alignment.centerRight,
          end: toRight ? Alignment.centerRight : Alignment.centerLeft,
          colors: [glow(1), glow(1), glow(0.55), glow(0.18), glow(0)],
          stops: const [0.0, 0.45, 0.7, 0.88, 1.0],
        ),
      );
    } else {
      tileDecoration = BoxDecoration(
        color: isActive
            ? accentColor.withValues(alpha: 0.13)
            : AppTheme.card(context),
      );
    }
    final protocolColor = _protocolColor(server.protocol, context);

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
                        padding: const EdgeInsets.only(right: 4),
                        child: Transform.rotate(
                          // слегка наклонённая канцелярская кнопка — как
                          // «приколотый» пин в мессенджерах
                          angle: 45 * pi / 180,
                          child: Icon(
                            Icons.push_pin,
                            size: 13,
                            color: accentColor,
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
                                ?.copyWith(color: textColor),
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
                          color: protocolColor.withValues(alpha: 0.15),
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
                        pingMs != null
                            ? PingService.formatPingValue(pingMs, pingColorType)
                            : (lastTestedAt != null ? 'N/A' : '- ms'),
                        // Пинг — числовой показатель, у M3 это роль label, а
                        // не body: плотнее и заметнее при том же кегле.
                        style: textTheme.labelMedium?.copyWith(
                          color: pingMs != null
                              ? _pingColor(pingMs, context, pingColorType)
                              : textLightColor,
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

    final tileBody = SizedBox(height: _subCardRowHeight, child: rowBody);

    // Один семантический узел на тайл (имя + протокол + пинг + tap). Сервис
    // доступности/autofill включает семантику реально, а её геометрия
    // пересчитывается на каждом кадре свайпа — чем меньше узлов, тем дешевле.
    return RepaintBoundary(
      child: MergeSemantics(
        child: ClipRRect(
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: tileDecoration,
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
                child: tileBody,
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
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bg(context),
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
              ListTile(
                leading: Icon(
                  Icons.network_ping,
                  color: AppTheme.text(context),
                ),
                title: Text(AppLocalizations.of(context)!.serversPingServer),
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
              ListTile(
                leading: Transform.rotate(
                  angle: server.isPinned ? 0 : 45 * pi / 180,
                  child: Icon(
                    server.isPinned
                        ? Icons.push_pin_outlined
                        : Icons.push_pin,
                    color: server.isPinned
                        ? AppTheme.textLight(context)
                        : AppTheme.accent(context),
                  ),
                ),
                title: Text(
                  server.isPinned
                      ? AppLocalizations.of(context)!.serversUnpin
                      : AppLocalizations.of(context)!.serversPin,
                ),
                subtitle: server.isPinned
                    ? null
                    : Text(
                        AppLocalizations.of(context)!.serversPinDesc,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textLight(context),
                        ),
                      ),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(
                    ref.read(serversProvider.notifier).togglePin(server.id),
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.drive_file_rename_outline,
                  color: AppTheme.text(context),
                ),
                title: Text(AppLocalizations.of(context)!.serversRename),
                onTap: () {
                  Navigator.pop(context);
                  _showRenameDialog(context, ref);
                },
              ),
              ListTile(
                leading: Icon(Icons.tune, color: AppTheme.text(context)),
                title: Text(AppLocalizations.of(context)!.serversEditConfig),
                subtitle: Text(
                  AppLocalizations.of(context)!.serversEditConfigDesc,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textLight(context),
                  ),
                ),
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
              ListTile(
                leading: Icon(Icons.link, color: AppTheme.text(context)),
                title: Text(AppLocalizations.of(context)!.serversCopyConfig),
                subtitle: Text(
                  server.protocol.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textLight(context),
                  ),
                ),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: server.config));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(context)!.serversConfigCopied,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: AppTheme.red(context),
                ),
                title: Text(
                  AppLocalizations.of(context)!.serversDeleteServer,
                  style: TextStyle(color: AppTheme.red(context)),
                ),
                onTap: () {
                  Navigator.pop(context);
                  // Подтверждение как у удаления подписки: пункт стоит сразу
                  // под безобидными «копировать», промахнуться слишком легко.
                  _showDeleteConfirmation(context);
                },
              ),
              const SizedBox(height: 8),
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
                style: TextStyle(color: textColor, fontSize: 18),
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
              style: TextStyle(color: textColor, fontSize: 14),
              decoration: InputDecoration(
                hintText: l10n.serversRenameHint,
                hintStyle: TextStyle(
                  color: textLightColor.withValues(alpha: 0.5),
                ),
                filled: true,
                fillColor: AppTheme.bg(ctx),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
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
                style: TextStyle(fontSize: 11, color: textLightColor),
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
                borderRadius: BorderRadius.circular(12),
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
                style: TextStyle(color: textColor, fontSize: 18),
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
                borderRadius: BorderRadius.circular(12),
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

  Color _protocolColor(String p, BuildContext ctx) => switch (p) {
    'vless' => const Color(0xFF4A90D9),
    'awg' => const Color(0xFF2E7D32),
    'vmess' => const Color(0xFF7B68EE),
    'trojan' => const Color(0xFFE53935),
    'ss' => const Color(0xFF43A047),
    'hysteria' => const Color(0xFF00897B),
    'hysteria2' => const Color(0xFF00695C),
    'hy2' => const Color(0xFF004D40),
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

