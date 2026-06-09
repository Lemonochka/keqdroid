import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/shared/extensions/build_context_l10n.dart';
import 'package:keqdroid/shared/ui/app_theme.dart';

import '../core/app_logger.dart';
import '../models/app_settings.dart';
import '../models/server_item.dart';
import '../models/server_name_utils.dart';
import '../models/subscription.dart';
import '../providers/providers.dart';
import '../services/ping_service.dart';
import '../services/vpn_engine.dart';
import '../platform/platform_bootstrap.dart';
import '../platform/vpn_native_bridge.dart';
import '../ui/responsive/desktop_page_layout.dart';
import '../utils/error_messages.dart';

class ServersTab extends ConsumerStatefulWidget {
  const ServersTab({super.key});

  @override
  ConsumerState<ServersTab> createState() => _ServersTabState();
}

class _ServersTabState extends ConsumerState<ServersTab>
    with TickerProviderStateMixin, WidgetsBindingObserver {

  late final AnimationController _breathCtrl;
  late final Animation<double>   _breathAnim;
  late final AnimationController _waveCtrl;
  late final AnimationController _stateCtrl;

  final _headerKey = GlobalKey();
  double _headerHeight = 0;
  bool _handlingLaunchAction = false;
  bool _appInForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    VpnNativeBridge.registerLaunchHandler(_onNativeMethodCall);
    _breathCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);
    _breathAnim = Tween<double>(begin: 1.0, end: 1.05)
        .animate(CurvedAnimation(parent: _breathCtrl, curve: Curves.easeInOut));
    _waveCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
    _stateCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Platform.isAndroid) {
        unawaited(_checkLaunchAction());
      }
      _syncHeaderAnimations();
      _scheduleHeaderMeasure();
    });
  }

  void _scheduleHeaderMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _headerKey.currentContext;
      if (ctx != null) {
        final h = ctx.size?.height ?? 0;
        if (h > 0 && h != _headerHeight) {
          setState(() => _headerHeight = h);
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    VpnNativeBridge.registerLaunchHandler(null);
    _breathCtrl.dispose();
    _waveCtrl.dispose();
    _stateCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _appInForeground = false;
      _syncHeaderAnimations();
    } else if (state == AppLifecycleState.resumed) {
      _appInForeground = true;
      _syncHeaderAnimations();
      if (Platform.isAndroid) {
        unawaited(_checkLaunchAction());
      }
    }
  }

  bool _isServersHomeTab() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return ref.read(homeTabIndexProvider) == 0;
    }
    return ref.read(homeTabPageProvider) < 0.05;
  }

  bool get _serversTabVisible => _isServersHomeTab();

  void _syncHeaderAnimations() {
    final status = ref.read(vpnStateProvider).value?.status;
    final vpnActive = status == VpnStatus.connecting ||
        status == VpnStatus.disconnecting ||
        status == VpnStatus.connected;
    final run = (_serversTabVisible && _appInForeground) || vpnActive;
    if (run) {
      if (!_waveCtrl.isAnimating) _waveCtrl.repeat();
      if (!_breathCtrl.isAnimating) _breathCtrl.repeat(reverse: true);
    } else {
      _waveCtrl.stop();
      _breathCtrl.stop();
    }
  }

  Future<void> _onNativeMethodCall(MethodCall call) async {
    if (call.method == 'onLaunchAction') {
      await _checkLaunchAction();
    }
  }

  Future<void> _checkLaunchAction() async {
    if (!Platform.isAndroid || _handlingLaunchAction) return;
    _handlingLaunchAction = true;

    try {
      final action = await VpnNativeBridge.getLaunchAction();
      if (action != 'connect_from_notification') return;

      // ?????????? ???? ?? connect(), ????? resume ????? ????????? ?????? connect()
      await VpnNativeBridge.clearLaunchAction();

      if (!mounted) return;

      final active = ref.read(serversProvider).activeServer;
      if (active == null) {
        _showSnack(context.l10n.vpnSelectServerFirst);
        return;
      }

      await ref.read(vpnStateProvider.notifier).connect();
    } catch (e, st) {
      AppLogger.instance.error(
        'Failed to handle launch action connect_from_notification',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        _showSnack(friendlyError(e, context));
      }
    } finally {
      _handlingLaunchAction = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<VpnState>>(vpnStateProvider, (prev, next) {
      final prevStatus = prev?.value?.status;
      final nextStatus = next.value?.status;
      if (prevStatus == nextStatus) return;

      final wasActive = prevStatus == VpnStatus.connected ||
          prevStatus == VpnStatus.connecting ||
          prevStatus == VpnStatus.disconnecting;
      final isActiveNow = nextStatus == VpnStatus.connected ||
          nextStatus == VpnStatus.connecting ||
          nextStatus == VpnStatus.disconnecting;
      if (wasActive != isActiveNow) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (isActiveNow) {
            _stateCtrl.forward();
          } else {
            _stateCtrl.reverse();
          }
          _scheduleHeaderMeasure();
        });
      }

      if (nextStatus == VpnStatus.connecting ||
          nextStatus == VpnStatus.disconnecting) {
        if (!_breathCtrl.isAnimating) _breathCtrl.repeat(reverse: true);
        if (!_waveCtrl.isAnimating) _waveCtrl.repeat();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncHeaderAnimations();
      });
    });

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      ref.listen<int>(homeTabIndexProvider, (prev, next) {
        final wasVisible = (prev ?? 0) == 0;
        final isVisible = next == 0;
        if (wasVisible != isVisible) _syncHeaderAnimations();
      });
    } else {
      ref.listen<double>(homeTabPageProvider, (prev, next) {
        final wasVisible = (prev ?? 0) < 0.05;
        final isVisible = next < 0.05;
        if (wasVisible != isVisible) _syncHeaderAnimations();
      });
    }

    final onServersTab = Platform.isWindows ||
            Platform.isLinux ||
            Platform.isMacOS
        ? ref.watch(homeTabIndexProvider.select((i) => i == 0))
        : ref.watch(homeTabPageProvider.select((p) => p < 0.05));
    final headerAnimationsEnabled = onServersTab && _appInForeground;

    final vpnStatus = ref.watch(
      vpnStateProvider.select(
        (a) => a.value?.status ?? VpnStatus.disconnected,
      ),
    );
    final vpnErrorMessage = ref.watch(
      vpnStateProvider.select((a) => a.value?.errorMessage),
    );
    final serverSwitchInProgress = ref.watch(vpnServerSwitchInProgressProvider);
    final activeServer = ref.watch(
      serversProvider.select((s) => s.activeServer),
    );

    final isConnected = vpnStatus == VpnStatus.connected;
    final isConnecting = vpnStatus == VpnStatus.connecting ||
        vpnStatus == VpnStatus.disconnecting;

    final isActive = isConnected || isConnecting;

    final isDesktop = PlatformBootstrap.isDesktop;
    // ?????????? ?????? ?? connecting/connected, ????? ?? ????????? ??? ???????????
    final waveHeight = isDesktop
        ? (isActive ? 32.0 : 40.0)
        : (isActive ? 28.0 : 36.0);
    final topPad = isDesktop ? 20.0 : MediaQuery.of(context).padding.top + 24;

    final connectHeader = NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _scheduleHeaderMeasure();
        return false;
      },
      child: SizeChangedLayoutNotifier(
        child: Padding(
          key: _headerKey,
          padding: EdgeInsets.fromLTRB(24, topPad, 24, 8),
          child: Column(
            children: [
          TickerMode(
            enabled: headerAnimationsEnabled || isConnecting,
            child: ScaleTransition(
              scale: (isConnected || isConnecting)
                  ? _breathAnim
                  : const AlwaysStoppedAnimation(1.0),
              child: GestureDetector(
                onTap: isConnecting ? null : () => _toggleVpn(vpnStatus),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isConnected
                        ? AppTheme.accentContainer(context)
                        : isConnecting
                            ? AppTheme.accent(context).withValues(alpha: 0.18)
                            : AppTheme.card(context),
                    border: (!isConnected && !isConnecting)
                        ? Border.all(color: AppTheme.divider(context), width: 1)
                        : Border.all(
                            color: AppTheme.accent(context).withValues(alpha: 0.45),
                            width: 2,
                          ),
                    boxShadow: [
                      BoxShadow(
                        color: (isConnected || isConnecting
                                ? AppTheme.accent(context)
                                : AppTheme.card(context))
                            .withValues(alpha: 0.35),
                        blurRadius: 30,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                  child: isConnecting
                      ? Padding(
                          padding: const EdgeInsets.all(36),
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: AppTheme.accent(context),
                          ),
                        )
                      : Icon(
                          isConnected ? Icons.pause : Icons.play_arrow,
                          size: 52,
                          color: isConnected
                              ? AppTheme.onAccentContainer(context)
                              : AppTheme.text(context),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            constraints: const BoxConstraints(
              minHeight: 36,
              maxHeight: 56,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _statusText(
                serverSwitchInProgress && vpnStatus == VpnStatus.error
                    ? VpnStatus.connecting
                    : vpnStatus,
                serverSwitchInProgress ? null : vpnErrorMessage,
                activeServer,
              ),
            ),
          ),
          if (vpnStatus == VpnStatus.error &&
              vpnErrorMessage != null &&
              !serverSwitchInProgress)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                _friendlyErrorDetailed(vpnErrorMessage),
                textAlign: TextAlign.center,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: AppTheme.red(context)),
              ),
            ),
          if (PlatformBootstrap.isDesktop && isConnected)
            const _DesktopConnectionStats(),
          SizedBox(height: isActive ? 12 : 20),
          TickerMode(
            enabled: headerAnimationsEnabled || isConnecting || isConnected,
            child: _WavePaintWidget(
              waveCtrl: _waveCtrl,
              stateCtrl: _stateCtrl,
              context: context,
              height: waveHeight,
            ),
          ),
            ],
          ),
        ),
      ),
    );

    Widget body = Column(
      children: [
        connectHeader,
        Expanded(
          child: _ServersListPanel(
            topPadding: _listTopFadeHeight - _listTopFadeTileOverlap,
            onSelectServer: _selectServer,
            emptyState: _emptyState(),
          ),
        ),
      ],
    );

    if (isDesktop) {
      body = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: DesktopBreakpoints.serversContentMaxWidth,
          ),
          child: body,
        ),
      );
    }

    return SizedBox.expand(
      child: Stack(
      fit: StackFit.expand,
      children:[
        body,

        if (_headerHeight > 0)
          Positioned(
            top: _headerHeight - _listTopFadeUpExtension,
            left: 0,
            right: 0,
            height: _listTopFadeOverlayHeight,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppTheme.bg(context),
                      AppTheme.bg(context).withValues(alpha: 1.0),
                      AppTheme.bg(context).withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, _listTopFadeSolidStop, 1.0],
                  ),
                ),
              ),
            ),
          ),

        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 56,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppTheme.bg(context).withValues(alpha: 0.0),
                    AppTheme.bg(context).withValues(alpha: 1.0),
                    AppTheme.bg(context),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 20, bottom: 20,
          child: FloatingActionButton(
            heroTag: 'servers_add_server_fab',
            backgroundColor: AppTheme.accentContainer(context),
            foregroundColor: AppTheme.onAccentContainer(context),
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onPressed: () => _showAddServerDialog(context),
            child: const Icon(Icons.add, size: 26),
          ),
        ),
      ],
      ),
    );
  }

  void _showAddServerDialog(BuildContext ctx) {
    final l10n = AppLocalizations.of(ctx)!;
    showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: AppTheme.bg(ctx),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx2) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.serversAddServer, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.text(ctx))),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.link, color: AppTheme.accent(ctx)),
              title: Text(l10n.serversPasteLinks, style: TextStyle(color: AppTheme.text(ctx))),
              subtitle: Text('vless, vmess, trojan, ss, hysteria2, hy2?', style: TextStyle(fontSize: 12, color: AppTheme.textLight(ctx))),
              onTap: () {
                Navigator.pop(ctx2);
                _showPasteLinksSheet(ctx);
              },
            ),
            ListTile(
              leading: Icon(Icons.description_outlined, color: AppTheme.accent(ctx)),
              title: Text(l10n.serversImportFile, style: TextStyle(color: AppTheme.text(ctx))),
              subtitle: Text(l10n.serversNotSupported, style: TextStyle(fontSize: 12, color: AppTheme.textLight(ctx))),
              onTap: null,
            ),
          ],
        ),
      ),
    );
  }

  void _showPasteLinksSheet(BuildContext ctx) {
    final l10n = AppLocalizations.of(ctx)!;
    final ctrl = TextEditingController();
    bool loading = false;
    showModalBottomSheet(
      context: ctx, backgroundColor: AppTheme.bg(ctx), isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx2) => StatefulBuilder(
        builder: (ctx2, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx2).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.serversAddServerTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.text(ctx))),
              const SizedBox(height: 6),
              Text(l10n.serversPasteVlessHint, style: TextStyle(fontSize: 12, color: AppTheme.textLight(ctx))),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl, autofocus: true, maxLines: 4,
                style: TextStyle(color: AppTheme.text(ctx), fontSize: 13),
                decoration: InputDecoration(
                  hintText: l10n.serversPasteHint,
                  hintStyle: TextStyle(color: AppTheme.textLight(ctx).withValues(alpha: 0.5)),
                  filled: true, fillColor: AppTheme.card(ctx),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppTheme.accent(ctx), width: 2)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentContainer(ctx),
                      foregroundColor: AppTheme.onAccentContainer(ctx),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: loading ? null : () async {
                    final raw = ctrl.text.trim();
                    if (raw.isEmpty) return;
                    setModalState(() => loading = true);
                    try {
                      final configs = raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
                      for (final c in configs) {
                        await ref.read(serversProvider.notifier).addManual(c);
                      }
                      if (ctx2.mounted) Navigator.pop(ctx2);
                    } catch (e) {
                      setModalState(() => loading = false);
                      if (ctx2.mounted) Navigator.pop(ctx2);
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(_friendlyError(e)),
                            backgroundColor: AppTheme.red(ctx),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            duration: const Duration(seconds: 5),
                          ),
                        );
                      }
                    }
                  },
                  child: loading
                      ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.onAccentContainer(ctx),
                    ),
                  )
                      : Text(l10n.serversAdd, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusText(
    VpnStatus status,
    String? errorMessage,
    ServerItem? activeServer,
  ) {
    final l10n = AppLocalizations.of(context)!;
    if (status == VpnStatus.connected && activeServer != null) {
      final cleanName = ServerNameUtils.formatForDisplay(
          ServerNameUtils.cleanDisplayName(activeServer.displayName));
      return Container(
        key: const ValueKey('connected'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.accent(context).withValues(alpha: 0.5), width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          l10n.vpnConnectedTo(cleanName),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.text(context),
          ),
        ),
      );
    } else {
      final statusKey = switch (status) {
        VpnStatus.connected     => 'connected',
        VpnStatus.connecting    => 'connecting',
        VpnStatus.disconnecting => 'disconnecting',
        VpnStatus.error         => 'error',
        _                       => activeServer != null ? 'ready' : 'no-server',
      };
      final label = switch (status) {
        VpnStatus.connecting    => l10n.vpnConnecting,
        VpnStatus.disconnecting => l10n.vpnDisconnecting,
        VpnStatus.error         => _vpnErrorStatusLabel(errorMessage, context),
        _                       => activeServer != null
            ? l10n.vpnTapToConnect(ServerNameUtils.formatForDisplay(ServerNameUtils.cleanDisplayName(activeServer.displayName)))
            : l10n.vpnSelectServer,
      };
      return Text(
        label,
        key: ValueKey(statusKey),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 14, color: AppTheme.textLight(context)),
      );
    }
  }

  Widget _emptyState() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 48, color: AppTheme.accent(context).withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(l10n.serversEmptyTitle, style: TextStyle(color: AppTheme.textLight(context))),
          const SizedBox(height: 8),
          Text(
            l10n.serversEmptyHint,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppTheme.textLight(context)),
          ),
        ],
      ),
    );
  }

  Future<void> _selectServer(ServerItem server) async {
    await ref.read(serversProvider.notifier).setActive(server);
    final vpnStatus = ref.read(vpnStateProvider).value?.status;
    if (vpnStatus == VpnStatus.connected || vpnStatus == VpnStatus.connecting) {
      await ref.read(vpnStateProvider.notifier).reconnectToActiveServer();
    }
  }

  Future<void> _toggleVpn(VpnStatus status) async {
    if (status == VpnStatus.connected) {
      await ref.read(vpnStateProvider.notifier).disconnect();
    } else {
      final active = ref.read(serversProvider).activeServer;
      if (active == null) {
        _showSnack(context.l10n.vpnSelectServerFirst);
        return;
      }
      try {
        await ref.read(vpnStateProvider.notifier).connect();
      } catch (e) {
        _showSnack(e.toString());
      }
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppTheme.text(context),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _ServersListPanel extends ConsumerWidget {
  final double topPadding;
  final Future<void> Function(ServerItem) onSelectServer;
  final Widget emptyState;

  const _ServersListPanel({
    this.topPadding = 0,
    required this.onSelectServer,
    required this.emptyState,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serversState = ref.watch(serversProvider);
    final subs = ref.watch(subscriptionsProvider).value ?? [];

    if (serversState.isLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppTheme.accent(context)),
      );
    }
    if (subs.isEmpty && serversState.servers.isEmpty) {
      return emptyState;
    }

    final manual =
        serversState.servers.where((s) => s.subscriptionId == null).toList();
    final bySubId = <String, List<ServerItem>>{};
    for (final s
        in serversState.servers.where((s) => s.subscriptionId != null)) {
      bySubId.putIfAbsent(s.subscriptionId!, () => []).add(s);
    }

    final groups = <_ServerGroupEntry>[];
    for (final sub in subs) {
      final servers = bySubId[sub.id] ?? [];
      if (servers.isEmpty) continue;
      groups.add(_ServerGroupEntry(
        key: ValueKey('server-group-${sub.id}'),
        subscription: sub,
        servers: servers,
        onRefresh: () =>
            ref.read(subscriptionsProvider.notifier).refreshTracked(sub),
        onPingAll: () =>
            ref.read(serversProvider.notifier).pingSubscription(sub.id),
      ));
    }
    if (manual.isNotEmpty) {
      groups.add(_ServerGroupEntry(
        key: const ValueKey('server-group-manual'),
        subscription: null,
        servers: manual,
        onRefresh: null,
        onPingAll: () =>
            ref.read(serversProvider.notifier).pingSubscription(null),
      ));
    }

    return ListView.builder(
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, 80),
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final entry = groups[index];
        return Padding(
          padding: EdgeInsets.only(bottom: index < groups.length - 1 ? 20 : 0),
          child: _SubCard(
            key: entry.key,
            subscription: entry.subscription,
            servers: entry.servers,
            onSelectServer: onSelectServer,
            onRefresh: entry.onRefresh,
            onPingAll: entry.onPingAll,
          ),
        );
      },
    );
  }
}

class _ServerGroupEntry {
  final Key key;
  final Subscription? subscription;
  final List<ServerItem> servers;
  final Future<void> Function()? onRefresh;
  final Future<void> Function() onPingAll;

  const _ServerGroupEntry({
    required this.key,
    required this.subscription,
    required this.servers,
    this.onRefresh,
    required this.onPingAll,
  });
}

/// ?????? ???????? ????? ??????
const _listTopFadeHeight = 56.0;
/// ????????? ?????? ?????? ???????? ??? ???? (??? ?? android)
const _listTopFadeTileOverlap = 34.0;

// ????? ???? ????? ?? ?????? padding ?????, ????? ?? ???? ??????? ?????? ????
const _listTopFadeUpExtension = 8.0;
const _listTopFadeOverlayHeight =
    _listTopFadeHeight + _listTopFadeUpExtension;
// ???? ???????????? ????? ??????? ???? ?? extension, ????? ???? ???????? ?? ??????
const _listTopFadeSolidStop =
    (_listTopFadeUpExtension + 0.45 * _listTopFadeHeight) /
        _listTopFadeOverlayHeight;

/// ????? ?????? ?????? ????????? ???????? ? [_ServerTile]
const _subCardRowHeight = 76.0;

/// ???? ? ?????: ????????????? asset ????? BoxFit.cover, ??? ??????? ?? ???????
Widget _countryFlagCircle({
  required String? countryCode,
  required Color protocolColor,
  required String protocol,
  double size = 40,
}) {
  return SizedBox(
    width: size,
    height: size,
    child: ClipOval(
      clipBehavior: Clip.antiAlias,
      child: countryCode != null
          ? FittedBox(
              fit: BoxFit.cover,
              alignment: Alignment.center,
              child: CountryFlag.fromCountryCode(
                countryCode,
                theme: const ImageTheme(
                  width: 60,
                  height: 40,
                ),
              ),
            )
          : ColoredBox(
              color: protocolColor,
              child: Center(
                child: Text(
                  protocol.isNotEmpty ? protocol[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
    ),
  );
}

const _subCardHeaderIconSize = 32.0;
const _subCardHeaderActionGap = 8.0;
const _subCardHeaderIntervalGap = 10.0;

Widget _subCardHeaderIconButton({
  required String tooltip,
  required VoidCallback? onPressed,
  required Widget icon,
}) {
  return IconButton(
    onPressed: onPressed,
    tooltip: tooltip,
    icon: icon,
    padding: EdgeInsets.zero,
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints(
      minWidth: _subCardHeaderIconSize,
      maxWidth: _subCardHeaderIconSize,
      minHeight: _subCardHeaderIconSize,
      maxHeight: _subCardHeaderIconSize,
    ),
    style: IconButton.styleFrom(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: const Size(_subCardHeaderIconSize, _subCardHeaderIconSize),
      fixedSize: const Size(_subCardHeaderIconSize, _subCardHeaderIconSize),
      padding: EdgeInsets.zero,
    ),
  );
}

class _SubCard extends ConsumerStatefulWidget {
  final Subscription? subscription;
  final List<ServerItem> servers;
  final void Function(ServerItem) onSelectServer;
  final Future<void> Function()? onRefresh;
  final Future<void> Function() onPingAll;

  const _SubCard({
    super.key,
    required this.subscription,
    required this.servers,
    required this.onSelectServer,
    required this.onRefresh,
    required this.onPingAll,
  });

  @override
  ConsumerState<_SubCard> createState() => _SubCardState();
}

class _SubCardState extends ConsumerState<_SubCard> {
  @override
  Widget build(BuildContext context) {
    final sub = widget.subscription;
    final collapseKey = sub?.id ?? '__manual__';
    final collapsed = ref.watch(
      collapsedServerGroupsProvider.select((m) => m[collapseKey] ?? false),
    );
    final isRefreshing = sub != null &&
        ref.watch(
          subscriptionRefreshingIdsProvider.select((ids) => ids.contains(sub.id)),
        );
    final hasRefreshError = sub != null &&
        ref.watch(
          subscriptionRefreshErrorsProvider.select((m) => m.containsKey(sub.id)),
        );
    final pingScope = sub?.id ?? '__manual__';
    final isPingingAll = ref.watch(
      pingingScopesProvider.select((scopes) => scopes.contains(pingScope)),
    );
    final activeServerId = ref.watch(
      serversProvider.select((s) => s.activeServerId),
    );
    final title = sub != null
        ? '${sub.name}  |  ${sub.usageLabel}'
        : 'Manual servers';

    // ???????? ?????, ????? ?? ??????? Theme.of() ?? ?????? ??????
    final cardColor = AppTheme.card(context);
    final dividerColor = AppTheme.divider(context);
    final accentColor = AppTheme.accent(context);
    final textLightColor = AppTheme.textLight(context);

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: dividerColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

            SizedBox(
              height: _subCardRowHeight,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 14, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                    SizedBox(
                      width: 40,
                      height: _subCardHeaderIconSize,
                      child: Center(
                        child: GestureDetector(
                          onTap: () => ref
                              .read(collapsedServerGroupsProvider.notifier)
                              .update((m) => {...m, collapseKey: !collapsed}),
                          child: AnimatedRotation(
                            turns: collapsed ? -0.25 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              Icons.expand_more,
                              size: 22,
                              color: textLightColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => ref
                            .read(collapsedServerGroupsProvider.notifier)
                            .update((m) => {...m, collapseKey: !collapsed}),
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: textLightColor,
                            letterSpacing: 0.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),

                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (sub != null && sub.autoUpdate) ...[
                          GestureDetector(
                            onTap: () => _showIntervalPicker(context, sub),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${sub.updateIntervalHours}h',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: accentColor,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: _subCardHeaderIntervalGap),
                        ],
                        if (widget.onRefresh != null) ...[
                          _subCardHeaderIconButton(
                            tooltip: AppLocalizations.of(context)!.serversRefreshSubscription,
                            onPressed: isRefreshing
                                ? null
                                : () async {
                              try {
                                await widget.onRefresh!.call();
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
                            icon: isRefreshing
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: accentColor,
                                    ),
                                  )
                                : Icon(
                                    Icons.refresh,
                                    size: 18,
                                    color: hasRefreshError
                                        ? AppTheme.red(context)
                                        : textLightColor,
                                  ),
                          ),
                          const SizedBox(width: _subCardHeaderActionGap),
                        ],
                        _subCardHeaderIconButton(
                          tooltip: AppLocalizations.of(context)!.serversPingAll,
                          onPressed: isPingingAll
                              ? null
                              : () async {
                            try {
                              await widget.onPingAll();
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
                          icon: isPingingAll
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: accentColor,
                                  ),
                                )
                              : Icon(
                                  Icons.network_ping,
                                  size: 18,
                                  color: textLightColor,
                                ),
                        ),
                      ],
                    ),
                  ),
                    ],
                  ),
                ),
              ),
            ),

            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: collapsed
                  ? const SizedBox(
                      key: ValueKey('servers-collapsed'),
                      width: double.infinity,
                    )
                  : _buildExpandedServerList(
                      activeServerId: activeServerId,
                      textLightColor: textLightColor,
                    ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  // column ?????? ?????????? listview: ??? ???????????? ?? ???? viewport ? ????? ????? ??????
  Widget _buildExpandedServerList({
    required String? activeServerId,
    required Color textLightColor,
  }) {
    if (widget.servers.isEmpty) {
      return Padding(
        key: const ValueKey('servers-expanded-empty'),
        padding: const EdgeInsets.all(16),
        child: Text(
          'No servers in this subscription',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: textLightColor),
        ),
      );
    }

    return Column(
      key: const ValueKey('servers-expanded'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < widget.servers.length; index++)
          _ServerTile(
            key: ValueKey(widget.servers[index].id),
            server: widget.servers[index],
            isActive: widget.servers[index].id == activeServerId,
            isFirst: index == 0,
            isLast: index == widget.servers.length - 1,
            onTap: () => widget.onSelectServer(widget.servers[index]),
            onDelete: () => ref
                .read(serversProvider.notifier)
                .delete(widget.servers[index].id),
            onPing: () => ref
                .read(serversProvider.notifier)
                .pingSingle(widget.servers[index].id),
          ),
      ],
    );
  }

  void _showIntervalPicker(BuildContext context, Subscription sub) {
    const options = [1, 3, 6, 12, 24, 48, 72];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final maxHeight = MediaQuery.sizeOf(ctx).height * 0.85;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.textLight(context).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Auto-update interval',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.text(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Current: every ${sub.updateIntervalHours}h',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppTheme.textLight(context)),
                ),
                const SizedBox(height: 8),
                ...options.map((h) => ListTile(
                      title: Text(
                        h == 1
                            ? 'Every hour'
                            : h < 24
                                ? 'Every $h hours'
                                : h == 24
                                    ? 'Every day'
                                    : 'Every ${h ~/ 24} days',
                        style: TextStyle(
                          color: AppTheme.text(context),
                          fontWeight: h == sub.updateIntervalHours
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      trailing: h == sub.updateIntervalHours
                          ? Icon(Icons.check, color: AppTheme.accent(context))
                          : null,
                      onTap: () {
                        ref.read(subscriptionsProvider.notifier).updateInterval(sub.id, h);
                        Navigator.pop(ctx);
                      },
                    )),
              ],
            ),
          ),
        );
      },
    );
  }
}

Widget _vpnDebugChip(BuildContext context, String label, String value) {
  return SizedBox(
    height: 26,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.inset(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.divider(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppTheme.textLight(context),
                height: 1.0,
              ),
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.text(context),
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String _formatVpnRate(int? bytesPerSec) {
  if (bytesPerSec == null || bytesPerSec <= 0) return '0 B/s';
  return '${_formatVpnBytes(bytesPerSec)}/s';
}

String _formatVpnBytes(int? bytes) {
  if (bytes == null || bytes <= 0) return '0 B';
  const kb = 1024.0;
  const mb = kb * 1024;
  const gb = mb * 1024;
  final b = bytes.toDouble();
  if (b >= gb) return '${(b / gb).toStringAsFixed(2)} GB';
  if (b >= mb) return '${(b / mb).toStringAsFixed(1)} MB';
  if (b >= kb) return '${(b / kb).toStringAsFixed(1)} KB';
  return '$bytes B';
}

String _formatVpnDuration(Duration? d) {
  if (d == null) return '0s';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

// Скорость и объём трафика под кнопкой подключения (desktop).
class _DesktopConnectionStats extends ConsumerWidget {
  const _DesktopConnectionStats();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(
      vpnStateProvider.select((a) {
        final v = a.value;
        if (v == null) return (null, null, null, null);
        return (
          v.downloadSpeed,
          v.uploadSpeed,
          v.totalDownload,
          v.duration,
        );
      }),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _statChip(
            context,
            icon: Icons.arrow_downward,
            value: _formatVpnRate(stats.$1),
          ),
          const SizedBox(width: 8),
          _statChip(
            context,
            icon: Icons.arrow_upward,
            value: _formatVpnRate(stats.$2),
          ),
          const SizedBox(width: 8),
          _statChip(context, label: 'In', value: _formatVpnBytes(stats.$3)),
          const SizedBox(width: 8),
          _statChip(context, label: 'Time', value: _formatVpnDuration(stats.$4)),
        ],
      ),
    );
  }

  Widget _statChip(
    BuildContext context, {
    IconData? icon,
    String? label,
    required String value,
  }) {
    final color = AppTheme.textLight(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.divider(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 12, color: color)
          else
            Text(
              label ?? '',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerTileVpnDebugPanel extends ConsumerWidget {
  final VpnStatus vpnStatus;

  const _ServerTileVpnDebugPanel({required this.vpnStatus});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(
      vpnStateProvider.select((a) {
        final v = a.value;
        if (v == null) return (null, null, null, null, null);
        return (
          v.downloadSpeed,
          v.uploadSpeed,
          v.totalDownload,
          v.totalUpload,
          v.duration,
        );
      }),
    );

    return Column(
      children: [
        const SizedBox(height: 5),
        SizedBox(
          height: 26 * 2 + 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _vpnDebugChip(
                      context,
                      'State',
                      vpnStatus.name.toUpperCase(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _vpnDebugChip(
                      context,
                      'DL',
                      _formatVpnRate(stats.$1),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _vpnDebugChip(
                      context,
                      'UL',
                      _formatVpnRate(stats.$2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _vpnDebugChip(
                      context,
                      'In',
                      _formatVpnBytes(stats.$3),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _vpnDebugChip(
                      context,
                      'Out',
                      _formatVpnBytes(stats.$4),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _vpnDebugChip(
                      context,
                      'Up',
                      _formatVpnDuration(stats.$5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

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
        for (final item in s.servers) {
          if (item.id == server.id) {
            return (item.pingMs, item.lastTestedAt, item.lastPingType);
          }
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
    final showDebugStats = isActive &&
        !PlatformBootstrap.isDesktop &&
        ref.watch(
          settingsNotifierProvider.select(
            (a) => a.value?.debugMode ?? false,
          ),
        );

    final isConnected = isActive && vpnStatus == VpnStatus.connected;
    final isConnecting = isActive &&
        (vpnStatus == VpnStatus.connecting ||
            vpnStatus == VpnStatus.disconnecting);

    final radius = BorderRadius.vertical(
      bottom: isLast ? const Radius.circular(22) : Radius.zero,
    );

    // ???????? ?????, ????? ?? ??????? Theme.of() ?? ?????? ??????
    final cardBgColor = isActive ? AppTheme.accent(context).withValues(alpha: 0.13) : AppTheme.card(context);
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: protocolColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        server.protocol.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: protocolColor,
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

    final tileBody = showDebugStats
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: _subCardRowHeight, child: rowBody),
              _ServerTileVpnDebugPanel(vpnStatus: vpnStatus),
            ],
          )
        : SizedBox(height: _subCardRowHeight, child: rowBody);

    return RepaintBoundary(
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
              // ?? ???????? ?????? ???? ????????? ?? ?? ????
              onSecondaryTap: () => _showOptions(context),
              splashColor: accentColor.withValues(alpha: 0.2),
              highlightColor: accentColor.withValues(alpha: 0.08),
              child: tileBody,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrailing(BuildContext context, bool isConnected, bool isConnecting, bool isActive, bool isPinging, Color accentColor, Color textLightColor) {
    if (isConnected) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.green(context).withValues(alpha: 0.25),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.pause, size: 18, color: AppTheme.green(context)),
      );
    }
    if (isConnecting) {
      return SizedBox(
        width: 34, height: 34,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: accentColor,
          ),
        ),
      );
    }
    if (isActive) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.play_arrow, size: 18, color: accentColor),
      );
    }
    if (isPinging) {
      return SizedBox(
        width: 34,
        height: 34,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: accentColor,
          ),
        ),
      );
    }
    return Icon(Icons.chevron_right, color: textLightColor);
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
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textLight(context).withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                ServerNameUtils.formatForDisplay(ServerNameUtils.cleanDisplayName(server.displayName)),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.text(context)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              Text(
                '${server.address}:${server.port}',
                style: TextStyle(fontSize: 12, color: AppTheme.textLight(context)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(Icons.network_ping, color: AppTheme.text(context)),
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
                leading: Icon(Icons.health_and_safety_outlined, color: AppTheme.text(context)),
                title: Text(AppLocalizations.of(context)!.serversHealthCheck),
                subtitle: Text(
                  AppLocalizations.of(context)!.serversHealthCheckDesc,
                  style: TextStyle(fontSize: 11, color: AppTheme.textLight(context)),
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
                  Clipboard.setData(ClipboardData(text: '${server.address}:${server.port}'));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(AppLocalizations.of(context)!.serversCopiedToClipboard)),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.link, color: AppTheme.text(context)),
                title: Text(AppLocalizations.of(context)!.serversCopyConfig),
                subtitle: Text(
                  server.protocol.toUpperCase(),
                  style: TextStyle(fontSize: 11, color: AppTheme.textLight(context)),
                ),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: server.config));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(AppLocalizations.of(context)!.serversConfigCopied)),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: AppTheme.red(context)),
                title: Text(AppLocalizations.of(context)!.serversDeleteServer, style: TextStyle(color: AppTheme.red(context))),
                onTap: () { Navigator.pop(context); onDelete(); },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showHealthCheckSheet(BuildContext context) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bg(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => FutureBuilder<List<({String name, bool ok, String details})>>(
        future: _runHealthCheck(),
        builder: (ctx, snapshot) {
          final loading = snapshot.connectionState != ConnectionState.done;
          final checks = snapshot.data ?? const <({String name, bool ok, String details})>[];
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
                        color: AppTheme.textLight(context).withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Health check',
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
                    style: TextStyle(fontSize: 12, color: AppTheme.textLight(context)),
                  ),
                  const SizedBox(height: 14),
                  if (loading)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: CircularProgressIndicator(color: AppTheme.accent(context)),
                      ),
                    )
                  else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: successCount == checks.length
                            ? AppTheme.green(context).withValues(alpha: 0.12)
                            : AppTheme.orange(context).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: successCount == checks.length
                              ? AppTheme.green(context).withValues(alpha: 0.35)
                              : AppTheme.orange(context).withValues(alpha: 0.35),
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
                                ? AppTheme.green(context).withValues(alpha: 0.35)
                                : AppTheme.red(context).withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              c.ok ? Icons.check_circle : Icons.error_outline,
                              size: 16,
                              color: c.ok ? AppTheme.green(context) : AppTheme.red(context),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                    style: TextStyle(fontSize: 11, color: AppTheme.textLight(context)),
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

  Future<List<({String name, bool ok, String details})>> _runHealthCheck() async {
    final checks = <({String name, bool ok, String details})>[];
    checks.add((
    name: 'Server fields',
    ok: server.address.trim().isNotEmpty && server.port > 0 && server.port <= 65535,
    details: '${server.address}:${server.port}',
    ));

    try {
      final addresses = await InternetAddress.lookup(server.address)
          .timeout(const Duration(seconds: 5));
      checks.add((
      name: 'DNS resolve',
      ok: addresses.isNotEmpty,
      details: addresses.isNotEmpty ? addresses.first.address : 'No IP resolved',
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
    final hasScheme = RegExp(r'^[a-zA-Z0-9+.-]+://').hasMatch(server.config.trim());
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
    'vless'     => const Color(0xFF4A90D9),
    'vmess'     => const Color(0xFF7B68EE),
    'trojan'    => const Color(0xFFE53935),
    'ss'        => const Color(0xFF43A047),
    'hysteria'   => const Color(0xFF00897B),
    'hysteria2'  => const Color(0xFF00695C),
    'hy2'        => const Color(0xFF004D40),
    _           => AppTheme.textLight(ctx),
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

// ????? ? RepaintBoundary, ????? ??????????? ???????????
class _WavePaintWidget extends StatelessWidget {
  final AnimationController waveCtrl;
  final AnimationController stateCtrl;
  final BuildContext context;
  final double height;

  const _WavePaintWidget({
    required this.waveCtrl,
    required this.stateCtrl,
    required this.context,
    this.height = 36,
  });

  @override
  Widget build(BuildContext context) {
    // ???????? ?????, ????? ?? ??????? Theme.of() ?? ?????? ??????
    final accentColor = AppTheme.accent(context);
    final greenColor = AppTheme.green(context);

    final compact = height <= 24;
    final large = height > 36;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([waveCtrl, stateCtrl]),
          builder: (context, _) {
            final t = stateCtrl.value;
            final color = Color.lerp(accentColor, greenColor, t)!;
            return CustomPaint(
              painter: _M3WavePainter(
                progress: waveCtrl.value,
                amplitude: _lerp(
                  compact ? 2.5 : (large ? 6.0 : 4.0),
                  compact ? 5.0 : (large ? 14.0 : 10.0),
                  t,
                ),
                strokeWidth: _lerp(
                  compact ? 2.0 : (large ? 3.0 : 2.5),
                  compact ? 3.0 : (large ? 4.5 : 4.0),
                  t,
                ),
                color: color,
              ),
              size: Size(double.infinity, height),
            );
          },
        ),
      ),
    );
  }
}

class _M3WavePainter extends CustomPainter {
  final double progress;
  final double amplitude;
  final double strokeWidth;
  final Color color;

  _M3WavePainter({
    required this.progress,
    required this.amplitude,
    required this.strokeWidth,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w   = size.width;
    final mid = size.height / 2;

    const wl = 56.0;
    final path = Path();
    for (double x = 0; x <= w; x += 1.0) {
      final y = mid + amplitude * sin(2 * pi * (x / wl - progress));
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color       = color
        ..strokeWidth = strokeWidth
        ..strokeCap   = StrokeCap.round
        ..style       = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_M3WavePainter old) =>
      old.progress    != progress    ||
          old.amplitude   != amplitude   ||
          old.strokeWidth != strokeWidth ||
          old.color       != color;
}

double _lerp(double a, double b, double t) => a + (b - a) * t;
