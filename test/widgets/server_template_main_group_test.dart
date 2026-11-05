import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/providers/halloween_provider.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/servers_tab.dart';
import 'package:keqdroid/services/mihomo_groups_api.dart';
import 'package:keqdroid/services/subscription_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/utils/clash_template.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

// подписка как у Moondrop: в главной группе Trial и Public, внутри Public группы автовыбора из proxy-providers

final _body =
    File('test/fixtures/subscription_payloads/clash-template-main-groups.txt')
        .readAsStringSync();

final _servers = [
  for (final c in SubscriptionService.parseBodyForTest(_body))
    ServerItem.fromRaw(c, subscriptionId: 's1'),
];

const _main = '🌙 Main';
const _public = '🌏 Public';
const _auto = '⚡ Auto';
const _denl = '🇩🇪 Germany | 🇳🇱 Netherlands';
const _de = '🇩🇪 DE • Scan #1';
const _nl = '🇳🇱 NL • Scan #2';

final Map<String, MihomoGroupState> _live = {
  _main: (
    type: 'selector',
    now: '🇩🇪 Germany #1',
    all: ['🇩🇪 Germany #1', '💎 Trial', _public, '🇳🇱 Netherlands #1'],
    fixed: null,
  ),
  _public: (type: 'selector', now: _auto, all: [_auto, _denl], fixed: null),
  _auto: (type: 'urltest', now: _de, all: [_de, _nl], fixed: null),
  _denl: (type: 'urltest', now: _de, all: [_de, _nl], fixed: null),
};

class _FakeServers extends ServersNotifier {
  @override
  ServersState build() =>
      ServersState(servers: _servers, activeServerId: _servers.first.id);
}

class _FakeSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async =>
      const AppSettings(vpnCore: AppSettings.vpnCoreMihomo);
}

class _FakeVpn extends VpnStateNotifier {
  @override
  Future<VpnState> build() async =>
      const VpnState(status: VpnStatus.disconnected);
}

class _NoHalloween extends HalloweenActiveNotifier {
  @override
  bool build() => false;
}

class _Subs extends SubscriptionsNotifier {
  @override
  Future<List<Subscription>> build() =>
      ref.read(storageProvider).getSubscriptions();
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Map<String, String> choices = const {},
  Map<String, MihomoGroupState>? live,
}) async {
  tester.view.physicalSize = const Size(412, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final storage = await tester.runAsync(() => buildStorageService(
        initialValues: {
          'keqdis_subscriptions': jsonEncode([
            {
              'id': 's1',
              'name': 'Moondrop',
              'url': 'https://example.com/s1',
              'groupChoices': choices,
            },
          ]),
          'keqdis_clash_template_s1': ClashTemplate.fromBody(_body)!.encode(),
        },
      ));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage!),
        serversProvider.overrideWith(_FakeServers.new),
        subscriptionsProvider.overrideWith(_Subs.new),
        settingsNotifierProvider.overrideWith(_FakeSettings.new),
        vpnStateProvider.overrideWith(_FakeVpn.new),
        halloweenActiveProvider.overrideWith(_NoHalloween.new),
        exitIpProvider.overrideWith((ref) async => null),
        vpnEngineProvider.overrideWithValue(
          VpnEngine.withBackend(FakeTunnelBackend()),
        ),
        liveTemplateGroupsProvider.overrideWith((ref, id) async => live),
        liveTemplateDelaysProvider
            .overrideWith((ref, id) async => {_nl: 41, _de: 95}),
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: ServersTab()),
      ),
    ),
  );
  await _settle(tester);
  return ProviderScope.containerOf(tester.element(find.byType(ServersTab)));
}

// волна в шапке анимируется вечно, pumpAndSettle повис бы
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

// очередь хранилища стоит за операцией экрана с настоящим вводом-выводом: в фальшивом времени она не идёт
Future<void> _flushStorage(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await _settle(tester);
}

Map<String, String> _choices(ProviderContainer container) =>
    container.read(subscriptionsProvider).value!.single.groupChoices;

void main() {
  testWidgets('главная группа первой строкой, флаги стран не печатаются буквами',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Группы · 2'));
    await _settle(tester);
    expect(find.text(_main), findsOneWidget);
    expect(find.text(_public), findsOneWidget);

    await tester.tap(find.text(_public));
    await _settle(tester);
    expect(find.text('Germany | Netherlands'), findsOneWidget);
    expect(find.textContaining('🇩🇪'), findsNothing,
        reason: 'на Windows эмодзи-флаг рисуется буквами DE');
    expect(find.text('Действует, когда выбрана в 🌙 Main'), findsOneWidget,
        reason: 'правил на Public нет, без выбора в главной она не действует');
  });

  testWidgets('Public, выбранная в главной, сохраняется, а нажатый сервер забирает главную назад',
      (tester) async {
    final container = await _pump(tester);
    await tester.tap(find.text('Группы · 2'));
    await _settle(tester);
    await tester.tap(find.text(_main));
    await _settle(tester);
    expect(find.text('Сюда идёт всё, что не ушло в другие группы'), findsOneWidget);

    await tester.tap(find.text(_public).last);
    await _flushStorage(tester);
    expect(_choices(container), {_main: _public});
    final saved =
        (await container.read(storageProvider).getSubscriptions()).single;
    expect(saved.groupChoices, {_main: _public});

    await tester.tap(find.text('Серверы'));
    await _settle(tester);
    await tester.tap(find.text('Netherlands #1'));
    await _flushStorage(tester);
    await _flushStorage(tester);
    expect(_choices(container), isEmpty);
    expect(container.read(serversProvider).activeServer?.id, _servers[1].id);
  });

  testWidgets('серверы внутри группы автовыбора: быстрые сверху, выбор закрепляет и выбирает группу',
      (tester) async {
    final container = await _pump(tester, live: _live);
    await tester.tap(find.text('Группы · 2'));
    await _settle(tester);
    await tester.tap(find.text(_public));
    await _settle(tester);
    await tester.tap(find.text('Germany | Netherlands'));
    await _settle(tester);

    expect(find.text('Автоматически'), findsOneWidget);
    expect(find.text('сейчас DE • Scan #1'), findsWidgets,
        reason: 'то же видно и в шторке Public под этой');
    expect(
      tester.getTopLeft(find.text('NL • Scan #2')).dy,
      lessThan(tester.getTopLeft(find.text('DE • Scan #1')).dy),
      reason: '41 мс выше 95 мс',
    );

    await tester.tap(find.text('NL • Scan #2'));
    await _flushStorage(tester);
    expect(_choices(container), {_public: _denl, _denl: _nl});
  });

  testWidgets('«Автоматически» снимает закрепление', (tester) async {
    final container =
        await _pump(tester, live: _live, choices: {_public: _denl, _denl: _nl});
    await tester.tap(find.text('Группы · 2'));
    await _settle(tester);
    await tester.tap(find.text(_public));
    await _settle(tester);
    await tester.tap(find.text('Germany | Netherlands'));
    await _settle(tester);
    await tester.tap(find.text('Автоматически'));
    await _flushStorage(tester);
    expect(_choices(container), {_public: _denl});
  });

  testWidgets('без подключения закреплённый сервер виден в подписи группы', (tester) async {
    await _pump(tester, choices: {_public: _denl, _denl: _nl});
    await tester.tap(find.text('Группы · 2'));
    await _settle(tester);
    await tester.tap(find.text(_public));
    await _settle(tester);
    expect(find.text('закреплён NL • Scan #2'), findsOneWidget);
  });
}
