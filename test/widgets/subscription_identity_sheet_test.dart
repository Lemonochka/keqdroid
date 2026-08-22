import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/subscriptions_tab.dart';

import '../helpers/test_storage.dart';

class _FakeSubs extends SubscriptionsNotifier {
  _FakeSubs(this._subs);

  final List<Subscription> _subs;

  @override
  Future<List<Subscription>> build() async => _subs;
}

class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this._settings);

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

Future<void> _pumpTab(
  WidgetTester tester, {
  AppSettings settings = const AppSettings(),
  List<Subscription> subscriptions = const [],
}) async {
  final storage = await buildStorageService();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
        subscriptionsProvider.overrideWith(() => _FakeSubs(subscriptions)),
        settingsNotifierProvider.overrideWith(() => _FakeSettings(settings)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SubscriptionsTab(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Доводит до открытой шторки идентичности из формы добавления подписки.
Future<void> _openIdentitySheet(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.add_rounded));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Device identity'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('идентичность настраивается прямо в форме добавления', (
    tester,
  ) async {
    // Экран рослый: пять строк выбора плюс кнопки. На 600 px шторка ушла бы в
    // overflow, а тест ловил бы не то, что проверяет.
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpTab(tester);
    await _openIdentitySheet(tester);

    // Выключенная подмена не показывает полей вовсе.
    expect(find.text('User-Agent'), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('User-Agent'), findsOneWidget);
    expect(find.text('HWID'), findsOneWidget);

    await tester.tap(find.text('User-Agent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Happ/3.20.4').last);
    await tester.pumpAndSettle();

    // Выбранное значение видно в строке ещё до применения.
    expect(find.textContaining('Happ/3.20.4'), findsOneWidget);

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    // Форма добавления снова на экране, и подмена в ней уже сведена в строку.
    expect(find.text('Add Subscription'), findsOneWidget);
    expect(find.textContaining('Happ/3.20.4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('выключённый обмен HWID сопровождается предупреждением', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpTab(tester, settings: const AppSettings(shareDeviceHwid: false));
    await _openIdentitySheet(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sharing the device HWID'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('на невысоком экране шторка и список прокручиваются, а не рвутся',
      (tester) async {
    // 360×640 — нижняя граница живых телефонов. Пять строк выбора плюс кнопки
    // туда не влезают по построению: список обязан прокручиваться, а не
    // уходить в overflow, который в релизе виден только пропавшим виджетом.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpTab(tester);
    await _openIdentitySheet(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Список вариантов длиннее экрана — проверяем и его.
    await tester.tap(find.text('User-Agent'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('UA, которого нет в каталоге, вписывается руками', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpTab(tester);
    await _openIdentitySheet(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    await tester.tap(find.text('User-Agent'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(SearchBar), 'MyClient/9.9');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this value'));
    await tester.pumpAndSettle();

    // Регистр UA значим — приводить его к нижнему, как HWID, нельзя.
    expect(find.textContaining('MyClient/9.9'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('набранный HWID показывается тем же, каким уйдёт в запрос', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpTab(tester);
    await _openIdentitySheet(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    await tester.tap(find.text('HWID'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(SearchBar), 'CAFEBABE1234');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this value'));
    await tester.pumpAndSettle();

    // Сервис всё равно шлёт HWID в нижнем регистре: показывать одно, а слать
    // другое было бы враньём.
    expect(find.textContaining('cafebabe1234'), findsOneWidget);
    expect(find.textContaining('CAFEBABE1234'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('на высоком окне шторка не дорастает до верха экрана', (
    tester,
  ) async {
    // Regression: список UA длиннее любого экрана, и без потолка шторка
    // занимала окно целиком — ручка уезжала под рамку (на ноутбуке под
    // вебкамеру), фона для закрытия тапом не оставалось совсем.
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpTab(tester);
    await _openIdentitySheet(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('User-Agent'));
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byType(BottomSheet).last).top, greaterThan(400));
    // И по ширине это колонка, а не строка во весь монитор. Меряем по
    // содержимому: `constraints` Flutter применяет ВНУТРИ BottomSheet, и сам
    // он остаётся во всю ширину окна.
    expect(tester.getRect(find.byType(SearchBar)).width, lessThan(600));

    // Крестик закрывает список, не трогая шторку идентичности под ним.
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();
    expect(find.byType(SearchBar), findsNothing);
    expect(find.text('User-Agent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('сброс возвращает подписку к идентичности приложения', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpTab(tester);
    await _openIdentitySheet(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('User-Agent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Happ/3.20.4').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Happ/3.20.4'), findsNothing);
    expect(find.text('App default'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
