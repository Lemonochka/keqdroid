import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';

// Выбранный язык обязан пережить перезапуск: настройки сохраняются в JSON и
// читаются обратно. Фарси проходил только первую половину: выбрать его было
// можно, а после перезапуска он молча становился системным.
void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    final code = locale.languageCode;
    test('язык «$code» переживает перезапуск', () {
      final saved = AppSettings(appLanguageCode: code).toJsonString();
      expect(AppSettings.fromJsonString(saved).appLanguageCode, code);
    });
  }

  test('неизвестный код — системный язык', () {
    const saved = '{"appLanguageCode":"xx"}';
    expect(AppSettings.fromJsonString(saved).appLanguageCode, 'system');
  });
}
