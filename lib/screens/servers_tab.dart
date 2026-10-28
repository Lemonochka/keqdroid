import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/shared/extensions/build_context_l10n.dart';
import 'package:keqdroid/shared/ui/app_theme.dart';
import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:keqdroid/shared/ui/expressive_group.dart';
import 'package:keqdroid/shared/ui/connected_status_chip.dart';
import 'package:keqdroid/shared/ui/expressive_toggle_button.dart';
import 'package:keqdroid/shared/ui/floating_bar.dart';
import 'package:keqdroid/shared/ui/halloween/halloween_icons.dart';
import 'package:keqdroid/shared/ui/halloween/halloween_sky.dart';
import 'package:keqdroid/shared/ui/halloween/pumpkin_button.dart';
import 'package:keqdroid/shared/ui/haptics.dart';
import 'package:keqdroid/shared/ui/liquid_bud.dart';
import 'package:keqdroid/shared/ui/liquid_wave.dart';
import 'package:keqdroid/shared/ui/server_group_anchors.dart';
import 'package:keqdroid/shared/ui/scroll_hidden_fab.dart';
import 'package:keqdroid/shared/ui/scroll_jump_overlay.dart';
import 'package:keqdroid/shared/ui/server_row.dart';
import 'package:keqdroid/shared/ui/shape_morph.dart';
import 'package:keqdroid/shared/ui/sliver_reveal.dart';
import 'package:keqdroid/shared/ui/smooth_fade.dart';
import 'package:keqdroid/shared/ui/shape_loading_indicator.dart';
import 'package:keqdroid/shared/ui/smooth_scroll.dart';
import 'package:keqdroid/shared/ui/stat_strip.dart';
import 'package:keqdroid/shared/ui/tv_focus.dart';
import 'package:keqdroid/shared/ui/update_interval_sheet.dart';

import '../core/app_logger.dart';
import '../core/exceptions.dart';
import '../models/app_settings.dart';
import '../models/server_group.dart';
import '../models/server_item.dart';
import '../models/server_name_utils.dart';
import '../models/subscription.dart';
import '../models/subscription_card_theme.dart';
import '../models/traffic_split.dart';
import '../providers/halloween_provider.dart';
import '../providers/providers.dart';
import '../providers/traffic_split_provider.dart';
import '../services/auto_server_select.dart';
import '../services/exit_ip_service.dart';
import '../services/file_dialog_service.dart';
import '../services/ping_service.dart';
import '../services/subscription_accent_service.dart';
import '../services/tv_handoff.dart';
import '../services/vpn_engine.dart';
import '../platform/platform_bootstrap.dart';
import '../platform/vpn_native_bridge.dart';
import '../ui/responsive/desktop_page_layout.dart';
import '../ui/responsive/window_breakpoints.dart';
import '../utils/clipboard_import.dart';
import '../utils/subscription_deep_link.dart';
import '../utils/bidi.dart';
import '../utils/error_messages.dart';
import '../utils/import_payload.dart';
import '../utils/vpn_core_support.dart';
import '../utils/server_sort.dart';
import 'qr_scan_screen.dart';
import 'tv_receive_screen.dart';
import 'tv_send_dialog.dart';
import 'servers/chain_editor.dart';
import 'servers/server_config_editor.dart';
import 'package:keqdroid/shared/ui/liquid_toast.dart';

part 'servers/server_groups.dart';
part 'servers/server_tile.dart';
part 'servers/connection_stats.dart';
part 'servers/connect_button.dart';
part 'servers/connect_panel.dart';
part 'servers/server_plaque.dart';

// с выбранным сервером состояние показывает плашка, сюда доходят ошибка и «нет сервера»
Widget _serversStatusText(
  BuildContext context,
  VpnStatus status,
  String? errorMessage,
  ServerItem? activeServer,
) {
  final l10n = AppLocalizations.of(context)!;
  final textTheme = Theme.of(context).textTheme;
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
    VpnStatus.connected => l10n.vpnConnectedGeneric,
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
    style: textTheme.bodyMedium?.copyWith(
      color: AppTheme.textLight(context),
    ),
  );
}

class _ConnectHeader extends ConsumerWidget {
  const _ConnectHeader({
    super.key,
    required this.waveCtrl,
    required this.onToggle,
    required this.onJumpToActive,
    required this.plaqueKey,
    required this.buttonKey,
  });

  final AnimationController waveCtrl;

  final void Function(VpnStatus) onToggle;
  final VoidCallback onJumpToActive;

  // из плашки (легаси) или кнопки (модерн) вытекает строка трафика
  final GlobalKey plaqueKey;
  final GlobalKey buttonKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modern = ref.watch(
      settingsNotifierProvider.select(
        (a) => a.value?.modernConnectPanel ?? false,
      ),
    );
    if (modern) {
      return _ModernConnectPanel(
        waveCtrl: waveCtrl,
        onToggle: onToggle,
        onJumpToActive: onJumpToActive,
        buttonKey: buttonKey,
      );
    }
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
    final exitLookup = ref.watch(exitIpProvider);
    final exit = exitLookup.isLoading ? null : exitLookup.value;
    final isConnected =
        vpnStatus == VpnStatus.connected && !serverSwitchInProgress;
    final isConnecting =
        serverSwitchInProgress || vpnStatus == VpnStatus.connecting;
    // по нему, а не по пустой строке внутри: включённая в настройках статистика тоже выплывает
    final hasStats = ref.watch(
      settingsNotifierProvider.select((async) {
        final s = async.value ?? const AppSettings();
        return s.showTrafficStats || s.showTrafficSplit || s.showConnectionTime;
      }),
    );

    // connecting тапабелен: это отмена попытки
    final VoidCallback? onTap =
        vpnStatus == VpnStatus.disconnecting ? null : () => onToggle(vpnStatus);
    final halloween = ref.watch(halloweenActiveProvider);

    final isDesktop = PlatformBootstrap.isDesktop;
    final topPad = isDesktop ? 20.0 : MediaQuery.of(context).padding.top + 24;
    final shownStatus =
        serverSwitchInProgress ? VpnStatus.connecting : vpnStatus;
    // вода догасает ниже шапки: под плашкой места мало, и она обрывалась. снизу пустой
    // отступ списка или ничего, а непрозрачные карточки ложатся поверх
    const overhang = 44.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          bottom: -overhang,
          child: IgnorePointer(
            child: _HeaderLiquid(
              clock: waveCtrl,
              panel: false,
              shapesTop: topPad,
              overhang: overhang,
            ),
          ),
        ),
        Padding(
      padding: EdgeInsets.fromLTRB(24, topPad, 24, 8),
      child: Column(
        children: [
              RepaintBoundary(
                child: halloween
                    // ошибку показывает только тыква, при смене сервера она ложная
                    ? HalloweenSky(
                        child: PumpkinConnectButton(
                          isConnected: isConnected,
                          isConnecting: isConnecting,
                          isError: vpnStatus == VpnStatus.error && !serverSwitchInProgress,
                          onTap: onTap,
                        ),
                      )
                    : _ConnectButton(
                        isConnected: isConnected,
                        isConnecting: isConnecting,
                        onTap: onTap,
                      ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: _ServersTabState._statusAreaHeight(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: AnimatedSwitcher(
                    duration: ExpressiveMotion.durationFast,
                    child: activeServer != null &&
                            shownStatus != VpnStatus.error
                        ? Center(
                            key: const ValueKey('plaque'),
                            child: _StatusServerPlaque(
                              server: activeServer,
                              status: shownStatus,
                              exit: exit,
                              onJumpToActive: onJumpToActive,
                              serverKey: plaqueKey,
                            ),
                          )
                        : _serversStatusText(
                            context,
                            shownStatus,
                            serverSwitchInProgress ? null : vpnErrorMessage,
                            activeServer,
                          ),
                  ),
                ),
              ),
              if (vpnStatus == VpnStatus.error &&
                  vpnErrorMessage != null &&
                  !serverSwitchInProgress)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    friendlyError(vpnErrorMessage, context),
                    textAlign: TextAlign.center,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.red(context)),
                  ),
                ),
              _StatsBud(
                shown: isConnected && hasStats,
                source: plaqueKey,
                sourceRadius: _plaqueHeight / 2,
                sourceColor: isConnected
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const _ConnectionStats(),
              ),
          // место под воду у дна шапки
          const SizedBox(height: 24),
        ],
      ),
    ),
      ],
    );
  }
}

class ServersTab extends ConsumerStatefulWidget {
  const ServersTab({super.key});

  @override
  ConsumerState<ServersTab> createState() => _ServersTabState();
}

class _ServersTabState extends ConsumerState<ServersTab>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _waveCtrl;
  late final AnimationController _stateCtrl;

  static const _waveSettleGrace = Duration(seconds: 2);
  Timer? _waveSettleTimer;

  bool _handlingLaunchAction = false;
  bool _appInForeground = true;

  final _headerKey = GlobalKey();
  final _plaqueKey = GlobalKey();
  final _buttonKey = GlobalKey();
  final _listKey = GlobalKey();

  static const double _headerPaneWidth = 360;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    VpnNativeBridge.registerLaunchHandler(_onNativeMethodCall);
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _stateCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    // после возврата из трея вкладка строится заново, а listener ловит только смену статуса
    final initialStatus = ref.read(vpnStateProvider).value?.status;
    final initiallyActive =
        initialStatus == VpnStatus.connected ||
        initialStatus == VpnStatus.connecting ||
        initialStatus == VpnStatus.disconnecting;
    _stateCtrl.value = initiallyActive ? 1.0 : 0.0;
    _stateCtrl.addStatusListener((status) {
      if (status != AnimationStatus.dismissed) return;
      _waveSettleTimer?.cancel();
      _waveSettleTimer = Timer(_waveSettleGrace, () {
        if (mounted) _syncHeaderAnimations();
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(serversProvider.notifier).autoPingAll());
      if (Platform.isAndroid) {
        unawaited(_checkLaunchAction());
      }
      unawaited(_checkPendingDeepLink());
      _syncHeaderAnimations();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    VpnNativeBridge.registerLaunchHandler(null);
    _waveSettleTimer?.cancel();
    _waveCtrl.dispose();
    _stateCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // на десктопе inactive значит окно видно без фокуса, Windows при развороте из трея часто шлёт только его
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final background = state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        (!isDesktop && state == AppLifecycleState.inactive);

    if (background) {
      _appInForeground = false;
      _syncHeaderAnimations();
    } else {
      _appInForeground = true;
      _syncHeaderAnimations();
      if (state == AppLifecycleState.resumed) {
        unawaited(ref.read(serversProvider.notifier).autoPingAll());
      }
      if (Platform.isAndroid && state == AppLifecycleState.resumed) {
        unawaited(_syncVpnStateFromNative());
        unawaited(_checkLaunchAction());
        unawaited(_checkPendingDeepLink());
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

  void _syncConnectButtonAnimation() {
    final status = ref.read(vpnStateProvider).value?.status;
    final active =
        status == VpnStatus.connected ||
        status == VpnStatus.connecting ||
        status == VpnStatus.disconnecting;
    // снапшоты из натива приходят и при обычном подключении, жёсткий value= обрывал морф волны
    final target = active ? 1.0 : 0.0;
    final atTarget = _stateCtrl.value == target && !_stateCtrl.isAnimating;
    final movingToTarget = active
        ? _stateCtrl.status == AnimationStatus.forward
        : _stateCtrl.status == AnimationStatus.reverse;
    if (!atTarget && !movingToTarget) {
      if (active) {
        _stateCtrl.forward();
      } else {
        _stateCtrl.reverse();
      }
    }
    _syncHeaderAnimations();
  }

  Future<void> _syncVpnStateFromNative() async {
    await ref.read(vpnStateProvider.notifier).syncFromNative();
    if (!mounted) return;
    _syncConnectButtonAnimation();
  }

  void _syncHeaderAnimations() {
    final status = ref.read(vpnStateProvider).value?.status;
    final vpnActive =
        status == VpnStatus.connecting ||
        status == VpnStatus.disconnecting ||
        status == VpnStatus.connected;
    // ровную волну не крутим: на Linux без GPU такая анимация ела почти половину ядра
    final settled = !vpnActive &&
        _stateCtrl.isDismissed &&
        _waveSettleTimer?.isActive != true;
    final run =
        _appInForeground && (vpnActive || (_serversTabVisible && !settled));
    if (run) {
      if (!_waveCtrl.isAnimating) _waveCtrl.repeat();
    } else {
      _waveCtrl.stop();
    }
  }

  Future<void> _onNativeMethodCall(MethodCall call) async {
    if (call.method == 'onLaunchAction') {
      await _checkLaunchAction();
      return;
    }
    if (call.method == 'onDeepLink') {
      final url = ((call.arguments as Map?)?['url'] as String?)?.trim();
      if (url != null && url.isNotEmpty) {
        await _importDeepLink(url);
      } else {
        await _checkPendingDeepLink();
      }
      return;
    }
    if (call.method == 'onVpnStatusSnapshot') {
      try {
        await ref.read(vpnStateProvider.notifier).syncFromNative();
        if (!mounted) return;
        _syncConnectButtonAnimation();
      } catch (e, st) {
        AppLogger.instance.debug('Failed to sync VPN state from native', error: e, stackTrace: st);
      }
    }
  }

  Future<void> _checkPendingDeepLink() async {
    if (!VpnNativeBridge.supportsDeepLinks) return;
    try {
      final url = (await VpnNativeBridge.getPendingDeepLink())?.trim();
      if (url == null || url.isEmpty || !mounted) return;
      await _importDeepLink(url);
    } catch (e, st) {
      AppLogger.instance.debug(
        'Failed to handle pending deep link',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _addSubscriptionFromUrl(BuildContext ctx, String url) async {
    final host = Uri.tryParse(url)?.host ?? url;
    try {
      final sub = Subscription.create(name: host, url: url, nameIsAuto: true);
      await ref.read(subscriptionsProvider.notifier).add(sub);
      if (ctx.mounted) {
        _showSnack(AppLocalizations.of(ctx)!.qrSubscriptionAdded(host));
      }
    } catch (e) {
      if (ctx.mounted) _showImportError(ctx, e);
    }
  }

  Future<void> _importDeepLink(String raw) async {
    if (!mounted) return;
    final tv = TvPairing.parse(raw);
    if (tv != null) {
      await sendSubscriptionToTv(context, ref, tv);
      return;
    }
    final subUrl = subscriptionUrlFromDeepLink(raw);
    if (subUrl != null) {
      await _addSubscriptionFromUrl(context, subUrl);
      return;
    }
    final result = await _addConfigsResilient([raw]);
    if (!mounted) return;
    if (result.firstError != null) {
      _showImportError(context, result.firstError!);
    } else {
      _showSnack(
        AppLocalizations.of(context)!.serversImportedSummary(result.added, 1),
      );
    }
  }

  Future<void> _checkLaunchAction() async {
    if (!Platform.isAndroid || _handlingLaunchAction) return;
    _handlingLaunchAction = true;

    try {
      final action = await VpnNativeBridge.getLaunchAction();
      if (action != 'connect_from_notification' &&
          action != 'disconnect_from_shortcut') {
        return;
      }

      await VpnNativeBridge.clearLaunchAction();

      if (!mounted) return;

      // VPN мог подняться из уведомления или плитки, второй connect() не нужен
      await ref.read(vpnStateProvider.notifier).syncFromNative();
      if (!mounted) return;
      final currentStatus = ref.read(vpnStateProvider).value?.status;

      // лаунчер умеет запускать только активности, поэтому ярлык отключения идёт через приложение
      if (action == 'disconnect_from_shortcut') {
        if (currentStatus == VpnStatus.connected ||
            currentStatus == VpnStatus.connecting) {
          await ref.read(vpnStateProvider.notifier).disconnect();
        }
        _syncConnectButtonAnimation();
        return;
      }

      if (currentStatus == VpnStatus.connected ||
          currentStatus == VpnStatus.connecting) {
        _syncConnectButtonAnimation();
        return;
      }

      final active = ref.read(serversProvider).activeServer;
      if (active == null) {
        _showSnack(context.l10n.vpnSelectServerFirst);
        return;
      }

      await ref.read(vpnStateProvider.notifier).connect();
    } catch (e, st) {
      AppLogger.instance.error(
        'Failed to handle launch action',
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
        });
      }

      if (nextStatus == VpnStatus.connecting ||
          nextStatus == VpnStatus.disconnecting) {
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

    final isDesktop = PlatformBootstrap.isDesktop;
    final twoPane = WindowBreakpoints.isExpandedMobile(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    // ключи переносят шапку и список между раскладками при повороте вместе с состоянием
    final header = _ConnectHeader(
      key: _headerKey,
      waveCtrl: _waveCtrl,
      onToggle: _toggleVpn,
      onJumpToActive: _jumpToActiveServer,
      plaqueKey: _plaqueKey,
      buttonKey: _buttonKey,
    );

    final modern = ref.watch(
      settingsNotifierProvider.select(
        (a) => a.value?.modernConnectPanel ?? false,
      ),
    );
    final listArea = _ListEdgeFade(
      underPanel: modern && !twoPane,
      child: _ServersListPanel(
        key: _listKey,
        topPadding: _listTopPadding,
        onSelectServer: _selectServer,
        emptyState: _emptyState(),
      ),
    );

    if (twoPane) {
      return Row(
        children: [
          SizedBox(
            width: _headerPaneWidth,
            child: Center(
              child: SingleChildScrollView(
                clipBehavior: Clip.none,
                child: header,
              ),
            ),
          ),
          Expanded(
            child: SafeArea(
              bottom: false,
              child: _withListChrome(context, listArea, bottomInset),
            ),
          ),
        ],
      );
    }

    Widget body = Column(
      children: [
        header,
        Expanded(child: listArea),
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

    return HalloweenIconScope(child: _withListChrome(context, body, bottomInset));
  }

  Widget _withListChrome(BuildContext context, Widget child, double bottomInset) {
    final isDesktop = PlatformBootstrap.isDesktop;
    final floating = FloatingBar.shown(context);
    final owned = FloatingBar.owns(context);
    if (owned) {
      FloatingBar.actions[0] = () => _showAddServerDialog(context);
    }
    return ValueListenableBuilder<double>(
      valueListenable: FloatingBar.bottomInset,
      builder: (context, barInset, child) => ScrollJumpOverlay(
      enabled: !isDesktop,
      endLabel: context.l10n.serversScrollToEnd,
      topLabel: context.l10n.serversScrollToTop,
      bottomInset: floating
          ? FloatingBar.clearance(context) + 12
          : 20 + bottomInset,
      child: SizedBox.expand(
          child: floating
              ? FloatingBarHideOnScroll(child: child!)
              : owned
              ? child!
              : ScrollHiddenFab(
                  bottom: 16 + bottomInset,
                  fab: TvFocus.fab(
                    (fabContext) => FloatingActionButton(
                      heroTag: 'servers_add_server_fab',
                      backgroundColor: AppTheme.accentContainer(fabContext),
                      foregroundColor: AppTheme.onAccentContainer(fabContext),
                      onPressed: () => _showAddServerDialog(context),
                      child: const SeasonalIcon(Icons.add_rounded),
                    ),
                  ),
                  child: child!,
                ),
        ),
      ),
      child: child,
    );
  }

  int get _chainCandidateCount {
    final core = preferredBackend(
      ref.read(settingsNotifierProvider).value?.vpnCore ??
          AppSettings.vpnCoreXray,
    );
    return ref
        .read(serversProvider)
        .servers
        .where((s) => chainHopBackends(s.config).contains(core))
        .length;
  }

  void _showAddServerDialog(BuildContext ctx) {
    final l10n = AppLocalizations.of(ctx)!;
    showModalBottomSheet<void>(
      context: ctx,
      showDragHandle: true,
      // без этого шторка не выше 9/16 экрана, и на телевизоре пункты обрезались
      isScrollControlled: true,
      builder: (ctx2) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                l10n.serversAddServer,
                textAlign: TextAlign.center,
                style: Theme.of(ctx).textTheme
                    .emphasized(Theme.of(ctx).textTheme.titleLarge)
                    ?.copyWith(color: AppTheme.text(ctx)),
              ),
            ),
            ExpressiveGroup(
              children: [
                ExpressiveActionTile(
                  icon: Icons.link_rounded,
                  title: l10n.serversPasteLinks,
                  subtitle: l10n.serversPasteLinksHint,
                  accent: ExpressiveAccent.primary,
                  onTap: () {
                    Navigator.pop(ctx2);
                    _showPasteLinksSheet(ctx);
                  },
                ),
                ExpressiveActionTile(
                  icon: Icons.description_rounded,
                  title: l10n.serversImportFile,
                  subtitle: 'AmneziaWG (.conf)',
                  accent: ExpressiveAccent.secondary,
                  onTap: () {
                    Navigator.pop(ctx2);
                    _importConfigFile(ctx);
                  },
                ),
                if (PlatformBootstrap.isTelevision)
                  ExpressiveActionTile(
                    icon: Icons.install_mobile_rounded,
                    title: l10n.tvReceiveTitle,
                    subtitle: l10n.tvReceiveSubtitle,
                    accent: ExpressiveAccent.tertiary,
                    onTap: () {
                      Navigator.pop(ctx2);
                      unawaited(TvReceiveScreen.open(ctx));
                    },
                  )
                else if (!PlatformBootstrap.isDesktop)
                  ExpressiveActionTile(
                    icon: Icons.qr_code_scanner_rounded,
                    title: l10n.qrScanTitle,
                    subtitle: l10n.serversScanQrHint,
                    accent: ExpressiveAccent.tertiary,
                    onTap: () {
                      Navigator.pop(ctx2);
                      _scanQrAndImport(ctx);
                    },
                  ),
                if (_chainCandidateCount >= 2)
                  ExpressiveActionTile(
                    icon: Icons.route_rounded,
                    title: l10n.chainCreate,
                    subtitle: l10n.chainCreateDesc,
                    onTap: () {
                      Navigator.pop(ctx2);
                      Navigator.of(ctx).push(
                        MaterialPageRoute<void>(
                          fullscreenDialog: true,
                          builder: (_) => const ChainEditorScreen(),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scanQrAndImport(BuildContext ctx) async {
    final raw = await QrScanScreen.scan(ctx);
    if (raw == null || raw.isEmpty || !ctx.mounted) return;

    final tv = TvPairing.parse(raw);
    if (tv != null) {
      await sendSubscriptionToTv(ctx, ref, tv);
      return;
    }

    final asUri = Uri.tryParse(raw);
    if (asUri != null && (asUri.scheme == 'http' || asUri.scheme == 'https')) {
      await _addSubscriptionFromUrl(ctx, raw);
      return;
    }

    final configs = splitServerImportPayload(raw);
    final result = await _addConfigsResilient(configs);
    if (!ctx.mounted) return;
    if (result.firstError != null) {
      _showImportSummary(
        ctx,
        summary: AppLocalizations.of(ctx)!
            .serversImportedSummary(result.added, configs.length),
        anyAdded: result.added > 0,
        error: result.firstError!,
      );
    } else {
      _showSnack(
        AppLocalizations.of(ctx)!
            .serversImportedSummary(result.added, configs.length),
      );
    }
  }

  Future<void> _importConfigFile(BuildContext ctx) async {
    String? content;
    try {
      final file = await AppFileDialogs.pickFile(
        dialogTitle: AppLocalizations.of(ctx)!.serversImportFile,
        type: FileType.any,
      );
      if (file == null) return;
      if (file.path != null && file.path!.isNotEmpty) {
        content = await File(file.path!).readAsString();
      } else {
        content = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      }
    } catch (e) {
      if (!ctx.mounted) return;
      _showImportError(
        ctx,
        e,
        detailed: e is FileDialogUnavailableException,
        action: e is FileDialogUnavailableException
            ? SnackBarAction(
                label: AppLocalizations.of(ctx)!.serversPasteLinks,
                onPressed: () {
                  if (ctx.mounted) _showPasteLinksSheet(ctx);
                },
              )
            : null,
      );
      return;
    }

    final raw = content.trim();
    if (raw.isEmpty) return;

    final configs = splitServerImportPayload(raw);

    // по одной: на первом дубликате остальные строки терялись
    final result = await _addConfigsResilient(configs);
    if (!ctx.mounted) return;
    if (result.firstError != null) {
      _showImportSummary(
        ctx,
        summary: AppLocalizations.of(ctx)!
            .serversImportedSummary(result.added, configs.length),
        anyAdded: result.added > 0,
        error: result.firstError!,
      );
    }
  }

  Future<({int added, Object? firstError})> _addConfigsResilient(
    List<String> configs,
  ) async {
    var added = 0;
    Object? firstError;
    for (final c in configs) {
      try {
        await ref.read(serversProvider.notifier).addManual(c);
        added++;
      } catch (e) {
        firstError ??= e;
      }
    }
    return (added: added, firstError: firstError);
  }

  void _showImportError(
    BuildContext ctx,
    Object e, {
    bool detailed = false,
    SnackBarAction? action,
  }) {
    AppSnack.of(ctx).showSnackBar(
      SnackBar(
        content: Text(
          detailed ? friendlyErrorDetailed(e, ctx) : _shortError(e, ctx),
        ),
        backgroundColor: AppTheme.red(ctx),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ExpressiveShape.medium)),
        action: action,
        duration: Duration(seconds: action != null ? 10 : 5),
      ),
    );
  }

  void _showImportSummary(
    BuildContext ctx, {
    required String summary,
    required bool anyAdded,
    required Object error,
  }) {
    AppSnack.of(ctx).showSnackBar(
      SnackBar(
        content: Text('$summary\n${_shortError(error, ctx)}'),
        backgroundColor: anyAdded ? AppTheme.orange(ctx) : AppTheme.red(ctx),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ExpressiveShape.medium)),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _showPasteLinksSheet(BuildContext ctx) {
    final l10n = AppLocalizations.of(ctx)!;
    final ctrl = TextEditingController();
    bool loading = false;
    // снек-бар был бы скрыт за модальным барьером
    String? sheetError;
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      showDragHandle: true,
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
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(color: AppTheme.text(ctx)),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.serversPasteVlessHint,
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: AppTheme.textLight(ctx)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                textDirection: technicalInputDirection,
                autofocus: true,
                maxLines: 4,
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: AppTheme.text(ctx)),
                decoration: InputDecoration(
                  hintText: l10n.serversPasteHint,
                  hintStyle: TextStyle(
                    color: AppTheme.textLight(ctx).withValues(alpha: 0.5),
                  ),
                  filled: true,
                  fillColor: AppTheme.card(ctx),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ExpressiveShape.large),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ExpressiveShape.large),
                    borderSide: BorderSide(
                      color: AppTheme.accent(ctx),
                      width: 2,
                    ),
                  ),
                ),
              ),
              if (sheetError != null) ...[
                const SizedBox(height: 8),
                Text(
                  sheetError!,
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: AppTheme.red(ctx)),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentContainer(ctx),
                    foregroundColor: AppTheme.onAccentContainer(ctx),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ExpressiveShape.large),
                    ),
                  ),
                  onPressed: loading
                      ? null
                      : () async {
                          final raw = ctrl.text.trim();
                          if (raw.isEmpty) return;
                          setModalState(() {
                            loading = true;
                            sheetError = null;
                          });
                          final result = await importPastedLinksInto(ref, raw);
                          if (!ctx2.mounted) return;
                          if (result.firstError == null) {
                            Navigator.pop(ctx2);
                            return;
                          }
                          if (result.added > 0) {
                            Navigator.pop(ctx2);
                            if (ctx.mounted) {
                              _showImportSummary(
                                ctx,
                                summary: pastedLinksSummary(l10n, result)!,
                                anyAdded: true,
                                error: result.firstError!,
                              );
                            }
                          } else {
                            setModalState(() {
                              loading = false;
                              sheetError = ctx.mounted
                                  ? _shortError(result.firstError!, ctx)
                                  : _shortError(result.firstError!);
                            });
                          }
                        },
                  child: loading
                      ? ShapeLoadingIndicator(
                          size: 20,
                          color: AppTheme.onAccentContainer(ctx),
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

  static const double _statusChipVerticalPadding = 8;
  static const double _statusChipChrome = _statusChipVerticalPadding * 2;

  // тот же стиль идёт в расчёт высоты, иначе вторая строка имени обрезается
  static TextStyle? _statusChipTextStyle(TextTheme textTheme) =>
      textTheme.emphasized(textTheme.labelLarge);

  static double _statusAreaHeight(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    double twoLines(TextStyle? style) {
      final size = style?.fontSize ?? 14;
      return scaler.scale(size) * (style?.height ?? 1.2) * 2;
    }

    return max(
      twoLines(textTheme.bodyMedium),
      twoLines(_statusChipTextStyle(textTheme)) + _statusChipChrome,
    );
  }


  Widget _emptyState() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_rounded,
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
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textLight(context)),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accentContainer(context),
              foregroundColor: AppTheme.onAccentContainer(context),
            ),
            onPressed: () => _showAddServerDialog(context),
            icon: const SeasonalIcon(Icons.add_rounded, size: 18),
            label: Text(l10n.serversAddServer),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => pasteLinksFromClipboard(context, ref),
            icon: Icon(
              Icons.content_paste_rounded,
              size: 16,
              color: AppTheme.accent(context),
            ),
            label: Text(
              l10n.serversPasteLinks,
              style: TextStyle(color: AppTheme.accent(context)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectServer(ServerItem server) async {
    final vpnStatus = ref.read(vpnStateProvider).value?.status;
    final tunnelActive =
        vpnStatus == VpnStatus.connected || vpnStatus == VpnStatus.connecting;
    if (tunnelActive &&
        server.id == ref.read(serversProvider).activeServer?.id) {
      return;
    }
    final subs = ref.read(subscriptionsProvider).value ?? const [];
    if (subs.any((s) => s.autoSelect)) {
      unawaited(ref.read(subscriptionsProvider.notifier).handAutoSelectTo(null));
    }
    await ref.read(serversProvider.notifier).setActive(server);
    if (tunnelActive) {
      try {
        await ref.read(vpnStateProvider.notifier).reconnectToActiveServer();
      } catch (e) {
        if (!mounted) return;
        _showSnack(_shortError(e, context));
      }
    }
  }

  // ensureVisible тут не сработает: строки ленивые, у недолистанного сервера нет render object
  Future<void> _jumpToActiveServer() async {
    final id = ref.read(serversProvider).activeServerId;
    if (id == null) return;
    final anchors = ServerGroupAnchors.instance;
    final place = anchors.placeOfServer(id);
    if (place == null) return;
    if (place.collapsed) {
      ref
          .read(collapsedServerGroupsProvider.notifier)
          .update((m) => {...m, place.groupKey: false});
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    await anchors.jumpToServer(id);
  }

  Future<void> _toggleVpn(VpnStatus status) async {
    if (status == VpnStatus.connected) {
      try {
        await ref.read(vpnStateProvider.notifier).disconnect();
      } catch (e) {
        if (!mounted) return;
        _showSnack(_shortError(e, context));
      }
    } else if (status == VpnStatus.connecting) {
      try {
        await ref.read(vpnStateProvider.notifier).cancelConnect();
      } catch (e) {
        if (!mounted) return;
        _showSnack(_shortError(e, context));
      }
    } else if (status == VpnStatus.disconnecting) {
      return;
    } else {
      final active = ref.read(serversProvider).activeServer;
      if (active == null) {
        _showSnack(context.l10n.vpnSelectServerFirst);
        return;
      }
      try {
        await ref.read(vpnStateProvider.notifier).connect();
      } catch (e) {
        if (!mounted) return;
        _showSnack(_shortError(e, context));
      }
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    AppSnack.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppTheme.text(context),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ExpressiveShape.medium)),
      ),
    );
  }
}

