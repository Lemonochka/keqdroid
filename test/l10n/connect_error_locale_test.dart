import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/utils/error_messages.dart';

/// Текст ошибки под кнопкой подключения на главном экране.
///
/// Показывался по-английски на любой локали — не потому, что перевода нет, а
/// потому, что вызов шёл через перегрузку без `BuildContext`, и локализацию
/// просто не спрашивали.
///
/// Тест сторожит обе стороны правки: на `en` строка обязана остаться ровно той
/// же, что была до неё, на `ru` — стать русской. Первое важнее: если бы
/// перегрузка была выбрана неправильно, английский текст тоже поехал бы.
Future<String> _renderFor(WidgetTester tester, String locale, Object error) async {
  late String rendered;
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          rendered = friendlyError(error, context);
          return const SizedBox();
        },
      ),
    ),
  );
  return rendered;
}

void main() {
  group('текст ошибки подключения', () {
    // Строка, которую explainError разбирает в осмысленный код, а не в unknown:
    // у unknown message остаётся сырым по построению.
    const error = 'permission denied';

    testWidgets('на en текст совпадает с прежним хардкодом', (tester) async {
      // Главный инвариант правки. Раньше сюда приходил explainError(e).full —
      // английский текст мимо локализации. Теперь тот же текст приходит из ARB,
      // и он обязан совпасть посимвольно: иначе англоязычные пользователи
      // молча получили бы другую формулировку.
      expect(await _renderFor(tester, 'en', error), explainError(error).full);
    });

    testWidgets('заголовок различает коды, а не только вид ошибки',
        (tester) async {
      // До правки заголовок брался по UiErrorKind: шесть видов на одиннадцать
      // кодов, поэтому «лимит устройств» и «отказ авторизации» показывались
      // одинаковым «Connection failed: auth». Теперь у каждого свой.
      final deviceLimit = await _renderFor(tester, 'en', 'device limit reached');
      final authDenied = await _renderFor(tester, 'en', 'unauthorized');

      expect(deviceLimit.split('\n').first, 'Device Limit Reached');
      expect(authDenied.split('\n').first, isNot('Device Limit Reached'));
    });

    testWidgets('на ru текст на русском', (tester) async {
      final rendered = await _renderFor(tester, 'ru', error);

      expect(rendered, contains('Действие: '));
      expect(rendered, isNot(equals(explainError(error).full)));
    });

    testWidgets('локаль без перевода действия не ломает формат', (tester) async {
      // Три строки: заголовок, сообщение, действие — на любой локали.
      for (final locale in ['en', 'ru', 'de', 'zh', 'fa']) {
        final rendered = await _renderFor(tester, locale, error);
        expect(rendered.split('\n').length, 3, reason: 'локаль $locale');
      }
    });
  });
}
