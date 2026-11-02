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
import 'package:keqdroid/services/subscription_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/utils/clash_template.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

// подписка с шаблоном mihomo: вкладка групп, выбор пункта в шторке

final _body =
    File('test/fixtures/subscription_payloads/clash-template-groups.txt')
        .readAsStringSync();

final _servers = [
  for (final c in SubscriptionService.parseBodyForTest(_body))
    ServerItem.fromRaw(c, subscriptionId: 's1'),
];

class _FakeServers extends ServersNotifier {
  @override
  ServersState build() =>
      ServersState(servers: _servers, activeServerId: _servers.first.id);
}

class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this.settings);
  final AppSettings settings;
  @override
  Future<AppSettings> build() async => settings;
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

// без фоновых напоминаний и автовыбора настоящего build: в тесте они держат очередь хранилища
class _Subs extends SubscriptionsNotifier {
  @override
  Future<List<Subscription>> build() =>
      ref.read(storageProvider).getSubscriptions();
}

const _mihomo = AppSettings(vpnCore: AppSettings.vpnCoreMihomo);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  AppSettings settings = _mihomo,
}) async {
  tester.view.physicalSize = const Size(412, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final storage = await tester.runAsync(() => buildStorageService(
        initialValues: {
          'keqdis_subscriptions':
              '[{"id":"s1","name":"Kequinq","url":"https://example.com/s1"}]',
          'keqdis_clash_template_s1': ClashTemplate.fromBody(_body)!.encode(),
        },
      ));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage!),
        serversProvider.overrideWith(_FakeServers.new),
        subscriptionsProvider.overrideWith(_Subs.new),
        settingsNotifierProvider.overrideWith(() => _FakeSettings(settings)),
        vpnStateProvider.overrideWith(_FakeVpn.new),
        halloweenActiveProvider.overrideWith(_NoHalloween.new),
        exitIpProvider.overrideWith((ref) async => null),
        vpnEngineProvider.overrideWithValue(
          VpnEngine.withBackend(FakeTunnelBackend()),
        ),
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

void main() {
  testWidgets('группы вместо серверов, выбор в шторке сохраняется в подписке',
      (tester) async {
    final container = await _pump(tester);
    expect(find.text('Группы · 2'), findsOneWidget);
    expect(find.text('YouTube'), findsNothing);

    await tester.tap(find.text('Группы · 2'));
    await _settle(tester);
    expect(find.text('Недоступные сайты'), findsOneWidget);
    expect(find.text('YouTube'), findsOneWidget);

    await tester.tap(find.text('YouTube'));
    await _settle(tester);
    expect(find.text('Только для этих сайтов, остальное не меняется'),
        findsOneWidget);
    await tester.tap(find.text('Finland', findRichText: true).last);
    // очередь хранилища стоит за операцией экрана с настоящим вводом-выводом: в фальшивом времени она не идёт
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await _settle(tester);
    expect(find.text('Finland'), findsOneWidget,
        reason: 'строка YouTube показывает выбранный сервер');

    final sub = container.read(subscriptionsProvider).value!.single;
    expect(sub.groupChoices, {'YouTube': '🇫🇮 Finland'});
    final saved = (await container.read(storageProvider).getSubscriptions())
        .single;
    expect(saved.groupChoices, {'YouTube': '🇫🇮 Finland'});
  });

  testWidgets('с «Не учитывать правила провайдера» карточка как раньше',
      (tester) async {
    await _pump(
      tester,
      settings: _mihomo.copyWith(ignoreProviderRules: true),
    );
    expect(find.textContaining('Группы'), findsNothing);
    expect(find.text('Germany'), findsWidgets);
  });

  testWidgets('на xray карточка как раньше', (tester) async {
    await _pump(tester, settings: const AppSettings());
    expect(find.textContaining('Группы'), findsNothing);
    expect(find.text('Germany'), findsWidgets);
  });
}
