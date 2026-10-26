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
      style: LiquidBarStyle.strip,
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

  test('bar style survives a settings round trip and defaults to the modern strip', () {
    expect(const AppSettings().bottomBarStyle, 'strip');
    expect(LiquidBarStyle.tryParse('legacy'), isNull);
    final saved = const AppSettings().copyWith(bottomBarStyle: 'islands').toJsonString();
    expect(AppSettings.fromJsonString(saved).bottomBarStyle, 'islands');
    expect(LiquidBarStyle.fromId('нечто'), LiquidBarStyle.strip);
  });
}
