import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';

/// Русские счётчики склоняются по последней цифре, а не по числу целиком.
///
/// `=1{…}` в ICU значит «ровно один», и 21, 31, 101 без формы `one` уходили в
/// запасную `other`: выходило «21 записи», «21 соединения». Страж смотрит
/// каждую строку с числом в русском переводе, чтобы новая не повторила ошибку.
void main() {
  test('у каждого русского счётчика есть форма one', () {
    final arb =
        jsonDecode(File('lib/l10n/app_ru.arb').readAsStringSync())
            as Map<String, dynamic>;
    final missing = [
      for (final e in arb.entries)
        if (!e.key.startsWith('@') &&
            e.value is String &&
            (e.value as String).contains('plural,') &&
            !RegExp(r'[\s,}]one\{').hasMatch(e.value as String))
          e.key,
    ];
    expect(missing, isEmpty);
  });

  test('21 — как 1, 22 — как 2, 11 и 25 — как 5', () {
    final ru = lookupAppLocalizations(const Locale('ru'));
    expect(ru.connectionsCount(1), '1 соединение');
    expect(ru.connectionsCount(21), '21 соединение');
    expect(ru.connectionsCount(22), '22 соединения');
    expect(ru.connectionsCount(11), '11 соединений');
    expect(ru.connectionsCount(25), '25 соединений');
    expect(ru.chainNodesCount(21), '21 узел');
    expect(ru.chainNodesCount(3), '3 узла');
    expect(ru.chainNodesCount(12), '12 узлов');
    expect(ru.settingsRoutingItemCount(31), '31 запись');
  });
}
