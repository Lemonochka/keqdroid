import 'dart:ui';

import '../l10n/app_localizations.dart';
import '../models/subscription.dart';
import '../utils/app_locale.dart';
import 'storage_service.dart';

const expiryReminderWindow = Duration(days: 3);

String _day(DateTime t) => '${t.year}-${t.month}-${t.day}';

String _date(DateTime t) => '${t.day.toString().padLeft(2, '0')}.'
    '${t.month.toString().padLeft(2, '0')}.${t.year}';

// как у Happ по notification-subs-expire: раз в день в последние трое суток, пока срок не продлили
List<Subscription> expiryRemindersDue(
  List<Subscription> subs, {
  required DateTime now,
  required Map<String, String> reminded,
}) =>
    [
      for (final s in subs)
        if (s.remindExpiry &&
            s.expiresAt != null &&
            s.expiresAt!.isAfter(now) &&
            s.expiresAt!.difference(now) <= expiryReminderWindow &&
            reminded[s.id] != _day(now))
          s,
    ];

// зовут и открытое приложение, и фоновый воркер Android: иначе с VPN из плитки напоминание не дошло бы
Future<void> remindExpiringSubscriptions(
  StorageService storage,
  List<Subscription> subs, {
  required DateTime now,
  required Future<void> Function(Subscription sub, String title, String body)
      show,
}) async {
  final reminded = storage.getExpiryReminded();
  final due = expiryRemindersDue(subs, now: now, reminded: reminded);
  if (due.isEmpty) return;
  final settings = await storage.getSettings();
  final l10n = lookupAppLocalizations(resolveAppLocale(
    localeFromSettings(settings),
    PlatformDispatcher.instance.locale,
    AppLocalizations.supportedLocales,
  ));
  for (final sub in due) {
    await show(
      sub,
      l10n.subscriptionsExpiringNotifTitle,
      l10n.subscriptionsExpiringNotifBody(sub.name, _date(sub.expiresAt!)),
    );
    reminded[sub.id] = _day(now);
  }
  await storage.setExpiryReminded(reminded);
}
