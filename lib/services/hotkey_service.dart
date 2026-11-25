import 'dart:io';

import 'package:flutter/foundation.dart' show mapEquals, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/app_logger.dart';
import '../models/hotkey_config.dart';

enum LinuxHotkeyBackend { x11, portal, none }

class HotkeyService {
  HotkeyService._();

  static const _channel = MethodChannel('keqdroid_vpn_channel');

  // linux/runner/global_hotkeys.cc
  @visibleForTesting
  static const linuxChannel = MethodChannel('keqdroid/linux_hotkeys');

  // macos/Runner/MacosPlatformBridge.swift
  @visibleForTesting
  static const macosChannel = MethodChannel('keqdroid/macos_hotkeys');

  static bool get isSupported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static LinuxHotkeyBackend? _linuxBackend;
  static bool _macosHandlerInstalled = false;

  static bool get isGlobal =>
      Platform.isWindows ||
      Platform.isMacOS ||
      (_linuxBackend != null && _linuxBackend != LinuxHotkeyBackend.none);

  // на Wayland сочетание назначает и подтверждает сама система
  static bool get systemConfirmsBindings =>
      _linuxBackend == LinuxHotkeyBackend.portal;

  static void Function(HotkeyAction action)? onPressed;

  static bool captureMode = false;

  static Map<HotkeyAction, HotkeyBinding> _bindings = {};
  static Set<HotkeyAction> _global = {};
  static bool _keyHandlerInstalled = false;

  static Map<HotkeyAction, String> _descriptions = {};
  static List<Map<String, Object>>? _lastLinuxPayload;
  static List<String> _lastLinuxFailed = const [];

  static bool isBound(PhysicalKeyboardKey key, HardwareKeyboard hk) =>
      _bindings.values.any((binding) => binding.matches(key, hk));

  static Map<HotkeyAction, HotkeyBinding> parseBindings(
    Map<String, String> raw,
  ) {
    final out = <HotkeyAction, HotkeyBinding>{};
    raw.forEach((id, token) {
      final action = HotkeyAction.fromId(id);
      final binding = HotkeyBinding.fromToken(token);
      if (action != null && binding != null) out[action] = binding;
    });
    return out;
  }

  static Future<LinuxHotkeyBackend> linuxBackend() async {
    final known = _linuxBackend;
    if (known != null) return known;
    var backend = LinuxHotkeyBackend.none;
    try {
      final name = await linuxChannel.invokeMethod<String>('getBackend');
      backend = LinuxHotkeyBackend.values.firstWhere(
        (b) => b.name == name,
        orElse: () => LinuxHotkeyBackend.none,
      );
    } on MissingPluginException {
      // старый раннер без канала: остаются хоткеи внутри окна
    } on PlatformException catch (e) {
      AppLogger.instance.warn('Global hotkey backend check failed', error: e);
    }
    linuxChannel.setMethodCallHandler(_onLinuxCall);
    AppLogger.instance.info('Global hotkeys on Linux: ${backend.name}');
    return _linuxBackend = backend;
  }

  static Future<void> _onLinuxCall(MethodCall call) async {
    if (call.method != 'onHotkeyPressed') return;
    final args = call.arguments;
    dispatchAction(args is Map ? args['action'] as String? : null);
  }

  // descriptions нужны порталу: их показывает окно системы
  static Future<List<String>> apply(
    Map<HotkeyAction, HotkeyBinding> bindings, {
    Map<HotkeyAction, String>? descriptions,
  }) async {
    if (descriptions != null) _descriptions = Map.of(descriptions);
    _bindings = Map.of(bindings);

    if (Platform.isWindows) {
      final payload = <Map<String, Object>>[];
      bindings.forEach((action, binding) {
        final vk = binding.windowsKeyCode;
        if (vk == null) return;
        payload.add({
          'action': action.id,
          'modifiers': binding.windowsModifiers,
          'keyCode': vk,
        });
      });
      try {
        final failed = await _channel.invokeListMethod<String>(
          'setGlobalHotkeys',
          payload,
        );
        return failed ?? const [];
      } on PlatformException catch (e, st) {
        AppLogger.instance.warn(
          'Failed to register global hotkeys',
          error: e,
          stackTrace: st,
        );
        return const [];
      }
    }

    if (Platform.isLinux) return _applyLinux(bindings);
    if (Platform.isMacOS) return _applyMacos(bindings);
    return const [];
  }

  static Future<List<String>> _applyMacos(
    Map<HotkeyAction, HotkeyBinding> bindings,
  ) async {
    if (!_macosHandlerInstalled) {
      macosChannel.setMethodCallHandler(_onLinuxCall);
      _macosHandlerInstalled = true;
    }
    final payload = <Map<String, Object>>[];
    bindings.forEach((action, binding) {
      final code = binding.macosKeyCode;
      if (code == null) return;
      payload.add({
        'action': action.id,
        'modifiers': binding.windowsModifiers,
        'keyCode': code,
      });
    });
    var failed = const <String>[];
    try {
      failed =
          await macosChannel.invokeListMethod<String>(
            'setGlobalHotkeys',
            payload,
          ) ??
          const [];
    } on MissingPluginException {
      failed = [for (final a in bindings.keys) a.id];
    } on PlatformException catch (e, st) {
      AppLogger.instance.warn(
        'Failed to register macOS global hotkeys',
        error: e,
        stackTrace: st,
      );
      failed = [for (final a in bindings.keys) a.id];
    }
    _global = {
      for (final action in bindings.keys)
        if (!failed.contains(action.id)) action,
    };
    _syncKeyHandler();
    return failed;
  }

  @visibleForTesting
  static Future<List<String>> applyLinuxForTesting(
    Map<HotkeyAction, HotkeyBinding> bindings, {
    Map<HotkeyAction, String>? descriptions,
  }) {
    if (descriptions != null) _descriptions = Map.of(descriptions);
    _bindings = Map.of(bindings);
    return _applyLinux(bindings);
  }

  static Future<List<String>> _applyLinux(
    Map<HotkeyAction, HotkeyBinding> bindings,
  ) async {
    final backend = await linuxBackend();
    if (backend == LinuxHotkeyBackend.none) {
      _global = {};
      _syncKeyHandler();
      return const [];
    }
    // снятие набора закрывает сессию портала, и новая снова спросит пользователя;
    // на время записи сочетания держим прежний
    if (backend == LinuxHotkeyBackend.portal &&
        captureMode &&
        bindings.isEmpty) {
      return const [];
    }

    final payload = linuxPayload(bindings, _descriptions);
    final last = _lastLinuxPayload;
    if (last != null && _samePayload(last, payload)) {
      return _reportable(backend, _lastLinuxFailed);
    }
    _lastLinuxPayload = payload;

    var failed = const <String>[];
    try {
      failed =
          await linuxChannel.invokeListMethod<String>(
            'setGlobalHotkeys',
            payload,
          ) ??
          const [];
    } on PlatformException catch (e, st) {
      AppLogger.instance.warn(
        'Failed to register global hotkeys',
        error: e,
        stackTrace: st,
      );
      failed = [for (final a in bindings.keys) a.id];
    }
    // пока ждали окно портала, набор мог смениться: отвечает уже следующий вызов
    if (!identical(_lastLinuxPayload, payload)) return const [];
    _lastLinuxFailed = failed;
    _global = {
      for (final action in bindings.keys)
        if (!failed.contains(action.id)) action,
    };
    _syncKeyHandler();
    if (failed.isNotEmpty) {
      AppLogger.instance.info(
        'Global hotkeys not taken by ${backend.name}: ${failed.join(', ')}',
      );
    }
    return _reportable(backend, failed);
  }

  // отказ в окне портала не говорит, что сочетание занято, поэтому про занято другим приложением молчим
  static List<String> _reportable(
    LinuxHotkeyBackend backend,
    List<String> failed,
  ) => backend == LinuxHotkeyBackend.portal ? const [] : failed;

  @visibleForTesting
  static List<Map<String, Object>> linuxPayload(
    Map<HotkeyAction, HotkeyBinding> bindings,
    Map<HotkeyAction, String> descriptions,
  ) => [
    for (final MapEntry(key: action, value: binding) in bindings.entries)
      {
        'action': action.id,
        'evdevCode': binding.linuxEvdevCode ?? 0,
        'modifiers': binding.windowsModifiers,
        'portalId': binding.portalId(action),
        'trigger': binding.portalTrigger ?? '',
        'description': descriptions[action] ?? action.id,
      },
  ];

  static bool _samePayload(
    List<Map<String, Object>> a,
    List<Map<String, Object>> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!mapEquals(a[i], b[i])) return false;
    }
    return true;
  }

  static void dispatchAction(String? actionId) {
    if (captureMode) return;
    final action = HotkeyAction.fromId(actionId);
    if (action == null) return;
    onPressed?.call(action);
  }

  // глобально взятое сочетание до окна не доходит; остальные ловим, пока окно в фокусе
  static void _syncKeyHandler() {
    final local = _bindings.keys.any((a) => !_global.contains(a));
    if (local) {
      _installKeyHandler();
    } else {
      _removeKeyHandler();
    }
  }

  static void _installKeyHandler() {
    if (_keyHandlerInstalled) return;
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    _keyHandlerInstalled = true;
  }

  static void _removeKeyHandler() {
    if (!_keyHandlerInstalled) return;
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _keyHandlerInstalled = false;
  }

  static bool _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (captureMode) return false;
    final cb = onPressed;
    if (cb == null || _bindings.isEmpty) return false;
    if (FocusManager.instance.primaryFocus?.context?.widget is EditableText) {
      return false;
    }
    final hk = HardwareKeyboard.instance;
    for (final entry in _bindings.entries) {
      if (_global.contains(entry.key)) continue;
      if (entry.value.matches(event.physicalKey, hk)) {
        cb(entry.key);
        return true;
      }
    }
    return false;
  }

  @visibleForTesting
  static void resetForTesting() {
    _linuxBackend = null;
    _macosHandlerInstalled = false;
    _bindings = {};
    _global = {};
    _descriptions = {};
    _lastLinuxPayload = null;
    _lastLinuxFailed = const [];
    _removeKeyHandler();
    captureMode = false;
    onPressed = null;
  }
}
