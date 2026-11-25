import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/models/app_info.dart';
import 'package:keqdroid/models/app_internals.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/ping_test_config.dart';
import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/settings_tab.dart';
import 'package:keqdroid/screens/subscriptions_tab.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/shared/ui/tv_focus.dart';
import 'package:keqdroid/utils/geo_asset_index.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

final _tvInternals = AppInternals(
  cores: [
    for (final name in ['libxray.so', 'libmihomo.so'])
      CoreInfo(
        name: name,
        role: CoreRole.core,
        version: 'v1.0.0',
        sizeBytes: 30 << 20,
        modified: DateTime(2026, 11),
      ),
  ],
  geoBases: const [
    GeoBaseInfo(name: 'geoip.dat', codeCount: 250),
    GeoBaseInfo(name: 'geosite.dat', codeCount: 1400),
  ],
  session: const SessionInfo(
    status: VpnStatus.disconnected,
    engine: 'mihomo',
    socksPort: 10808,
    httpPort: 10809,
  ),
  build: const BuildInfo(
    appVersion: '0.39.2',
    buildNumber: '91',
    packageName: 'com.keqdroid.keqdroid',
    operatingSystem: 'android',
    osVersion: 'Android 14 (SDK 34)',
    abi: 'arm64-v8a',
    dartVersion: '3.11.3',
    releaseMode: true,
  ),
);

const _tvApps = [
  AppInfo(packageName: 'org.telegram.messenger', appName: 'Telegram'),
  AppInfo(packageName: 'com.google.android.youtube.tv', appName: 'YouTube'),
  AppInfo(
    packageName: 'com.google.android.youtube.tvmusic',
    appName: 'YouTube Music',
  ),
];

void _setTvViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = const Size(1920, 1080);
  addTearDown(tester.view.reset);
}

bool _focusContainsText(String label) {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  var found = false;
  void visit(Element el) {
    if (found) return;
    final w = el.widget;
    if (w is Text) {
      final text = (w.data ?? w.textSpan?.toPlainText() ?? '').replaceAll(
        RegExp('[\u2066-\u2069]'),
        '',
      );
      if (text.contains(label)) {
        found = true;
        return;
      }
    }
    el.visitChildren(visit);
  }

  (ctx as Element).visitChildren(visit);
  return found;
}

bool _isEditingText() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  return ctx.widget is EditableText ||
      ctx.findAncestorWidgetOfExactType<EditableText>() != null;
}

void main() {
  setUp(() {
    PlatformBootstrap.debugIsDesktopOverride = false;
    PlatformBootstrap.debugIsTelevisionOverride = true;
  });

  tearDown(() {
    PlatformBootstrap.debugIsDesktopOverride = null;
    PlatformBootstrap.debugIsTelevisionOverride = null;
  });

  testWidgets(
    'Настройки ядра на ТВ: пульт переключается между карточками ядер',
    (tester) async {
      _setTvViewport(tester);
      final StorageService storage = (await tester.runAsync(
        () => buildStorageService(
          initialValues: {
            'keqdis_settings': const AppSettings(
              appLanguageCode: 'ru',
              vpnCore: AppSettings.vpnCoreXray,
            ).toJsonString(),
          },
        ),
      ))!;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageProvider.overrideWithValue(storage),
            vpnEngineProvider.overrideWithValue(
              VpnEngine.withBackend(FakeTunnelBackend()),
            ),
            appInternalsProviderForTest.overrideWith(
              (ref) async => _tvInternals,
            ),
          ],
          child: KeqdroidApp(home: xrayCoreSettingsScreenForTest()),
        ),
      );
      await tester.pumpAndSettle();

      final xrayNode = Focus.of(tester.element(find.text('libxray.so')));
      xrayNode.requestFocus();
      await tester.pumpAndSettle();
      expect(xrayNode.hasPrimaryFocus, isTrue);

      var reachedMihomo = false;
      for (var i = 0; i < 12; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        if (_focusContainsText('libmihomo.so')) {
          reachedMihomo = true;
          break;
        }
      }
      expect(reachedMihomo, isTrue);

      var backToXray = false;
      for (var i = 0; i < 12; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        if (_focusContainsText('libxray.so')) {
          backToXray = true;
          break;
        }
      }
      expect(backToXray, isTrue);
    },
  );

  testWidgets(
    'Шторка Кто на ТВ: из поля поиска стрелка вниз переходит на найденное приложение и Готово',
    (tester) async {
      _setTvViewport(tester);
      final StorageService storage = await buildStorageService(
        initialValues: {
          'keqdis_settings': const AppSettings(
            appLanguageCode: 'ru',
          ).toJsonString(),
        },
      );
      await storage.saveRoutes(const []);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageProvider.overrideWithValue(storage),
            vpnEngineProvider.overrideWithValue(
              VpnEngine.withBackend(FakeTunnelBackend()),
            ),
            routeCapabilitiesProvider.overrideWithValue(
              const RouteCapabilities(apps: true, servers: true),
            ),
            installedAppsProvider(false).overrideWith((ref) async => _tvApps),
            installedAppsProvider(true).overrideWith((ref) async => _tvApps),
            geoAssetIndexProvider.overrideWith(
              (ref) async => const GeoAssetIndex(
                geositeCodes: {'google', 'youtube'},
                geoipCodes: {'ru'},
              ),
            ),
          ],
          child: KeqdroidApp(home: routingScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('Новый маршрут'), findsOneWidget);

      await tester.tap(find.text('Кто'));
      await tester.pumpAndSettle();

      final allAppsNode = Focus.of(
        tester.element(find.text('Всё, что идёт через VPN')),
      );
      allAppsNode.requestFocus();
      await tester.pumpAndSettle();

      var onTelegram = false;
      for (var i = 0; i < 6; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        if (_focusContainsText('Telegram')) {
          onTelegram = true;
          break;
        }
      }
      expect(
        onTelegram,
        isTrue,
        reason: 'стрелка вниз должна проходить мимо поля поиска к приложениям',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.context?.widget is EditableText,
        isFalse,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      tester.testTextInput.enterText('youtu');
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        _focusContainsText('com.google.android.youtube.tv'),
        isTrue,
        reason: 'стрелка вниз из активного поиска должна встать на YouTube',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_focusContainsText('Готово'), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              ((w.data ?? '').contains('YouTube') ||
                  (w.data ?? '').contains('youtube.tv')),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Редактор маршрута на ТВ: проход мимо поля сайтов, переход на гео-коды и Назад снимает ввод без закрытия правила',
    (tester) async {
      _setTvViewport(tester);
      final StorageService storage = await buildStorageService(
        initialValues: {
          'keqdis_settings': const AppSettings(
            appLanguageCode: 'ru',
          ).toJsonString(),
        },
      );
      await storage.saveRoutes(const []);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageProvider.overrideWithValue(storage),
            vpnEngineProvider.overrideWithValue(
              VpnEngine.withBackend(FakeTunnelBackend()),
            ),
            routeCapabilitiesProvider.overrideWithValue(
              const RouteCapabilities(apps: true, servers: true),
            ),
            installedAppsProvider(false).overrideWith((ref) async => _tvApps),
            installedAppsProvider(true).overrideWith((ref) async => _tvApps),
            geoAssetIndexProvider.overrideWith(
              (ref) async => const GeoAssetIndex(
                geositeCodes: {'google', 'youtube'},
                geoipCodes: {'ru'},
              ),
            ),
          ],
          child: KeqdroidApp(home: routingScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('Новый маршрут'), findsOneWidget);

      final whatNode = Focus.of(tester.element(find.text('Что')));
      whatNode.requestFocus();
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final fieldCtx = FocusManager.instance.primaryFocus!.context!;
      expect(TvFocusHighlight.containerOf(fieldCtx), isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      final geoBtnNode = Focus.of(
        tester.element(find.byIcon(Icons.travel_explore_rounded)),
      );
      expect(geoBtnNode.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_focusContainsText('Протокол'), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(
        _isEditingText(),
        isTrue,
        reason: 'после select фокус должен быть внутри EditableText',
      );

      tester.testTextInput.enterText('youtube.com');
      await tester.pumpAndSettle();
      expect(
        _isEditingText(),
        isTrue,
        reason: 'после enterText фокус должен оставаться внутри EditableText',
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.text('Протокол'),
        findsOneWidget,
        reason: 'Назад при активном поле ввода не должен закрывать редактор',
      );
      expect(_isEditingText(), isFalse);
      expect(find.text('youtube.com'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_focusContainsText('Протокол'), isTrue);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Протокол'), findsNothing);
      final routes = await storage.getRoutes();
      expect(routes.single.sites, 'youtube.com');
    },
  );

  testWidgets(
    'Поле с CommitOnBlur на ТВ сохраняет введённое при выходе кнопкой Назад',
    (tester) async {
      _setTvViewport(tester);
      final StorageService storage = await buildStorageService(
        initialValues: {
          'keqdis_settings': const AppSettings(
            appLanguageCode: 'ru',
            pingTestTarget: PingTestConfig.targetCustom,
          ).toJsonString(),
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageProvider.overrideWithValue(storage),
            vpnEngineProvider.overrideWithValue(
              VpnEngine.withBackend(FakeTunnelBackend()),
            ),
            updateInfoProvider.overrideWith((ref) async => null),
          ],
          child: const KeqdroidApp(home: SettingsTab()),
        ),
      );
      await tester.pumpAndSettle();

      final advNode = Focus.of(tester.element(find.byIcon(Icons.tune_rounded)));
      await tester.ensureVisible(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      advNode.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byIcon(Icons.network_ping_rounded));
      await tester.pumpAndSettle();
      final pingNode = Focus.of(
        tester.element(find.byIcon(Icons.network_ping_rounded)),
      );
      pingNode.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      final fieldFinder = find.byType(TvTextField);
      await tester.scrollUntilVisible(
        fieldFinder,
        120,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      final fieldNavNode = tester
          .widget<Focus>(
            find.descendant(
              of: fieldFinder,
              matching: find.byWidgetPredicate(
                (w) => w is Focus && w.focusNode?.debugLabel == 'TvTextField',
              ),
            ),
          )
          .focusNode!;
      fieldNavNode.requestFocus();
      await tester.pumpAndSettle();
      expect(_isEditingText(), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(
        _isEditingText(),
        isTrue,
        reason: 'после select в пинге фокус должен быть внутри EditableText',
      );

      tester.testTextInput.enterText('https://cp.cloudflare.com/generate_204');
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      final saved = await storage.getSettings();
      expect(saved.pingTestUrlCustom, 'https://cp.cloudflare.com/generate_204');
    },
  );

  testWidgets(
    'Многострочное поле на ТВ двигает курсор между строками и выходит на крайней строке',
    (tester) async {
      _setTvViewport(tester);
      final ctrl = TextEditingController(text: 'first\nsecond');
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TvTextField(
                  builder: (ctx, canRequestFocus) => TextField(
                    controller: ctrl,
                    canRequestFocus: canRequestFocus,
                    maxLines: 4,
                  ),
                ),
                ElevatedButton(onPressed: () {}, child: const Text('Ниже')),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final navNode = tester
          .widget<Focus>(
            find.byWidgetPredicate(
              (w) => w is Focus && w.focusNode?.debugLabel == 'TvTextField',
            ),
          )
          .focusNode!;
      navNode.requestFocus();
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      ctrl.selection = const TextSelection.collapsed(offset: 2);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        _isEditingText(),
        isTrue,
        reason:
            'с первой строки стрелка вниз должна перевести курсор на вторую, а не выйти из поля',
      );
      expect(ctrl.selection.baseOffset, greaterThanOrEqualTo(6));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_isEditingText(), isFalse);
      expect(_focusContainsText('Ниже'), isTrue);
    },
  );

  testWidgets(
    'Шторка подписки на ТВ в фарси (RTL) и светлой теме: контраст поля и переход на кнопку приёма с телефона',
    (tester) async {
      _setTvViewport(tester);
      final StorageService storage = await buildStorageService(
        initialValues: {
          'keqdis_settings': const AppSettings(
            appLanguageCode: 'fa',
            darkTheme: false,
            followSystemTheme: false,
          ).toJsonString(),
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageProvider.overrideWithValue(storage),
            vpnEngineProvider.overrideWithValue(
              VpnEngine.withBackend(FakeTunnelBackend()),
            ),
          ],
          child: const KeqdroidApp(home: SubscriptionsTab()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();

      final fields = tester
          .widgetList<Focus>(
            find.byWidgetPredicate(
              (w) => w is Focus && w.focusNode?.debugLabel == 'TvTextField',
            ),
          )
          .toList();
      final urlNavNode = fields[1].focusNode!;
      urlNavNode.requestFocus();
      await tester.pumpAndSettle();

      final fieldFill = TvFocusHighlight.containerOf(urlNavNode.context!)!;
      final textStyle = tester
          .widget<TextField>(find.byType(TextField).at(1))
          .style!;
      expect(textStyle.color, isNot(equals(fieldFill)));

      // В RTL конец строки слева: стрелка влево переходит на внутреннюю кнопку приёма с телефона.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      final receiveBtnNode = Focus.of(
        tester.element(find.byIcon(Icons.install_mobile_rounded)),
      );
      expect(receiveBtnNode.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(urlNavNode.hasPrimaryFocus, isTrue);
    },
  );

  testWidgets(
    'На телефоне TvTextField ничего не перехватывает и оставляет штатный ввод',
    (tester) async {
      PlatformBootstrap.debugIsTelevisionOverride = false;
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TvTextField(
              builder: (ctx, canRequestFocus) =>
                  TextField(controller: ctrl, canRequestFocus: canRequestFocus),
            ),
          ),
        ),
      );

      expect(
        find.byWidgetPredicate(
          (w) => w is Focus && w.focusNode?.debugLabel == 'TvTextField',
        ),
        findsNothing,
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(_isEditingText(), isTrue);
      expect(
        TvFocusHighlight.containerOf(tester.element(find.byType(TextField))),
        isNull,
      );
    },
  );
}
