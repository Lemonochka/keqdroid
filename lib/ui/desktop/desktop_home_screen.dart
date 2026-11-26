import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_logger.dart';
import '../../platform/vpn_native_bridge.dart';
import '../../services/desktop_background_service.dart';
import '../../services/hotkey_service.dart';
import '../../services/linux_autostart.dart';
import '../../services/linux_background_service.dart';
import '../../services/linux_tray_vpn.dart';
import '../../services/macos_autostart.dart';
import '../../services/macos_background_service.dart';
import '../../services/macos_tray_vpn.dart';
import '../../services/macos_tun_service.dart';
import '../../services/resume_after_update.dart';

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
import '../../services/windows_tun_service.dart';
import '../../services/windows_tray_menu.dart';
import '../../shared/ui/app_theme.dart';
import '../../shared/ui/halloween/halloween_icons.dart';
import '../../shared/ui/liquid_toast.dart';
import '../../shared/ui/update_dialog.dart';
import '../../tunnel/macos_elevation.dart';
import '../../utils/clipboard_import.dart';
import 'connect_rehearsal_host.dart';
import 'desktop_connection_mode.dart';
import 'desktop_rail.dart';
import 'desktop_tab_switcher.dart';

// свой сайдбар: NavigationRail на Windows ломал раскладку
class DesktopHomeScreen extends ConsumerStatefulWidget {
  const DesktopHomeScreen({super.key});

  @override
  ConsumerState<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends ConsumerState<DesktopHomeScreen>
    with WidgetsBindingObserver {
  int _index = 0;
  bool _startupTasksDone = false;
  bool _startupConnectInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onGlobalKey);
    if (Platform.isLinux) {
      LinuxBackgroundService.instance.onQuit = _disconnectForQuit;
      LinuxBackgroundService.instance.uiVisible.addListener(
        _onLinuxWindowVisibility,
      );
    } else if (Platform.isMacOS) {
      MacosBackgroundService.instance.onQuit = _disconnectForQuit;
      MacosBackgroundService.instance.uiVisible.addListener(
        _onMacosWindowVisibility,
      );
      VpnNativeBridge.registerOpenSettingsHandler(_openSettingsFromMenu);
    }
    VpnNativeBridge.registerAutostartHandler(
      () => _maybeAutostartConnect(force: true),
    );
    VpnNativeBridge.registerWindowVisibilityHandler(_onWindowVisibility);
    if (Platform.isWindows) {
      // при автозапуске в трей окно не показывалось, и сказать об этом раннер мог только до подписки
      unawaited(
        WindowsDesktopService.isHiddenInTray().then((hidden) {
          if (hidden) _onWindowVisibility(false);
        }),
      );
    }
    HotkeyService.onPressed = _onHotkeyAction;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // при автозапуске в трей окно спрятано ещё до runApp, слушатель этого не застал
      if (Platform.isLinux) _onLinuxWindowVisibility();
      if (Platform.isMacOS) _onMacosWindowVisibility();
      ref.read(homeTabIndexProvider.notifier).set(_index);
      ref.read(homeTabPageProvider.notifier).set(_index.toDouble());
      ref.read(updateInfoProvider);
      unawaited(_runStartupTasks());
      unawaited(_applyHotkeysFromSettings());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context);
    if (Platform.isLinux && l10n != null) {
      unawaited(
        LinuxBackgroundService.instance.setTrayLabels(
          show: l10n.trayOpenApp,
          quit: l10n.trayExit,
          connect: l10n.trayConnect,
          disconnect: l10n.trayDisconnect,
        ),
      );
    } else if (Platform.isMacOS && l10n != null) {
      unawaited(
        MacosBackgroundService.instance.setTrayLabels(
          show: l10n.trayOpenApp,
          quit: l10n.trayExit,
          connect: l10n.trayConnect,
          disconnect: l10n.trayDisconnect,
        ),
      );
    }
  }

  Future<void> _applyHotkeysFromSettings() async {
    if (!HotkeyService.isSupported) return;
    final settings = await ref.read(storageProvider).getSettings();
    final bindings = HotkeyService.parseBindings(settings.hotkeys);
    final l10n = mounted ? AppLocalizations.of(context) : null;
    var failed = await HotkeyService.apply(
      bindings,
      descriptions: l10n == null ? null : hotkeyDescriptions(l10n),
    );
    // прошлый процесс после перезапуска ещё может держать RegisterHotKey
    for (var attempt = 0; failed.isNotEmpty && attempt < 3; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      failed = await HotkeyService.apply(bindings);
    }
    if (failed.isNotEmpty && mounted) {
      _showHotkeyConflictSnack(failed, settings.hotkeys);
    }
  }

  void _showHotkeyConflictSnack(
    List<String> failedActionIds,
    Map<String, String> hotkeys,
  ) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;
    final labels = failedActionIds
        .map((id) => HotkeyBinding.fromToken(hotkeys[id])?.label ?? id)
        .join(', ');
    AppSnack.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.hotkeyConflictTaken(labels))));
  }

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
          } else if (Platform.isMacOS) {
            await MacosBackgroundService.instance.toggleWindowVisibility();
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
    if (!await ensureTunReadyToConnect(
      context,
      ref.read(settingsNotifierProvider).value,
      showWindow: true,
    )) {
      return;
    }
    if (!mounted) return;
    await ref.read(vpnStateProvider.notifier).connect();
  }

  Future<void> _hotkeyToggleTunMode() async {
    final settings =
        ref.read(settingsNotifierProvider).value ?? const AppSettings();
    final next = settings.connectionModeEnum == ConnectionMode.tun
        ? ConnectionMode.proxy
        : ConnectionMode.tun;

    if (next == ConnectionMode.tun) {
      if (Platform.isWindows &&
          !await WindowsDesktopService.isProcessElevated() &&
          await WindowsTunService.state() != TunServiceState.ready) {
        // без службы спросим про неё, а окно в трее спрятало бы вопрос
        await WindowsDesktopService.restoreMainWindow();
      } else if (Platform.isMacOS &&
          !macosRunningAsRoot() &&
          await MacosTunService.state() != TunServiceState.ready) {
        await MacosBackgroundService.instance.restoreMainWindow();
      }
    }
    if (!mounted) return;
    await applyDesktopConnectionMode(
      context,
      DesktopModeDeps.of(ref),
      settings,
      next,
    );
  }

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
    await ref.read(subscriptionsProvider.notifier).releaseMainGroup(best);
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
    AppSnack.of(context).showSnackBar(SnackBar(content: Text(message(l10n))));
  }

  Future<void> _runWindowsStartupTasks() async {
    if (!Platform.isWindows || _startupTasksDone) return;
    _startupTasksDone = true;

    final storage = ref.read(storageProvider);
    final settings = await storage.getSettings();
    await WindowsDesktopService.applySettings(settings);

    await _maybeAutostartConnect();
    unawaited(_retireElevatedAutostart(settings));
  }

  // настройки запуска с правами больше нет, её задачу планировщика заменяют служба TUN и обычный автозапуск
  Future<void> _retireElevatedAutostart(AppSettings settings) async {
    try {
      final retired = await WindowsDesktopService.retireElevatedAutostart(
        tun: settings.connectionModeEnum == ConnectionMode.tun,
      );
      if (!retired || !mounted) return;
      final current = await ref.read(settingsNotifierProvider.future);
      if (!mounted) return;
      await ref
          .read(settingsNotifierProvider.notifier)
          .save(
            current.copyWith(
              launchAtStartup: true,
              launchAtStartupElevated: false,
            ),
          );
      AppLogger.instance.info('Elevated autostart task replaced by Run entry');
    } catch (e) {
      AppLogger.instance.warn('Elevated autostart not retired', error: e);
    }
  }

  Future<void> _runStartupTasks() async {
    try {
      await _runWindowsStartupTasks();
      await _runLinuxStartupTasks();
      await _runMacosStartupTasks();
    } finally {
      // после автостарта: оба подключают один и тот же сервер
      await _maybeResumeAfterUpdate();
    }
  }

  Future<void> _runLinuxStartupTasks() async {
    if (!Platform.isLinux || _startupTasksDone) return;
    _startupTasksDone = true;
    final settings = await ref.read(storageProvider).getSettings();
    await LinuxAutostart.setStartInTray(settings.autostartInTray);
    await LinuxAutostart.refresh();
    await _maybeAutostartConnect();
  }

  Future<void> _runMacosStartupTasks() async {
    if (!Platform.isMacOS || _startupTasksDone) return;
    _startupTasksDone = true;
    final settings = await ref.read(storageProvider).getSettings();
    await MacosAutostart.setStartInTray(settings.autostartInTray);
    await MacosAutostart.refresh();
    await _maybeAutostartConnect();
  }

  Future<void> _maybeAutostartConnect({bool force = false}) async {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS) ||
        _startupConnectInFlight) {
      return;
    }

    _startupConnectInFlight = true;
    try {
      if (!force) {
        final isAutostart = Platform.isLinux
            ? LinuxAutostart.launchedAtLogin()
            : Platform.isMacOS
            ? MacosAutostart.launchedAtLogin()
            : await WindowsDesktopService.isAutostartLaunch();
        if (!isAutostart) return;
      }

      final storage = ref.read(storageProvider);
      final settings = await storage.getSettings();
      if (!settings.launchAtStartup || !settings.autoConnectLastServer) return;
      await _connectActiveOnStartup('Autostart');
    } catch (e, st) {
      AppLogger.instance.error(
        'Autostart connect failed',
        error: e,
        stackTrace: st,
      );
    } finally {
      _startupConnectInFlight = false;
    }
  }

  Future<void> _maybeResumeAfterUpdate() async {
    if (!await ResumeAfterUpdate.take() || _startupConnectInFlight) return;

    _startupConnectInFlight = true;
    try {
      await _connectActiveOnStartup('After update');
    } catch (e, st) {
      AppLogger.instance.error(
        'Reconnect after update failed',
        error: e,
        stackTrace: st,
      );
    } finally {
      _startupConnectInFlight = false;
    }
  }

  Future<void> _connectActiveOnStartup(String reason) async {
    await ref.read(vpnStateProvider.future);
    await ref.read(serversProvider.notifier).reloadPreservingActive();
    if (!mounted) return;

    final active = ref.read(serversProvider).activeServer;
    if (active == null) {
      AppLogger.instance.warn(
        '$reason connect skipped: no active server selected',
      );
      return;
    }

    final vpn = ref.read(vpnStateProvider).value;
    if (vpn?.status == VpnStatus.connected ||
        vpn?.status == VpnStatus.connecting) {
      return;
    }

    AppLogger.instance.info('$reason: connecting to ${active.displayName}');
    final settings = await ref.read(settingsNotifierProvider.future);
    if (!mounted) return;
    await connectOnStartup(
      context,
      settings: settings,
      vpn: ref.read(vpnStateProvider.notifier),
      status: () => ref.read(vpnStateProvider).value?.status,
    );
  }

  Future<void> _disconnectForQuit() async {
    try {
      await ref.read(vpnStateProvider.notifier).disconnect();
    } catch (e, st) {
      AppLogger.instance.warn('Exit cleanup failed', error: e, stackTrace: st);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onGlobalKey);
    if (Platform.isLinux) {
      LinuxBackgroundService.instance.onQuit = null;
      LinuxBackgroundService.instance.uiVisible.removeListener(
        _onLinuxWindowVisibility,
      );
    } else if (Platform.isMacOS) {
      MacosBackgroundService.instance.onQuit = null;
      MacosBackgroundService.instance.uiVisible.removeListener(
        _onMacosWindowVisibility,
      );
      VpnNativeBridge.registerOpenSettingsHandler(null);
    }
    HotkeyService.onPressed = null;
    VpnNativeBridge.registerAutostartHandler(null);
    VpnNativeBridge.registerWindowVisibilityHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onWindowVisibility(bool visible) {
    if (!mounted) return;
    ref.read(desktopWindowVisibleProvider.notifier).set(visible);
  }

  void _onLinuxWindowVisibility() =>
      _onWindowVisibility(LinuxBackgroundService.instance.uiVisible.value);

  void _onMacosWindowVisibility() =>
      _onWindowVisibility(MacosBackgroundService.instance.uiVisible.value);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(DesktopBackgroundService.onAppResumed());
    }
  }

  void _openSettingsFromMenu() {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    _selectTab(2);
    unawaited(MacosBackgroundService.instance.restoreMainWindow());
  }

  void _selectTab(int index) {
    if (_index == index) return;
    setState(() => _index = index);
    ref.read(homeTabIndexProvider.notifier).set(index);
    ref.read(homeTabPageProvider.notifier).set(index.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    // до ранних return: подписка должна жить на каждом билде
    ref.listen<AsyncValue<AppSettings>>(settingsNotifierProvider, (prev, next) {
      final prevHotkeys = prev?.value?.hotkeys;
      final nextHotkeys = next.value?.hotkeys;
      if (nextHotkeys == null) return;
      if (prevHotkeys != null && mapEquals(prevHotkeys, nextHotkeys)) return;
      unawaited(
        HotkeyService.apply(HotkeyService.parseBindings(nextHotkeys)).then((
          failed,
        ) {
          if (failed.isEmpty || !mounted) return;
          _showHotkeyConflictSnack(failed, nextHotkeys);
        }),
      );
    });

    ref.watch(windowsTrayMenuProvider);
    ref.watch(linuxTrayVpnProvider);
    ref.watch(macosTrayVpnProvider);
    if (Platform.isLinux) {
      ref.listen(
        vpnStateProvider.select((a) => a.value?.status == VpnStatus.connected),
        (_, connected) =>
            unawaited(LinuxBackgroundService.instance.showConnected(connected)),
      );
    } else if (Platform.isMacOS) {
      ref.listen(
        vpnStateProvider.select((a) => a.value?.status == VpnStatus.connected),
        (_, connected) =>
            unawaited(MacosBackgroundService.instance.showConnected(connected)),
      );
    }
    LiquidToast.enabled = true;

    ref.listen<AsyncValue<UpdateInfo?>>(updateInfoProvider, (prev, next) {
      if (!shouldAutoPromptForUpdate(prev, next)) return;
      final info = next.value;
      if (info == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final days =
            ref.read(settingsNotifierProvider).value?.updatePromptDays ??
            const AppSettings().updatePromptDays;
        unawaited(autoPromptForUpdate(context, info, days: days));
      });
    });

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LiquidToastSource(
            child: HalloweenIconScope(
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: DesktopRail(index: _index, onSelect: _selectTab),
              ),
            ),
          ),
          VerticalDivider(width: 1, color: AppTheme.divider(context)),
          Expanded(
            child: ConnectRehearsalHost(
              enabled: Platform.isWindows,
              child: DesktopTabSwitcher(
                index: _index,
                // подписки к этому времени уже прочитаны из хранилища
                warmUpAfter: const Duration(seconds: 3),
                windowHidden: () => !ref.read(desktopUiVisibleProvider),
                children: [
                  for (final tab in const [
                    ServersTab(),
                    SubscriptionsTab(),
                    SettingsTab(),
                  ])
                    _DesktopTabHost(child: tab),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // глобальный обработчик: Focus.onKeyEvent на Linux/GTK событий не получал; физическая V работает и на ЙЦУКЕН
  bool _onGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    if (Platform.isLinux && _isQuitShortcut(event)) {
      unawaited(LinuxBackgroundService.instance.quit());
      return true;
    }
    final mod =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (!mod || event.physicalKey != PhysicalKeyboardKey.keyV) return false;
    // поверх вкладки что-то открыто, Ctrl+V принадлежит ему: иначе подписка добавлялась мимо открытой формы
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    if (FocusManager.instance.primaryFocus?.context?.widget is EditableText) {
      return false;
    }
    switch (_index) {
      case 0:
        pasteLinksFromClipboard(context, ref);
        return true;
      case 1:
        pasteSubscriptionFromClipboard(context, ref);
        return true;
    }
    return false;
  }

  bool _isQuitShortcut(KeyEvent event) {
    final hk = HardwareKeyboard.instance;
    return event.physicalKey == PhysicalKeyboardKey.keyQ &&
        hk.isControlPressed &&
        !hk.isAltPressed &&
        !hk.isShiftPressed &&
        !hk.isMetaPressed &&
        !HotkeyService.captureMode &&
        !HotkeyService.isBound(event.physicalKey, hk);
  }
}

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

// подписи для окна портала на Wayland: там пользователь видит, что подтверждает
Map<HotkeyAction, String> hotkeyDescriptions(AppLocalizations l10n) => {
  HotkeyAction.toggleConnection: l10n.hotkeyActionToggleConnection,
  HotkeyAction.toggleTunMode: l10n.hotkeyActionToggleTun,
  HotkeyAction.bestPingServer: l10n.hotkeyActionBestPing,
  HotkeyAction.toggleWindow: l10n.hotkeyActionToggleWindow,
};
