import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/providers/halloween_provider.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/servers_tab.dart';
import 'package:keqdroid/services/vpn_engine.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

// долгое нажатие на Авто: отмеченные серверы автовыбор не берёт
var _skipped = <String>{};
var _auto = true;

ServerItem _node(int i, int ping) => ServerItem(
      id: 'n$i',
      config: 'vless://00000000-0000-0000-0000-000000000000@n$i'
          '.example.com:443?security=reality&type=tcp#Node%20$i',
      type: ServerItemType.subscription,
      subscriptionId: 's1',
      pingMs: ping,
      lastTestedAt: DateTime(2026, 11, 2),
      autoSkip: _skipped.contains('n$i'),
    );

class _FakeServers extends ServersNotifier {
  @override
  ServersState build() => ServersState(
        servers: [_node(0, 40), _node(1, 90), _node(2, 60)],
        activeServerId: 'n0',
      );
}

class _FakeSubs extends SubscriptionsNotifier {
  @override
  Future<List<Subscription>> build() async => [
        Subscription(
          id: 's1',
          name: 'Group',
          url: 'https://example.com/s1',
          serverCount: 3,
          autoSelectVisible: true,
          autoSelect: _auto,
        ),
      ];
}

class _NoHalloween extends HalloweenActiveNotifier {
  @override
  bool build() => false;
}

late ProviderContainer _container;

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(412, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final storage = await tester.runAsync(buildStorageService);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage!),
        serversProvider.overrideWith(_FakeServers.new),
        subscriptionsProvider.overrideWith(_FakeSubs.new),
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
  _container = ProviderScope.containerOf(tester.element(find.byType(ServersTab)));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tapAndSettle(WidgetTester tester, Finder f) async {
  await tester.tap(f);
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await _settle(tester);
}

bool _isSkipped(String id) =>
    _container.read(serversProvider).servers.firstWhere((s) => s.id == id).autoSkip;

final _badges = find.byIcon(Icons.remove_rounded);

Finder _tile(String name) => find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.text(name),
    );

void main() {
  setUp(() {
    _skipped = {};
    _auto = true;
  });

  testWidgets('обычное нажатие на Авто выделение не включает', (tester) async {
    _auto = false;
    await _pump(tester);

    await _tapAndSettle(tester, find.text('Auto'));

    expect(_container.read(autoSkipPickingProvider), isNull);
    expect(find.text('Auto skips the marked ones'), findsNothing);
  });

  testWidgets(
      'долгое нажатие на Авто включает выделение: нажатие на сервер '
      'отмечает его и не подключает, повторное снимает', (tester) async {
    await _pump(tester);

    await tester.longPress(find.text('Auto'));
    await _settle(tester);
    expect(_container.read(autoSkipPickingProvider), 's1');
    expect(find.text('Auto skips the marked ones'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    await _tapAndSettle(tester, _tile('Node 2'));
    expect(_isSkipped('n2'), isTrue);
    expect(_container.read(serversProvider).activeServerId, 'n0');
    expect(_badges, findsOneWidget);

    await _tapAndSettle(tester, _tile('Node 2'));
    expect(_isSkipped('n2'), isFalse);
    expect(_badges, findsNothing);
  });

  testWidgets('последний неотмеченный отметить нельзя', (tester) async {
    _skipped = {'n1', 'n2'};
    await _pump(tester);
    await tester.longPress(find.text('Auto'));
    await _settle(tester);

    await _tapAndSettle(tester, _tile('Node 0'));

    expect(_isSkipped('n0'), isFalse);
    expect(find.text('Auto needs at least one server'), findsOneWidget);
  });

  testWidgets(
      'Готово выходит из выделения, и Авто уходит с отмеченного текущего '
      'на лучший из оставшихся', (tester) async {
    await _pump(tester);
    await tester.longPress(find.text('Auto'));
    await _settle(tester);
    await _tapAndSettle(tester, _tile('Node 0'));

    await _tapAndSettle(tester, find.text('Done'));

    expect(_container.read(autoSkipPickingProvider), isNull);
    expect(find.text('Auto skips the marked ones'), findsNothing);
    expect(_container.read(serversProvider).activeServerId, 'n2');
  });

  testWidgets('при выключенном Авто отмеченный текущий остаётся выбранным',
      (tester) async {
    _auto = false;
    await _pump(tester);
    await tester.longPress(find.text('Auto'));
    await _settle(tester);
    await _tapAndSettle(tester, _tile('Node 0'));

    await _tapAndSettle(tester, find.text('Done'));

    expect(_container.read(serversProvider).activeServerId, 'n0');
  });

  testWidgets('кнопка Назад выходит из выделения', (tester) async {
    await _pump(tester);
    await tester.longPress(find.text('Auto'));
    await _settle(tester);

    await tester.binding.handlePopRoute();
    await _settle(tester);

    expect(_container.read(autoSkipPickingProvider), isNull);
  });

  testWidgets('вне выделения пометку видно, только пока Авто включено',
      (tester) async {
    _skipped = {'n2'};
    _auto = false;
    await _pump(tester);
    expect(_badges, findsNothing);
  });

  testWidgets('вне выделения при включённом Авто отмеченный помечен',
      (tester) async {
    _skipped = {'n2'};
    await _pump(tester);
    expect(_badges, findsOneWidget);
  });
}
