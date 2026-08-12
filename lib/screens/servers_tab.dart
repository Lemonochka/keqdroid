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
import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:keqdroid/shared/ui/expressive_group.dart';
import 'package:keqdroid/shared/ui/haptics.dart';
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
import '../utils/clipboard_import.dart';
import '../utils/bidi.dart';
import '../utils/error_messages.dart';
import '../utils/import_payload.dart';
import 'qr_scan_screen.dart';
import 'servers/server_config_editor.dart';
import 'servers/wave_window.dart';

part 'servers/server_groups.dart';
part 'servers/server_tile.dart';
part 'servers/connection_stats.dart';
part 'servers/connect_button.dart';
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
        unawaited(_checkPendingDeepLink());
      }
      _syncHeaderAnimations();
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
    // На десктопе `inactive` = окно ВИДИМО, но не в фокусе (клик по другому
    // окну, разворот из трея через таскбар) — считать его «фоном» нельзя:
    // при развороте через таскбар Windows нередко доставляет только `inactive`
    // (`resumed` — лишь при получении фокуса), и анимация линии подключения
    // осталась бы замороженной. Фон на десктопе — только `hidden`/`paused`
    // (реально свёрнуто/скрыто в трей).
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
    // Снапшоты из натива (onVpnStatusSnapshot, resumed) приходят и при обычном
    // подключении из приложения — жёсткое `_stateCtrl.value =` здесь обрывало
    // 600мс морф волны, уже запущенный listener'ом vpnStateProvider. Поэтому
    // доводим плавно, и только если контроллер не в цели и не едет к ней.
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
    // Бесконечные анимации (60fps) крутим только на переднем плане: в свёрнутом
    // окне движок рендерил бы их за кадром и жёг 3-4% CPU. При возврате из трея
    // (resumed) анимация перезапускается. Трей-hide (SW_HIDE = lifecycle
    // `inactive`) дополнительно гасится глобальным TickerMode в app.dart
    // (там же — kawaii-оверлей), см. desktopUiVisibleProvider.
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
      return;
    }
    if (call.method == 'onDeepLink') {
      final url = ((call.arguments as Map?)?['url'] as String?)?.trim();
      if (url != null && url.isNotEmpty) await _importDeepLink(url);
      return;
    }
    // Notification / QS tile may send a quick status snapshot via native
    // method channel when EventChannel stream isn't connected. In that case
    // trigger an explicit sync from native to update VPN state in Riverpod.
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

  /// Ссылка со схемой сервера (vless:// и т.п.), которой открыли приложение
  /// снаружи (Telegram, браузер). Холодный старт — забираем одноразовую
  /// pending-ссылку у натива; тёплый приходит пушем onDeepLink.
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

  Future<void> _importDeepLink(String raw) async {
    if (!mounted) return;
    // Тот же путь, что вставка/QR: дубликат или битая ссылка показываются
    // как ошибка импорта, а не роняют обработчик.
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

      // VPN мог уже подняться из уведомления/плитки — не запускаем второй connect().
      await ref.read(vpnStateProvider.notifier).syncFromNative();
      if (!mounted) return;
      final currentStatus = ref.read(vpnStateProvider).value?.status;

      // Ярлык «Отключить» с иконки приложения: сервис нельзя дёрнуть напрямую
      // из ярлыка (лаунчер умеет запускать только активности), поэтому
      // приложение открывается и рвёт соединение здесь.
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
        if (!_breathCtrl.isAnimating) _breathCtrl.repeat(reverse: true);
        if (!_waveCtrl.isAnimating) _waveCtrl.repeat();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncHeaderAnimations();
      });
    });

    // Видимость вкладки — только listen, НЕ watch: она влияет лишь на явные
    // контроллеры (wave/breath) через _syncHeaderAnimations, а watch
    // перестраивал бы весь таб (хедер + список) прямо в кадре свайпа.
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

    final isDesktop = PlatformBootstrap.isDesktop;
    // Высота волны ПОСТОЯННА. Раньше она ужималась на connecting/connected,
    // чтобы шапка не разрасталась от чипов трафика, но менялась мгновенно —
    // и всё выше списка прыгало и слегка уменьшалось в момент подключения.
    // Единственное, что теперь меняет высоту шапки, — появление чипов, а его
    // плавно разводит AnimatedSize ниже.
    final waveHeight = isDesktop ? 40.0 : 36.0;
    final topPad = isDesktop ? 20.0 : MediaQuery.of(context).padding.top + 24;

    final connectHeader = Padding(
      padding: EdgeInsets.fromLTRB(24, topPad, 24, 8),
      child: Column(
        children: [
              // При connected «дыхание» и blur-тень перерисовываются каждый
              // кадр — boundary не даёт им тянуть перерисовку всего хедера.
              RepaintBoundary(
                child: ScaleTransition(
                  scale: (isConnected || isConnecting)
                      ? _breathAnim
                      : const AlwaysStoppedAnimation(1.0),
                  child: _ConnectButton(
                    isConnected: isConnected,
                    isConnecting: isConnecting,
                    // connecting остаётся тапабельным — это отмена попытки;
                    // блокируем только disconnecting (гасить уже нечего).
                    onTap: vpnStatus == VpnStatus.disconnecting
                        ? null
                        : () => _toggleVpn(vpnStatus),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                // Высота под статус ФИКСИРОВАНА и рассчитана на две строки.
                // Имена серверов разной длины занимают то одну строку, то две,
                // и шапка меняла высоту при переключении сервера — волна и
                // список под ней подпрыгивали.
                height: _statusAreaHeight(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: AnimatedSwitcher(
                    duration: ExpressiveMotion.durationFast,
                    child: _statusText(
                      serverSwitchInProgress && vpnStatus == VpnStatus.error
                          ? VpnStatus.connecting
                          : vpnStatus,
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
                    _friendlyErrorDetailed(vpnErrorMessage),
                    textAlign: TextAlign.center,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.red(context)),
                  ),
                ),
              // Скорость/трафик/время. Появление плавное: AnimatedSize
              // раздвигает место (контент ниже не прыгает), а чипы всплывают
              // снизу с фейдом; дефолтный клип AnimatedSize обрезает их на
              // входе — эффект «из тумана снизу».
              AnimatedSize(
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 420),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.45),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: isConnected
                      ? const _ConnectionStats(key: ValueKey('stats'))
                      : const SizedBox(
                          key: ValueKey('stats-hidden'),
                          width: double.infinity,
                        ),
                ),
              ),
          // Отступ до волны тоже постоянный — он прыгал вместе с её высотой.
          const SizedBox(height: 20),
          _WavePaintWidget(
            waveCtrl: _waveCtrl,
            stateCtrl: _stateCtrl,
            height: waveHeight,
          ),
        ],
      ),
    );

    Widget body = Column(
      children: [
        connectHeader,
        Expanded(
          // Градиент лежит в этой же колонке, а не в общем Stack по измеренной
          // высоте шапки. Замер делался после кадра, поэтому пока шапка меняла
          // высоту (подключение убирает часть отступов и укорачивает волну),
          // градиент отставал на кадр — и из-под волны на мгновение выглядывал
          // список. Здесь верх Stack и есть низ шапки, всегда в том же кадре.
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              _ServersListPanel(
                topPadding: _listTopFadeHeight - _listTopFadeTileOverlap,
                onSelectServer: _selectServer,
                emptyState: _emptyState(),
              ),
              Positioned(
                top: -_listTopFadeUpExtension,
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
            ],
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
                    borderRadius: BorderRadius.circular(ExpressiveShape.large),
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
      showDragHandle: true,
      builder: (ctx2) => Padding(
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
                  icon: Icons.link,
                  title: l10n.serversPasteLinks,
                  subtitle: 'vless, vmess, trojan, ss, hysteria2, hy2',
                  accent: ExpressiveAccent.primary,
                  onTap: () {
                    Navigator.pop(ctx2);
                    _showPasteLinksSheet(ctx);
                  },
                ),
                ExpressiveActionTile(
                  icon: Icons.description_outlined,
                  title: l10n.serversImportFile,
                  subtitle: 'AmneziaWG (.conf)',
                  accent: ExpressiveAccent.secondary,
                  onTap: () {
                    Navigator.pop(ctx2);
                    _importConfigFile(ctx);
                  },
                ),
                // у mobile_scanner нет имплементации под Windows/Linux
                if (!PlatformBootstrap.isDesktop)
                  ExpressiveActionTile(
                    icon: Icons.qr_code_scanner,
                    title: l10n.qrScanTitle,
                    subtitle: l10n.serversScanQrHint,
                    accent: ExpressiveAccent.tertiary,
                    onTap: () {
                      Navigator.pop(ctx2);
                      _scanQrAndImport(ctx);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Импорт из QR-кода: серверные ссылки/AWG-конфиг добавляются как серверы;
  /// http(s)-ссылка — это подписка, добавляем её сразу, не гоняя пользователя
  /// на соседнюю вкладку.
  Future<void> _scanQrAndImport(BuildContext ctx) async {
    final raw = await QrScanScreen.scan(ctx);
    if (raw == null || raw.isEmpty || !ctx.mounted) return;

    final asUri = Uri.tryParse(raw);
    if (asUri != null && (asUri.scheme == 'http' || asUri.scheme == 'https')) {
      try {
        // Имя выведено из URL, а не задано — пусть его заменит название от
        // провайдера, когда оно придёт заголовком.
        final sub = Subscription.create(
          name: asUri.host,
          url: raw,
          nameIsAuto: true,
        );
        await ref.read(subscriptionsProvider.notifier).add(sub);
        if (ctx.mounted) {
          _showSnack(AppLocalizations.of(ctx)!.qrSubscriptionAdded(asUri.host));
        }
      } catch (e) {
        if (ctx.mounted) _showImportError(ctx, e);
      }
      return;
    }

    final configs = splitServerImportPayload(raw);
    final result = await _addConfigsResilient(configs);
    if (!ctx.mounted) return;
    if (result.firstError != null) {
      _showImportSummary(
        ctx,
        added: result.added,
        total: configs.length,
        error: result.firstError!,
      );
    } else {
      // после возврата с камеры без фидбека непонятно, добавилось ли что-то
      _showSnack(
        AppLocalizations.of(ctx)!
            .serversImportedSummary(result.added, configs.length),
      );
    }
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

    // AmneziaWG .conf и готовый json-конфиг ядра — единые многострочные блоки;
    // иначе список ссылок построчно.
    final configs = splitServerImportPayload(raw);

    // Каждую строку добавляем независимо: если первый же дубликат/битая
    // ссылка обрывает импорт, остальные валидные строки молча теряются.
    final result = await _addConfigsResilient(configs);
    if (!ctx.mounted) return;
    if (result.firstError != null) {
      _showImportSummary(
        ctx,
        added: result.added,
        total: configs.length,
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

  void _showImportError(BuildContext ctx, Object e) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(_friendlyError(e, ctx)),
        backgroundColor: AppTheme.red(ctx),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ExpressiveShape.medium)),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _showImportSummary(
    BuildContext ctx, {
    required int added,
    required int total,
    required Object error,
  }) {
    final summary = AppLocalizations.of(ctx)!.serversImportedSummary(added, total);
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text('$summary\n${_friendlyError(error, ctx)}'),
        backgroundColor: added > 0 ? AppTheme.orange(ctx) : AppTheme.red(ctx),
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
    // Ошибка показывается в самой шторке (snackbar был бы скрыт за модальным
    // барьером), а текст пользователя не теряется при неудаче.
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
                          final configs = splitServerImportPayload(raw);
                          // Строки добавляются независимо, чтобы первый же
                          // дубликат не обрывал импорт (шторка закрылась бы,
                          // потеряв вставленный текст).
                          final result = await _addConfigsResilient(configs);
                          if (!ctx2.mounted) return;
                          if (result.firstError == null) {
                            Navigator.pop(ctx2);
                            return;
                          }
                          if (result.added > 0) {
                            // часть добавилась — закрываем и показываем сводку
                            Navigator.pop(ctx2);
                            if (ctx.mounted) {
                              _showImportSummary(
                                ctx,
                                added: result.added,
                                total: configs.length,
                                error: result.firstError!,
                              );
                            }
                          } else {
                            // ничего не добавилось — оставляем шторку с
                            // текстом и показываем ошибку прямо в ней
                            setModalState(() {
                              loading = false;
                              sheetError = ctx.mounted
                                  ? _friendlyError(result.firstError!, ctx)
                                  : _friendlyError(result.firstError!);
                            });
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

  /// Вертикальный отступ чипа «подключено». В отличие от текста он не
  /// масштабируется вместе со шрифтом, поэтому в расчёт высоты области входит
  /// отдельным слагаемым.
  static const double _statusChipVerticalPadding = 8;
  static const double _statusChipChrome = _statusChipVerticalPadding * 2;

  /// Стиль надписи в чипе — один и тот же и в разметке, и в расчёте высоты.
  ///
  /// Держать его здесь обязательно: когда чип переехал на `labelLarge`, а
  /// расчёт высоты остался на `labelMedium`, области не хватило 9 px и вторая
  /// строка длинного имени сервера обрезалась по нижнему краю.
  static TextStyle? _statusChipTextStyle(TextTheme textTheme) =>
      textTheme.emphasized(textTheme.labelLarge);

  /// Высота области статуса: столько занимают две строки самого высокого из
  /// двух вариантов — обычной подписи и чипа «подключено».
  ///
  /// Считаем из ролей темы, а не подбираем число: при системном увеличении
  /// шрифта две строки становятся выше, и фиксированная константа их обрезала
  /// бы. Роли берём те же, что использует [_statusText].
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

  Widget _statusText(
    VpnStatus status,
    String? errorMessage,
    ServerItem? activeServer,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    if (status == VpnStatus.connected && activeServer != null) {
      final cleanName = ServerNameUtils.formatForDisplay(
        ServerNameUtils.cleanDisplayName(activeServer.displayName),
      );
      final scheme = Theme.of(context).colorScheme;
      // Тональный чип-пилюля вместо обводки: у M3E это штатный вид «активного»
      // статуса, и он же даёт главному экрану второй цветовой акцент после
      // кнопки. Тот же secondaryContainer носит активный сервер в списке —
      // цвет читается как «вот это выбрано» на обоих экранах.
      return Container(
        key: const ValueKey('connected'),
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: _statusChipVerticalPadding,
        ),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: ExpressiveShape.radius(ExpressiveShape.full),
        ),
        child: Text(
          l10n.vpnConnectedTo(cleanName),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: _statusChipTextStyle(textTheme)
              ?.copyWith(color: scheme.onSecondaryContainer),
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
        // connected, но activeServer == null (активный сервер удалили при
        // живом туннеле) — показываем «подключено», а не «выберите сервер»
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
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textLight(context)),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accentContainer(context),
              foregroundColor: AppTheme.onAccentContainer(context),
            ),
            onPressed: () => _showAddServerDialog(context),
            icon: const Icon(Icons.add, size: 18),
            label: Text(l10n.serversAddServer),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => pasteServersFromClipboard(context, ref),
            icon: Icon(
              Icons.content_paste,
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
    // Повторный тап по уже активному серверу не перезапускает туннель:
    // случайное касание не должно рвать соединение циклом disconnect/connect.
    if (tunnelActive &&
        server.id == ref.read(serversProvider).activeServer?.id) {
      return;
    }
    await ref.read(serversProvider.notifier).setActive(server);
    if (tunnelActive) {
      try {
        await ref.read(vpnStateProvider.notifier).reconnectToActiveServer();
      } catch (e) {
        if (!mounted) return;
        _showSnack(_friendlyError(e, context));
      }
    }
  }

  Future<void> _toggleVpn(VpnStatus status) async {
    if (status == VpnStatus.connected) {
      try {
        await ref.read(vpnStateProvider.notifier).disconnect();
      } catch (e) {
        if (!mounted) return;
        _showSnack(_friendlyError(e, context));
      }
    } else if (status == VpnStatus.connecting) {
      // Тап по кругу во время подключения — отмена попытки, иначе мёртвый
      // сервер держит пользователя на спиннере до конца 45-сек. поллинга.
      try {
        await ref.read(vpnStateProvider.notifier).cancelConnect();
      } catch (e) {
        if (!mounted) return;
        _showSnack(_friendlyError(e, context));
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
        // человекочитаемый текст вместо сырого e.toString(); после await
        // виджет мог быть демонтирован (сворачивание в трей)
        if (!mounted) return;
        _showSnack(_friendlyError(e, context));
      }
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppTheme.text(context),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ExpressiveShape.medium)),
      ),
    );
  }
}

