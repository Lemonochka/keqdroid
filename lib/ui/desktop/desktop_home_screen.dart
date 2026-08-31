import 'dart:async';
import 'package:keqdroid/shared/ui/expressive.dart';
import 'dart:io';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_logger.dart';
import '../../platform/vpn_native_bridge.dart';
import '../../services/desktop_background_service.dart';
import '../../services/hotkey_service.dart';
import '../../services/linux_background_service.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_settings.dart';
import '../../models/hotkey_config.dart';
import '../../models/server_item.dart';
import '../../providers/providers.dart';
import '../../screens/servers_tab.dart';
import '../../screens/settings_tab.dart';
import '../../screens/subscriptions_tab.dart';
import '../../services/update_service.dart';
import '../../services/vpn_engine.dart';
import '../../services/windows_desktop_service.dart';
import '../../tunnel/linux_tunnel_backend.dart';
import '../../shared/ui/app_theme.dart';
import '../../shared/ui/expressive_button_group.dart';
import '../../shared/ui/update_dialog.dart';
import '../../utils/clipboard_import.dart';
import 'desktop_connection_mode.dart';
import 'sidebar_group_nav.dart';
import 'tray_menu_screen.dart';

/// desktop shell: фиксированный sidebar + вкладки (без NavigationRail — на windows ломается layout)
class DesktopHomeScreen extends ConsumerStatefulWidget {
  const DesktopHomeScreen({super.key});

  @override
  ConsumerState<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends ConsumerState<DesktopHomeScreen>
    with WidgetsBindingObserver {
  int _index = 0;
  bool _startupTasksDone = false;
  bool _autostartConnectInFlight = false;
  StreamSubscription<void>? _tunRememberSub;
  bool _tunRememberDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onGlobalKey);
    // Linux: window close hides to tray (handled in main via window_manager).
    // The tray "Quit" tears the tunnel down first via this callback.
    if (Platform.isLinux) {
      LinuxBackgroundService.instance.onQuit = _disconnectForQuit;
      // После первого ввода пароля в polkit для TUN — предложить сделать запуск
      // беспарольным (установить правило). См. LinuxTunnelBackend.
      _tunRememberSub = linuxTunRememberOffers.listen((_) {
        if (mounted) unawaited(_maybeOfferTunRemember());
      });
    }
    VpnNativeBridge.registerAutostartHandler(
      () => _maybeAutostartConnect(force: true),
    );
    VpnNativeBridge.registerTrayMenuHandler(_onTrayMenuOpen);
    VpnNativeBridge.registerTrayMenuCloseHandler(_onTrayMenuClose);
    VpnNativeBridge.registerWindowVisibilityHandler(_onWindowVisibility);
    HotkeyService.onPressed = _onHotkeyAction;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(homeTabIndexProvider.notifier).set(_index);
      ref.read(homeTabPageProvider.notifier).set(_index.toDouble());
      ref.read(updateInfoProvider);
      unawaited(_runWindowsStartupTasks());
      unawaited(_applyHotkeysFromSettings());
    });
  }

  Future<void> _applyHotkeysFromSettings() async {
    if (!HotkeyService.isSupported) return;
    final settings = await ref.read(storageProvider).getSettings();
    final bindings = HotkeyService.parseBindings(settings.hotkeys);
    var failed = await HotkeyService.apply(bindings);
    // После перезапуска (elevation для TUN, быстрый релонч) предыдущий
    // процесс может ещё доживать и держать свои RegisterHotKey — повторяем
    // попытку, прежде чем сообщать «занято другим приложением».
    for (var attempt = 0; failed.isNotEmpty && attempt < 3; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      failed = await HotkeyService.apply(bindings);
    }
    if (failed.isNotEmpty && mounted) {
      _showHotkeyConflictSnack(failed, settings.hotkeys);
    }
  }

  /// Snackbar о сочетаниях, занятых другими приложениями. Вызывать только
  /// после проверки [mounted].
  void _showHotkeyConflictSnack(
    List<String> failedActionIds,
    Map<String, String> hotkeys,
  ) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;
    final labels = failedActionIds
        .map((id) => HotkeyBinding.fromToken(hotkeys[id])?.label ?? id)
        .join(', ');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.hotkeyConflictTaken(labels))),
    );
  }

  /// Срабатывание хоткея: Windows — из натива (даже при скрытом окне),
  /// Linux — из in-app обработчика HotkeyService.
  Future<void> _onHotkeyAction(HotkeyAction action) async {
    if (!mounted) return;
    try {
      switch (action) {
        case HotkeyAction.toggleConnection:
          await _hotkeyToggleConnection();
        case HotkeyAction.toggleTunMode:
          await _hotkeyToggleTunMode();
        case HotkeyAction.bestPingServer:
          await _hotkeyBestPingServer();
        case HotkeyAction.toggleWindow:
          if (Platform.isWindows) {
            await WindowsDesktopService.toggleMainWindow();
          } else if (Platform.isLinux) {
            await LinuxBackgroundService.instance.toggleWindowVisibility();
          }
      }
    } catch (e, st) {
      AppLogger.instance.error(
        'Hotkey action ${action.id} failed',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _hotkeyToggleConnection() async {
    final status = ref.read(vpnStateProvider).value?.status;
    if (status == VpnStatus.connected || status == VpnStatus.connecting) {
      await ref.read(vpnStateProvider.notifier).disconnect();
      return;
    }
    final active = ref.read(serversProvider).activeServer;
    if (active == null) {
      _showHotkeySnack((l10n) => l10n.vpnSelectServerFirst);
      return;
    }
    await ref.read(vpnStateProvider.notifier).connect();
  }

  /// Переключить Proxy ⇄ TUN; при активном туннеле — с переподключением.
  Future<void> _hotkeyToggleTunMode() async {
    final settings =
        ref.read(settingsNotifierProvider).value ?? const AppSettings();
    final next = settings.connectionModeEnum == ConnectionMode.tun
        ? ConnectionMode.proxy
        : ConnectionMode.tun;

    if (next == ConnectionMode.tun && Platform.isWindows) {
      final elevated = await WindowsDesktopService.isProcessElevated();
      if (!elevated) {
        // Молчаливый UAC из глобального хоткея дезориентирует — показываем
        // окно, диалог перезапуска покажет applyDesktopConnectionMode.
        await WindowsDesktopService.restoreMainWindow();
      }
    }
    if (!mounted) return;
    await applyDesktopConnectionMode(context, ref, settings, next);
  }

  /// Переключиться на сервер с наименьшим пингом (speed-замеры не считаются).
  Future<void> _hotkeyBestPingServer() async {
    final serversState = ref.read(serversProvider);
    ServerItem? best;
    var bestPing = 1 << 30;
    for (final s in serversState.servers) {
      final ping = s.pingMs;
      if (ping == null || s.lastPingType == 'speed') continue;
      if (ping < bestPing) {
        bestPing = ping;
        best = s;
      }
    }
    if (best == null) {
      _showHotkeySnack((l10n) => l10n.hotkeyNoPingData);
      return;
    }
    if (best.id != serversState.activeServerId) {
      await ref.read(serversProvider.notifier).setActive(best);
    }
    final status = ref.read(vpnStateProvider).value?.status;
    if (status == VpnStatus.connected || status == VpnStatus.connecting) {
      await ref.read(vpnStateProvider.notifier).reconnectToActiveServer();
    }
  }

  void _showHotkeySnack(String Function(AppLocalizations l10n) message) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message(l10n))),
    );
  }

  Future<void> _runWindowsStartupTasks() async {
    if (!Platform.isWindows || _startupTasksDone) return;
    _startupTasksDone = true;

    final storage = ref.read(storageProvider);
    final settings = await storage.getSettings();
    await WindowsDesktopService.applySettings(settings);

    await _maybeAutostartConnect();
  }

  Future<void> _maybeAutostartConnect({bool force = false}) async {
    if (!Platform.isWindows || _autostartConnectInFlight) return;

    _autostartConnectInFlight = true;
    try {
      if (!force) {
        final isAutostart = await WindowsDesktopService.isAutostartLaunch();
        if (!isAutostart) return;
      }

      final storage = ref.read(storageProvider);
      final settings = await storage.getSettings();
      if (!settings.launchAtStartup || !settings.autoConnectLastServer) return;
      await ref.read(vpnStateProvider.future);
      await ref.read(serversProvider.notifier).reloadPreservingActive();
      if (!mounted) return;

      final active = ref.read(serversProvider).activeServer;
      if (active == null) {
        AppLogger.instance.warn(
          'Autostart connect skipped: no active server selected',
        );
        return;
      }

      final vpn = ref.read(vpnStateProvider).value;
      if (vpn?.status == VpnStatus.connected ||
          vpn?.status == VpnStatus.connecting) {
        return;
      }

      AppLogger.instance.info(
        'Autostart: connecting to ${active.displayName}',
      );
      await ref
          .read(vpnStateProvider.notifier)
          .connect(autostartTunFallback: true);
    } catch (e, st) {
      AppLogger.instance.error(
        'Autostart connect failed',
        error: e,
        stackTrace: st,
      );
    } finally {
      _autostartConnectInFlight = false;
    }
  }

  /// Tray "Quit" on Linux: disconnect (kills cores + clears system proxy)
  /// before the process exits.
  Future<void> _disconnectForQuit() async {
    try {
      await ref.read(vpnStateProvider.notifier).disconnect();
    } catch (e, st) {
      AppLogger.instance.warn('Exit cleanup failed', error: e, stackTrace: st);
    }
  }

  /// Предложить установить беспарольное правило polkit для TUN (Linux). Один раз:
  /// не показываем, если пользователь уже отклонил (linuxTunRememberDismissed)
  /// или правило уже стоит.
  Future<void> _maybeOfferTunRemember() async {
    if (!Platform.isLinux || _tunRememberDialogOpen) return;
    if (LinuxTunnelBackend.isPasswordlessTunInstalled()) return;
    final settings = await ref.read(storageProvider).getSettings();
    if (settings.linuxTunRememberDismissed) return;
    if (!mounted) return;

    _tunRememberDialogOpen = true;
    final l10n = AppLocalizations.of(context)!;
    final enable = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card(ctx),
        title: Row(
          children: [
            Icon(Icons.lock_open_rounded, color: AppTheme.accent(ctx), size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.tunRememberTitle,
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(color: AppTheme.text(ctx)),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.tunRememberMessage,
              style: TextStyle(color: AppTheme.textLight(ctx), height: 1.4),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.tunRememberWarning,
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: AppTheme.textLight(ctx), height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              l10n.tunRememberNotNow,
              style: TextStyle(color: AppTheme.textLight(ctx)),
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
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.tunRememberEnable,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    _tunRememberDialogOpen = false;
    if (!mounted) return;

    // В любом случае больше не спрашиваем автоматически (управление — в
    // «Разрешениях»). Отметку ставим до установки, чтобы отказ тоже запомнился.
    final current = ref.read(settingsNotifierProvider).value;
    if (current != null) {
      await ref
          .read(settingsNotifierProvider.notifier)
          .save(current.copyWith(linuxTunRememberDismissed: true));
    }

    if (enable != true || !mounted) return;

    final ok = await LinuxTunnelBackend.installPasswordlessTun();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? l10n.tunRememberInstalled : l10n.tunRememberFailed),
        backgroundColor: ok ? AppTheme.green(context) : AppTheme.red(context),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onGlobalKey);
    unawaited(_tunRememberSub?.cancel());
    if (Platform.isLinux) LinuxBackgroundService.instance.onQuit = null;
    HotkeyService.onPressed = null;
    VpnNativeBridge.registerAutostartHandler(null);
    VpnNativeBridge.registerTrayMenuHandler(null);
    VpnNativeBridge.registerTrayMenuCloseHandler(null);
    VpnNativeBridge.registerWindowVisibilityHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _onTrayMenuOpen(MethodCall call) async {
    if (!mounted) return;

    final args = call.arguments;
    final map = args is Map ? args : null;
    final anchorX = (map?['x'] as num?)?.toDouble() ?? 0;
    final anchorY = (map?['y'] as num?)?.toDouble() ?? 0;

    final servers = ref.read(serversProvider).servers;
    final settings =
        ref.read(settingsNotifierProvider).value ?? const AppSettings();
    // Ровно как themeMode в app.dart: яркость приложения задаёт ТОЛЬКО
    // settings.darkTheme (followSystemTheme переключает цветовую схему, а не
    // яркость) — иначе при системной тёмной теме трей был тёмным на светлом
    // приложении.
    final darkTheme = settings.darkTheme;

    ref.read(trayMenuVisibleProvider.notifier).set(true);
    WidgetsBinding.instance.ensureVisualUpdate();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    await WindowsDesktopService.showTrayMenu(
      anchorX: anchorX,
      anchorY: anchorY,
      width: TrayMenuScreen.width,
      height: TrayMenuScreen.estimateHeight(
        serverCount: servers.length,
        serversExpanded: false,
      ),
      darkTheme: darkTheme,
    );
  }

  Future<void> _onTrayMenuClose() async {
    if (!mounted) return;
    ref.read(trayMenuVisibleProvider.notifier).set(false);
  }

  /// Нативный трей сообщил, скрыто окно (SW_HIDE) или восстановлено. Это
  /// авторитетный сигнал видимости для десктопа — гасит/возобновляет волну и
  /// опрос трафика (Flutter-lifecycle на трей-hide отдаёт лишь `inactive`).
  void _onWindowVisibility(bool visible) {
    if (!mounted) return;
    ref.read(desktopWindowVisibleProvider.notifier).set(visible);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(DesktopBackgroundService.onAppResumed());
    }
  }

  void _selectTab(int index) {
    if (_index == index) return;
    setState(() => _index = index);
    ref.read(homeTabIndexProvider.notifier).set(index);
    ref.read(homeTabPageProvider.notifier).set(index.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    // До ранних return'ов, чтобы подписка жила на каждом билде: хоткеи
    // переприменяются при любом изменении настроек (экран хоткеев, восстановление
    // бэкапа). До первого изменения действует применение из initState.
    ref.listen<AsyncValue<AppSettings>>(settingsNotifierProvider, (prev, next) {
      final prevHotkeys = prev?.value?.hotkeys;
      final nextHotkeys = next.value?.hotkeys;
      if (nextHotkeys == null) return;
      if (prevHotkeys != null && mapEquals(prevHotkeys, nextHotkeys)) return;
      unawaited(
        HotkeyService.apply(HotkeyService.parseBindings(nextHotkeys)).then(
          (failed) {
            if (failed.isEmpty || !mounted) return;
            _showHotkeyConflictSnack(failed, nextHotkeys);
          },
        ),
      );
    });

    final trayMenuVisible = ref.watch(trayMenuVisibleProvider);
    if (trayMenuVisible) {
      return const TrayMenuScreen();
    }

    // Окно трея использует то же самое окно приложения и сужает его до ширины
    // попапа (~288px). При показе/скрытии трея есть переходные кадры, где флаг
    // меню уже снят, а окно ещё узкое (или наоборот). Чтобы обычные вкладки не
    // раскладывались на ширине попапа и не ловили RenderFlex overflow, не строим
    // их, пока окно сужено. Как только окно вернётся к нормальному размеру —
    // MediaQuery вызовет rebuild и вкладки появятся.
    if (MediaQuery.sizeOf(context).width < 480) {
      return ColoredBox(color: AppTheme.bg(context));
    }

    final l10n = AppLocalizations.of(context)!;
    ref.listen<AsyncValue<UpdateInfo?>>(updateInfoProvider, (prev, next) {
      if (!shouldAutoPromptForUpdate(prev, next)) return;
      final info = next.value;
      if (info == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showUpdateDialog(context, info);
      });
    });

    final destinations = [
      (icon: Icons.dns_rounded, label: l10n.navServers),
      (icon: Icons.subscriptions_rounded, label: l10n.navSubscriptions),
      (icon: Icons.settings_rounded, label: l10n.navSettings),
    ];

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: SizedBox(
              width: MediaQuery.sizeOf(context).width >= 900 ? 220.0 : 76.0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  if (Platform.isWindows || Platform.isLinux) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: MediaQuery.sizeOf(context).width >= 900
                          ? const _ConnectionModeChip()
                          : const Center(child: _ConnectionModeMenuButton()),
                    ),
                    const SizedBox(height: 12),
                    Divider(height: 1, color: AppTheme.divider(context)),
                    const SizedBox(height: 8),
                  ],
                  for (var i = 0; i < destinations.length; i++)
                    _SidebarTile(
                      icon: destinations[i].icon,
                      label: destinations[i].label,
                      selected: _index == i,
                      compact: MediaQuery.sizeOf(context).width < 900,
                      onTap: () => _selectTab(i),
                    ),
                  // Пустоту под разделами занимает быстрый переход по группам
                  // серверов: он сам разворачивается в Expanded и потому
                  // работает и как прежний Spacer. На одной группе (прыгать
                  // некуда) схлопывается в ноль, и панель выглядит как раньше.
                  SidebarGroupNav(
                    compact: MediaQuery.sizeOf(context).width < 900,
                    onOpenServers: () => _selectTab(0),
                  ),
                ],
              ),
            ),
          ),
          VerticalDivider(width: 1, color: AppTheme.divider(context)),
          Expanded(
            child: IndexedStack(
              index: _index,
              sizing: StackFit.expand,
              children: const [
                _DesktopTabHost(child: ServersTab()),
                _DesktopTabHost(child: SubscriptionsTab()),
                _DesktopTabHost(child: SettingsTab()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Ctrl/Cmd+V on the active tab → paste-add (subscriptions/servers). Registered
  /// as a GLOBAL keyboard handler (not a Focus.onKeyEvent) so it fires regardless
  /// of which widget holds focus — the Focus-based version never received events
  /// on Linux/GTK. Matches the PHYSICAL V key, so it works on any layout (on
  /// ЙЦУКЕН the logical key is "м"). A focused text field keeps its own paste.
  bool _onGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    final mod = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (!mod || event.physicalKey != PhysicalKeyboardKey.keyV) return false;
    // Don't hijack paste while the user is typing in a text field.
    if (FocusManager.instance.primaryFocus?.context?.widget is EditableText) {
      return false;
    }
    switch (_index) {
      case 0:
        pasteServersFromClipboard(context, ref);
        return true;
      case 1:
        pasteSubscriptionFromClipboard(context, ref);
        return true;
    }
    return false;
  }
}

/// bounded constraints для корней вкладок (нужно в IndexedStack)
class _DesktopTabHost extends StatelessWidget {
  final Widget child;
  const _DesktopTabHost({required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppTheme.bg(context),
      child: SizedBox.expand(child: child),
    );
  }
}

/// Пункт боковой навигации.
///
/// Переключение идёт пружиной, как в нижней панели на телефоне
/// (`lib/shared/ui/bottom_nav.dart`), и по той же механике: цвет пилюли, её
/// отступы и цвет содержимого считаются от ОДНОГО значения покадрово. Раньше
/// здесь всё переключалось мгновенно, и панель ощущалась мёртвой рядом с
/// телефонной.
class _SidebarTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  @override
  State<_SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<_SidebarTile>
    with SingleTickerProviderStateMixin {
  /// Unbounded — пружина M3E недодемпфирована и обязана перелетать за цель.
  late final AnimationController _ctrl = AnimationController.unbounded(
    vsync: this,
    value: widget.selected ? 1 : 0,
  );

  @override
  void didUpdateWidget(_SidebarTile old) {
    super.didUpdateWidget(old);
    if (old.selected == widget.selected) return;
    ExpressiveMotion.springTo(
      _ctrl,
      widget.selected ? 1 : 0,
      spring: ExpressiveMotion.spatialFast,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Пункт навигации у M3E — пилюля, как и в нижней панели. Здесь стояло
    // скругление 12, и панель читалась как список прямоугольников.
    final shape = BorderRadius.circular(ExpressiveShape.full);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        // Перелёт пружины нужен геометрии, но не цвету: там он читается как
        // мигание.
        final t = _ctrl.value;
        final tc = t.clamp(0.0, 1.0);

        final bg = Color.lerp(Colors.transparent, scheme.secondaryContainer, tc)!;
        final fg = Color.lerp(
          scheme.onSurfaceVariant,
          scheme.onSecondaryContainer,
          tc,
        )!;
        // Выбранная пилюля «набухает»: поля вокруг неё поджимаются, и она
        // раздаётся в стороны — то же движение, что раскрытие пункта внизу.
        final outerInset = 10.0 - 4.0 * tc;

        final pill = Material(
          color: bg,
          borderRadius: shape,
          // Цвет ведём пружиной покадрово — неявная 200-миллисекундная
          // анимация Material тянулась бы следом и отставала от отступов.
          animationDuration: Duration.zero,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: shape,
            child: widget.compact
                ? SizedBox(
                    height: 48,
                    child: Icon(widget.icon, color: fg),
                  )
                : Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12 + 2 * tc,
                    ),
                    child: Row(
                      children: [
                        Icon(widget.icon, color: fg, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.label,
                            // Вес из шкалы: у выбранного усиленный вариант роли.
                            style:
                                (widget.selected
                                        ? textTheme.emphasized(
                                            textTheme.labelLarge)
                                        : textTheme.labelLarge)
                                    ?.copyWith(color: fg),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        );

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: outerInset, vertical: 4),
          child: widget.compact
              ? Tooltip(message: widget.label, child: pill)
              : pill,
        );
      },
    );
  }
}

class _ConnectionModeMenuButton extends ConsumerWidget {
  const _ConnectionModeMenuButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();
    final mode = settings.connectionModeEnum;

    return PopupMenuButton<ConnectionMode>(
      tooltip: AppLocalizations.of(context)!.desktopConnectionMode,
      icon: Icon(
        mode == ConnectionMode.tun ? Icons.vpn_lock_rounded : Icons.lan_rounded,
        size: 22,
      ),
      onSelected: (next) =>
          applyDesktopConnectionMode(context, ref, settings, next),
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: ConnectionMode.proxy,
          checked: mode == ConnectionMode.proxy,
          child: const Text('Proxy'),
        ),
        CheckedPopupMenuItem(
          value: ConnectionMode.tun,
          checked: mode == ConnectionMode.tun,
          child: const Text('TUN'),
        ),
      ],
    );
  }
}

class _ConnectionModeChip extends ConsumerWidget {
  const _ConnectionModeChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();
    final mode = settings.connectionModeEnum;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            AppLocalizations.of(context)!.desktopModeShort,
            // Тот же вид, что у заголовков секций в настройках.
            style: Theme.of(context).textTheme
                .emphasized(Theme.of(context).textTheme.labelLarge)
                ?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
        ),
        ExpressiveConnectedButtons<ConnectionMode>(
          segments: const [
            ExpressiveSegment(
              value: ConnectionMode.proxy,
              label: 'Proxy',
              icon: Icons.lan_rounded,
            ),
            ExpressiveSegment(
              value: ConnectionMode.tun,
              label: 'TUN',
              icon: Icons.vpn_lock_rounded,
            ),
          ],
          selected: mode,
          onChanged: (next) =>
              applyDesktopConnectionMode(context, ref, settings, next),
        ),
      ],
    );
  }
}
