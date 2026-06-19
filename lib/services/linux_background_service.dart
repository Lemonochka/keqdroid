import 'dart:io';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_logger.dart';

/// Linux background/tray behaviour (Windows has its own native tray).
///
/// * Closing the window hides it (the tunnel keeps running) instead of quitting.
/// * A tray icon restores the window / quits — on vanilla GNOME the icon needs
///   the AppIndicator extension to be visible.
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

    trayManager.addListener(this);
    try {
      await trayManager.setIcon('assets/icon.png');
      await trayManager.setToolTip('KeqDroid');
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

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  // ---- WindowListener -----------------------------------------------------

  @override
  void onWindowClose() {
    // preventClose is on: hide to background rather than exit.
    windowManager.hide();
  }

  // ---- TrayListener -------------------------------------------------------

  @override
  void onTrayIconMouseDown() => _showWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

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
    try {
      await trayManager.destroy();
    } catch (_) {}
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }
}
