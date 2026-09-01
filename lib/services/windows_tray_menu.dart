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

/// Меню трея на Windows — НАТИВНОЕ, через `tray_manager`.
///
/// Прежде меню рисовал Flutter: то же окно приложения на время превращалось в
/// попап — менялся стиль на `WS_POPUP`, размер на 288px, z-порядок на topmost,
/// вешался глобальный мышиный хук, скруглялись углы через DWM, а потом всё это
/// откатывалось. Каждый шаг мог не откатиться, и отсюда росла вся семья багов:
/// «микроокно без рамки» (под неё в C++ была отдельная функция-спасатель),
/// «меню не открывается» (рассинхрон флага между C++ и Dart) и окно поверх
/// панели задач (снятый только в ex-стиле, но не в z-порядке topmost).
///
/// Здесь меню — обычный `TrackPopupMenu` самой Windows: окно приложения никто
/// не трогает, а позиционирование, DPI, мультимонитор, закрытие по клику мимо и
/// клавиатурная навигация достаются от системы бесплатно. Linux в этом
/// приложении так работал всегда — теперь платформы одинаковы.
///
/// Цена — вид: меню системное, а не в теме приложения, и без кружков с флагами.
class WindowsTrayMenu with TrayListener {
  WindowsTrayMenu(this._ref);

  final Ref _ref;

  /// Иконка трея. `.ico` вместо `.png` намеренно: Windows берёт из ico кадр
  /// нужного размера, а один отмасштабированный png в трее мылится.
  static const _iconAsset = 'assets/tray_icon.ico';

  static const _keyToggleVpn = 'vpn';
  static const _keyModeProxy = 'mode.proxy';
  static const _keyModeTun = 'mode.tun';
  static const _keyOpen = 'open';
  static const _keyExit = 'exit';
  static const _serverPrefix = 'server.';

  bool _busy = false;

  /// Меню сейчас на экране (TrackPopupMenu модален и держит нас в await).
  bool _menuOpen = false;

  /// Когда меню закрылось в последний раз — см. [_reopenGuard].
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
    } catch (_) {
      // Выходим в любом случае — иконку подберёт завершение процесса.
    }
  }

  // --- события иконки ---------------------------------------------------

  @override
  void onTrayIconMouseDown() {
    // Левый клик — развернуть окно. Меню он не открывает: так же ведут себя
    // Telegram и Discord, и так же вела себя прежняя реализация.
    WindowsDesktopService.restoreMainWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    // Повторный правый клик обязан ЗАКРЫТЬ меню, а не открыть новое.
    //
    // Само закрытие делает Windows: `TrackPopupMenu` модален и гасит меню от
    // клика где угодно, в том числе по иконке трея. Но следом этот же клик
    // приезжает к нам обычным уведомлением от иконки — и меню открывалось
    // заново, будто оно и не закрывалось.
    //
    // Ловим двумя способами сразу, потому что порядок «меню закрылось» и
    // «пришло уведомление» не гарантирован: флагом — если уведомление успело
    // прийти, пока меню ещё живо, и окном времени — если уже после.
    if (_menuOpen) return;
    final closedAt = _menuClosedAt;
    if (closedAt != null &&
        DateTime.now().difference(closedAt) < _reopenGuard) {
      _menuClosedAt = null;
      return;
    }
    _showMenu();
  }

  /// Сколько после закрытия меню правый клик считается «тем самым, который его
  /// и закрыл». Человек не успевает осознанно кликнуть повторно быстрее.
  static const _reopenGuard = Duration(milliseconds: 300);

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key;
    if (key == null) return;
    _handle(key);
  }

  // --- построение меню --------------------------------------------------

  /// Меню собирается ЗАНОВО на каждый правый клик, а не поддерживается живым.
  ///
  /// Иначе его пришлось бы пересобирать на каждое изменение статуса, списка
  /// серверов и настроек — то есть держать подписки ради окна, которого 99%
  /// времени нет на экране. А правый клик и так даёт точку, где состояние
  /// заведомо свежее.
  Future<void> _showMenu() async {
    if (_menuOpen) return;
    _menuOpen = true;
    try {
      await trayManager.setContextMenu(await _buildMenu());
      // Возвращается, когда меню закрыто: `TrackPopupMenu` модален.
      //
      // Флаг `bringAppToFront` не нужен и ни на что не влияет: в нашей копии
      // пакета меню принадлежит отдельному невидимому окну, а окно приложения
      // не активируется вовсе (см. third_party/tray_manager/PATCH.md).
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
      // Статус — неактивным пунктом: в нативном меню это единственный способ
      // показать текст, который не нажимается.
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
        // «Отключить» доступен и во время подключения — это отмена попытки.
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

  /// Серверы, сгруппированные по подпискам. Группы становятся вложенными
  /// подменю — в нативном меню это единственная иерархия, а плоский список из
  /// сотни строк без заголовков не читается вовсе.
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

    // Имена подписок берём из провайдера: у ServerItem.subscriptionName часто
    // пусто, и группа получала бы заголовок «Подписки» вместо своего имени.
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

    // Одна группа — незачем прятать её в ещё одно подменю.
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

  /// Длина, после которой Windows вешает на меню кнопки прокрутки.
  ///
  /// Точного числа нет — оно зависит от высоты рабочей области и высоты пункта,
  /// на ноутбучном экране это примерно три десятка. Берём с запасом: 24 пункта
  /// в одном меню и так предел читаемости.
  static const _maxItemsPerMenu = 24;

  /// Режет длинный список на подменю, чтобы прокрутка не появлялась.
  ///
  /// Это про читаемость: полсотни строк подряд в нативном меню не
  /// просматриваются, а кнопки прокрутки Win32-меню — худший способ листать
  /// список из всех возможных.
  ///
  /// Уезжание меню под панель задач, с которого началась эта нарезка, лечится
  /// не здесь, а позиционированием в нашей копии пакета: меню встаёт на границу
  /// рабочей области (third_party/tray_manager/PATCH.md).
  ///
  /// Подписи кусков — по крайним именам: «Германия … Польша» показывает, что
  /// внутри, а «1–24» не показывает ничего.
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
    // Кусков тоже может набраться больше предела — тогда режем ещё раз.
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

  /// Имя для подписи куска: длинные режем, иначе подпись шире самого меню.
  static String _short(String name) {
    final trimmed = name.trim();
    return trimmed.length <= 14 ? trimmed : '${trimmed.substring(0, 13)}…';
  }

  // --- действия ---------------------------------------------------------

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
      // В трее нет снекбаров: ошибку в лог, а статус увидит следующее открытие
      // меню — там он читается из того же провайдера.
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
        final status =
            _ref.read(vpnStateProvider).value?.status ?? VpnStatus.disconnected;
        final tunnelActive = status == VpnStatus.connected ||
            status == VpnStatus.connecting;
        // Повторный выбор активного сервера туннель не перезапускает.
        if (tunnelActive && server.id == serversState.activeServer?.id) return;
        await _ref.read(serversProvider.notifier).setActive(server);
        if (tunnelActive) {
          await _ref.read(vpnStateProvider.notifier).reconnectToActiveServer();
        }
      }, 'server select');

  /// Смена режима.
  ///
  /// TUN на Windows требует прав администратора, и перезапуск с UAC показывает
  /// диалог — а диалогу нужен экран. Поэтому здесь окно сперва разворачивается,
  /// и всё остальное происходит уже в приложении: в прежней реализации ровно за
  /// этим тянулся хвост «взять всё из ref ДО закрытия меню, иначе ref мёртв».
  Future<void> _setMode(ConnectionMode next) => _guard(() async {
        final settings =
            _ref.read(settingsNotifierProvider).value ?? const AppSettings();
        if (next == settings.connectionModeEnum) return;
        // Окно разворачиваем ЗАРАНЕЕ: переход в TUN может спросить про
        // перезапуск с правами администратора, а диалогу нужен экран. Раньше
        // ради этого же меню закрывалось вручную, и дальше тянулся хвост
        // «взять всё из ref до закрытия, иначе ref мёртв» — нативное меню к
        // этому моменту уже закрыто самой Windows.
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
    // Симметрично Linux (tray Quit): сперва рвём туннель, иначе системный прокси
    // остаётся указывать на мёртвый 127.0.0.1-порт и после выхода ломает
    // интернет во всей системе.
    try {
      await _ref.read(vpnStateProvider.notifier).disconnect();
    } catch (_) {
      // Выходим в любом случае; стартовая зачистка подберёт остатки.
    }
    await WindowsDesktopService.exitApp();
  }

  // --- локализация ------------------------------------------------------

  /// Строки меню вне дерева виджетов: `AppLocalizations.of(context)` тут нет.
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

/// Живёт всё время работы приложения: меню трея доступно и тогда, когда окно
/// спрятано, поэтому провайдер держится за корневой контейнер, а не за экран.
final windowsTrayMenuProvider = Provider<WindowsTrayMenu?>((ref) {
  if (!Platform.isWindows) return null;
  final menu = WindowsTrayMenu(ref);
  ref.onDispose(menu.dispose);
  menu.init();
  return menu;
});
