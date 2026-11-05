part of '../servers_tab.dart';

const _trailingSlotSize = 32.0;

// кружок выдавливается каплей из угла флага, а уходит в край флага на месте: обратный путь
// показывал точку, которая ползла по флагу к середине
class _AutoSkipBadge extends StatefulWidget {
  const _AutoSkipBadge({required this.shown, required this.ring});

  final bool shown;
  final Color ring;

  static const size = 18.0;

  @override
  State<_AutoSkipBadge> createState() => _AutoSkipBadgeState();
}

class _AutoSkipBadgeState extends State<_AutoSkipBadge>
    with SingleTickerProviderStateMixin {
  static final _out = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 420,
    ratio: 0.6,
  );

  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
    value: widget.shown ? 1 : 0,
  );

  // глубину выбирает старт почти из покоя, по положению: пружина ещё 0,8 с дрожит в долях
  // пикселя и считается в пути. смена глубины посреди пути дёргала кружок
  double _depth = 7;

  @override
  void didUpdateWidget(_AutoSkipBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shown == widget.shown) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = widget.shown ? 1 : 0;
      return;
    }
    final v = _c.value;
    if (widget.shown && v < 0.05) _depth = 7;
    if (!widget.shown && v > 0.85) _depth = 2;
    if (widget.shown) {
      ExpressiveMotion.springTo(_c, 1, spring: _out, snapToEnd: true);
    } else {
      // 220 мс на easeIn, одобренные на гифке, на телефоне ей показались медленными
      _c.animateTo(
        0,
        duration: Duration(milliseconds: (150 * v.clamp(0.3, 1.0)).round()),
        curve: Curves.easeInQuad,
      );
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _icon(double scale) => Icon(
        Icons.remove_rounded,
        size: 13 * scale,
        color: Colors.white,
      );

  @override
  Widget build(BuildContext context) {
    final red = AppTheme.red(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        if (!_c.isAnimating) {
          if (!widget.shown) {
            return const SizedBox.square(dimension: _AutoSkipBadge.size);
          }
          return Container(
            width: _AutoSkipBadge.size,
            height: _AutoSkipBadge.size,
            decoration: BoxDecoration(
              color: red,
              shape: BoxShape.circle,
              border: Border.all(color: widget.ring, width: 1.5),
            ),
            child: _icon(1),
          );
        }
        final v = _c.value;
        final shallow = _depth < 7;
        final drop = _DropGeometry(v, rtl: rtl, depth: _depth);
        final icon = shallow ? const Interval(0.35, 0.8) : const Interval(0.6, 1);
        return SizedBox.square(
          dimension: _AutoSkipBadge.size,
          child: CustomPaint(
            painter: _DropPainter(drop, red: red, ring: widget.ring),
            child: Transform.translate(
              offset: drop.center - _DropGeometry.home,
              child: Opacity(
                opacity: icon.transform(v.clamp(0.0, 1.0)),
                child: Center(child: _icon(drop.scale)),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DropGeometry {
  _DropGeometry(this.v, {required bool rtl, required double depth})
      : origin = home + Offset(rtl ? depth : -depth, -depth);

  final double v;
  final Offset origin;

  static const home = Offset(_AutoSkipBadge.size / 2, _AutoSkipBadge.size / 2);

  double get scale =>
      max(0.0, ui.lerpDouble(0.3, 1, v)!) * (v / 0.15).clamp(0.0, 1.0);
  Offset get center => Offset.lerp(origin, home, v)!;
  double get outer => _AutoSkipBadge.size / 2 * scale;
  double get inner => outer - 1.5 * scale;

  Offset get tail {
    final off = ((v.clamp(0.0, 1.0) - 0.65) / 0.25).clamp(0.0, 1.0);
    return Offset.lerp(origin, center, off)!;
  }
}

class _DropPainter extends CustomPainter {
  _DropPainter(this.drop, {required this.red, required this.ring});

  final _DropGeometry drop;
  final Color red;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final c = drop.center;
    final r = drop.inner;
    if (drop.outer <= 0) return;
    canvas.drawCircle(c, drop.outer, Paint()..color = ring);
    final tip = drop.tail;
    final along = c - tip;
    final length = along.distance;
    final fill = Paint()..color = red;
    if (r > 0 && length > r * 0.5) {
      final u = along / length;
      final n = Offset(-u.dy, u.dx);
      final w = r * 0.75;
      final waist = c - u * (length * 0.55);
      canvas.drawPath(
        Path()
          ..moveTo((c + n * w).dx, (c + n * w).dy)
          ..quadraticBezierTo(
            (waist + n * w * 0.3).dx,
            (waist + n * w * 0.3).dy,
            tip.dx,
            tip.dy,
          )
          ..quadraticBezierTo(
            (waist - n * w * 0.3).dx,
            (waist - n * w * 0.3).dy,
            (c - n * w).dx,
            (c - n * w).dy,
          )
          ..close(),
        fill,
      );
    }
    if (r > 0) canvas.drawCircle(c, r, fill);
  }

  @override
  bool shouldRepaint(_DropPainter oldDelegate) =>
      oldDelegate.drop.v != drop.v ||
      oldDelegate.red != red ||
      oldDelegate.ring != ring;
}

class _ServerTile extends ConsumerWidget {
  final ServerItem server;
  final bool isActive;

  final BorderRadius radius;

  final EdgeInsets margin;

  final ServerRowLayout layout;
  final double height;

  final SubscriptionAccent? accent;
  final bool picking;
  final bool autoSkipShown;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final Future<void> Function() onPing;

  const _ServerTile({
    super.key,
    required this.server,
    required this.isActive,
    required this.radius,
    required this.margin,
    required this.layout,
    required this.height,
    this.accent,
    this.picking = false,
    this.autoSkipShown = false,
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

    final switching = ref.watch(vpnServerSwitchInProgressProvider);
    final isConnected =
        isActive && vpnStatus == VpnStatus.connected && !switching;
    final isConnecting =
        isActive &&
        (switching ||
            vpnStatus == VpnStatus.connecting ||
            vpnStatus == VpnStatus.disconnecting);

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = this.accent;
    final accentColor = accent?.seed ?? AppTheme.accent(context);
    final textLightColor = AppTheme.textLight(context);

    final tileColor =
        accent?.surface(AppTheme.card(context)) ?? AppTheme.card(context);
    final selectedColor = accent?.container ?? scheme.secondaryContainer;

    final rowBody = Builder(
      builder: (context) => ServerRow(
        server: server,
        pingMs: pingMs,
        lastTestedAt: lastTestedAt,
        pingColorType: pingColorType,
        foreground: isActive && TvFocusHighlight.containerOf(context) == null
            ? (accent?.onContainer ?? scheme.onSecondaryContainer)
            : null,
        opaqueBadge: isActive,
        emphasizeTitle: isActive,
        layout: layout,
        muted: autoSkipShown && picking,
        avatarBadge: _AutoSkipBadge(
          shown: autoSkipShown,
          ring: isActive ? selectedColor : tileColor,
        ),
        trailing: layout == ServerRowLayout.inline
            ? _buildTrailing(
                context,
                isConnected,
                isConnecting,
                isActive,
                isPinging,
                accentColor,
                textLightColor,
              )
            : null,
        status: layout == ServerRowLayout.card
            ? _buildInlineStatus(
                context,
                isConnected,
                isConnecting,
                isActive,
                isPinging,
                accentColor,
              )
            : null,
      ),
    );

    return RepaintBoundary(
      child: MergeSemantics(
        child: SizedBox(
          height: height,
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
    final green = AppTheme.green(context);

    final Color bgColor;
    final Widget center;
    if (isPinging || isConnecting) {
      bgColor = accentColor.withValues(alpha: 0.18);
      center = SizedBox(
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

  Widget? _buildInlineStatus(
    BuildContext context,
    bool isConnected,
    bool isConnecting,
    bool isActive,
    bool isPinging,
    Color accentColor,
  ) {
    final Widget glyph;
    if (isPinging || isConnecting) {
      glyph = ShapeLoadingIndicator(
        key: const ValueKey('spinner'),
        size: ExpressiveIconSize.inline,
        color: accentColor,
      );
    } else if (isConnected) {
      glyph = Icon(
        Icons.pause_rounded,
        key: const ValueKey('pause'),
        size: ExpressiveIconSize.inline,
        color: AppTheme.green(context),
      );
    } else if (isActive) {
      glyph = Icon(
        Icons.play_arrow_outlined,
        key: const ValueKey('play'),
        size: ExpressiveIconSize.inline,
        color: accentColor,
      );
    } else {
      return null;
    }
    return SizedBox.square(
      dimension: ExpressiveIconSize.inline,
      child: AnimatedSwitcher(
        duration: ExpressiveMotion.durationFast,
        switchInCurve: ExpressiveMotion.emphasizedDecelerate,
        switchOutCurve: ExpressiveMotion.emphasizedAccelerate,
        child: glyph,
      ),
    );
  }

  void _showOptions(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
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
                _CopyableAddress(
                  text: '${server.address}:${server.port}',
                  onCopied: () => Navigator.pop(context),
                ),
              const SizedBox(height: 16),
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
                          AppSnack.of(context).showSnackBar(
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
                        AppSnack.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.serversConfigCopied)),
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

class _CopyableAddress extends StatelessWidget {
  final String text;

  // меню закрывается до снек-бара, иначе он оказался бы под шторкой
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
          final messenger = AppSnack.of(context);
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
                // направлением, без изоляторов: строка уходит и в буфер обмена, U+2066/U+2069 уехали бы с ней
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

