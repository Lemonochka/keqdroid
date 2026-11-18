import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect, Size;

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_logger.dart';
import 'linux_autostart.dart';
import 'linux_deep_links.dart';
import 'linux_desktop_entry.dart';
import 'storage_service.dart';

class LinuxBackgroundService with WindowListener, TrayListener {
  LinuxBackgroundService._();
  static final LinuxBackgroundService instance = LinuxBackgroundService._();

  @visibleForTesting
  LinuxBackgroundService.forTesting();

  static const _trayId = 'keqdroid';
  static const _trayIcon = 'assets/icon.png';
  static const _trayIconConnected = 'assets/icon_connected.png';

  @visibleForTesting
  static Duration quitSettleDelay = const Duration(milliseconds: 300);

  bool _quitting = false;

  // на Wayland GTK3 композитор не сообщает о сворачивании, видимость ведём сами
  final ValueNotifier<bool> uiVisible = ValueNotifier(true);

  @visibleForTesting
  static String? desktopOverride;

  String _showLabel = 'Show keqdroid';
  String _quitLabel = 'Quit';

  ServerSocket? _lock;

  Future<void> Function()? onQuit;

  // абстрактный сокет с uid: TCP-порт на петле общий для всех пользователей машины
  static InternetAddress _lockAddress() => InternetAddress(
        '@keqdroid-${_uid() ?? 'user'}',
        type: InternetAddressType.unix,
      );

  static int? _uid() {
    try {
      for (final line in File('/proc/self/status').readAsLinesSync()) {
        if (!line.startsWith('Uid:')) continue;
        return int.tryParse(line.split(RegExp(r'\s+'))[1]);
      }
    } catch (_) {}
    return null;
  }

  static const _addressInUse = 98;

  Future<bool> ensureSingleInstance() async {
    final address = _lockAddress();
    try {
      _lock = await ServerSocket.bind(address, 0);
      _lock!.listen(_readPeer);
      return true;
    } on SocketException catch (e) {
      if (e.osError?.errorCode != _addressInUse) {
        AppLogger.instance.warn(
          'Single-instance lock unavailable, starting without it',
          error: e,
        );
        return true;
      }
      final link = LinuxDeepLinks.launchLink();
      // второй запуск при входе поднял бы окно, которое первый спрятал в трей
      if (link == null && LinuxAutostart.startedInTray()) return false;
      try {
        final s = await Socket.connect(
          address,
          0,
          timeout: const Duration(seconds: 2),
        );
        s.add(utf8.encode(peerMessage(link)));
        await s.flush();
        // close, а не destroy: первому нужен конец потока, чтобы дочитать ссылку
        await s.close();
      } catch (_) {}
      return false;
    }
  }

  @visibleForTesting
  static String peerMessage(String? link) => link == null ? 'show' : 'link $link';

  void _readPeer(Socket socket) {
    final bytes = <int>[];
    var handled = false;
    void finish() {
      if (handled) return;
      handled = true;
      socket.destroy();
      handlePeerMessage(utf8.decode(bytes, allowMalformed: true));
    }

    // 0.37.4 и раньше второй запуск слал show и рвал сокет, конец потока приходит и тогда
    final guard = Timer(const Duration(seconds: 2), finish);
    socket.listen(
      (chunk) {
        if (bytes.length < 16 * 1024) bytes.addAll(chunk);
      },
      onDone: () {
        guard.cancel();
        finish();
      },
      onError: (_) {
        guard.cancel();
        finish();
      },
      cancelOnError: true,
    );
  }

  @visibleForTesting
  void handlePeerMessage(String message) {
    unawaitedShow();
    if (!message.startsWith('link ')) return;
    final link = LinuxDeepLinks.fromCommandLine(['', message.substring(5)]);
    if (link != null) LinuxDeepLinks.deliver(link);
  }

  Future<void> initWindowAndTray() async {
    if (LinuxAutostart.startedInTray()) uiVisible.value = false;
    unawaited(LinuxDesktopEntry.sync());
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
    await _restoreWindowBounds();

    trayManager.addListener(this);
    try {
      await trayManager.setIcon(_trayIcon, id: _trayId, title: 'keqdroid');
      // без setToolTip: на Linux tray_manager кидает MissingPluginException, и меню остаётся пустым
      await _applyTrayMenu();
    } catch (e, st) {
      AppLogger.instance.warn(
        'Tray init failed (no AppIndicator host?). Background mode still works; '
        'relaunch the app to restore the window.',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _applyTrayMenu() => trayManager.setContextMenu(
        Menu(items: [
          MenuItem(key: 'show', label: _showLabel),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: _quitLabel),
        ]),
      );

  Future<void> showConnected(bool connected) async {
    try {
      await trayManager.setIcon(
        connected ? _trayIconConnected : _trayIcon,
        id: _trayId,
        title: 'keqdroid',
      );
    } catch (_) {}
  }

  Future<void> setTrayLabels({
    required String show,
    required String quit,
  }) async {
    if (show == _showLabel && quit == _quitLabel) return;
    _showLabel = show;
    _quitLabel = quit;
    try {
      await _applyTrayMenu();
    } catch (_) {}
  }

  void unawaitedShow() {
    _showWindow();
  }

  Future<void> toggleWindowVisibility() async {
    if (await windowManager.isVisible() && !await windowManager.isMinimized()) {
      _boundsSaveDebounce?.cancel();
      await _saveWindowBounds();
      await _sendToBackground();
    } else {
      await _showWindow();
    }
  }

  Future<void> _sendToBackground() async {
    uiVisible.value = false;
    if (await _trayAvailable() || isTilingDesktop(desktopOverride)) {
      await windowManager.hide();
    } else {
      await windowManager.minimize();
    }
  }

  static const _tilingDesktops = {'hyprland', 'sway', 'niri', 'river'};

  static bool isTilingDesktop([String? desktop]) =>
      (desktop ?? Platform.environment['XDG_CURRENT_DESKTOP'] ?? '')
          .toLowerCase()
          .split(':')
          .any(_tilingDesktops.contains);

  // в момент закрытия: панель с треем часто поднимается позже автозапуска
  Future<bool> _trayAvailable() async {
    try {
      return await trayManager.isAvailable();
    } catch (_) {
      return true;
    }
  }

  Future<void> _showWindow() async {
    uiVisible.value = true;
    await windowManager.show();
    await windowManager.focus();
  }

  Timer? _boundsSaveDebounce;

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
    _boundsSaveDebounce =
        Timer(const Duration(milliseconds: 600), () => _saveWindowBounds());
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
    _saveWindowBounds();
    unawaited(_onCloseButton());
  }

  Future<void> _onCloseButton() async {
    if (await closeToBackground()) {
      await _sendToBackground();
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

  // на Wayland другого сигнала о возврате из панели задач нет
  @override
  void onWindowFocus() => uiVisible.value = true;

  @override
  void onWindowResize() => _scheduleBoundsSave();

  @override
  void onWindowMove() => _scheduleBoundsSave();

  @override
  void onWindowMaximize() => _scheduleBoundsSave();

  @override
  void onWindowUnmaximize() => _scheduleBoundsSave();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _showWindow();
      case 'quit':
        quit();
    }
  }

  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    try {
      await onQuit?.call();
    } catch (_) {}
    _boundsSaveDebounce?.cancel();
    await _saveWindowBounds();
    try {
      await trayManager.destroy();
    } catch (_) {}
    // окно, уничтоженное посреди кадра, роняет движок (abort в g_mutex_clear), поэтому сначала прячем
    await windowManager.hide();
    await Future<void>.delayed(quitSettleDelay);
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }
}

