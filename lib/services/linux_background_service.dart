import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect, Size;

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_logger.dart';
import 'storage_service.dart';

/// Linux background/tray behaviour (Windows has its own native tray).
///
/// * Closing the window hides it (the tunnel keeps running) instead of quitting.
/// * The tray icon's menu restores the window / quits. AppIndicator is
///   menu-only: raw clicks are never delivered to the app, and on vanilla
///   GNOME the icon needs the AppIndicator extension to be visible.
/// * Single-instance: launching the app again brings the running window back to
///   front (the reliable way to restore on GNOME-without-tray) instead of
///   spawning a second copy.
class LinuxBackgroundService with WindowListener, TrayListener {
  LinuxBackgroundService._();
  static final LinuxBackgroundService instance = LinuxBackgroundService._();

  // Loopback "lock": only one process can bind it; later launches connect to it.
  static const int _lockPort = 47351;

  ServerSocket? _lock;

  /// Set by the UI so "Quit" can tear the tunnel down before exiting.
  Future<void> Function()? onQuit;

  /// Binds the single-instance lock. Returns `false` when another instance
  /// already holds it (after asking that instance to show its window) — the
  /// caller should then `exit(0)`.
  Future<bool> ensureSingleInstance() async {
    try {
      _lock = await ServerSocket.bind('127.0.0.1', _lockPort, shared: false);
      _lock!.listen((socket) {
        socket.destroy(); // any ping means "another launch happened" -> show
        unawaitedShow();
      });
      return true;
    } on SocketException {
      try {
        final s = await Socket.connect(
          '127.0.0.1',
          _lockPort,
          timeout: const Duration(seconds: 2),
        );
        s.add('show'.codeUnits);
        await s.flush();
        s.destroy();
      } catch (_) {
        // running instance not answering; fall through and let caller exit
      }
      return false;
    }
  }

  Future<void> initWindowAndTray() async {
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
    await _restoreWindowBounds();

    trayManager.addListener(this);
    try {
      await trayManager.setIcon('assets/icon.png');
      // Нет setToolTip: Linux-реализация tray_manager его не поддерживает
      // (MissingPluginException), а вылет здесь оставит индикатор с пустым
      // меню — AppIndicator без меню вообще не реагирует на клики.
      await trayManager.setContextMenu(
        Menu(items: [
          MenuItem(key: 'show', label: 'Show KeqDroid'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Quit'),
        ]),
      );
    } catch (e, st) {
      // No StatusNotifier/AppIndicator host (e.g. vanilla GNOME): the app still
      // runs in the background; single-instance relaunch restores the window.
      AppLogger.instance.warn(
        'Tray init failed (no AppIndicator host?). Background mode still works; '
        'relaunch the app to restore the window.',
        error: e,
        stackTrace: st,
      );
    }
  }

  void unawaitedShow() {
    _showWindow();
  }

  /// Хоткей «показать/скрыть окно»: видимое окно прячется (в фон/трей),
  /// скрытое — восстанавливается.
  Future<void> toggleWindowVisibility() async {
    if (await windowManager.isVisible()) {
      _boundsSaveDebounce?.cancel();
      await _saveWindowBounds();
      await windowManager.hide();
    } else {
      await _showWindow();
    }
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  // ---- Window bounds persistence -------------------------------------------
  //
  // GTK шлёт resize/move событиями непрерывно, поэтому запись дебаунсится.
  // Под Wayland позиция окна недоступна приложению — восстанавливается хотя бы
  // размер; на X11 работает и позиция.

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
        // Не затираем последние «нормальные» границы размером во весь экран —
        // после unmaximize окно должно вернуться к ним.
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

  // ---- WindowListener -----------------------------------------------------

  @override
  void onWindowClose() {
    // preventClose is on: hide to background rather than exit.
    _boundsSaveDebounce?.cancel();
    _saveWindowBounds();
    windowManager.hide();
  }

  @override
  void onWindowResize() => _scheduleBoundsSave();

  @override
  void onWindowMove() => _scheduleBoundsSave();

  @override
  void onWindowMaximize() => _scheduleBoundsSave();

  @override
  void onWindowUnmaximize() => _scheduleBoundsSave();

  // ---- TrayListener -------------------------------------------------------
  //
  // Только пункты меню: mouse-down событий и popUpContextMenu у AppIndicator
  // нет, меню показывает сам хост (шелл) по клику на иконку.

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _showWindow();
      case 'quit':
        _quit();
    }
  }

  Future<void> _quit() async {
    try {
      await onQuit?.call();
    } catch (_) {}
    _boundsSaveDebounce?.cancel();
    await _saveWindowBounds();
    try {
      await trayManager.destroy();
    } catch (_) {}
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }
}
