import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';

import '../app/app.dart';
import '../core/app_logger.dart';
import '../l10n/app_localizations.dart';
import '../models/app_settings.dart';
import '../models/server_item.dart';
import '../providers/providers.dart';
import '../services/vpn_engine.dart';
import '../services/windows_desktop_service.dart';
import '../ui/desktop/desktop_connection_mode.dart';
import '../utils/app_locale.dart';

class WindowsTrayMenu with TrayListener {
  WindowsTrayMenu(this._ref);

  final Ref _ref;

  // ico, чтобы Windows взяла кадр нужного размера, png в трее мылится
  static const _iconAsset = 'assets/tray_icon.ico';

  static const _keyToggleVpn = 'vpn';
  static const _keyModeProxy = 'mode.proxy';
  static const _keyModeTun = 'mode.tun';
  static const _keyOpen = 'open';
  static const _keyExit = 'exit';
  static const _serverPrefix = 'server.';

  bool _busy = false;

  bool _menuOpen = false;

  DateTime? _menuClosedAt;

  Future<void> init() async {
    trayManager.addListener(this);
    try {
      await trayManager.setIcon(_iconAsset);
      await trayManager.setToolTip('KeqDroid');
    } catch (e, st) {
      AppLogger.instance.warn(
        'Tray icon init failed',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> dispose() async {
    trayManager.removeListener(this);
    try {
      await trayManager.destroy();
    } catch (_) {}
  }

  @override
  void onTrayIconMouseDown() {
    WindowsDesktopService.restoreMainWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    // повторный правый клик должен закрыть меню: Windows гасит его сама, но тот же клик
    // приходит к нам уведомлением. ловим и флагом, и окном времени, порядок не гарантирован
    if (_menuOpen) return;
    final closedAt = _menuClosedAt;
    if (closedAt != null &&
        DateTime.now().difference(closedAt) < _reopenGuard) {
      _menuClosedAt = null;
      return;
    }
    _showMenu();
  }

  static const _reopenGuard = Duration(milliseconds: 300);

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key;
    if (key == null) return;
    _handle(key);
  }

  Future<void> _showMenu() async {
    if (_menuOpen) return;
    _menuOpen = true;
    try {
      await trayManager.setContextMenu(await _buildMenu());
      // TrackPopupMenu модален, вернёмся после закрытия (патч пакета: third_party/tray_manager/PATCH.md)
      await trayManager.popUpContextMenu();
    } catch (e, st) {
      AppLogger.instance.warn(
        'Tray menu popup failed',
        error: e,
        stackTrace: st,
      );
    } finally {
      _menuOpen = false;
      _menuClosedAt = DateTime.now();
    }
  }

  Future<Menu> _buildMenu() async {
    final l10n = await _l10n();
    final settings =
        _ref.read(settingsNotifierProvider).value ?? const AppSettings();
    final serversState = _ref.read(serversProvider);
    final servers = serversState.servers;
    final active = serversState.activeServer;
    final status =
        _ref.read(vpnStateProvider).value?.status ?? VpnStatus.disconnected;

    final busy = _busy ||
        status == VpnStatus.connecting ||
        status == VpnStatus.disconnecting;
    final connected =
        status == VpnStatus.connected || status == VpnStatus.connecting;

    final items = <MenuItem>[
      MenuItem(
        label: switch (status) {
          VpnStatus.connected => l10n.trayStatusConnected,
          VpnStatus.connecting => l10n.vpnConnecting,
          VpnStatus.disconnecting => l10n.vpnDisconnecting,
          VpnStatus.error => l10n.trayStatusError,
          _ => l10n.trayStatusDisconnected,
        },
        disabled: true,
      ),
      MenuItem.separator(),
      MenuItem(
        key: _keyToggleVpn,
        label: connected ? l10n.trayDisconnect : l10n.trayConnect,
        disabled: connected ? _busy : (active == null || busy),
      ),
      MenuItem.separator(),
      MenuItem.checkbox(
        key: _keyModeProxy,
        label: l10n.trayModeProxy,
        checked: settings.connectionModeEnum == ConnectionMode.proxy,
        disabled: busy,
      ),
      MenuItem.checkbox(
        key: _keyModeTun,
        label: l10n.trayModeTun,
        checked: settings.connectionModeEnum == ConnectionMode.tun,
        disabled: busy,
      ),
      MenuItem.separator(),
    ];

    if (servers.isEmpty) {
      items.add(MenuItem(label: l10n.trayPickServer, disabled: true));
    } else {
      items.add(
        MenuItem.submenu(
          label: active?.cleanName ?? l10n.trayPickServer,
          disabled: busy,
          submenu: Menu(
            items: _serverItems(servers: servers, active: active, l10n: l10n),
          ),
        ),
      );
    }

    items.addAll([
      MenuItem.separator(),
      MenuItem(key: _keyOpen, label: l10n.trayOpenApp),
      MenuItem(key: _keyExit, label: l10n.trayExit),
    ]);

    return Menu(items: items);
  }

  List<MenuItem> _serverItems({
    required List<ServerItem> servers,
    required ServerItem? active,
    required AppLocalizations l10n,
  }) {
    final manual = <ServerItem>[];
    final subOrder = <String>[];
    final bySub = <String, List<ServerItem>>{};
    for (final s in servers) {
      final id = s.subscriptionId;
      if (id == null) {
        manual.add(s);
      } else {
        (bySub[id] ??= (() {
          subOrder.add(id);
          return <ServerItem>[];
        })())
            .add(s);
      }
    }

    // имена из провайдера: у ServerItem.subscriptionName часто пусто
    final subs = _ref.read(subscriptionsProvider).value ?? const [];
    final subNames = {for (final s in subs) s.id: s.name};
    String subTitle(String id) {
      final fromProvider = subNames[id]?.trim() ?? '';
      if (fromProvider.isNotEmpty) return fromProvider;
      final fromServer = (bySub[id]!.first.subscriptionName ?? '').trim();
      if (fromServer.isNotEmpty) return fromServer;
      return l10n.subscriptionsTitle;
    }

    int byName(ServerItem a, ServerItem b) =>
        a.cleanName.toLowerCase().compareTo(b.cleanName.toLowerCase());

    MenuItem entry(ServerItem s) => MenuItem.checkbox(
          key: '$_serverPrefix${s.id}',
          label: s.cleanName,
          checked: s.id == active?.id,
        );

    final groups = <(String, List<ServerItem>)>[
      if (manual.isNotEmpty) (l10n.serversManualServers, manual),
      for (final id in [...subOrder]..sort(
            (a, b) => subTitle(a).toLowerCase().compareTo(
                  subTitle(b).toLowerCase(),
                ),
          ))
        (subTitle(id), bySub[id]!),
    ];

    if (groups.length <= 1) {
      final only = groups.isEmpty ? servers : groups.first.$2;
      return _chunked([...only]..sort(byName), entry);
    }

    return [
      for (final (title, list) in groups)
        MenuItem.submenu(
          label: title,
          submenu: Menu(
            items: _chunked([...list]..sort(byName), entry),
          ),
        ),
    ];
  }

  static const _maxItemsPerMenu = 24;

  static List<MenuItem> _chunked(
    List<ServerItem> servers,
    MenuItem Function(ServerItem) entry,
  ) {
    if (servers.length <= _maxItemsPerMenu) {
      return [for (final s in servers) entry(s)];
    }
    final chunks = <MenuItem>[];
    for (var i = 0; i < servers.length; i += _maxItemsPerMenu) {
      final end = math.min(i + _maxItemsPerMenu, servers.length);
      final part = servers.sublist(i, end);
      chunks.add(
        MenuItem.submenu(
          label: '${_short(part.first.cleanName)} … '
              '${_short(part.last.cleanName)}',
          submenu: Menu(items: [for (final s in part) entry(s)]),
        ),
      );
    }
    return chunks.length <= _maxItemsPerMenu
        ? chunks
        : [
            for (var i = 0; i < chunks.length; i += _maxItemsPerMenu)
              MenuItem.submenu(
                label: '${i + 1}–'
                    '${math.min(i + _maxItemsPerMenu, chunks.length)}',
                submenu: Menu(
                  items: chunks.sublist(
                    i,
                    math.min(i + _maxItemsPerMenu, chunks.length),
                  ),
                ),
              ),
          ];
  }

  static String _short(String name) {
    final trimmed = name.trim();
    return trimmed.length <= 14 ? trimmed : '${trimmed.substring(0, 13)}…';
  }

  Future<void> _handle(String key) async {
    if (key.startsWith(_serverPrefix)) {
      await _selectServer(key.substring(_serverPrefix.length));
      return;
    }
    switch (key) {
      case _keyToggleVpn:
        await _toggleVpn();
      case _keyModeProxy:
        await _setMode(ConnectionMode.proxy);
      case _keyModeTun:
        await _setMode(ConnectionMode.tun);
      case _keyOpen:
        await WindowsDesktopService.restoreMainWindow();
      case _keyExit:
        await _exit();
    }
  }

  Future<void> _guard(Future<void> Function() action, String what) async {
    if (_busy) return;
    _busy = true;
    try {
      await action();
    } catch (e, st) {
      AppLogger.instance.warn('Tray $what failed', error: e, stackTrace: st);
    } finally {
      _busy = false;
    }
  }

  Future<void> _toggleVpn() => _guard(() async {
        final status =
            _ref.read(vpnStateProvider).value?.status ?? VpnStatus.disconnected;
        final notifier = _ref.read(vpnStateProvider.notifier);
        if (status == VpnStatus.connected) {
          await notifier.disconnect();
        } else if (status == VpnStatus.connecting) {
          await notifier.cancelConnect();
        } else if (_ref.read(serversProvider).activeServer != null) {
          await notifier.connect();
        }
      }, 'VPN toggle');

  Future<void> _selectServer(String id) => _guard(() async {
        final serversState = _ref.read(serversProvider);
        ServerItem? server;
        for (final s in serversState.servers) {
          if (s.id == id) {
            server = s;
            break;
          }
        }
        if (server == null) return;
        await _ref.read(subscriptionsProvider.notifier).releaseMainGroup(server);
        final status =
            _ref.read(vpnStateProvider).value?.status ?? VpnStatus.disconnected;
        final tunnelActive = status == VpnStatus.connected ||
            status == VpnStatus.connecting;
        if (tunnelActive && server.id == serversState.activeServer?.id) return;
        await _ref.read(serversProvider.notifier).setActive(server);
        if (tunnelActive) {
          await _ref.read(vpnStateProvider.notifier).reconnectToActiveServer();
        }
      }, 'server select');

  Future<void> _setMode(ConnectionMode next) => _guard(() async {
        final settings =
            _ref.read(settingsNotifierProvider).value ?? const AppSettings();
        if (next == settings.connectionModeEnum) return;
        // окно сперва разворачиваем: переход в TUN может спросить про UAC, диалогу нужен экран
        await WindowsDesktopService.restoreMainWindow();
        final context = rootNavigatorKey.currentContext;
        if (context == null || !context.mounted) return;
        await applyDesktopConnectionMode(
          context,
          DesktopModeDeps.ofRef(_ref),
          settings,
          next,
        );
      }, 'mode switch');

  Future<void> _exit() async {
    // сначала рвём туннель, иначе системный прокси после выхода смотрит в мёртвый порт
    try {
      await _ref.read(vpnStateProvider.notifier).disconnect();
    } catch (_) {}
    await WindowsDesktopService.exitApp();
  }

  Future<AppLocalizations> _l10n() async {
    final settings =
        _ref.read(settingsNotifierProvider).value ?? const AppSettings();
    final chosen = localeFromSettings(settings);
    if (chosen != null) return AppLocalizations.delegate.load(chosen);
    final system = PlatformDispatcher.instance.locale;
    final match = AppLocalizations.supportedLocales.firstWhere(
      (l) => l.languageCode == system.languageCode,
      orElse: () => const Locale('en'),
    );
    return AppLocalizations.delegate.load(match);
  }
}

final windowsTrayMenuProvider = Provider<WindowsTrayMenu?>((ref) {
  if (!Platform.isWindows) return null;
  final menu = WindowsTrayMenu(ref);
  ref.onDispose(menu.dispose);
  menu.init();
  return menu;
});
