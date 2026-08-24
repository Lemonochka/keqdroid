import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/tun_settings.dart';

/// Подписи под полями TUN называют умолчания числом, и число это живёт в другом
/// файле. Когда умолчание сменили (`system`/1400 → `gvisor`/9000), подпись
/// осталась прежней — пользователь читал «по умолчанию 1400» над полем, где
/// стояло 9000, и это выглядело как сбитая настройка, а не как устаревший
/// текст. Пять локалей забыть ещё легче, чем одну.
void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    test('подпись MTU (${locale.languageCode}) называет актуальное умолчание',
        () async {
      final l10n = await AppLocalizations.delegate.load(locale);

      expect(
        l10n.settingsTunMtuHint,
        contains('${TunSettings.defaultMtu}'),
        reason: 'подпись обязана совпадать с TunSettings.defaultMtu',
      );
      expect(
        l10n.settingsTunUdpTimeoutHint,
        contains('${TunSettings.defaultUdpTimeoutSec}'),
      );
    });
  }

  test('подписи полей не пережили смену умолчаний незамеченными', () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
      en.settingsTunMtuHint,
      isNot(contains('1400')),
      reason: 'прежнее умолчание MTU',
    );
  });
}
