import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_info.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/routing_profile.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/models/traffic_route.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/settings_tab.dart';
import 'package:keqdroid/services/rule_list_service.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:keqdroid/shared/ui/expressive_elements.dart';
import 'package:keqdroid/shared/ui/expressive_group.dart';
import 'package:keqdroid/tunnel/vpn_backend.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this._initial);
  final AppSettings _initial;

  @override
  Future<AppSettings> build() async => _initial;

  @override
  Future<void> save(AppSettings settings) async => state = AsyncData(settings);
}

class _FakeVpn extends VpnStateNotifier {
  _FakeVpn(this._status);
  final VpnStatus _status;
  var reconnects = 0;

  @override
  Future<VpnState> build() async => VpnState(status: _status);

  @override
  Future<void> reconnectToActiveServer() async => reconnects++;
}

/// Списки по ссылкам без сети и диска: экран только показывает их состояние.
class _FakeRuleLists extends RuleListsNotifier {
  _FakeRuleLists(this._statuses);
  final Map<String, RuleListStatus> _statuses;

  @override
  Map<String, RuleListStatus> build() => _statuses;
}

/// Подписки без таймера синхронизации: шторка серверов читает их ради
/// заголовков групп.
class _FakeSubs extends SubscriptionsNotifier {
  _FakeSubs([this._subs = const []]);
  final List<Subscription> _subs;

  @override
  Future<List<Subscription>> build() async => _subs;
}

late _FakeVpn _vpn;
late StorageService _storage;

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  VpnStatus status = VpnStatus.disconnected,
  AppSettings settings = const AppSettings(),
  List<TrafficRoute>? routes,
  List<ServerItem> servers = const [],
  bool hint = false,
  Map<String, RuleListStatus> ruleLists = const {},
  RouteCapabilities? caps,
  List<AppInfo> apps = const [],
  List<AppInfo> systemApps = const [],
  List<String> splitExclude = const [],
  List<String> splitInclude = const [],
  List<RoutingProfile> profiles = const [],
  List<Subscription> subs = const [],
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);

  _storage = await buildStorageService(
    initialValues: {if (hint) 'keqdis_routes_hint': true},
  );
  if (routes != null) await _storage.saveRoutes(routes);
  if (profiles.isNotEmpty) await _storage.saveRoutingProfiles(profiles);
  if (splitExclude.isNotEmpty) await _storage.setExcludePackages(splitExclude);
  if (splitInclude.isNotEmpty) await _storage.setIncludePackages(splitInclude);
  if (servers.isNotEmpty) {
    await _storage.saveServers(servers);
    await _storage.setActiveServerId(servers.first.id);
  }
  _vpn = _FakeVpn(status);
  final container = ProviderContainer(
    overrides: [
      storageProvider.overrideWithValue(_storage),
      settingsNotifierProvider.overrideWith(() => _FakeSettings(settings)),
      vpnStateProvider.overrideWith(() => _vpn),
      ruleListsProvider.overrideWith(() => _FakeRuleLists(ruleLists)),
      subscriptionsProvider.overrideWith(() => _FakeSubs(subs)),
      vpnEngineProvider.overrideWithValue(
        VpnEngine.withBackend(FakeTunnelBackend()),
      ),
      if (caps != null) routeCapabilitiesProvider.overrideWithValue(caps),
      installedAppsProvider(false).overrideWith((ref) async => apps),
      installedAppsProvider(true)
          .overrideWith((ref) async => [...apps, ...systemApps]),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAppTheme(
          ColorScheme.fromSeed(
            seedColor: const Color(0xFF6750A4),
            brightness: Brightness.dark,
          ),
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ru'),
        home: routingScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Тексты на экране без изоляторов направления, которыми код обкладывает
/// адреса для фарси.
List<String> _texts(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        (t.data ?? t.textSpan?.toPlainText() ?? '')
            .replaceAll(RegExp('[\u2066-\u2069]'), ''),
    ];

const _block = TrafficRoute(
  id: 'block',
  sites: 'doubleclick.net, criteo.com',
  target: RouteTarget.block,
);
const _direct = TrafficRoute(
  id: 'direct',
  sites: 'ru, yandex.ru, vk.com',
  target: RouteTarget.direct,
);
const _vpnOff = TrafficRoute(
  id: 'off',
  sites: 'geosite:telegram',
  target: RouteTarget.vpn,
  enabled: false,
);

void main() {
  group('главный экран', () {
    testWidgets('разделы по порядку проверки, пустые не показываются',
        (tester) async {
      await _pump(tester, routes: const [_direct, _block]);
      final texts = _texts(tester);
      expect(texts, contains('Блокировка'));
      expect(texts, isNot(contains('Приложения')),
          reason: 'маршрутов отдельных приложений нет — и раздела нет');
      expect(
        texts.indexOf('Блокировка'),
        lessThan(texts.indexOf('Все приложения')),
      );
      expect(texts, contains('doubleclick.net, criteo.com'));
      expect(texts, contains('→ блокировать'));
      expect(texts, contains('→ напрямую'));
      // «Всё остальное» — последней строкой раздела всех приложений.
      expect(
        texts.indexOf('ru, yandex.ru, vk.com'),
        lessThan(texts.indexOf('Всё остальное')),
      );
    });

    testWidgets('выключенный маршрут подписан', (tester) async {
      await _pump(tester, routes: const [_vpnOff]);
      expect(_texts(tester), contains('→ через VPN · выключен'));
    });

    testWidgets('подсказка после обновления закрывается навсегда',
        (tester) async {
      await _pump(tester, routes: const [_direct], hint: true);
      expect(find.text('Понятно'), findsOneWidget);
      await tester.tap(find.text('Понятно'));
      await tester.pumpAndSettle();
      expect(find.text('Понятно'), findsNothing);
      expect(_storage.routesHintPending, isFalse);
    });

    testWidgets('«Всё остальное» — те же три пути, что у маршрутов',
        (tester) async {
      final c = await _pump(tester, routes: const [_direct]);
      await tester.tap(find.text('Всё остальное'));
      await tester.pumpAndSettle();
      expect(find.text('Через VPN'), findsOneWidget);
      expect(find.text('Напрямую'), findsOneWidget);
      await tester.tap(find.text('Блокировать'));
      await tester.pumpAndSettle();
      expect(
        c.read(settingsNotifierProvider).value!.finalOutbound,
        AppSettings.finalOutboundBlock,
      );
      expect(_texts(tester), contains('→ блокировать'));
    });

    testWidgets('при поднятом туннеле — напоминание и переподключение',
        (tester) async {
      await _pump(tester, routes: const [_direct], status: VpnStatus.connected);
      await tester.tap(find.text('Переподключить'));
      await tester.pumpAndSettle();
      expect(_vpn.reconnects, 1);
    });

    testWidgets('напоминание и подсказка не слипаются', (tester) async {
      await _pump(
        tester,
        routes: const [_direct],
        status: VpnStatus.connected,
        hint: true,
      );
      final notices = find.byType(ExpressiveNotice);
      expect(notices, findsNWidgets(2));
      final gap = tester.getTopLeft(notices.at(1)).dy -
          tester.getBottomLeft(notices.at(0)).dy;
      expect(gap, greaterThanOrEqualTo(ExpressiveSpacing.medium));
    });

    testWidgets('без туннеля напоминания нет', (tester) async {
      await _pump(tester, routes: const [_direct]);
      expect(find.text('Переподключить'), findsNothing);
    });
  });

  group('редактор', () {
    Future<void> openNew(WidgetTester tester) async {
      await tester.tap(find.text('Новый маршрут'));
      await tester.pumpAndSettle();
    }

    testWidgets('новый маршрут: по умолчанию свои сайты через VPN',
        (tester) async {
      // Ядро без своего туннеля приложений не различает, строки «Кто» тогда
      // нет: выбирать не из чего.
      await _pump(
        tester,
        routes: const [],
        caps: const RouteCapabilities(servers: true),
      );
      await openNew(tester);
      expect(find.text('Новый маршрут'), findsWidgets);
      expect(find.text('Кто'), findsNothing);
      expect(find.text('Свои сайты · пусто'), findsOneWidget);
      expect(find.text('Через VPN'), findsOneWidget);
    });

    testWidgets('пустой новый маршрут при уходе не сохраняется',
        (tester) async {
      await _pump(tester, routes: const []);
      await openNew(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(await _storage.getRoutes(), isEmpty);
    });

    // Набор сохраняется на паузе; уйти со страницы можно раньше паузы.
    testWidgets('набранное сразу перед уходом не теряется', (tester) async {
      await _pump(tester, routes: const []);
      await openNew(tester);
      await tester.enterText(find.byType(TextField), 'youtube.com');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      final saved = await _storage.getRoutes();
      expect(saved.single.sites, 'youtube.com');
      expect(saved.single.target, RouteTarget.vpn);
      expect(_texts(tester), contains('youtube.com'));
    });

    testWidgets('готовый список ставит своё «куда»', (tester) async {
      await _pump(tester, routes: const []);
      await openNew(tester);
      await tester.tap(find.text('Что'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Реклама и трекеры'));
      await tester.pumpAndSettle();
      expect(find.text('Готовый список · Реклама и трекеры'), findsOneWidget);
      final saved = (await _storage.getRoutes()).single;
      expect(saved.content, RouteContent.preset);
      expect(saved.presetId, 'ads');
      expect(saved.target, RouteTarget.block);
    });

    testWidgets('Re-filter заодно отправляет «Всё остальное» напрямую',
        (tester) async {
      final c = await _pump(tester, routes: const []);
      await openNew(tester);
      await tester.tap(find.text('Что'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Заблокировано в РФ (Re-filter)'));
      await tester.pumpAndSettle();
      expect(
        c.read(settingsNotifierProvider).value!.finalOutbound,
        AppSettings.finalOutboundDirect,
      );
      expect(find.text('«Всё остальное» теперь идёт напрямую'), findsOneWidget);
      expect((await _storage.getRoutes()).single.target, RouteTarget.vpn);
    });

    testWidgets('белые списки: напрямую, рунет напрямую выключен, остальное в VPN',
        (tester) async {
      const ruPreset = TrafficRoute(
        id: 'ru-preset',
        content: RouteContent.preset,
        presetId: 'ru',
        target: RouteTarget.direct,
      );
      const own = TrafficRoute(
        id: 'own',
        sites: 'work.example, 192.168.0.0/16',
        target: RouteTarget.direct,
      );
      final c = await _pump(
        tester,
        settings: const AppSettings(
          finalOutbound: AppSettings.finalOutboundDirect,
        ),
        routes: const [_direct, ruPreset, own, _block],
      );
      await openNew(tester);
      await tester.tap(find.text('Что'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Белые списки мобильной связи'));
      await tester.pumpAndSettle();

      final saved = {for (final r in await _storage.getRoutes()) r.id: r};
      final added = saved.values
          .singleWhere((r) => r.presetId == 'whitelist');
      expect(added.target, RouteTarget.direct);
      expect(saved['direct']!.enabled, isFalse);
      expect(saved['ru-preset']!.enabled, isFalse);
      expect(saved['own']!.enabled, isTrue);
      expect(saved['block']!.enabled, isTrue);
      expect(
        c.read(settingsNotifierProvider).value!.finalOutbound,
        AppSettings.finalOutboundProxy,
      );
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('«куда» меняется в шторке', (tester) async {
      await _pump(tester, routes: const [_direct]);
      await tester.tap(find.text('ru, yandex.ru, vk.com'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Куда'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Блокировать').last);
      await tester.pumpAndSettle();
      expect((await _storage.getRoutes()).single.target, RouteTarget.block);
    });

    testWidgets('маршрут выключается и удаляется', (tester) async {
      await _pump(tester, routes: const [_direct]);
      await tester.tap(find.text('ru, yandex.ru, vk.com'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect((await _storage.getRoutes()).single.enabled, isFalse);

      await tester.tap(find.byTooltip('Удалить'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
      await tester.pumpAndSettle();
      expect(await _storage.getRoutes(), isEmpty);
      expect(find.text('Всё остальное'), findsOneWidget,
          reason: 'после удаления — снова главный экран');
    });

    // Перенесённое правило по процессу: отдельные приложения ядро пока не
    // различает, и карточка обязана сказать, что маршрут не работает.
    testWidgets('маршрут приложений без поддержки ядра — с причиной',
        (tester) async {
      await _pump(tester, caps: const RouteCapabilities(servers: true), routes: const [
        TrafficRoute(
          id: 'app',
          apps: ['chrome.exe'],
          content: RouteContent.allTraffic,
          target: RouteTarget.direct,
          enabled: false,
        ),
      ]);
      expect(_texts(tester), contains('Приложения'));
      expect(_texts(tester), contains('chrome'));
      expect(
        _texts(tester).any((t) => t.contains('не различает приложения')),
        isTrue,
      );
    });
  });

  group('другой сервер', () {
    final active = ServerItem(
      id: 'nl',
      type: ServerItemType.manual,
      config: 'vless://00000000-0000-4000-8000-000000000000@nl.example:443'
          '?type=tcp&security=tls&sni=nl.example#Netherlands',
    );
    final de = ServerItem(
      id: 'de',
      type: ServerItemType.manual,
      config: 'trojan://pw@de.example:443?security=tls&sni=de.example#Germany',
    );
    // готовый конфиг встаёт выходом только у своего ядра: JSON у xray, Clash у mihomo
    final customJson = ServerItem(
      id: 'custom',
      type: ServerItemType.manual,
      config: '{"remarks":"Ready JSON","outbounds":[{"protocol":"vless",'
          '"tag":"proxy","settings":{"vnext":[{"address":"x.example",'
          '"port":443,"users":[{"id":"00000000-0000-4000-8000-000000000000",'
          '"encryption":"none"}]}]}}]}',
    );
    final customClash = ServerItem(
      id: 'clash',
      type: ServerItemType.manual,
      config: '{"remarks":"Ready Clash","proxies":[{"name":"NL",'
          '"type":"trojan","server":"c.example","port":443,"password":"pw"}],'
          '"proxy-groups":[{"name":"Proxy","type":"select","proxies":["NL"]}]}',
    );

    Future<void> openPicker(WidgetTester tester) async {
      await tester.tap(find.text('youtube.com'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Куда'));
      await tester.pumpAndSettle();
      expect(find.text('Другой сервер'), findsOneWidget);
      await tester.tap(find.text('Выберите сервер'));
      await tester.pumpAndSettle();
    }

    testWidgets('у mihomo в списке Clash, а не JSON', (tester) async {
      await _pump(
        tester,
        settings: const AppSettings(vpnCore: AppSettings.vpnCoreMihomo),
        routes: const [TrafficRoute(id: 'r', sites: 'youtube.com')],
        servers: [active, de, customJson, customClash],
      );
      await openPicker(tester);
      expect(find.text('Germany'), findsOneWidget);
      expect(find.text('Ready Clash'), findsOneWidget);
      expect(find.text('Ready JSON'), findsNothing);
    });

    testWidgets('выбирается из списка серверов, которые возьмёт ядро',
        (tester) async {
      await _pump(
        tester,
        routes: const [TrafficRoute(id: 'r', sites: 'youtube.com')],
        servers: [active, de, customJson, customClash],
      );
      await openPicker(tester);
      expect(find.text('Germany'), findsOneWidget);
      expect(find.text('Ready JSON'), findsOneWidget);
      expect(find.text('Ready Clash'), findsNothing);
      await tester.tap(find.text('Germany'));
      await tester.pumpAndSettle();

      final saved = (await _storage.getRoutes()).single;
      expect(saved.target, RouteTarget.server);
      expect(saved.serverId, 'de');
      expect(find.text('Germany'), findsOneWidget,
          reason: '«Куда» в редакторе называет выбранный сервер');
    });

    testWidgets('флаг сервера один: значком, а не ещё и эмодзи в имени',
        (tester) async {
      final flagged = ServerItem(
        id: 'de',
        type: ServerItemType.manual,
        config: 'trojan://pw@de.example:443?security=tls&sni=de.example'
            '#${Uri.encodeComponent('🇩🇪 Germany')}',
      );
      await _pump(
        tester,
        routes: const [
          TrafficRoute(
            id: 'r',
            sites: 'youtube.com',
            target: RouteTarget.server,
            serverId: 'de',
          ),
        ],
        servers: [active, flagged],
      );
      expect(_texts(tester).any((t) => t.contains('Germany')), isTrue);
      expect(_texts(tester).any((t) => t.contains('🇩🇪')), isFalse);

      await tester.tap(find.text('youtube.com'));
      await tester.pumpAndSettle();
      expect(_texts(tester).any((t) => t.contains('Germany')), isTrue);
      expect(_texts(tester).any((t) => t.contains('🇩🇪')), isFalse,
          reason: 'в редакторе флаг тоже значком');
    });

    testWidgets('пропавший сервер — причина на карточке', (tester) async {
      await _pump(
        tester,
        routes: const [
          TrafficRoute(
            id: 'r',
            sites: 'youtube.com',
            target: RouteTarget.server,
            serverId: 'gone',
          ),
        ],
        servers: [active],
      );
      expect(
        _texts(tester).any((t) => t.contains('сервера больше нет')),
        isTrue,
      );
    });
  });

  group('списки по ссылкам', () {
    const ads = 'https://adguardteam.github.io/filter.txt';
    const big = 'https://big.oisd.nl/';
    const local = 'https://lists.example/hosts';

    testWidgets('под полем строка на каждую ссылку, в подписи их домены',
        (tester) async {
      await _pump(
        tester,
        routes: const [
          TrafficRoute(
            id: 'b',
            sites: 'doubleclick.net, $ads\n$big\n$local',
            target: RouteTarget.block,
          ),
        ],
        ruleLists: {
          ads: RuleListStatus(
            url: ads,
            domains: 82341,
            updatedAt: DateTime.now().subtract(const Duration(hours: 3)),
          ),
          big: const RuleListStatus(
            url: big,
            failure: RuleListFailure.network,
          ),
          local: RuleListStatus(
            url: local,
            domains: 120,
            updatedAt: DateTime.now().subtract(const Duration(days: 2)),
            failure: RuleListFailure.http,
            httpStatus: 404,
          ),
        },
      );
      await tester.tap(find.textContaining('doubleclick.net'));
      await tester.pumpAndSettle();

      final texts = _texts(tester);
      expect(
        texts,
        contains('Свои сайты · 1 запись, 82\u00a0461 домен по ссылкам'),
      );
      expect(
        texts,
        contains('adguardteam.github.io — 82\u00a0341 домен, обновлён 3ч назад'),
      );
      expect(
        texts,
        contains(
          'big.oisd.nl — не загрузился, повтор при следующем подключении',
        ),
      );
      // Скачанное раньше остаётся в силе — строка об этом, а не об ошибке.
      expect(
        texts,
        contains(
          'lists.example — 120 доменов, обновлён 2д назад, '
          'свежий не загрузился',
        ),
      );
    });

    testWidgets('пока ничего не скачано, ссылка — обычная запись',
        (tester) async {
      await _pump(
        tester,
        routes: const [
          TrafficRoute(id: 'b', sites: ads, target: RouteTarget.block),
        ],
        ruleLists: {ads: const RuleListStatus(url: ads, loading: true)},
      );
      await tester.tap(find.textContaining('adguardteam'));
      await tester.pumpAndSettle();
      final texts = _texts(tester);
      expect(texts, contains('Свои сайты · 1 запись'));
      expect(texts, contains('adguardteam.github.io — загружается…'));
    });
  });

  test('счётчик записей склоняется и для 21, 22, 25', () {
    final ru = lookupAppLocalizations(const Locale('ru'));
    expect(ru.settingsRoutingItemCount(0), 'пусто');
    expect(ru.settingsRoutingItemCount(1), '1 запись');
    expect(ru.settingsRoutingItemCount(21), '21 запись');
    expect(ru.settingsRoutingItemCount(22), '22 записи');
    expect(ru.settingsRoutingItemCount(25), '25 записей');
    expect(ru.settingsRoutingRouteCount(21), '21 маршрут');
    expect(ru.settingsRoutingRouteCount(5), '5 маршрутов');
  });
  // Отдельные приложения: mihomo на ПК. Выбор — как в сплите, пометки на
  // карточке — почему маршрут не сработает.
  group('отдельные приложения', () {
    const caps = RouteCapabilities(
      apps: true,
      servers: true,
      core: VpnBackend.mihomo,
    );
    const chrome = AppInfo(
      packageName: 'chrome.exe',
      appName: 'chrome.exe',
      installPath: r'C:\Program Files\Google\Chrome\chrome.exe',
    );
    const firefox = AppInfo(
      packageName: 'firefox.exe',
      appName: 'firefox.exe',
      installPath: r'C:\Program Files\Mozilla Firefox\firefox.exe',
    );
    const discord = AppInfo(packageName: 'Discord.exe', appName: 'Discord.exe');

    testWidgets('приложения выбираются отметками и «Готово»', (tester) async {
      await _pump(
        tester,
        routes: const [TrafficRoute(id: 'r', sites: 'youtube.com')],
        caps: caps,
        apps: const [chrome, discord, firefox],
      );
      await tester.tap(find.text('youtube.com'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Кто'));
      await tester.pumpAndSettle();
      expect(find.text('Отдельные приложения'), findsOneWidget);
      final done = find.widgetWithText(FilledButton, 'Готово · 0');
      expect(tester.widget<FilledButton>(done).onPressed, isNull,
          reason: 'без единого приложения выбирать нечего');

      await tester.tap(find.text('chrome.exe'));
      await tester.pump();
      await tester.tap(find.text('firefox.exe'));
      await tester.pump();
      await tester.tap(find.text('Готово · 2'));
      await tester.pumpAndSettle();

      final saved = (await _storage.getRoutes()).single;
      expect(saved.apps, ['chrome.exe', 'firefox.exe']);
      expect(find.text('chrome, firefox'), findsOneWidget);
    });

    testWidgets('системные приложения — по кнопке, как в сплите',
        (tester) async {
      const system = AppInfo(
        packageName: 'svchost.exe',
        appName: 'svchost.exe',
        isSystem: true,
      );
      await _pump(
        tester,
        routes: const [TrafficRoute(id: 'r', sites: 'youtube.com')],
        caps: caps,
        apps: const [chrome],
        systemApps: const [system],
      );
      await tester.tap(find.text('youtube.com'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Кто'));
      await tester.pumpAndSettle();
      expect(find.text('svchost.exe'), findsNothing);

      await tester.tap(find.byTooltip('Показать системные'));
      await tester.pumpAndSettle();
      expect(find.text('svchost.exe'), findsWidgets);
      expect(find.text('chrome.exe'), findsWidgets);
      expect(find.byTooltip('Скрыть системные'), findsOneWidget);
    });

    testWidgets('«Все приложения» снимает выбор, «весь трафик» уходит',
        (tester) async {
      await _pump(
        tester,
        routes: const [
          TrafficRoute(
            id: 'r',
            apps: ['chrome.exe'],
            content: RouteContent.allTraffic,
            target: RouteTarget.direct,
          ),
        ],
        caps: caps,
        apps: const [chrome],
      );
      await tester.tap(find.text('chrome'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Кто'));
      await tester.pumpAndSettle();
      // Выбранное раньше — сверху и с отметкой.
      expect(find.text('Готово · 1'), findsOneWidget);
      await tester.tap(find.text('Все приложения').last);
      await tester.pumpAndSettle();

      final saved = (await _storage.getRoutes()).single;
      expect(saved.apps, isEmpty);
      expect(saved.content, RouteContent.sites,
          reason: '«все приложения + весь трафик» — это «Всё остальное»');
    });

    testWidgets('не запущенное приложение маршрута — своей строкой',
        (tester) async {
      await _pump(
        tester,
        routes: const [
          TrafficRoute(id: 'r', apps: ['Telegram.exe'], sites: 't.me'),
        ],
        caps: caps,
        apps: const [chrome],
      );
      await tester.tap(find.text('Telegram'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Кто'));
      await tester.pumpAndSettle();
      // Имя и подпись у такой строки одни и те же, как в сплите.
      expect(find.text('Telegram.exe'), findsWidgets);
      expect(find.text('Готово · 1'), findsOneWidget);
    });

    testWidgets('в режиме прокси — «только в режиме TUN»', (tester) async {
      await _pump(
        tester,
        routes: const [
          TrafficRoute(id: 'r', apps: ['chrome.exe'], sites: 'youtube.com'),
        ],
        caps: const RouteCapabilities(
          appsNeedTun: true,
          servers: true,
          core: VpnBackend.mihomo,
        ),
      );
      expect(
        _texts(tester).any((t) => t.contains('только в режиме TUN')),
        isTrue,
      );
      // Выбор приложений при этом не прячется: до рабочего маршрута один
      // переключатель.
      await tester.tap(find.text('Новый маршрут'));
      await tester.pumpAndSettle();
      expect(find.text('Кто'), findsOneWidget);
    });

    testWidgets('приложение, которое сплит ведёт мимо VPN, — с причиной',
        (tester) async {
      await _pump(
        tester,
        routes: const [
          TrafficRoute(
            id: 'r',
            apps: ['Discord.exe', 'chrome.exe'],
            sites: 'discord.com',
          ),
        ],
        caps: caps,
        splitExclude: const ['discord.exe'],
      );
      expect(
        _texts(tester).any(
          (t) => t.contains('раздельное туннелирование ведёт мимо VPN: Discord'),
        ),
        isTrue,
      );
    });

    testWidgets('при «только выбранных» — невыбранные', (tester) async {
      await _pump(
        tester,
        routes: const [
          TrafficRoute(id: 'r', apps: ['chrome.exe'], sites: 'youtube.com'),
        ],
        caps: caps,
        splitInclude: const ['firefox.exe'],
      );
      expect(
        _texts(tester).any(
          (t) => t.contains('раздельное туннелирование ведёт мимо VPN: chrome'),
        ),
        isTrue,
      );
    });
  });

  group('профили', () {
    const subs = [
      Subscription(id: 'sub-games', name: 'Gaming VPN', url: 'https://a.example'),
      Subscription(id: 'sub-work', name: 'Office VPN', url: 'https://b.example'),
    ];
    const games = RoutingProfile(
      id: 'games',
      name: 'Игры',
      subscriptionIds: ['sub-games'],
      finalOutbound: AppSettings.finalOutboundDirect,
      routes: [
        TrafficRoute(
          id: 'steam',
          sites: 'steampowered.com',
          target: RouteTarget.direct,
        ),
      ],
    );

    Finder inCard(String id, Finder f) => find.descendant(
          of: find.byKey(ValueKey('routing-profile-$id')),
          matching: f,
        );

    // карточка профиля ниже раскрытого «Основного» и уходит за край экрана
    Future<void> tapInCard(WidgetTester tester, String id, String text) async {
      final f = inCard(id, find.text(text));
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    testWidgets('без профилей «Основной» раскрыт и действует на всё',
        (tester) async {
      await _pump(tester, routes: const [_direct]);
      final texts = _texts(tester);
      expect(texts, contains('Основной'));
      expect(texts, contains('Все подписки и свои серверы'));
      expect(find.byType(Switch), findsNothing,
          reason: '«Основной» не выключается');
      expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
      expect(find.text('Новый профиль'), findsOneWidget);
    });

    testWidgets('профиль свёрнут: подписки плашками, сводка без маршрутов',
        (tester) async {
      await _pump(
        tester,
        routes: const [_direct],
        profiles: const [games],
        subs: subs,
      );
      final texts = _texts(tester);
      expect(texts, contains('Остальные подписки и свои серверы'));
      expect(texts, contains('1 маршрут · всё остальное → напрямую'));
      expect(texts, contains('Gaming VPN'));
      expect(texts, isNot(contains('Office VPN')));
      expect(texts, isNot(contains('steampowered.com')));

      await tester.tap(find.text('Игры'));
      await tester.pumpAndSettle();
      expect(_texts(tester), contains('steampowered.com'));
      final row = find.text('steampowered.com');
      expect(
        tester
            .widget<ExpressiveGroupTile>(
              find.ancestor(of: row, matching: find.byType(ExpressiveGroupTile)),
            )
            .color,
        Theme.of(tester.element(row)).colorScheme.surfaceContainer,
        reason: 'строка темнее карточки, а не цвета своего «куда»',
      );

      await tester.tap(find.text('Основной'));
      await tester.pumpAndSettle();
      expect(_texts(tester), isNot(contains('ru, yandex.ru, vk.com')));
      expect(
        _texts(tester),
        contains('Остальные подписки и свои серверы\n1 маршрут'),
      );
    });

    testWidgets('на телевизоре профиль раскрывается пультом: стрелка и OK',
        (tester) async {
      PlatformBootstrap.debugIsTelevisionOverride = true;
      addTearDown(() => PlatformBootstrap.debugIsTelevisionOverride = null);
      await _pump(
        tester,
        routes: const [_direct],
        profiles: const [games],
        subs: subs,
      );
      Focus.of(tester.element(find.descendant(
        of: find.byKey(const ValueKey('routing-profile-games')),
        matching: find.byIcon(Icons.expand_more_rounded),
      ))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(_texts(tester), contains('steampowered.com'));
    });

    testWidgets('переключатель профиля не меняет высоту свёрнутого «Основного»',
        (tester) async {
      await _pump(
        tester,
        routes: const [_direct],
        profiles: const [games],
        subs: subs,
      );
      // ширина, на которой «Все… · 1 маршрут» влезал в строку, а «Остальные…» уже нет
      tester.view.physicalSize = const Size(660 * 2.625, 2400);
      await tester.tap(find.text('Основной'));
      await tester.pumpAndSettle();
      final main = find.byKey(const ValueKey('routing-profile-main'));
      final before = tester.getSize(main).height;
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(_texts(tester), contains('Все подписки и свои серверы\n1 маршрут'));
      expect(tester.getSize(main).height, before);
    });

    testWidgets('выключатель сохраняется, выключенный подписан',
        (tester) async {
      await _pump(tester, profiles: const [games], subs: subs);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect((await _storage.getRoutingProfiles()).single.enabled, isFalse);
      expect(_texts(tester), contains('Выключен: работает «Основной»'));
      expect(_texts(tester), contains('Все подписки и свои серверы'),
          reason: 'выключенный профиль ничего у «Основного» не забирает');
    });

    testWidgets('профиль без подписок так и подписан', (tester) async {
      await _pump(
        tester,
        profiles: const [RoutingProfile(id: 'p', name: 'Пустой')],
        subs: subs,
      );
      expect(_texts(tester), contains('Не привязан ни к одной подписке'));
    });

    testWidgets('новый профиль копией «Основного» забирает подписку',
        (tester) async {
      await _pump(
        tester,
        routes: const [_direct],
        settings: const AppSettings(
          finalOutbound: AppSettings.finalOutboundBlock,
        ),
        profiles: const [
          RoutingProfile(
            id: 'work',
            name: 'Работа',
            subscriptionIds: ['sub-work'],
          ),
        ],
        subs: subs,
      );
      await tester.tap(find.text('Новый профиль'));
      await tester.pumpAndSettle();
      expect(find.text('сейчас по профилю «Работа»'), findsOneWidget);
      final freeRow = find.ancestor(
        of: find.text('Gaming VPN').last,
        matching: find.byType(ExpressiveGroupTile),
      );
      expect(
        find.descendant(of: freeRow, matching: find.byType(Text)),
        findsOneWidget,
        reason: 'у свободной подписки только имя, без подписи',
      );
      final create = find.widgetWithText(FilledButton, 'Создать');
      expect(tester.widget<FilledButton>(create).onPressed, isNull,
          reason: 'без названия создавать нечего');

      await tester.enterText(find.byType(TextField), 'Игры');
      await tester.tap(find.text('Gaming VPN').last);
      await tester.tap(find.text('Office VPN').last);
      await tester.pump();
      await tester.tap(create);
      await tester.pumpAndSettle();

      final saved = await _storage.getRoutingProfiles();
      expect(saved.map((p) => p.name), ['Работа', 'Игры']);
      expect(saved.first.subscriptionIds, isEmpty,
          reason: 'у подписки один профиль');
      expect(saved.last.subscriptionIds, ['sub-games', 'sub-work']);
      expect(saved.last.routes, const [_direct]);
      expect(saved.last.finalOutbound, AppSettings.finalOutboundBlock);
      expect(
        inCard(saved.last.id, find.text('ru, yandex.ru, vk.com')),
        findsOneWidget,
        reason: 'только что созданный профиль раскрыт',
      );
    });

    testWidgets('пустой профиль: без маршрутов, остальное через VPN',
        (tester) async {
      await _pump(
        tester,
        routes: const [_direct],
        settings: const AppSettings(
          finalOutbound: AppSettings.finalOutboundDirect,
        ),
        subs: subs,
      );
      await tester.tap(find.text('Новый профиль'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Чистый');
      await tester.tap(find.text('Пустого профиля'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Создать'));
      await tester.pumpAndSettle();
      final saved = (await _storage.getRoutingProfiles()).single;
      expect(saved.routes, isEmpty);
      expect(saved.finalOutbound, AppSettings.finalOutboundProxy);
    });

    testWidgets('маршрут из карточки профиля пишется в профиль',
        (tester) async {
      await _pump(
        tester,
        routes: const [_direct],
        profiles: const [games],
        subs: subs,
      );
      await tester.tap(find.text('Игры'));
      await tester.pumpAndSettle();
      await tapInCard(tester, 'games', 'Новый маршрут');
      await tester.enterText(find.byType(TextField), 'twitch.tv');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(await _storage.getRoutes(), const [_direct]);
      final profile = (await _storage.getRoutingProfiles()).single;
      expect(
        profile.routes.map((r) => r.sites),
        ['steampowered.com', 'twitch.tv'],
      );
    });

    testWidgets('удаление маршрута профиля не трогает основные',
        (tester) async {
      await _pump(
        tester,
        routes: const [_direct],
        profiles: const [games],
        subs: subs,
      );
      await tester.tap(find.text('Игры'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('steampowered.com'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Удалить'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
      await tester.pumpAndSettle();

      expect(await _storage.getRoutes(), const [_direct]);
      expect((await _storage.getRoutingProfiles()).single.routes, isEmpty);
    });

    testWidgets('«Всё остальное» профиля пишется в профиль, не в настройки',
        (tester) async {
      final c = await _pump(tester, profiles: const [games], subs: subs);
      await tester.tap(find.text('Игры'));
      await tester.pumpAndSettle();
      await tapInCard(tester, 'games', 'Всё остальное');
      await tester.tap(find.text('Блокировать'));
      await tester.pumpAndSettle();

      expect(
        (await _storage.getRoutingProfiles()).single.finalOutbound,
        AppSettings.finalOutboundBlock,
      );
      expect(
        c.read(settingsNotifierProvider).value!.finalOutbound,
        AppSettings.finalOutboundProxy,
      );
    });

    testWidgets('Re-filter в профиле ставит напрямую «Всё остальное» профиля',
        (tester) async {
      final c = await _pump(
        tester,
        profiles: const [RoutingProfile(id: 'p', name: 'Профиль')],
        subs: subs,
      );
      await tester.tap(find.text('Профиль'));
      await tester.pumpAndSettle();
      await tapInCard(tester, 'p', 'Новый маршрут');
      await tester.tap(find.text('Что'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Заблокировано в РФ (Re-filter)'));
      await tester.pumpAndSettle();

      expect(
        (await _storage.getRoutingProfiles()).single.finalOutbound,
        AppSettings.finalOutboundDirect,
      );
      expect(
        c.read(settingsNotifierProvider).value!.finalOutbound,
        AppSettings.finalOutboundProxy,
      );
    });

    testWidgets('белые списки в профиле выключают рунет только в профиле',
        (tester) async {
      await _pump(
        tester,
        routes: const [_direct],
        profiles: const [
          RoutingProfile(id: 'p', name: 'Профиль', routes: [_direct]),
        ],
        subs: subs,
      );
      await tester.tap(find.text('Профиль'));
      await tester.pumpAndSettle();
      await tapInCard(tester, 'p', 'Новый маршрут');
      await tester.tap(find.text('Что'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Белые списки мобильной связи'));
      await tester.pumpAndSettle();

      final profile = (await _storage.getRoutingProfiles()).single;
      expect(
        profile.routes.singleWhere((r) => r.id == 'direct').enabled,
        isFalse,
      );
      expect(profile.routes.any((r) => r.presetId == 'whitelist'), isTrue);
      expect((await _storage.getRoutes()).single.enabled, isTrue);
    });

    testWidgets('меню: переименовать, подписки, удалить', (tester) async {
      await _pump(tester, profiles: const [games], subs: subs);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Переименовать'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Стрим');
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();
      expect((await _storage.getRoutingProfiles()).single.name, 'Стрим');
      expect(find.text('Стрим'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Подписки'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gaming VPN').last);
      await tester.tap(find.text('Office VPN'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();
      expect(
        (await _storage.getRoutingProfiles()).single.subscriptionIds,
        ['sub-work'],
      );

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Удалить профиль «Стрим»? Его подписки перейдут на «Основной».',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
      await tester.pumpAndSettle();
      expect(await _storage.getRoutingProfiles(), isEmpty);
      expect(find.text('Стрим'), findsNothing);
    });
  });
  group('правила провайдера', () {
    final provider = ServerItem(
      id: 'provider',
      type: ServerItemType.manual,
      config: '{"remarks":"Provider","outbounds":[{"tag":"proxy","protocol":"vless",'
          '"settings":{"vnext":[{"address":"198.51.100.50","port":443,'
          '"users":[{"id":"00000000-0000-4000-8000-000000000000"}]}]}},'
          '{"tag":"direct","protocol":"freedom"}],'
          '"routing":{"rules":[{"type":"field","domain":["domain:ru"],"outboundTag":"direct"}]}}',
    );
    final plain = ServerItem(
      id: 'plain',
      type: ServerItemType.manual,
      config: 'trojan://pw@de.example:443?security=tls&sni=de.example#Germany',
    );

    testWidgets('без серверов со своими правилами строки нет', (tester) async {
      await _pump(tester, servers: [plain]);
      expect(find.text('Не учитывать правила провайдера'), findsNothing);
    });

    testWidgets('есть такой сервер: строка первой, выключена, включается',
        (tester) async {
      final container = await _pump(tester, servers: [plain, provider]);
      final row = find.text('Не учитывать правила провайдера');
      expect(row, findsOneWidget);
      expect(find.text('Работают только ваши маршруты'), findsOneWidget);
      expect(tester.getRect(row).top,
          lessThan(tester.getRect(find.text('Основной')).top));

      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(
        container.read(settingsNotifierProvider).value?.ignoreProviderRules,
        isTrue,
      );
    });

    testWidgets('включённую строку не прячем, даже если таких серверов не осталось',
        (tester) async {
      await _pump(
        tester,
        servers: [plain],
        settings: const AppSettings(ignoreProviderRules: true),
      );
      expect(find.text('Не учитывать правила провайдера'), findsOneWidget);
    });
  });
}
