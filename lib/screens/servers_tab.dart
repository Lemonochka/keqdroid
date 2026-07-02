import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:country_flags/country_flags.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/shared/extensions/build_context_l10n.dart';
import 'package:keqdroid/shared/ui/app_theme.dart';
import 'package:keqdroid/shared/ui/smooth_scroll.dart';

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
import '../utils/awg_profile.dart';
import '../utils/error_messages.dart';

part 'servers/server_groups.dart';
part 'servers/server_tile.dart';
part 'servers/vpn_stats_debug.dart';
part 'servers/wave_header.dart';

class ServersTab extends ConsumerStatefulWidget {
  const ServersTab({super.key});

  @override
  ConsumerState<ServersTab> createState() => _ServersTabState();
}

class _ServersTabState extends ConsumerState<ServersTab>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _breathCtrl;
  late final Animation<double> _breathAnim;
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
    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _breathAnim = Tween<double>(
      begin: 1.0,
      end: 1.05,
    ).animate(CurvedAnimation(parent: _breathCtrl, curve: Curves.easeInOut));
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _stateCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    // Seed the connected/disconnected wave style from the current VPN status.
    // Without this, reopening from the tray rebuilds this tab fresh while the
    // VPN is still connected — and since the listener only reacts to status
    // *changes*, the wave would stay stuck in the disconnected style.
    final initialStatus = ref.read(vpnStateProvider).value?.status;
    final initiallyActive =
        initialStatus == VpnStatus.connected ||
        initialStatus == VpnStatus.connecting ||
        initialStatus == VpnStatus.disconnecting;
    _stateCtrl.value = initiallyActive ? 1.0 : 0.0;

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
    // На десктопе `inactive` = окно ВИДИМО, но не в фокусе (клик по другому окну,
    // разворот из трея через таскбар). Раньше `inactive` считался «фоном» и глушил
    // анимацию линии подключения. При возврате через таскбар Windows нередко
    // доставляет только `inactive` (а `resumed` — лишь при получении фокуса), так
    // что линия оставалась замороженной. Поэтому фоном на десктопе считаем только
    // `hidden`/`paused` (реально свёрнуто/скрыто в трей); `inactive` = передний план.
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final background = state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        (!isDesktop && state == AppLifecycleState.inactive);

    if (background) {
      _appInForeground = false;
      _syncHeaderAnimations();
    } else {
      // resumed, либо (на десктопе) inactive — окно на переднем плане
      _appInForeground = true;
      _syncHeaderAnimations();
      if (Platform.isAndroid && state == AppLifecycleState.resumed) {
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
    final vpnActive =
        status == VpnStatus.connecting ||
        status == VpnStatus.disconnecting ||
        status == VpnStatus.connected;
    // Крутим бесконечные анимации (60fps) только когда окно на переднем плане.
    // Раньше при vpnActive они продолжались и в свёрнутом окне → движок рендерил
    // в фоне и жёг 3-4% CPU. При возврате из трея (resumed) анимация перезапустится.
    final run = _appInForeground && (_serversTabVisible || vpnActive);
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

      final wasActive =
          prevStatus == VpnStatus.connected ||
          prevStatus == VpnStatus.connecting ||
          prevStatus == VpnStatus.disconnecting;
      final isActiveNow =
          nextStatus == VpnStatus.connected ||
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

    final onServersTab =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS
        ? ref.watch(homeTabIndexProvider.select((i) => i == 0))
        : ref.watch(homeTabPageProvider.select((p) => p < 0.05));
    final headerAnimationsEnabled = onServersTab && _appInForeground;

    final vpnStatus = ref.watch(
      vpnStateProvider.select((a) => a.value?.status ?? VpnStatus.disconnected),
    );
    final vpnErrorMessage = ref.watch(
      vpnStateProvider.select((a) => a.value?.errorMessage),
    );
    final serverSwitchInProgress = ref.watch(vpnServerSwitchInProgressProvider);
    final activeServer = ref.watch(
      serversProvider.select((s) => s.activeServer),
    );

    // При смене сервера на активном VPN движок на миг проходит через
    // `disconnected` (старый сервер отключается перед подключением нового).
    // Без учёта serverSwitchInProgress круг проваливался в серый «неактивный»
    // вид (spinner → серый → spinner). Пока идёт переключение — держим круг в
    // состоянии «подключается», чтобы переход был одной плавной дугой.
    final isConnected =
        vpnStatus == VpnStatus.connected && !serverSwitchInProgress;
    final isConnecting =
        serverSwitchInProgress ||
        vpnStatus == VpnStatus.connecting ||
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
                            ? Border.all(
                                color: AppTheme.divider(context),
                                width: 1,
                              )
                            : Border.all(
                                color: AppTheme.accent(
                                  context,
                                ).withValues(alpha: 0.45),
                                width: 2,
                              ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                (isConnected || isConnecting
                                        ? AppTheme.accent(context)
                                        : AppTheme.card(context))
                                    .withValues(alpha: 0.35),
                            blurRadius: 30,
                            spreadRadius: 6,
                          ),
                        ],
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: Tween<double>(
                              begin: 0.7,
                              end: 1.0,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: isConnecting
                            ? Padding(
                                key: const ValueKey('spinner'),
                                padding: const EdgeInsets.all(36),
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: AppTheme.accent(context),
                                ),
                              )
                            : Icon(
                                isConnected ? Icons.pause : Icons.play_arrow,
                                key: ValueKey(isConnected ? 'pause' : 'play'),
                                size: 52,
                                color: isConnected
                                    ? AppTheme.onAccentContainer(context)
                                    : AppTheme.text(context),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                constraints: const BoxConstraints(minHeight: 36, maxHeight: 56),
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
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.red(context),
                    ),
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
            children: [
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
                right: 20,
                bottom: 20,
                child: FloatingActionButton(
                  heroTag: 'servers_add_server_fab',
                  backgroundColor: AppTheme.accentContainer(context),
                  foregroundColor: AppTheme.onAccentContainer(context),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
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
            Text(
              l10n.serversAddServer,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.text(ctx),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.link, color: AppTheme.accent(ctx)),
              title: Text(
                l10n.serversPasteLinks,
                style: TextStyle(color: AppTheme.text(ctx)),
              ),
              subtitle: Text(
                'vless, vmess, trojan, ss, hysteria2, hy2',
                style: TextStyle(fontSize: 12, color: AppTheme.textLight(ctx)),
              ),
              onTap: () {
                Navigator.pop(ctx2);
                _showPasteLinksSheet(ctx);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.description_outlined,
                color: AppTheme.accent(ctx),
              ),
              title: Text(
                l10n.serversImportFile,
                style: TextStyle(color: AppTheme.text(ctx)),
              ),
              subtitle: Text(
                'AmneziaWG (.conf)',
                style: TextStyle(fontSize: 12, color: AppTheme.textLight(ctx)),
              ),
              onTap: () {
                Navigator.pop(ctx2);
                _importConfigFile(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Импорт серверного конфига из файла (AmneziaWG `.conf` или список ссылок).
  Future<void> _importConfigFile(BuildContext ctx) async {
    String? content;
    try {
      final file = await FilePicker.pickFile(type: FileType.any);
      if (file == null) return;
      if (file.path != null && file.path!.isNotEmpty) {
        content = await File(file.path!).readAsString();
      } else {
        content = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      }
    } catch (e) {
      if (ctx.mounted) _showImportError(ctx, e);
      return;
    }

    final raw = content.trim();
    if (raw.isEmpty) return;

    // AmneziaWG .conf — единый многострочный блок; иначе список ссылок построчно.
    final configs = AwgProfile.isAwgConfig(raw)
        ? [raw]
        : raw
              .split('\n')
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty)
              .toList();

    try {
      for (final c in configs) {
        await ref.read(serversProvider.notifier).addManual(c);
      }
    } catch (e) {
      if (ctx.mounted) _showImportError(ctx, e);
    }
  }

  void _showImportError(BuildContext ctx, Object e) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(_friendlyError(e)),
        backgroundColor: AppTheme.red(ctx),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _showPasteLinksSheet(BuildContext ctx) {
    final l10n = AppLocalizations.of(ctx)!;
    final ctrl = TextEditingController();
    bool loading = false;
    showModalBottomSheet(
      context: ctx,
      backgroundColor: AppTheme.bg(ctx),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx2) => StatefulBuilder(
        builder: (ctx2, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            MediaQuery.of(ctx2).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.serversAddServerTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.text(ctx),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.serversPasteVlessHint,
                style: TextStyle(fontSize: 12, color: AppTheme.textLight(ctx)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLines: 4,
                style: TextStyle(color: AppTheme.text(ctx), fontSize: 13),
                decoration: InputDecoration(
                  hintText: l10n.serversPasteHint,
                  hintStyle: TextStyle(
                    color: AppTheme.textLight(ctx).withValues(alpha: 0.5),
                  ),
                  filled: true,
                  fillColor: AppTheme.card(ctx),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: AppTheme.accent(ctx),
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentContainer(ctx),
                    foregroundColor: AppTheme.onAccentContainer(ctx),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: loading
                      ? null
                      : () async {
                          final raw = ctrl.text.trim();
                          if (raw.isEmpty) return;
                          setModalState(() => loading = true);
                          try {
                            final configs = AwgProfile.isAwgConfig(raw)
                                ? [raw]
                                : raw
                                      .split('\n')
                                      .map((line) => line.trim())
                                      .where((line) => line.isNotEmpty)
                                      .toList();
                            for (final c in configs) {
                              await ref
                                  .read(serversProvider.notifier)
                                  .addManual(c);
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
                      : Text(
                          l10n.serversAdd,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
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
        ServerNameUtils.cleanDisplayName(activeServer.displayName),
      );
      return Container(
        key: const ValueKey('connected'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(
            color: AppTheme.accent(context).withValues(alpha: 0.5),
            width: 1.5,
          ),
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
        VpnStatus.connected => 'connected',
        VpnStatus.connecting => 'connecting',
        VpnStatus.disconnecting => 'disconnecting',
        VpnStatus.error => 'error',
        _ => activeServer != null ? 'ready' : 'no-server',
      };
      final label = switch (status) {
        VpnStatus.connecting => l10n.vpnConnecting,
        VpnStatus.disconnecting => l10n.vpnDisconnecting,
        VpnStatus.error => _vpnErrorStatusLabel(errorMessage, context),
        _ =>
          activeServer != null
              ? l10n.vpnTapToConnect(
                  ServerNameUtils.formatForDisplay(
                    ServerNameUtils.cleanDisplayName(activeServer.displayName),
                  ),
                )
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
          Icon(
            Icons.cloud_off,
            size: 48,
            color: AppTheme.accent(context).withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.serversEmptyTitle,
            style: TextStyle(color: AppTheme.textLight(context)),
          ),
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

