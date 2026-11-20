import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';

/// Словарь немецкого и китайского сверен с клиентами на этих языках (Clash
/// Verge, Mullvad, Proton, WireGuard, AOSP; v2rayN, v2rayNG, NekoBox, Hiddify,
/// Throne, FlClash). Хозяйка этих языков не читает, поэтому новая строка с
/// чужим термином или английской пунктуацией ловится здесь, а не на экране.
void main() {
  Map<String, String> strings(String locale) {
    final raw =
        jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
            as Map<String, dynamic>;
    return {
      for (final e in raw.entries)
        if (!e.key.startsWith('@')) e.key: e.value as String,
    };
  }

  // Пример адреса подписки печатается как есть, многоточие в нём — часть URL.
  const urlExample = 'subscriptionUrlHint';

  List<String> offending(Map<String, String> s, RegExp pattern) => [
    for (final e in s.entries)
      if (e.key != urlExample && pattern.hasMatch(e.value)) e.key,
  ];

  test('every language has every string', () {
    final en = strings('en');
    for (final locale in AppLocalizations.supportedLocales) {
      final tr = strings(locale.languageCode);
      expect(
        en.keys.where((k) => !tr.containsKey(k)),
        isEmpty,
        reason: '${locale.languageCode}: без перевода покажется английский',
      );
    }
  });

  group('German', () {
    final de = strings('de');

    test('addresses the user with du, like Android itself', () {
      expect(offending(de, RegExp(r'\b(Sie|Ihr|Ihre|Ihnen)\b')), isEmpty);
    });

    test('keeps one word per thing', () {
      // «Abo», «Core», «Provider» стояли вперемешку с полными словами.
      expect(
        offending(de, RegExp(r'\bAbos?\b|\bAbo-|\bCore\b|\bProvider\b')),
        isEmpty,
      );
    });

    test('uses German typography', () {
      expect(offending(de, RegExp(r'"|\.\.\.| — ')), isEmpty);
    });
  });

  group('Chinese', () {
    final zh = strings('zh');
    final cjk = RegExp(r'[一-鿿]');

    test('uses the terms of Chinese proxy clients', () {
      // 服务商 — как у v2rayN/v2rayNG; 您 — как у Android и почти всех клиентов.
      expect(offending(zh, RegExp('提供商|你')), isEmpty);
    });

    test('uses mainland punctuation', () {
      // 「」 — кавычки Тайваня и Гонконга; в упрощённом письме “”.
      expect(offending(zh, RegExp(r'「|」|\.\.\.')), isEmpty);
      final asciiParens = [
        for (final e in zh.entries)
          if (cjk.hasMatch(e.value) && RegExp(r'[()]').hasMatch(e.value)) e.key,
      ];
      expect(
        asciiParens,
        isEmpty,
        reason: 'в китайской фразе скобки полноширинные: （）',
      );
    });
  });
}
