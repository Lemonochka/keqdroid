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
import 'package:keqdroid/shared/ui/card_art.dart';
import 'package:keqdroid/shared/ui/server_group_anchors.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

class _Servers extends ServersNotifier {
  @override
  ServersState build() => ServersState(
        servers: [
          for (var i = 0; i < 3; i++)
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

class _Subs extends SubscriptionsNotifier {
  _Subs(this.sub);

  final Subscription sub;

  @override
  Future<List<Subscription>> build() async => [sub];
}

class _NoHalloween extends HalloweenActiveNotifier {
  @override
  bool build() => false;
}

Subscription _sub(
  String theme, {
  bool inServers = true,
  CardVeil veil = CardVeil.medium,
}) =>
    Subscription(
      id: 's1',
      name: 'Group',
      url: 'https://example.com/s1',
      serverCount: 3,
      cardThemeId: theme,
      cardThemeInServers: inServers,
      cardVeil: veil,
    );

final _header = find.byType(ServerGroupAnchor).first;

final _art = find.descendant(
  of: _header,
  matching: find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is CardArtPainter,
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 75; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _pump(WidgetTester tester, Subscription sub) async {
  tester.view.physicalSize = const Size(412, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final storage = await tester.runAsync(buildStorageService);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage!),
        serversProvider.overrideWith(_Servers.new),
        subscriptionsProvider.overrideWith(() => _Subs(sub)),
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
  await _settle(tester);
}

void main() {
  // жалоба 19.11: после смены градиентов на рисунки группа на главной стала
  // неотличима от группы без оформления, в шапку шли только картинки
  testWidgets('рисунок подписки виден в шапке группы на главной', (tester) async {
    final arts = [
      for (final t in kSubscriptionCardThemes)
        if (t.art != null) t.id,
    ];
    expect(arts, hasLength(CardArt.values.length));
    for (final id in arts) {
      await _pump(tester, _sub(id));
      expect(_art, findsOneWidget, reason: id);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(const SizedBox());
    }
  });

  // ужатый до высоты шапки рисунок рассыпался на обрывки фигур, поэтому он в
  // размере карточки и низом стоит у края раскрытой шапки
  testWidgets('рисунок в размере карточки и не сдвигается при сворачивании', (
    tester,
  ) async {
    await _pump(tester, _sub('shapeEdge'));
    final open = tester.getRect(_art);
    expect(open.height, 150);
    expect(open.bottom, moreOrLessEquals(tester.getRect(_header).bottom + 1));

    ProviderScope.containerOf(tester.element(find.byType(ServersTab)))
        .read(collapsedServerGroupsProvider.notifier)
        .update((m) => {...m, 's1': true});
    await _settle(tester);
    expect(tester.getSize(_header).height, lessThan(open.height));
    expect(tester.getRect(_art).top, moreOrLessEquals(open.top));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('выключенный переключатель убирает рисунок и полосу под ним', (
    tester,
  ) async {
    await _pump(tester, _sub('halftone'));
    final withArt = tester.getSize(_header).height;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());

    await _pump(tester, _sub('halftone', inServers: false));
    expect(_art, findsNothing);
    expect(tester.getSize(_header).height, lessThan(withArt));
    await tester.pump(const Duration(seconds: 5));
  });

  // выбора силы затемнения у рисунка нет, а в подписке могло остаться
  // значение от прежней картинки
  testWidgets('у рисунка среднее затемнение, у картинки своё, как раньше', (
    tester,
  ) async {
    // у картинки внутри своя шторка с CardVeil.none, считаются только видимые
    CardVeil veilIn(WidgetTester tester) => tester
        .widgetList<CardVeilOverlay>(
          find.descendant(of: _header, matching: find.byType(CardVeilOverlay)),
        )
        .map((o) => o.veil)
        .where((v) => v != CardVeil.none)
        .single;

    await _pump(tester, _sub('depth', veil: CardVeil.strong));
    expect(veilIn(tester), CardVeil.medium);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());

    SubscriptionCardTheme.customDirectory = '/data/app/card_themes';
    addTearDown(() => SubscriptionCardTheme.customDirectory = null);
    await _pump(
      tester,
      _sub('${SubscriptionCardTheme.filePrefix}pic.png', veil: CardVeil.strong),
    );
    expect(veilIn(tester), CardVeil.strong);
    await tester.pump(const Duration(seconds: 5));
  });
}
