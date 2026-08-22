import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../services/hotkey_service.dart';
import '../utils/system_accent.dart';

/// android: действия из уведомления; windows: автоподключение, меню трея и хоткеи
class VpnNativeBridge {
  VpnNativeBridge._();

  static const channel = MethodChannel('keqdis_vpn_channel');

  static bool get supportsNotificationLaunch => Platform.isAndroid;
  static bool get supportsDeepLinks => Platform.isAndroid || Platform.isWindows;
  static bool get supportsAutostartNotification => Platform.isWindows;
  static bool get supportsTrayMenu => Platform.isWindows;
  static bool get supportsGlobalHotkeys => Platform.isWindows;

  static Future<void> Function(MethodCall call)? _launchHandler;
  static Future<void> Function()? _autostartHandler;
  static Future<void> Function(MethodCall call)? _trayMenuHandler;
  static Future<void> Function()? _trayMenuCloseHandler;
  static void Function(bool visible)? _windowVisibilityHandler;

  static Future<String?> getLaunchAction() async {
    if (!supportsNotificationLaunch) return null;
    return channel.invokeMethod<String>('getLaunchAction');
  }

  static Future<void> clearLaunchAction() async {
    if (!supportsNotificationLaunch) return;
    await channel.invokeMethod<void>('clearLaunchAction');
  }

  /// Ссылка vless://… или keqdroid://install-config?url=…, с которой систему
  /// попросили открыть приложение. Одноразовая: натив отдаёт и забывает её.
  ///
  /// На Windows этим же путём приходят и ссылки при живом приложении: натив
  /// держит их у себя, а `onDeepLink` только будит нас (см. ниже).
  static Future<String?> getPendingDeepLink() async {
    if (!supportsDeepLinks) return null;
    return channel.invokeMethod<String>('getPendingDeepLink');
  }

  /// Android-данные для панели «Внутренности»: каталог нативных библиотек
  /// (версии ядер читаются прямо из их файлов), PID запущенных ядер и сведения
  /// об устройстве. Пустая карта — не Android или сервис недоступен.
  static Future<Map<String, Object?>> getNativeInternals() async {
    if (!Platform.isAndroid) return const {};
    try {
      final info = await channel.invokeMapMethod<String, Object?>(
        'getNativeInternals',
      );
      return info ?? const {};
    } catch (_) {
      return const {};
    }
  }

  /// Все источники цвета системной темы разом; выбор между ними — за
  /// [pickSystemAccent]. Нужны, когда плагин dynamic_color молчит: официальный
  /// флаг Material You есть далеко не у каждой прошивки, а цвет темы у них при
  /// этом свой.
  static Future<SystemAccentCandidates> getSystemAccentCandidates() async {
    if (!Platform.isAndroid) return const SystemAccentCandidates.empty();
    try {
      final map = await channel.invokeMethod<Map<Object?, Object?>>(
        'getSystemAccentColor',
      );
      return SystemAccentCandidates.fromMap(map);
    } catch (_) {
      return const SystemAccentCandidates.empty();
    }
  }

  /// Цвета системы после смены обоев.
  ///
  /// Broadcast и без закрытия: слушателей может быть несколько (тема плюс
  /// диагностика), а живёт поток столько же, сколько само приложение.
  static final _systemAccentCtrl =
      StreamController<SystemAccentCandidates>.broadcast();

  static Stream<SystemAccentCandidates> get systemAccentChanges =>
      _systemAccentCtrl.stream;

  /// Слушать смену обоев имеет смысл только там, где её кто-то шлёт.
  static bool get supportsSystemAccentEvents => Platform.isAndroid;

  /// Лог tun2socks. Пишется только в дебаг-режиме: там на каждое соединение
  /// печатается сокет самого приложения, а больше его взять негде — в лог xray
  /// попадает уже наш собственный, со стороны SOCKS.
  static Future<String> getTun2SocksLogs({int maxLines = 600}) async {
    if (!Platform.isAndroid) return '';
    try {
      final text = await channel.invokeMethod<String>(
        'getTun2SocksLogs',
        {'maxLines': maxLines},
      );
      return text ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Координаты RESTful API у работающей mihomo-сессии: `port` и `secret`.
  ///
  /// Нужно только свежему Dart-изоляту, когда VpnService пережил пересоздание
  /// Flutter-движка (и после реконнекта из плитки — там сессию поднимает сам
  /// сервис, а Dart о ней узнаёт постфактум). Натив достаёт пару из того же
  /// файла конфига, который исполняет ядро, — расходиться им негде.
  /// null — сессии нет или она не на mihomo.
  static Future<({int port, String secret})?> getMihomoApi() async {
    if (!Platform.isAndroid) return null;
    try {
      final result = await channel.invokeMethod<Map>('getMihomoApi');
      final port = result?['port'] as int? ?? 0;
      final secret = result?['secret'] as String? ?? '';
      if (port <= 0 || secret.isEmpty) return null;
      return (port: port, secret: secret);
    } catch (_) {
      return null;
    }
  }

  /// Имена приложений-владельцев соединений, по одному на каждый элемент
  /// [connections] (`protocol`, `srcIp`, `srcPort`, `dstIp`, `dstPort`).
  ///
  /// Пустая строка — не определилось: соединение уже закрылось (система ищет
  /// его в живой таблице сокетов), Android младше 10 или у uid нет пакетов.
  static Future<List<String>> resolveConnectionOwners(
    List<Map<String, Object?>> connections,
  ) async {
    if (!Platform.isAndroid || connections.isEmpty) {
      return List.filled(connections.length, '');
    }
    try {
      final names = await channel.invokeListMethod<Object?>(
        'resolveConnectionOwners',
        {'connections': connections},
      );
      if (names == null) return List.filled(connections.length, '');
      return [for (final n in names) n?.toString() ?? ''];
    } catch (_) {
      return List.filled(connections.length, '');
    }
  }

  static void registerLaunchHandler(
    Future<void> Function(MethodCall call)? handler,
  ) {
    _launchHandler = handler;
    _syncMethodCallHandler();
  }

  static void registerAutostartHandler(
    Future<void> Function()? handler,
  ) {
    _autostartHandler = handler;
    _syncMethodCallHandler();
  }

  static void registerTrayMenuHandler(
    Future<void> Function(MethodCall call)? handler,
  ) {
    _trayMenuHandler = handler;
    _syncMethodCallHandler();
  }

  static void registerTrayMenuCloseHandler(
    Future<void> Function()? handler,
  ) {
    _trayMenuCloseHandler = handler;
    _syncMethodCallHandler();
  }

  /// Windows: окно скрыто в трей / восстановлено (нативный `onWindowVisibility`).
  static void registerWindowVisibilityHandler(
    void Function(bool visible)? handler,
  ) {
    _windowVisibilityHandler = handler;
    _syncMethodCallHandler();
  }

  static void _syncMethodCallHandler() {
    final needsHandler = supportsNotificationLaunch ||
        supportsDeepLinks ||
        supportsAutostartNotification ||
        supportsSystemAccentEvents ||
        supportsTrayMenu;
    if (!needsHandler) {
      channel.setMethodCallHandler(null);
      return;
    }
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onAutostartConnect' && supportsAutostartNotification) {
        await _autostartHandler?.call();
        return;
      }
      if (call.method == 'onTrayMenuOpen' && supportsTrayMenu) {
        await _trayMenuHandler?.call(call);
        return;
      }
      if (call.method == 'onTrayMenuClose' && supportsTrayMenu) {
        await _trayMenuCloseHandler?.call();
        return;
      }
      if (call.method == 'onWindowVisibility' && supportsTrayMenu) {
        final args = call.arguments;
        final visible = args is Map ? args['visible'] as bool? ?? true : true;
        _windowVisibilityHandler?.call(visible);
        return;
      }
      if (call.method == 'onSystemAccentChanged' && supportsSystemAccentEvents) {
        final args = call.arguments;
        _systemAccentCtrl.add(
          SystemAccentCandidates.fromMap(args is Map ? args : null),
        );
        return;
      }
      if (call.method == 'onHotkeyPressed' && supportsGlobalHotkeys) {
        final args = call.arguments;
        HotkeyService.dispatchAction(
          args is Map ? args['action'] as String? : null,
        );
        return;
      }
      await _launchHandler?.call(call);
    });
  }
}

