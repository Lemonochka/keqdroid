import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/services/expiry_reminder.dart';

import '../helpers/test_storage.dart';

final _now = DateTime(2026, 11, 1, 12);

Subscription _sub(String id, {Duration? left, bool remind = true}) => Subscription(
      id: id,
      name: 'Подписка $id',
      url: 'https://$id.example/s',
      expiresAt: left == null ? null : _now.add(left),
      remindExpiry: remind,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('кому напоминать', () {
    test('только в последние трое суток и только по просьбе провайдера', () {
      final due = expiryRemindersDue(
        [
          _sub('soon', left: const Duration(days: 2)),
          _sub('edge', left: const Duration(days: 3)),
          _sub('far', left: const Duration(days: 4)),
          _sub('gone', left: const Duration(hours: -1)),
          _sub('nodate'),
          _sub('off', left: const Duration(days: 1), remind: false),
        ],
        now: _now,
        reminded: const {},
      );
      expect(due.map((s) => s.id), ['soon', 'edge']);
    });

    test('раз в день', () {
      final soon = _sub('soon', left: const Duration(days: 2));
      expect(
        expiryRemindersDue([soon], now: _now, reminded: const {'soon': '2026-11-1'}),
        isEmpty,
      );
      expect(
        expiryRemindersDue([soon], now: _now, reminded: const {'soon': '2026-10-31'}),
        hasLength(1),
      );
    });
  });

  test('показывает по-русски и запоминает день', () async {
    final storage = await buildStorageService(
      initialValues: {'keqdis_settings': '{"appLanguageCode":"ru"}'},
    );
    final shown = <(String, String, String)>[];
    Future<void> show(Subscription s, String title, String body) async =>
        shown.add((s.id, title, body));
    final subs = [
      _sub('a', left: const Duration(days: 2)).copyWith(
        expiresAt: DateTime(2026, 11, 3, 18),
      ),
    ];

    await remindExpiringSubscriptions(storage, subs, now: _now, show: show);
    await remindExpiringSubscriptions(storage, subs, now: _now, show: show);
    expect(shown, [
      (
        'a',
        'Подписка скоро закончится',
        '«Подписка a» закончится 03.11.2026. Продлите подписку, чтобы серверы продолжали работать.',
      ),
    ]);
    expect(storage.getExpiryReminded(), {'a': '2026-11-1'});

    await remindExpiringSubscriptions(
      storage,
      subs,
      now: _now.add(const Duration(days: 1)),
      show: show,
    );
    expect(shown, hasLength(2));
  });
}
