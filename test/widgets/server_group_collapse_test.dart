import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/models/subscription_card_theme.dart';
import 'package:keqdroid/providers/halloween_provider.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/servers_tab.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/shared/ui/smooth_fade.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

const _count = 200;

class _FakeServers extends ServersNotifier {
  @override
  ServersState build() => ServersState(
        servers: [
          for (var i = 0; i < _count; i++)
            ServerItem(
              id: 'n$i',
              config: 'vless://00000000-0000-0000-0000-000000000000@n$i'
                  '.example.com:443?security=reality&type=tcp#Node%20$i',
              type: ServerItemType.subscription,
              subscriptionId: 's1',
            ),
        ],
      );
}

class _FakeSubs extends SubscriptionsNotifier {
  @override
  Future<List<Subscription>> build() async => const [
        Subscription(
          id: 's1',
          name: 'Group',
          url: 'https://example.com/s1',
          serverCount: _count,
        ),
      ];
}

class _PictureSubs extends SubscriptionsNotifier {
  @override
  Future<List<Subscription>> build() async => const [
        Subscription(
          id: 's1',
          name: 'Group',
          url: 'https://example.com/s1',
          serverCount: _count,
          cardThemeId: '${SubscriptionCardTheme.filePrefix}pic.png',
        ),
      ];
}

class _NoHalloween extends HalloweenActiveNotifier {
  @override
  bool build() => false;
}

int _builtTiles() => find.textContaining('Node ').evaluate().length;

// вуаль подписки тоже SmoothFadeBox, но поперёк: затухание в фон списка идёт сверху вниз
final _fadeIntoList = find.byWidgetPredicate(
  (w) => w is SmoothFadeBox && w.begin == Alignment.topCenter,
);

double _headerFade() => _fadeIntoList
    .evaluate()
    .map((e) => (e.widget as SmoothFadeBox).curve.alphas.last)
    .fold(0.0, (a, b) => a > b ? a : b);

Future<void> _pumpServers(
  WidgetTester tester,
  SubscriptionsNotifier Function() subs,
) async {
  tester.view.physicalSize = const Size(412, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final storage = await tester.runAsync(buildStorageService);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage!),
        serversProvider.overrideWith(_FakeServers.new),
        subscriptionsProvider.overrideWith(subs),
        halloweenActiveProvider.overrideWith(_NoHalloween.new),
        vpnEngineProvider.overrideWithValue(
          VpnEngine.withBackend(FakeTunnelBackend()),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: ServersTab()),
      ),
    ),
  );
}

void main() {
  testWidgets(
      'группа сворачивается и разворачивается пружиной, '
      'а плитки строятся только видимые', (tester) async {
    await _pumpServers(tester, _FakeSubs.new);
    Future<void> run(int ms) async {
      for (var i = 0; i < ms ~/ 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await run(1200);
    expect(_builtTiles(), inExclusiveRange(0, 60));
    final groups = ProviderScope.containerOf(
      tester.element(find.byType(ServersTab)),
    ).read(collapsedServerGroupsProvider.notifier);

    groups.update((m) => {...m, 's1': true});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // ещё сворачивается: не исчезла разом
    expect(_builtTiles(), greaterThan(0));
    await run(1000);
    expect(_builtTiles(), 0);

    groups.update((m) => {...m, 's1': false});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // уже раскрывается, и даже на середине пружины список не строится целиком
    expect(_builtTiles(), inExclusiveRange(0, 60));
    await run(1000);
    expect(_builtTiles(), inExclusiveRange(0, 60));
  });

  testWidgets(
      'картинка в шапке уходит в фон списка только у раскрытой группы, '
      'и после сворачивания затемнение не возвращается', (tester) async {
    SubscriptionCardTheme.customDirectory = '/data/app/card_themes';
    addTearDown(() => SubscriptionCardTheme.customDirectory = null);
    await _pumpServers(tester, _PictureSubs.new);
    Future<void> frames(int ms) async {
      for (var i = 0; i < ms ~/ 16; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    await frames(1200);
    expect(_headerFade(), 1);
    final groups = ProviderScope.containerOf(
      tester.element(find.byType(ServersTab)),
    ).read(collapsedServerGroupsProvider.notifier);

    groups.update((m) => {...m, 's1': true});
    await tester.pump();
    // пара кадров до остановки пружины даёт не больше 2 ступеней из 255 у самого края
    const unseen = 0.01;
    var gone = false;
    for (var i = 0; i < 1500 ~/ 16; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final fade = _headerFade();
      if (gone) {
        expect(fade, lessThan(unseen), reason: 'кадр ${i * 16} мс');
      } else if (fade < unseen) {
        gone = true;
      }
    }
    expect(gone, isTrue);
    expect(_fadeIntoList, findsNothing);

    groups.update((m) => {...m, 's1': false});
    await tester.pump();
    await frames(1200);
    expect(_headerFade(), 1);
    // цвет акцента ждёт несуществующую картинку 5 с
    await tester.pump(const Duration(seconds: 5));
  });
}
