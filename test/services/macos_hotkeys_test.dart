import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/hotkey_config.dart';

void main() {
  test('every recordable key token has a unique Carbon virtual keycode', () {
    final seen = <int, String>{};
    for (final token in HotkeyKeys.allTokens) {
      final code = HotkeyKeys.macosFor(token);
      expect(code, isNotNull, reason: 'missing macOS keycode for $token');
      expect(
        seen.containsKey(code),
        isFalse,
        reason: 'duplicate macOS keycode 0x${code!.toRadixString(16)} for '
            '$token and ${seen[code]}',
      );
      seen[code] = token;
    }
  });

  test('maps known ANSI and function keycodes accurately', () {
    expect(HotkeyKeys.macosFor('keyA'), 0x00);
    expect(HotkeyKeys.macosFor('keyK'), 0x28);
    expect(HotkeyKeys.macosFor('digit0'), 0x1D);
    expect(HotkeyKeys.macosFor('space'), 0x31);
    expect(HotkeyKeys.macosFor('f1'), 0x7A);
    expect(HotkeyKeys.macosFor('f12'), 0x6F);
    expect(HotkeyKeys.macosFor('arrowUp'), 0x7E);
  });
}
