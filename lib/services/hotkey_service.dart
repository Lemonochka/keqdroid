import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/app_logger.dart';
import '../models/hotkey_config.dart';

class HotkeyService {
  HotkeyService._();

  static const _channel = MethodChannel('keqdroid_vpn_channel');

  static bool get isSupported => Platform.isWindows || Platform.isLinux;

  static bool get isGlobal => Platform.isWindows;

  static void Function(HotkeyAction action)? onPressed;

  static bool captureMode = false;

  static Map<HotkeyAction, HotkeyBinding> _bindings = {};
  static bool _keyHandlerInstalled = false;

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

  static Future<List<String>> apply(
    Map<HotkeyAction, HotkeyBinding> bindings,
  ) async {
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

    if (Platform.isLinux) {
      if (_bindings.isEmpty) {
        _removeKeyHandler();
      } else {
        _installKeyHandler();
      }
    }
    return const [];
  }

  static void dispatchAction(String? actionId) {
    final action = HotkeyAction.fromId(actionId);
    if (action == null) return;
    onPressed?.call(action);
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
      if (entry.value.matches(event.physicalKey, hk)) {
        cb(entry.key);
        return true;
      }
    }
    return false;
  }
}
