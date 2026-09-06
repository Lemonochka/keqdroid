import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/servers_tab.dart';
import 'package:keqdroid/screens/subscriptions_tab.dart';

import '../helpers/test_storage.dart';

/// Шторка выбора интервала автообновления открывается из двух мест — из шапки
/// группы серверов и из карточки подписки. Это была одна и та же шторка,
/// написанная дважды, и разойтись они могли молча: правку в одной копии никто
/// бы не перенёс во вторую. Тест сторожит именно это — что оба входа приводят к
/// одному набору вариантов.
class _FakeServers extends ServersNotifier {
  _FakeServers(this._state);

  final ServersState _state;

  @override
  ServersState build() => _state;
}

class _FakeSubs extends SubscriptionsNotifier {
  _FakeSubs(this._subs);

  final List<Subscription> _subs;

  @override
  Future<List<Subscription>> build() async => _subs;
}

class _FakeSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

final _sub = Subscription(
  id: 'sub-a',
  name: 'Example subscription',
  url: 'https://example.org/sub',
  serverCount: 1,
  updateIntervalHours: 6,
  lastUpdatedAt: DateTime.utc(2026, 1, 1),
);

final _servers = <ServerItem>[
  ServerItem(
    id: 's1',
    config: 'vless://uuid-s1@example.org:443?security=tls&type=tcp#Server%201',
    type: ServerItemType.subscription,
    subscriptionId: 'sub-a',
  ),
];

Future<void> _pump(WidgetTester tester, Widget home) async {
  final storage = await buildStorageService();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
        serversProvider.overrideWith(
          () => _FakeServers(ServersState(servers: _servers)),
        ),
        subscriptionsProvider.overrideWith(() => _FakeSubs([_sub])),
        settingsNotifierProvider.overrideWith(_FakeSettings.new),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
}

/// В шапке вкладки серверов живёт непрерывная анимация волны, поэтому
/// `pumpAndSettle` там виснет по таймауту. Крутим фиксированное время: часы в
/// тестах фейковые, результат детерминирован.
Future<void> _advance(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _expectSameOptions(AppLocalizations l10n) {
  expect(find.text(l10n.subscriptionsAutoUpdateInterval), findsOneWidget);
  expect(find.text(l10n.subscriptionsAutoUpdateOff), findsOneWidget);
  expect(find.text(l10n.subscriptionsEveryHour), findsOneWidget);
  expect(find.text(l10n.subscriptionsEveryHours(6)), findsWidgets);
  expect(find.text(l10n.subscriptionsEveryDay), findsOneWidget);
  expect(find.text(l10n.subscriptionsEveryDays(2)), findsOneWidget);
  expect(find.text(l10n.subscriptionsEveryDays(3)), findsOneWidget);
}

void main() {
  testWidgets('шторка интервала из шапки группы серверов', (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(tester, const ServersTab());
    await _advance(tester);

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // Чип с текущим интервалом в шапке группы.
    await tester.tap(find.text('6h'));
    await _advance(tester);

    _expectSameOptions(l10n);
  });

  testWidgets('шторка интервала из карточки подписки', (tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(tester, const SubscriptionsTab());
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // Чип интервала на карточке подписан так же, как в шапке группы.
    await tester.tap(find.text('6h'));
    await tester.pumpAndSettle();

    _expectSameOptions(l10n);
  });
}
