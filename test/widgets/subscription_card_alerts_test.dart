import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/subscriptions_tab.dart';
import 'package:keqdroid/services/rule_list_service.dart';
import 'package:keqdroid/services/subscription_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

final _ru = lookupAppLocalizations(const Locale('ru'));

final _live = Subscription(
  id: 'a',
  name: 'Gaming VPN',
  url: 'https://a.example',
  usedBytes: 6353261407,
  expiresAt: DateTime.now().add(const Duration(days: 30)),
);

final _expired = Subscription(
  id: 'a',
  name: 'Gaming VPN',
  url: 'https://a.example',
  usedBytes: 6353261407,
  expiresAt: DateTime.now().subtract(const Duration(days: 3, hours: 1)),
);

var _subs = <Subscription>[_live];

class _FakeSubs extends SubscriptionsNotifier {
  @override
  Future<List<Subscription>> build() async => _subs;
}

class _FakeSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

class _FakeVpn extends VpnStateNotifier {
  @override
  Future<VpnState> build() async =>
      const VpnState(status: VpnStatus.disconnected);
}

class _FakeRuleLists extends RuleListsNotifier {
  @override
  Map<String, RuleListStatus> build() => const {};
}

class _DeviceLimitService extends SubscriptionService {
  _DeviceLimitService(super.storage);

  @override
  Future<UpdateResult> updateSubscription(Subscription sub, {cancelToken}) async =>
      UpdateResult(
        success: false,
        error: 'HTTP 429: max-devices-reached',
        subscription: sub,
      );
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Locale locale = const Locale('ru'),
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  final storage = await buildStorageService();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
        subscriptionsProvider.overrideWith(_FakeSubs.new),
        subscriptionServiceProvider.overrideWithValue(
          _DeviceLimitService(storage),
        ),
        settingsNotifierProvider.overrideWith(_FakeSettings.new),
        vpnStateProvider.overrideWith(_FakeVpn.new),
        ruleListsProvider.overrideWith(_FakeRuleLists.new),
        vpnEngineProvider.overrideWithValue(
          VpnEngine.withBackend(FakeTunnelBackend()),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: const SubscriptionsTab(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(SubscriptionsTab)),
  );
}

void _setError(ProviderContainer container, Object? error) => container
    .read(subscriptionRefreshErrorsProvider.notifier)
    .update((m) => {...m}..remove('a')..addAll({'a': ?error}));

Finder get _anyErrorText => find.textContaining('max-devices');

void main() {
  setUp(() => _subs = [_live]);

  testWidgets('неудачное обновление показывает ошибку словами приложения',
      (tester) async {
    final container = await _pump(tester);
    await expectLater(
      container.read(subscriptionsProvider.notifier).refreshTracked(_live),
      throwsA(anything),
    );
    await tester.pumpAndSettle();
    expect(find.text(_ru.errorDeviceLimitTitle), findsOneWidget);
    expect(find.text(_ru.errorDeviceLimitMessage), findsOneWidget);
    expect(find.textContaining('Device Limit'), findsNothing);
    // в развёрнутой карточке причину видно целиком: на немецком при крупном шрифте она обрезалась
    expect(tester.widget<Text>(find.text(_ru.errorDeviceLimitMessage)).maxLines, isNull);
  });

  testWidgets('ошибка уходит, когда обновление прошло', (tester) async {
    final container = await _pump(tester);
    _setError(container, 'HTTP 429: max-devices-reached');
    await tester.pumpAndSettle();
    expect(find.text(_ru.errorDeviceLimitTitle), findsOneWidget);
    _setError(container, null);
    await tester.pumpAndSettle();
    expect(find.text(_ru.errorDeviceLimitTitle), findsNothing);
    expect(_anyErrorText, findsNothing);
  });

  testWidgets('у истёкшей подписки только плашка про срок', (tester) async {
    _subs = [_expired];
    final container = await _pump(tester);
    _setError(container, 'HTTP 429: max-devices-reached');
    await tester.pumpAndSettle();
    expect(find.text(_ru.subscriptionsExpiredHint), findsOneWidget);
    expect(find.text(_ru.errorDeviceLimitTitle), findsNothing);
    expect(_anyErrorText, findsNothing);
  });

  // срок подставляется как «3д назад», а не датой: было «expired on 3d ago», «am vor 3 Tg.»
  for (final (code, title) in const [
    ('en', 'Subscription expired 3d ago'),
    ('ru', 'Подписка истекла 3д назад'),
    ('de', 'Abonnement vor 3 Tg. abgelaufen'),
    ('zh', '订阅已到期（3 天前）'),
    ('fa', 'اشتراک 3 روز پیش منقضی شد'),
  ]) {
    testWidgets('плашка истёкшей подписки читается по-человечески: $code',
        (tester) async {
      _subs = [_expired];
      await _pump(tester, locale: Locale(code));
      expect(find.text(title), findsOneWidget);
    });
  }

  testWidgets('свёрнутая карточка ошибку не прячет, как и объявление',
      (tester) async {
    final container = await _pump(tester);
    container
        .read(collapsedSubscriptionCardsProvider.notifier)
        .update((m) => {...m, 'a': true});
    await tester.pumpAndSettle();
    _setError(container, 'HTTP 429: max-devices-reached');
    await tester.pumpAndSettle();
    expect(find.text(_ru.errorDeviceLimitTitle), findsOneWidget);
    expect(tester.widget<Text>(find.text(_ru.errorDeviceLimitMessage)).maxLines, 2);
  });

  testWidgets('плашка ошибки выезжает, а не появляется рывком', (tester) async {
    final container = await _pump(tester);
    final usage = find.textContaining('GiB').first;
    final before = tester.getTopLeft(usage).dy;
    _setError(container, 'HTTP 429: max-devices-reached');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final moving = tester.getTopLeft(usage).dy;
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(usage).dy;
    expect(after, greaterThan(before + 40));
    expect(moving, greaterThan(before));
    expect(moving, lessThan(after - 10));
  });
}
