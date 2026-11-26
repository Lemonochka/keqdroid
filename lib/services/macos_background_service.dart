import 'dart:async';
import 'dart:convert';
import 'dart:io' show exit;
import 'dart:ui' show Rect, Size;

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_logger.dart';
import '../platform/vpn_native_bridge.dart';
import '../tunnel/tunnel_state.dart';
import 'macos_autostart.dart';
import 'storage_service.dart';

class MacosBackgroundService with WindowListener, TrayListener {
  MacosBackgroundService._();
  static final MacosBackgroundService instance = MacosBackgroundService._();

  @visibleForTesting
  MacosBackgroundService.forTesting();

  static const _trayIcon = 'assets/icon.png';
  static const _trayIconConnected = 'assets/icon_connected.png';

  bool _quitting = false;
  bool _pendingAppTerminate = false;
  bool _quitFinished = false;
  bool _boundsRestorePending = false;
  final ValueNotifier<bool> uiVisible = ValueNotifier(true);

  String _showLabel = 'Show keqdroid';
  String _quitLabel = 'Quit';
  String _connectLabel = 'Connect';
  String _disconnectLabel = 'Disconnect';

  ({bool connected, bool enabled})? _vpnItem;
  bool _togglingVpn = false;

  Future<void> Function()? onToggleVpn;
  Future<void> Function()? onQuit;

  Timer? _boundsSaveDebounce;

  Future<void> initWindowAndTray() async {
    final inTray = MacosAutostart.startedInTray();
    if (inTray) {
      uiVisible.value = false;
      _boundsRestorePending = true;
    }
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
    if (!inTray) {
      await _restoreWindowBounds();
    }

    trayManager.addListener(this);
    try {
      await trayManager.setIcon(_trayIcon);
      await _applyTrayMenu();
    } catch (e, st) {
      AppLogger.instance.warn(
        'Menu bar tray init failed',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _applyTrayMenu() {
    final vpn = _vpnItem;
    return trayManager.setContextMenu(
      Menu(
        items: [
          if (vpn != null) ...[
            MenuItem(
              key: 'vpn',
              label: vpn.connected ? _disconnectLabel : _connectLabel,
              disabled: !vpn.enabled,
            ),
            MenuItem.separator(),
          ],
          MenuItem(key: 'show', label: _showLabel),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: _quitLabel),
        ],
      ),
    );
  }

  Future<void> _refreshTrayMenu() async {
    try {
      await _applyTrayMenu();
    } catch (e) {
      AppLogger.instance.debug('Menu bar tray menu not updated', error: e);
    }
  }

  Future<void> setTrayVpn({
    required VpnStatus status,
    required bool hasServer,
  }) async {
    final connected =
        status == VpnStatus.connected || status == VpnStatus.connecting;
    final item = (
      connected: connected,
      enabled: connected || (hasServer && status != VpnStatus.disconnecting),
    );
    if (item == _vpnItem) return;
    _vpnItem = item;
    await _refreshTrayMenu();
  }

  Future<void> showConnected(bool connected) async {
    try {
      await trayManager.setIcon(connected ? _trayIconConnected : _trayIcon);
    } catch (e) {
      AppLogger.instance.debug('Menu bar tray icon not updated', error: e);
    }
  }

  Future<void> setTrayLabels({
    required String show,
    required String quit,
    required String connect,
    required String disconnect,
  }) async {
    if (show == _showLabel &&
        quit == _quitLabel &&
        connect == _connectLabel &&
        disconnect == _disconnectLabel) {
      return;
    }
    _showLabel = show;
    _quitLabel = quit;
    _connectLabel = connect;
    _disconnectLabel = disconnect;
    await _refreshTrayMenu();
  }

  Future<void> toggleWindowVisibility() async {
    if (await windowManager.isVisible() && !await windowManager.isMinimized()) {
      _boundsSaveDebounce?.cancel();
      await _saveWindowBounds();
      uiVisible.value = false;
      await windowManager.hide();
    } else {
      await _showWindow();
    }
  }

  Future<void> restoreMainWindow() => _showWindow();

  Future<void> _showWindow() async {
    if (_boundsRestorePending) {
      _boundsRestorePending = false;
      await _restoreWindowBounds();
    }
    uiVisible.value = true;
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _restoreWindowBounds() async {
    try {
      final storage = await StorageService.init();
      final raw = storage.getWindowBoundsJson();
      if (raw == null) return;
      final data = jsonDecode(raw);
      if (data is! Map) return;
      final w = (data['w'] as num?)?.toDouble();
      final h = (data['h'] as num?)?.toDouble();
      final x = (data['x'] as num?)?.toDouble();
      final y = (data['y'] as num?)?.toDouble();
      final maximized = data['maximized'] as bool? ?? false;
      if (w == null || h == null || w < 480 || h < 320) return;
      if (x != null && y != null && x > -10000 && y > -10000) {
        await windowManager.setBounds(Rect.fromLTWH(x, y, w, h));
      } else {
        await windowManager.setSize(Size(w, h));
      }
      if (maximized) {
        await windowManager.maximize();
      }
    } catch (e, st) {
      AppLogger.instance.warn(
        'Failed to restore window bounds',
        error: e,
        stackTrace: st,
      );
    }
  }

  void _scheduleBoundsSave() {
    _boundsSaveDebounce?.cancel();
    _boundsSaveDebounce = Timer(
      const Duration(milliseconds: 600),
      () => unawaited(_saveWindowBounds()),
    );
  }

  Future<void> _saveWindowBounds() async {
    try {
      final storage = await StorageService.init();
      final maximized = await windowManager.isMaximized();
      Map<String, dynamic> data;
      if (maximized) {
        final raw = storage.getWindowBoundsJson();
        final prev = raw != null ? jsonDecode(raw) : null;
        data = prev is Map
            ? {...prev.map((k, v) => MapEntry(k.toString(), v))}
            : <String, dynamic>{};
        data['maximized'] = true;
      } else {
        final bounds = await windowManager.getBounds();
        data = {
          'x': bounds.left,
          'y': bounds.top,
          'w': bounds.width,
          'h': bounds.height,
          'maximized': false,
        };
      }
      await storage.setWindowBoundsJson(jsonEncode(data));
    } catch (e, st) {
      AppLogger.instance.warn(
        'Failed to save window bounds',
        error: e,
        stackTrace: st,
      );
    }
  }

  @override
  void onWindowClose() {
    if (_quitting) return;
    _boundsSaveDebounce?.cancel();
    unawaited(_saveWindowBounds());
    unawaited(_onCloseButton());
  }

  Future<void> _onCloseButton() async {
    if (await closeToBackground()) {
      uiVisible.value = false;
      await windowManager.hide();
    } else {
      await quit();
    }
  }

  @visibleForTesting
  static Future<bool> Function() closeToBackground = () async {
    try {
      final storage = await StorageService.init();
      return (await storage.getSettings()).minimizeToTray;
    } catch (_) {
      return true;
    }
  };

  @override
  void onWindowFocus() => uiVisible.value = true;

  @override
  void onWindowMinimize() => uiVisible.value = false;

  @override
  void onWindowRestore() => uiVisible.value = true;

  @override
  void onWindowResize() => _scheduleBoundsSave();

  @override
  void onWindowMove() => _scheduleBoundsSave();

  @override
  void onWindowMaximize() => _scheduleBoundsSave();

  @override
  void onWindowUnmaximize() => _scheduleBoundsSave();

  @override
  void onTrayIconMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'vpn':
        unawaited(_toggleVpn());
      case 'show':
        unawaited(_showWindow());
      case 'quit':
        unawaited(quit());
    }
  }

  Future<void> _toggleVpn() async {
    final toggle = onToggleVpn;
    if (toggle == null || _togglingVpn) return;
    _togglingVpn = true;
    try {
      await toggle();
    } catch (e, st) {
      AppLogger.instance.warn(
        'Menu bar VPN toggle failed',
        error: e,
        stackTrace: st,
      );
    } finally {
      _togglingVpn = false;
    }
  }

  @visibleForTesting
  static void Function(int code) exitProcess = exit;

  Future<void> quit({bool fromAppTerminate = false}) async {
    if (_quitting) {
      if (fromAppTerminate) {
        _pendingAppTerminate = true;
        if (_quitFinished) {
          try {
            await VpnNativeBridge.channel.invokeMethod<void>(
              'confirmAppTerminate',
            );
          } catch (_) {}
        }
      }
      return;
    }
    _quitting = true;
    _pendingAppTerminate = fromAppTerminate;
    try {
      await onQuit?.call();
    } catch (e) {
      AppLogger.instance.warn('Quit hook failed', error: e);
    }
    _boundsSaveDebounce?.cancel();
    await _saveWindowBounds();
    try {
      await trayManager.destroy();
    } catch (_) {}
    await windowManager.setPreventClose(false);
    _quitFinished = true;
    try {
      await VpnNativeBridge.channel.invokeMethod<void>('confirmAppTerminate');
    } catch (_) {}
    if (_pendingAppTerminate) return;
    await windowManager.destroy();
    exitProcess(0);
  }
}
