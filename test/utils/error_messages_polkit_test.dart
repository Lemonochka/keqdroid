import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/utils/error_messages.dart';

/// Отказ TUN на Linux, когда polkit в системе нет.
///
/// polkit у пакетов в необязательных зависимостях, и на голой системе TUN
/// падал ещё до запроса прав — а пользователь получал `ProcessException`,
/// которая печатает себя вместе со всей командой, то есть с телом root-обёртки
/// на несколько экранов. Выглядело это как «команда с неподставленными
/// аргументами» (`$1`..`$8` в теле обёртки), и человек полез разбираться
/// вручную вместо того, чтобы поставить один пакет.
///
/// Причин две, и советы у них разные: пакета нет вовсе — ставить polkit;
/// пакет есть, а агент не запущен — запускать агент. Тест сторожит и то, что
/// соседние сообщения с тем же словом «polkit» в эти ветки не проваливаются.
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
  // Ровно те строки, которые бросает LinuxTunnelBackend.
  const missing = 'TUN mode needs root through pkexec, and polkit is not '
      'installed. Install polkit with an authentication agent, or use Proxy '
      'mode.';
  const noAgent = 'Could not get root for TUN mode: no polkit agent answered '
      '(pkexec). Install/start a polkit authentication agent, or use Proxy '
      'mode.';
  const timedOut = 'Polkit authorization timed out (2 min). Approve the '
      'password prompt to start TUN mode, or use Proxy mode.';

  test('нет пакета и нет агента — разные коды', () {
    expect(explainError(missing).code, UiErrorCode.tunPolkitMissing);
    expect(explainError(noAgent).code, UiErrorCode.tunPolkitNoAgent);
  });

  test('совет соответствует причине', () {
    expect(explainError(missing).action, contains('Install polkit'));
    expect(explainError(noAgent).action, contains('Start a polkit agent'));
  });

  test('таймаут ввода пароля не выдаёт себя за отсутствие polkit', () {
    // Слово polkit в тексте есть, но пакет на месте и агент ответил: совет
    // «поставьте polkit» отправил бы человека чинить то, что не сломано.
    final code = explainError(timedOut).code;
    expect(code, isNot(UiErrorCode.tunPolkitMissing));
    expect(code, isNot(UiErrorCode.tunPolkitNoAgent));
  });

  testWidgets('на ru объяснение по-русски', (tester) async {
    final rendered = await _renderFor(tester, 'ru', missing);
    expect(rendered, contains('polkit'));
    expect(rendered, contains('прокси'));
    // Сырой английский текст исключения до пользователя не доезжает.
    expect(rendered, isNot(contains('pkexec, and polkit is not installed')));
  });

  testWidgets('на en текст тот же, что в explainError', (tester) async {
    expect(await _renderFor(tester, 'en', noAgent), explainError(noAgent).full);
  });
}
