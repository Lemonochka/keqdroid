import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

enum HotkeyAction {
  toggleConnection('toggleConnection'),
  toggleTunMode('toggleTunMode'),
  bestPingServer('bestPingServer'),
  toggleWindow('toggleWindow');

  final String id;
  const HotkeyAction(this.id);

  static HotkeyAction? fromId(String? id) {
    for (final a in values) {
      if (a.id == id) return a;
    }
    return null;
  }
}

// по физической клавише, чтобы сочетание работало и на ЙЦУКЕН
class HotkeyBinding {
  final bool ctrl;
  final bool alt;
  final bool shift;
  final bool meta;

  final String key;

  const HotkeyBinding({
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
    this.meta = false,
    required this.key,
  });

  String toToken() => [
    if (ctrl) 'ctrl',
    if (alt) 'alt',
    if (shift) 'shift',
    if (meta) 'meta',
    key,
  ].join('+');

  static HotkeyBinding? fromToken(String? token) {
    if (token == null || token.isEmpty) return null;
    final parts = token.split('+');
    if (parts.isEmpty) return null;
    final key = parts.last;
    if (!HotkeyKeys.isKnown(key)) return null;
    final mods = parts.sublist(0, parts.length - 1).toSet();
    final binding = HotkeyBinding(
      ctrl: mods.contains('ctrl'),
      alt: mods.contains('alt'),
      shift: mods.contains('shift'),
      meta: mods.contains('meta'),
      key: key,
    );
    return binding.isValid ? binding : null;
  }

  bool get isValid {
    if (HotkeyKeys.isFunctionKey(key)) return true;
    return ctrl || alt || shift || meta;
  }

  String get label => [
    if (ctrl) 'Ctrl',
    if (alt) Platform.isMacOS ? 'Opt' : 'Alt',
    if (shift) 'Shift',
    if (meta) Platform.isMacOS ? 'Cmd' : 'Win',
    HotkeyKeys.labelFor(key),
  ].join(' + ');

  // MOD_ALT=1, MOD_CONTROL=2, MOD_SHIFT=4, MOD_WIN=8
  int get windowsModifiers =>
      (alt ? 1 : 0) | (ctrl ? 2 : 0) | (shift ? 4 : 0) | (meta ? 8 : 0);

  int? get windowsKeyCode => HotkeyKeys.vkFor(key);

  int? get linuxEvdevCode => HotkeyKeys.evdevFor(key);

  int? get macosKeyCode => HotkeyKeys.macosFor(key);

  // формат shortcuts-spec: модификаторы и имя keysym из xkbcommon через +
  String? get portalTrigger {
    final keysym = HotkeyKeys.keysymFor(key);
    if (keysym == null) return null;
    return [
      if (ctrl) 'CTRL',
      if (alt) 'ALT',
      if (shift) 'SHIFT',
      if (meta) 'LOGO',
      keysym,
    ].join('+');
  }

  // KDE спрашивает только про новые id и держит прежнее сочетание у знакомого, поэтому сочетание входит в id
  String portalId(HotkeyAction action) =>
      '${action.id}_${toToken().replaceAll('+', '_')}';

  bool matches(PhysicalKeyboardKey physical, HardwareKeyboard hk) {
    final token = HotkeyKeys.tokenForPhysical(physical);
    if (token != key) return false;
    return ctrl == hk.isControlPressed &&
        alt == hk.isAltPressed &&
        shift == hk.isShiftPressed &&
        meta == hk.isMetaPressed;
  }

  @override
  bool operator ==(Object other) =>
      other is HotkeyBinding && other.toToken() == toToken();

  @override
  int get hashCode => toToken().hashCode;
}

class _KeyEntry {
  final PhysicalKeyboardKey physical;
  final int vk;
  final String label;
  const _KeyEntry(this.physical, this.vk, this.label);
}

class HotkeyKeys {
  HotkeyKeys._();

  static const Map<String, _KeyEntry> _entries = {
    'keyA': _KeyEntry(PhysicalKeyboardKey.keyA, 0x41, 'A'),
    'keyB': _KeyEntry(PhysicalKeyboardKey.keyB, 0x42, 'B'),
    'keyC': _KeyEntry(PhysicalKeyboardKey.keyC, 0x43, 'C'),
    'keyD': _KeyEntry(PhysicalKeyboardKey.keyD, 0x44, 'D'),
    'keyE': _KeyEntry(PhysicalKeyboardKey.keyE, 0x45, 'E'),
    'keyF': _KeyEntry(PhysicalKeyboardKey.keyF, 0x46, 'F'),
    'keyG': _KeyEntry(PhysicalKeyboardKey.keyG, 0x47, 'G'),
    'keyH': _KeyEntry(PhysicalKeyboardKey.keyH, 0x48, 'H'),
    'keyI': _KeyEntry(PhysicalKeyboardKey.keyI, 0x49, 'I'),
    'keyJ': _KeyEntry(PhysicalKeyboardKey.keyJ, 0x4A, 'J'),
    'keyK': _KeyEntry(PhysicalKeyboardKey.keyK, 0x4B, 'K'),
    'keyL': _KeyEntry(PhysicalKeyboardKey.keyL, 0x4C, 'L'),
    'keyM': _KeyEntry(PhysicalKeyboardKey.keyM, 0x4D, 'M'),
    'keyN': _KeyEntry(PhysicalKeyboardKey.keyN, 0x4E, 'N'),
    'keyO': _KeyEntry(PhysicalKeyboardKey.keyO, 0x4F, 'O'),
    'keyP': _KeyEntry(PhysicalKeyboardKey.keyP, 0x50, 'P'),
    'keyQ': _KeyEntry(PhysicalKeyboardKey.keyQ, 0x51, 'Q'),
    'keyR': _KeyEntry(PhysicalKeyboardKey.keyR, 0x52, 'R'),
    'keyS': _KeyEntry(PhysicalKeyboardKey.keyS, 0x53, 'S'),
    'keyT': _KeyEntry(PhysicalKeyboardKey.keyT, 0x54, 'T'),
    'keyU': _KeyEntry(PhysicalKeyboardKey.keyU, 0x55, 'U'),
    'keyV': _KeyEntry(PhysicalKeyboardKey.keyV, 0x56, 'V'),
    'keyW': _KeyEntry(PhysicalKeyboardKey.keyW, 0x57, 'W'),
    'keyX': _KeyEntry(PhysicalKeyboardKey.keyX, 0x58, 'X'),
    'keyY': _KeyEntry(PhysicalKeyboardKey.keyY, 0x59, 'Y'),
    'keyZ': _KeyEntry(PhysicalKeyboardKey.keyZ, 0x5A, 'Z'),
    'digit0': _KeyEntry(PhysicalKeyboardKey.digit0, 0x30, '0'),
    'digit1': _KeyEntry(PhysicalKeyboardKey.digit1, 0x31, '1'),
    'digit2': _KeyEntry(PhysicalKeyboardKey.digit2, 0x32, '2'),
    'digit3': _KeyEntry(PhysicalKeyboardKey.digit3, 0x33, '3'),
    'digit4': _KeyEntry(PhysicalKeyboardKey.digit4, 0x34, '4'),
    'digit5': _KeyEntry(PhysicalKeyboardKey.digit5, 0x35, '5'),
    'digit6': _KeyEntry(PhysicalKeyboardKey.digit6, 0x36, '6'),
    'digit7': _KeyEntry(PhysicalKeyboardKey.digit7, 0x37, '7'),
    'digit8': _KeyEntry(PhysicalKeyboardKey.digit8, 0x38, '8'),
    'digit9': _KeyEntry(PhysicalKeyboardKey.digit9, 0x39, '9'),
    'f1': _KeyEntry(PhysicalKeyboardKey.f1, 0x70, 'F1'),
    'f2': _KeyEntry(PhysicalKeyboardKey.f2, 0x71, 'F2'),
    'f3': _KeyEntry(PhysicalKeyboardKey.f3, 0x72, 'F3'),
    'f4': _KeyEntry(PhysicalKeyboardKey.f4, 0x73, 'F4'),
    'f5': _KeyEntry(PhysicalKeyboardKey.f5, 0x74, 'F5'),
    'f6': _KeyEntry(PhysicalKeyboardKey.f6, 0x75, 'F6'),
    'f7': _KeyEntry(PhysicalKeyboardKey.f7, 0x76, 'F7'),
    'f8': _KeyEntry(PhysicalKeyboardKey.f8, 0x77, 'F8'),
    'f9': _KeyEntry(PhysicalKeyboardKey.f9, 0x78, 'F9'),
    'f10': _KeyEntry(PhysicalKeyboardKey.f10, 0x79, 'F10'),
    'f11': _KeyEntry(PhysicalKeyboardKey.f11, 0x7A, 'F11'),
    'f12': _KeyEntry(PhysicalKeyboardKey.f12, 0x7B, 'F12'),
    'space': _KeyEntry(PhysicalKeyboardKey.space, 0x20, 'Space'),
    'arrowLeft': _KeyEntry(PhysicalKeyboardKey.arrowLeft, 0x25, '←'),
    'arrowUp': _KeyEntry(PhysicalKeyboardKey.arrowUp, 0x26, '↑'),
    'arrowRight': _KeyEntry(PhysicalKeyboardKey.arrowRight, 0x27, '→'),
    'arrowDown': _KeyEntry(PhysicalKeyboardKey.arrowDown, 0x28, '↓'),
    'home': _KeyEntry(PhysicalKeyboardKey.home, 0x24, 'Home'),
    'end': _KeyEntry(PhysicalKeyboardKey.end, 0x23, 'End'),
    'pageUp': _KeyEntry(PhysicalKeyboardKey.pageUp, 0x21, 'PgUp'),
    'pageDown': _KeyEntry(PhysicalKeyboardKey.pageDown, 0x22, 'PgDn'),
    'insert': _KeyEntry(PhysicalKeyboardKey.insert, 0x2D, 'Ins'),
    'delete': _KeyEntry(PhysicalKeyboardKey.delete, 0x2E, 'Del'),
    'backquote': _KeyEntry(PhysicalKeyboardKey.backquote, 0xC0, '`'),
    'minus': _KeyEntry(PhysicalKeyboardKey.minus, 0xBD, '-'),
    'equal': _KeyEntry(PhysicalKeyboardKey.equal, 0xBB, '='),
    'bracketLeft': _KeyEntry(PhysicalKeyboardKey.bracketLeft, 0xDB, '['),
    'bracketRight': _KeyEntry(PhysicalKeyboardKey.bracketRight, 0xDD, ']'),
    'semicolon': _KeyEntry(PhysicalKeyboardKey.semicolon, 0xBA, ';'),
    'quote': _KeyEntry(PhysicalKeyboardKey.quote, 0xDE, "'"),
    'comma': _KeyEntry(PhysicalKeyboardKey.comma, 0xBC, ','),
    'period': _KeyEntry(PhysicalKeyboardKey.period, 0xBE, '.'),
    'slash': _KeyEntry(PhysicalKeyboardKey.slash, 0xBF, '/'),
    'backslash': _KeyEntry(PhysicalKeyboardKey.backslash, 0xDC, '\\'),
  };

  // linux/input-event-codes.h; раскладка на код не влияет, сочетание работает и на ЙЦУКЕН
  static const Map<String, int> _evdev = {
    'keyA': 30,
    'keyB': 48,
    'keyC': 46,
    'keyD': 32,
    'keyE': 18,
    'keyF': 33,
    'keyG': 34,
    'keyH': 35,
    'keyI': 23,
    'keyJ': 36,
    'keyK': 37,
    'keyL': 38,
    'keyM': 50,
    'keyN': 49,
    'keyO': 24,
    'keyP': 25,
    'keyQ': 16,
    'keyR': 19,
    'keyS': 31,
    'keyT': 20,
    'keyU': 22,
    'keyV': 47,
    'keyW': 17,
    'keyX': 45,
    'keyY': 21,
    'keyZ': 44,
    'digit0': 11,
    'digit1': 2,
    'digit2': 3,
    'digit3': 4,
    'digit4': 5,
    'digit5': 6,
    'digit6': 7,
    'digit7': 8,
    'digit8': 9,
    'digit9': 10,
    'f1': 59,
    'f2': 60,
    'f3': 61,
    'f4': 62,
    'f5': 63,
    'f6': 64,
    'f7': 65,
    'f8': 66,
    'f9': 67,
    'f10': 68,
    'f11': 87,
    'f12': 88,
    'space': 57,
    'arrowLeft': 105,
    'arrowUp': 103,
    'arrowRight': 106,
    'arrowDown': 108,
    'home': 102,
    'end': 107,
    'pageUp': 104,
    'pageDown': 109,
    'insert': 110,
    'delete': 111,
    'backquote': 41,
    'minus': 12,
    'equal': 13,
    'bracketLeft': 26,
    'bracketRight': 27,
    'semicolon': 39,
    'quote': 40,
    'comma': 51,
    'period': 52,
    'slash': 53,
    'backslash': 43,
  };

  // имена из xkbcommon-keysyms.h без XKB_KEY_; буквы строчные, это клавиша базового слоя
  static const Map<String, String> _keysyms = {
    'space': 'space',
    'arrowLeft': 'Left',
    'arrowUp': 'Up',
    'arrowRight': 'Right',
    'arrowDown': 'Down',
    'home': 'Home',
    'end': 'End',
    'pageUp': 'Page_Up',
    'pageDown': 'Page_Down',
    'insert': 'Insert',
    'delete': 'Delete',
    'backquote': 'grave',
    'minus': 'minus',
    'equal': 'equal',
    'bracketLeft': 'bracketleft',
    'bracketRight': 'bracketright',
    'semicolon': 'semicolon',
    'quote': 'apostrophe',
    'comma': 'comma',
    'period': 'period',
    'slash': 'slash',
    'backslash': 'backslash',
  };

  // Carbon HIToolbox/Events.h virtual keycodes (layout-independent ANSI positions).
  static const Map<String, int> _macosKeyCodes = {
    'keyA': 0x00,
    'keyS': 0x01,
    'keyD': 0x02,
    'keyF': 0x03,
    'keyH': 0x04,
    'keyG': 0x05,
    'keyZ': 0x06,
    'keyX': 0x07,
    'keyC': 0x08,
    'keyV': 0x09,
    'keyB': 0x0B,
    'keyQ': 0x0C,
    'keyW': 0x0D,
    'keyE': 0x0E,
    'keyR': 0x0F,
    'keyY': 0x10,
    'keyT': 0x11,
    'digit1': 0x12,
    'digit2': 0x13,
    'digit3': 0x14,
    'digit4': 0x15,
    'digit6': 0x16,
    'digit5': 0x17,
    'equal': 0x18,
    'digit9': 0x19,
    'digit7': 0x1A,
    'minus': 0x1B,
    'digit8': 0x1C,
    'digit0': 0x1D,
    'bracketRight': 0x1E,
    'keyO': 0x1F,
    'keyU': 0x20,
    'bracketLeft': 0x21,
    'keyI': 0x22,
    'keyP': 0x23,
    'keyL': 0x25,
    'keyJ': 0x26,
    'quote': 0x27,
    'keyK': 0x28,
    'semicolon': 0x29,
    'backslash': 0x2A,
    'comma': 0x2B,
    'slash': 0x2C,
    'keyN': 0x2D,
    'keyM': 0x2E,
    'period': 0x2F,
    'space': 0x31,
    'backquote': 0x32,
    'f5': 0x60,
    'f6': 0x61,
    'f7': 0x62,
    'f3': 0x63,
    'f8': 0x64,
    'f9': 0x65,
    'f11': 0x67,
    'f10': 0x6D,
    'f12': 0x6F,
    'insert': 0x72,
    'home': 0x73,
    'pageUp': 0x74,
    'delete': 0x75,
    'f4': 0x76,
    'end': 0x77,
    'f2': 0x78,
    'pageDown': 0x79,
    'f1': 0x7A,
    'arrowLeft': 0x7B,
    'arrowRight': 0x7C,
    'arrowDown': 0x7D,
    'arrowUp': 0x7E,
  };

  static int? evdevFor(String token) => _evdev[token];

  static int? macosFor(String token) => _macosKeyCodes[token];

  static String? keysymFor(String token) {
    final named = _keysyms[token];
    if (named != null) return named;
    if (token.startsWith('key') && token.length == 4) {
      return token.substring(3).toLowerCase();
    }
    if (token.startsWith('digit') && token.length == 6) {
      return token.substring(5);
    }
    if (isFunctionKey(token)) return token.toUpperCase();
    return null;
  }

  @visibleForTesting
  static Iterable<String> get allTokens => _entries.keys;

  static final Map<int, String> _byUsbHid = {
    for (final e in _entries.entries) e.value.physical.usbHidUsage: e.key,
  };

  static bool isKnown(String token) => _entries.containsKey(token);

  static bool isFunctionKey(String token) =>
      token.length >= 2 &&
      token.startsWith('f') &&
      int.tryParse(token.substring(1)) != null;

  static int? vkFor(String token) => _entries[token]?.vk;

  static String labelFor(String token) => _entries[token]?.label ?? token;

  static String? tokenForPhysical(PhysicalKeyboardKey key) =>
      _byUsbHid[key.usbHidUsage];
}
