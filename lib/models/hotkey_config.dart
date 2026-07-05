import 'package:flutter/services.dart';

/// Действия, на которые можно повесить хоткей (desktop). Все выключены,
/// пока пользователь сам не назначит сочетание.
enum HotkeyAction {
  toggleConnection('toggleConnection'),
  toggleTunMode('toggleTunMode'),
  bestPingServer('bestPingServer'),
  toggleWindow('toggleWindow');

  /// Стабильный id: ключ в настройках и идентификатор в native-канале.
  final String id;
  const HotkeyAction(this.id);

  static HotkeyAction? fromId(String? id) {
    for (final a in values) {
      if (a.id == id) return a;
    }
    return null;
  }
}

/// Сочетание клавиш: модификаторы + основная клавиша (токен из [HotkeyKeys]).
///
/// Матчинг идёт по ФИЗИЧЕСКОЙ клавише (как Ctrl+V-вставка в приложении):
/// на ЙЦУКЕН-раскладке логическая клавиша была бы «т», а физическая — keyT,
/// поэтому сочетание работает на любой раскладке.
class HotkeyBinding {
  final bool ctrl;
  final bool alt;
  final bool shift;
  final bool meta;

  /// Токен основной клавиши, например `keyT`, `f5`, `arrowUp`.
  final String key;

  const HotkeyBinding({
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
    this.meta = false,
    required this.key,
  });

  /// Сериализация в строку настроек: `ctrl+shift+keyT`.
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

  /// Голая буква/цифра глобальным хоткеем перехватила бы обычный набор текста
  /// во всех приложениях. F-клавиши разрешены без модификаторов (как в OBS).
  bool get isValid {
    if (HotkeyKeys.isFunctionKey(key)) return true;
    return ctrl || alt || shift || meta;
  }

  /// Человекочитаемая метка: `Ctrl + Shift + T`.
  String get label => [
        if (ctrl) 'Ctrl',
        if (alt) 'Alt',
        if (shift) 'Shift',
        if (meta) 'Win',
        HotkeyKeys.labelFor(key),
      ].join(' + ');

  /// Маска RegisterHotKey: MOD_ALT=1, MOD_CONTROL=2, MOD_SHIFT=4, MOD_WIN=8.
  int get windowsModifiers =>
      (alt ? 1 : 0) | (ctrl ? 2 : 0) | (shift ? 4 : 0) | (meta ? 8 : 0);

  int? get windowsKeyCode => HotkeyKeys.vkFor(key);

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

/// Таблица поддерживаемых основных клавиш: токен → физическая клавиша,
/// Windows virtual-key code и отображаемая метка.
class HotkeyKeys {
  HotkeyKeys._();

  static const Map<String, _KeyEntry> _entries = {
    // Буквы: VK 0x41..0x5A.
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
    // Цифры верхнего ряда: VK 0x30..0x39.
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
    // F-клавиши: VK 0x70..0x7B.
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
    // Навигация и прочее.
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

  // Обратный индекс PhysicalKeyboardKey.usbHidUsage → токен (для захвата).
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
