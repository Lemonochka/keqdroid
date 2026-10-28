import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/shared/ui/floating_bar.dart';
import 'package:keqdroid/shared/ui/liquid_nav.dart';

Future<void> _pumpNav(
  WidgetTester tester, {
  required LiquidBarStyle style,
  required int index,
  required Size screen,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        bottomNavigationBar: LiquidBottomNav(
          index: index,
          style: style,
          showConnectedBadge: true,
          onTap: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    FloatingBar.hidden.value = false;
    FloatingBar.jump.value = null;
    FloatingBar.actions.clear();
  });

  for (final style in LiquidBarStyle.values) {
    testWidgets('${style.name}: narrow window with long labels does not overflow', (
      tester,
    ) async {
      // меню трея сжимает окно примерно до 288 px, немецкие подписи длиннее английских
      for (var index = 0; index < 3; index++) {
        await _pumpNav(
          tester,
          style: style,
          index: index,
          screen: const Size(288, 700),
          locale: const Locale('de'),
        );
        expect(tester.takeException(), isNull, reason: 'пункт $index');
        expect(tester.getSize(find.byType(LiquidBottomNav)).height, lessThan(140));
      }
    });

    testWidgets('${style.name}: selected label is laid out in full when there is room', (
      tester,
    ) async {
      // в настройках кнопки действия нет, и подписи хватает места на обычном телефоне
      await _pumpNav(tester, style: style, index: 2, screen: const Size(411, 800));
      final label = find.text('Settings');
      final rendered = tester.getSize(label).width;
      final intrinsic = (tester.renderObject(label) as RenderBox)
          .getMaxIntrinsicWidth(double.infinity);
      expect(rendered, greaterThanOrEqualTo(intrinsic - 0.5));
    });

    testWidgets('${style.name}: the action drop runs the action of the open tab', (
      tester,
    ) async {
      var added = 0;
      FloatingBar.actions[0] = () => added++;
      await _pumpNav(tester, style: style, index: 0, screen: const Size(411, 800));
      await tester.tap(find.byIcon(Icons.add_rounded));
      expect(added, 1);
    });

    testWidgets('${style.name}: the scroll arrow rises only when the list asks for it', (
      tester,
    ) async {
      await _pumpNav(tester, style: style, index: 0, screen: const Size(411, 800));
      expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
      var jumped = 0;
      FloatingBar.jump.value = FloatingJump(up: false, onTap: () => jumped++);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_downward_rounded));
      expect(jumped, 1);
      FloatingBar.jump.value = null;
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
    });
  }

  testWidgets('settings tab has no action drop', (tester) async {
    await _pumpNav(
      tester,
      style: LiquidBarStyle.mainland,
      index: 2,
      screen: const Size(411, 800),
    );
    expect(find.byIcon(Icons.add_rounded), findsNothing);
  });

  testWidgets('hidden bar sinks below the screen edge and stops taking taps', (
    tester,
  ) async {
    var tapped = -1;
    tester.view.physicalSize = const Size(411, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          bottomNavigationBar: LiquidBottomNav(
            index: 0,
            style: LiquidBarStyle.islands,
            showConnectedBadge: false,
            onTap: (i) => tapped = i,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final shown = tester.getCenter(find.byIcon(Icons.settings_rounded));
    FloatingBar.hidden.value = true;
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byIcon(Icons.settings_rounded)).dy,
        greaterThan(800));
    await tester.tapAt(shown);
    expect(tapped, -1);
  });

  test('bar style survives a settings round trip and defaults to the mainland', () {
    expect(const AppSettings().bottomBarStyle, 'mainland');
    // ленту убрали, яркий плюс переименован: у сохранивших их панель не откатывается в легаси
    expect(LiquidBarStyle.tryParse('strip'), LiquidBarStyle.mainland);
    expect(LiquidBarStyle.tryParse('brightPlus'), LiquidBarStyle.mainland);
    expect(LiquidBarStyle.tryParse('legacy'), isNull);
    final saved = const AppSettings().copyWith(bottomBarStyle: 'islands').toJsonString();
    expect(AppSettings.fromJsonString(saved).bottomBarStyle, 'islands');
    expect(LiquidBarStyle.fromId('нечто'), LiquidBarStyle.mainland);
  });

  group('палец можно задержать на ленте и вести по кнопкам', () {
    Future<List<int>> pump(WidgetTester tester) async {
      final tapped = <int>[];
      tester.view.physicalSize = const Size(411, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            bottomNavigationBar: LiquidBottomNav(
              index: 0,
              style: LiquidBarStyle.mainland,
              showConnectedBadge: false,
              onTap: tapped.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tapped;
    }

    Offset tab(WidgetTester tester, String label) =>
        tester.getCenter(find.bySemanticsLabel(RegExp('^$label')));

    testWidgets('выбирается вкладка, на которой палец отпустили', (tester) async {
      final tapped = await pump(tester);
      final settings = tab(tester, 'Settings');
      final gesture = await tester.startGesture(tab(tester, 'Servers'));
      await tester.pump(const Duration(milliseconds: 400));
      for (var i = 1; i <= 10; i++) {
        await gesture.moveTo(Offset.lerp(tab(tester, 'Servers'), settings, i / 10)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tapped, isEmpty, reason: 'пока палец на ленте, вкладка не переключается');
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tapped, [2]);
    });

    testWidgets('короткое касание переключает, как раньше', (tester) async {
      final tapped = await pump(tester);
      await tester.tap(find.bySemanticsLabel('Settings'));
      await tester.pumpAndSettle();
      expect(tapped, [2]);
    });

    testWidgets('под пальцем вкладка растёт плавно, без скачка на границе', (tester) async {
      await pump(tester);
      double scale(String label) => tester
          .widget<Transform>(find.descendant(
            of: find.bySemanticsLabel(RegExp('^$label')),
            matching: find.byType(Transform),
          ).first)
          .transform
          .storage[0];
      final from = tab(tester, 'Servers');
      final to = tab(tester, 'Settings');
      final gesture = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 400));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      var last = scale('Servers');
      var lastSettings = scale('Settings');
      for (var i = 1; i <= 60; i++) {
        await gesture.moveTo(Offset.lerp(from, to, i / 60)!);
        await tester.pump(const Duration(milliseconds: 16));
        final now = scale('Servers');
        final nowSettings = scale('Settings');
        expect((now - last).abs(), lessThan(0.05), reason: 'шаг $i');
        expect((nowSettings - lastSettings).abs(), lessThan(0.05), reason: 'шаг $i');
        last = now;
        lastSettings = nowSettings;
      }
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('под пальцем кнопка не заливается своей фигурой', (tester) async {
      await pump(tester);
      final gesture = await tester.startGesture(tab(tester, 'Settings'));
      await tester.pump(const Duration(milliseconds: 400));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final fill = tester
          .widget<Material>(find.descendant(
            of: find.bySemanticsLabel(RegExp('^Settings')),
            matching: find.byType(Material),
          ).first)
          .color;
      expect(fill?.a ?? 0, 0);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('от короткого касания кнопки не прыгают', (tester) async {
      await pump(tester);
      final rest = tab(tester, 'Settings').dy;
      await tester.tap(find.bySemanticsLabel(RegExp('^Servers')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 60));
        expect(tab(tester, 'Settings').dy, rest, reason: 'кадр ${i * 60} мс');
      }
    });

    testWidgets('отпустили на открытой вкладке: ничего не переключается', (tester) async {
      final tapped = await pump(tester);
      final gesture = await tester.startGesture(tab(tester, 'Servers'));
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tapped, isEmpty);
    });
  });

  testWidgets('мелкая прокрутка туда-обратно ленту не прячет, заметная прячет', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: FloatingBarHideOnScroll(
          child: ListView(
            controller: controller,
            children: [for (var i = 0; i < 100; i++) SizedBox(height: 60, child: Text('row $i'))],
          ),
        ),
      ),
    );
    controller.jumpTo(300);
    await tester.pump();
    FloatingBar.hidden.value = false;
    final list = find.byType(ListView);
    // медленно, как при осторожном листании: без докатывания по инерции
    for (var i = 0; i < 6; i++) {
      await tester.timedDrag(list, const Offset(0, -12), const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tester.timedDrag(list, const Offset(0, 10), const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
    }
    expect(FloatingBar.hidden.value, isFalse);
    await tester.drag(list, const Offset(0, -80));
    await tester.pump();
    expect(FloatingBar.hidden.value, isTrue);
    await tester.drag(list, const Offset(0, 20));
    await tester.pump();
    expect(FloatingBar.hidden.value, isTrue, reason: 'на 20 dp назад ещё рано');
    await tester.drag(list, const Offset(0, 60));
    await tester.pump();
    expect(FloatingBar.hidden.value, isFalse);
  });

  testWidgets('переключение вкладки пружинит: ширина перелетает за конечную', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    Widget nav(int index) => MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            bottomNavigationBar: LiquidBottomNav(
              index: index,
              style: LiquidBarStyle.mainland,
              showConnectedBadge: false,
              onTap: (_) {},
            ),
          ),
        );
    await tester.pumpWidget(nav(0));
    await tester.pumpAndSettle();
    await tester.pumpWidget(nav(1));
    final widths = <double>[];
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      widths.add(tester.getSize(find.bySemanticsLabel(RegExp('^Subscriptions'))).width);
    }
    await tester.pumpAndSettle();
    final rest = tester.getSize(find.bySemanticsLabel(RegExp('^Subscriptions'))).width;
    expect(widths.reduce((a, b) => a > b ? a : b), greaterThan(rest + 3));
  });

  testWidgets('на отдаче пружины подпись вкладки не подрезается', (tester) async {
    tester.view.physicalSize = const Size(411, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    Widget nav(int index) => MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            bottomNavigationBar: LiquidBottomNav(
              index: index,
              style: LiquidBarStyle.mainland,
              showConnectedBadge: false,
              onTap: (_) {},
            ),
          ),
        );
    await tester.pumpWidget(nav(0));
    await tester.pumpAndSettle();
    await tester.pumpWidget(nav(1));
    final label = find.text('Subscriptions');
    var opened = false;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final shown =
          tester.getSize(find.ancestor(of: label, matching: find.byType(Align)).first).width;
      final full =
          tester.getSize(find.ancestor(of: label, matching: find.byType(Opacity)).first).width;
      if (opened) {
        expect(shown, greaterThanOrEqualTo(full - 0.5), reason: 'кадр ${i * 16} мс');
      } else if (shown >= full - 0.5) {
        opened = true;
      }
    }
    expect(opened, isTrue);
  });
}
