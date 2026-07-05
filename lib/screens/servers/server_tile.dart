part of '../servers_tab.dart';

class _ServerTile extends ConsumerWidget {
  final ServerItem server;
  final bool isActive;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final Future<void> Function() onPing;

  const _ServerTile({
    super.key,
    required this.server,
    required this.isActive,
    required this.isFirst,
    required this.isLast,
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

    final radius = BorderRadius.vertical(
      bottom: isLast ? const Radius.circular(22) : Radius.zero,
    );

    // кэшируем цвета, чтобы не дёргать Theme.of() на каждый вложенный виджет
    final cardBgColor = isActive
        ? AppTheme.accent(context).withValues(alpha: 0.13)
        : AppTheme.card(context);
    final textColor = AppTheme.text(context);
    final accentColor = AppTheme.accent(context);
    final textLightColor = AppTheme.textLight(context);
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
                Text(
                  titleText,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                    color: textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          server.protocol.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: protocolColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        pingMs != null
                            ? PingService.formatPingValue(pingMs, pingColorType)
                            : (lastTestedAt != null ? 'N/A' : '- ms'),
                        style: TextStyle(
                          fontSize: 12,
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
            color: cardBgColor,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                onLongPress: () => _showOptions(context),
                // на десктопе правый клик открывает то же меню
                onSecondaryTap: () => _showOptions(context),
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

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textLight(context).withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                ServerNameUtils.formatForDisplay(
                  ServerNameUtils.cleanDisplayName(server.displayName),
                ),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.text(context),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              Text(
                '${server.address}:${server.port}',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textLight(context),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
                leading: Icon(
                  Icons.health_and_safety_outlined,
                  color: AppTheme.text(context),
                ),
                title: Text(AppLocalizations.of(context)!.serversHealthCheck),
                subtitle: Text(
                  AppLocalizations.of(context)!.serversHealthCheckDesc,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textLight(context),
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showHealthCheckSheet(context);
                },
              ),
              ListTile(
                leading: Icon(Icons.copy, color: AppTheme.text(context)),
                title: Text(AppLocalizations.of(context)!.serversCopyAddress),
                onTap: () {
                  Clipboard.setData(
                    ClipboardData(text: '${server.address}:${server.port}'),
                  );
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(context)!.serversCopiedToClipboard,
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
                  onDelete();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showHealthCheckSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bg(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) =>
          FutureBuilder<List<({String name, bool ok, String details})>>(
            future: _runHealthCheck(),
            builder: (ctx, snapshot) {
              final loading = snapshot.connectionState != ConnectionState.done;
              final checks =
                  snapshot.data ??
                  const <({String name, bool ok, String details})>[];
              final successCount = checks.where((c) => c.ok).length;

              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppTheme.textLight(
                              context,
                            ).withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        context.l10n.serversHealthCheck,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.text(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ServerNameUtils.formatForDisplay(
                          ServerNameUtils.cleanDisplayName(server.displayName),
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textLight(context),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (loading)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: AppTheme.accent(context),
                            ),
                          ),
                        )
                      else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: successCount == checks.length
                                ? AppTheme.green(
                                    context,
                                  ).withValues(alpha: 0.12)
                                : AppTheme.orange(
                                    context,
                                  ).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: successCount == checks.length
                                  ? AppTheme.green(
                                      context,
                                    ).withValues(alpha: 0.35)
                                  : AppTheme.orange(
                                      context,
                                    ).withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            'Checks passed: $successCount/${checks.length}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.text(context),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...checks.map(
                          (c) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.card(context),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: c.ok
                                    ? AppTheme.green(
                                        context,
                                      ).withValues(alpha: 0.35)
                                    : AppTheme.red(
                                        context,
                                      ).withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  c.ok
                                      ? Icons.check_circle
                                      : Icons.error_outline,
                                  size: 16,
                                  color: c.ok
                                      ? AppTheme.green(context)
                                      : AppTheme.red(context),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        c.name,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.text(context),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        c.details,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.textLight(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }

  Future<List<({String name, bool ok, String details})>>
  _runHealthCheck() async {
    final checks = <({String name, bool ok, String details})>[];
    checks.add((
      name: 'Server fields',
      ok:
          server.address.trim().isNotEmpty &&
          server.port > 0 &&
          server.port <= 65535,
      details: '${server.address}:${server.port}',
    ));

    try {
      final addresses = await InternetAddress.lookup(
        server.address,
      ).timeout(const Duration(seconds: 5));
      checks.add((
        name: 'DNS resolve',
        ok: addresses.isNotEmpty,
        details: addresses.isNotEmpty
            ? addresses.first.address
            : 'No IP resolved',
      ));
    } catch (e) {
      checks.add((name: 'DNS resolve', ok: false, details: 'Failed: $e'));
    }

    final ping = await PingService.pingTcp(server, timeoutSeconds: 6);
    checks.add((
      name: 'TCP handshake',
      ok: ping.success,
      details: ping.success ? '${ping.latencyMs} ms' : ping.error,
    ));

    final hasConfig = server.config.trim().isNotEmpty;
    final hasScheme = RegExp(
      r'^[a-zA-Z0-9+.-]+://',
    ).hasMatch(server.config.trim());
    checks.add((
      name: 'Config format',
      ok: hasConfig && hasScheme,
      details: hasConfig
          ? (hasScheme ? 'URI format detected' : 'Missing URI scheme')
          : 'Config is empty',
    ));

    return checks;
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

