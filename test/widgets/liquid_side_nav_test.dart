import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/main.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/providers/halloween_provider.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/shared/ui/floating_bar.dart';
import 'package:keqdroid/shared/ui/liquid_nav.dart';
import 'package:keqdroid/shared/ui/nav_rail.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

// боком Модерн встаёт лентой у края экрана вместо прежней боковой панели

Future<List<int>> _pumpRail(
  WidgetTester tester, {
  LiquidBarStyle style = LiquidBarStyle.mainland,
  int index = 0,
  Locale locale = const Locale('en'),
}) async {
  final tapped = <int>[];
  tester.view.physicalSize = const Size(915, 412);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Row(
          children: [
            LiquidSideNav(
              index: index,
              style: style,
              showConnectedBadge: false,
              onTap: tapped.add,
            ),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tapped;
}

Rect _tab(WidgetTester tester, String label) =>
    tester.getRect(find.bySemanticsLabel(RegExp('^$label')));

class _NoSubs extends SubscriptionsNotifier {
  @override
  Future<List<Subscription>> build() async => const [];
}

class _NoHalloween extends HalloweenActiveNotifier {
  @override
  bool build() => false;
}

Future<void> _pumpHome(WidgetTester tester, {required String barStyle}) async {
  tester.view.physicalSize = const Size(915, 412);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = const AppSettings().copyWith(bottomBarStyle: barStyle);
  final storage = await tester.runAsync(() => buildStorageService(
        initialValues: {'keqdis_settings': settings.toJsonString()},
      ));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage!),
        subscriptionsProvider.overrideWith(_NoSubs.new),
        halloweenActiveProvider.overrideWith(_NoHalloween.new),
        exitIpProvider.overrideWith((ref) async => null),
        updateInfoProvider.overrideWith((ref) async => null),
        vpnEngineProvider.overrideWithValue(
          VpnEngine.withBackend(FakeTunnelBackend()),
        ),
      ],
      child: const KeqdisApp(home: VpnHomeScreen()),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  tearDown(() {
    FloatingBar.jump.value = null;
    FloatingBar.actions.clear();
  });

  for (final style in LiquidBarStyle.values) {
    testWidgets('${style.name}: лента у края, у выбранной подпись видна целиком', (
      tester,
    ) async {
      await _pumpRail(tester, style: style);
      expect(tester.getSize(find.byType(LiquidSideNav)).width, LiquidSideNav.width);
      final servers = _tab(tester, 'Servers');
      expect(servers.left, closeTo(FloatingBar.margin, 0.5));
      expect(servers.width, FloatingBar.height);
      // вкладки друг под другом, выбранная длиннее
      final subs = _tab(tester, 'Subscriptions');
      expect(subs.top, greaterThan(servers.bottom - 0.5));
      expect(servers.height, greaterThan(subs.height + 20));
      final label = find.text('Servers');
      final shown = tester
          .getSize(find.ancestor(of: label, matching: find.byType(Align)).first)
          .height;
      final full = tester
          .getSize(find.ancestor(of: label, matching: find.byType(Opacity)).first)
          .height;
      expect(shown, closeTo(full, 0.5));
    });

    testWidgets('${style.name}: плюс под лентой запускает действие вкладки, в настройках его нет', (
      tester,
    ) async {
      var added = 0;
      FloatingBar.actions[0] = () => added++;
      await _pumpRail(tester, style: style);
      final plus = tester.getRect(find.byIcon(Icons.add_rounded));
      expect(plus.top, greaterThan(_tab(tester, 'Settings').bottom - 0.5));
      await tester.tap(find.byIcon(Icons.add_rounded));
      expect(added, 1);

      await _pumpRail(tester, style: style, index: 2);
      expect(find.byIcon(Icons.add_rounded), findsNothing);
    });

    testWidgets('${style.name}: стрелка прокрутки вытекает над лентой, когда список просит', (
      tester,
    ) async {
      await _pumpRail(tester, style: style);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
      var jumped = 0;
      FloatingBar.jump.value = FloatingJump(up: false, onTap: () => jumped++);
      await tester.pumpAndSettle();
      final arrow = tester.getRect(find.byIcon(Icons.arrow_downward_rounded));
      expect(arrow.bottom, lessThan(_tab(tester, 'Servers').top + 0.5));
      await tester.tap(find.byIcon(Icons.arrow_downward_rounded));
      expect(jumped, 1);
      FloatingBar.jump.value = null;
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
    });
  }

  testWidgets('короткое касание выбирает вкладку', (tester) async {
    final tapped = await _pumpRail(tester);
    await tester.tap(find.byIcon(Icons.settings_rounded));
    expect(tapped, [2]);
  });

  testWidgets('палец можно задержать и вести вниз по вкладкам: выбор по отпусканию', (
    tester,
  ) async {
    final tapped = await _pumpRail(tester);
    final gesture = await tester.startGesture(_tab(tester, 'Servers').center);
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.moveTo(_tab(tester, 'Subscriptions').center);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(_tab(tester, 'Settings').center);
    await tester.pump(const Duration(milliseconds: 50));
    expect(tapped, isEmpty, reason: 'пока палец на ленте, вкладка не меняется');
    await gesture.up();
    expect(tapped, [2]);
    await tester.pumpAndSettle();
  });

  testWidgets('на отдаче пружины подпись не подрезается', (tester) async {
    tester.view.physicalSize = const Size(915, 412);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    Widget rail(int index) => MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Row(
              children: [
                LiquidSideNav(
                  index: index,
                  style: LiquidBarStyle.mainland,
                  showConnectedBadge: false,
                  onTap: (_) {},
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        );
    await tester.pumpWidget(rail(0));
    await tester.pumpAndSettle();
    await tester.pumpWidget(rail(1));
    final label = find.text('Subscriptions');
    var opened = false;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final shown = tester
          .getSize(find.ancestor(of: label, matching: find.byType(Align)).first)
          .height;
      final full = tester
          .getSize(find.ancestor(of: label, matching: find.byType(Opacity)).first)
          .height;
      if (opened) {
        expect(shown, greaterThanOrEqualTo(full - 0.5), reason: 'кадр ${i * 16} мс');
      } else if (shown >= full - 0.5) {
        opened = true;
      }
    }
    expect(opened, isTrue);
  });

  testWidgets('справа налево лента стоит у правого края', (tester) async {
    await _pumpRail(tester, locale: const Locale('fa'));
    final nav = tester.getRect(find.byType(LiquidSideNav));
    expect(nav.right, 915);
    final servers = tester.getRect(
      find.descendant(of: find.byType(LiquidSideNav), matching: find.byType(Material)).first,
    );
    expect(servers.right, closeTo(nav.right - FloatingBar.margin, 0.5));
  });

  group('главный экран боком', () {
    setUp(() => PlatformBootstrap.debugIsDesktopOverride = false);
    tearDown(() {
      PlatformBootstrap.debugIsDesktopOverride = null;
      PlatformBootstrap.debugIsTelevisionOverride = null;
    });

    testWidgets('в Модерне жидкая лента, плюс в ней, а не отдельной кнопкой', (
      tester,
    ) async {
      await _pumpHome(tester, barStyle: AppSettings.bottomBarModern);
      expect(find.byType(LiquidSideNav), findsOneWidget);
      expect(find.byType(AppNavRail), findsNothing);
      expect(find.byType(LiquidBottomNav), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(
        find.descendant(
          of: find.byType(LiquidSideNav),
          matching: find.byIcon(Icons.add_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('в Легаси прежняя боковая панель и кнопка добавления', (tester) async {
      await _pumpHome(tester, barStyle: AppSettings.bottomBarLegacy);
      expect(find.byType(AppNavRail), findsOneWidget);
      expect(find.byType(LiquidSideNav), findsNothing);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('на телевизоре прежняя панель: её водят пультом', (tester) async {
      PlatformBootstrap.debugIsTelevisionOverride = true;
      await _pumpHome(tester, barStyle: AppSettings.bottomBarModern);
      expect(find.byType(AppNavRail), findsOneWidget);
      expect(find.byType(LiquidSideNav), findsNothing);
    });
  });
}
