import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/settings_tab.dart';

import '../helpers/test_storage.dart';

/// `pumpAndSettle` на этом экране не годится: в настройках живёт бесконечная
/// анимация, и ожидание «пока всё успокоится» не кончается никогда. Гоняем
/// фиксированное число кадров — их хватает и на переход экрана, и на шторку.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this._settings);

  final AppSettings _settings;

  /// Последнее, что шторка отдала по «Применить». Диск в тесте не нужен —
  /// проверяется, что уехало из шторки, а не что записалось.
  AppSettings? saved;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> save(AppSettings settings) async {
    saved = settings;
    state = AsyncData(settings);
  }
}

/// Доводит до открытой шторки своего цвета: настройки → «Внешний вид» →
/// вкладка «Темы» → последняя плитка сетки.
Future<_FakeSettings> _openSheet(
  WidgetTester tester, {
  AppSettings settings = const AppSettings(),
}) async {
  final storage = await buildStorageService();
  final notifier = _FakeSettings(settings);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
        settingsNotifierProvider.overrideWith(() => notifier),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Тема приложения, а не голый MaterialApp: в ней живут компонентные
        // темы M3E, в том числе обновлённая отрисовка ползунка
        // (`SliderThemeData(year2023: false)`). Без неё тест смотрел бы на
        // виджеты, которых в приложении нет.
        theme: buildAppTheme(
          buildPresetScheme(themePresetFor(settings), Brightness.light),
        ),
        home: const SettingsTab(),
      ),
    ),
  );
  await _frames(tester);

  await tester.tap(find.text('Appearance'));
  await _frames(tester);

  await tester.tap(find.text('Themes'));
  await _frames(tester);

  await tester.scrollUntilVisible(
    find.text('Custom color'),
    300,
    scrollable: find.byType(Scrollable).last,
  );
  await _frames(tester);
  await tester.tap(find.text('Custom color'));
  await _frames(tester);
  return notifier;
}

/// Телефонный экран вместо дефолтных 800×600: шторка ограничена 85% высоты и
/// на низком окне обязана прокручиваться, а не рваться.
void _phoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('шторка открывается и раскладывается без переполнений', (
    tester,
  ) async {
    // Экран телефона, а не дефолтные 800×600 теста: шторка ограничена 85%
    // высоты и на низком окне обязана прокручиваться, а не рваться.
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openSheet(tester);

    expect(find.text('Palette'), findsOneWidget);
    expect(find.text('Calm'), findsOneWidget);
    expect(find.text('Vibrant'), findsOneWidget);
    expect(find.text('Exact'), findsOneWidget);
    expect(find.text('Hue'), findsOneWidget);
    expect(find.text('Saturation'), findsOneWidget);
    expect(find.text('Brightness'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(3));
  });

  testWidgets('hex и ползунки показывают один и тот же цвет', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openSheet(
      tester,
      settings: const AppSettings(
        themePresetId: kCustomThemePresetId,
        customThemeSeed: '2EC4B6',
      ),
    );

    // Поле открывается сохранённым цветом, а не дефолтным.
    expect(find.widgetWithText(TextField, '2EC4B6'), findsOneWidget);

    // Набранный код доезжает до ползунков: у бирюзы оттенок около 174°, и
    // после ввода фиолетового он обязан переехать.
    await tester.enterText(find.byType(TextField), '7B2CBF');
    await _frames(tester);

    final hue = tester.widgetList<Slider>(find.byType(Slider)).first;
    expect(hue.value, closeTo(HSVColor.fromColor(const Color(0xFF7B2CBF)).hue, 0.5));
  });

  testWidgets('ползунками нельзя получить цвет без оттенка', (tester) async {
    // «Выкрутил всё в ноль — стало розово»: у чёрного оттенка нет, конвертер
    // отдаёт 0°, а ноль градусов в HCT это красно-розовый угол. Замер показал,
    // что ниже насыщенности 0.10 и яркости 0.15 оттенки схлопываются в один,
    // поэтому шкалы там и заканчиваются.
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openSheet(
      tester,
      settings: const AppSettings(
        themePresetId: kCustomThemePresetId,
        customThemeSeed: '2EC4B6',
      ),
    );

    // Насыщенность и яркость — в самый левый край, докуда пустит шкала.
    for (final i in [1, 2]) {
      await tester.drag(find.byType(Slider).at(i), const Offset(-600, 0));
      await _frames(tester);
    }

    final text = tester.widget<TextField>(find.byType(TextField)).controller!.text;
    final picked = HSVColor.fromColor(parseThemeSeed(text)!);
    expect(picked.saturation, greaterThanOrEqualTo(0.09));
    expect(picked.value, greaterThanOrEqualTo(0.14));
    // Оттенок пережил выкручивание: бирюза осталась бирюзой, а не уехала в
    // розовое ничто.
    expect(picked.hue, closeTo(174, 6));
  });

  testWidgets('выбранный вариант палитры уезжает в настройки', (tester) async {
    _phoneScreen(tester);

    final notifier = await _openSheet(tester);

    await tester.tap(find.text('Exact'));
    await _frames(tester);
    await tester.tap(find.text('Apply'));
    await _frames(tester);

    final saved = notifier.saved!;
    expect(saved.customThemeVariant, 'fidelity');
    expect(saved.themePresetId, kCustomThemePresetId);
    // Вариант — часть выбора своей темы, поэтому системные цвета он выключает
    // так же, как выбор цвета: иначе палитра осталась бы системной.
    expect(saved.followSystemTheme, isFalse);
  });

  testWidgets('шторка открывается на сохранённом варианте', (tester) async {
    // Иначе человек, вернувшийся поправить оттенок, молча съезжал бы обратно
    // на спокойную палитру — не тронув переключатель вовсе.
    _phoneScreen(tester);

    final notifier = await _openSheet(
      tester,
      settings: const AppSettings(
        themePresetId: kCustomThemePresetId,
        customThemeSeed: '2EC4B6',
        customThemeVariant: 'vibrant',
      ),
    );

    await tester.tap(find.text('Apply'));
    await _frames(tester);

    expect(notifier.saved!.customThemeVariant, 'vibrant');
  });

  testWidgets('вариант виден на образце сразу, до «Применить»', (tester) async {
    // Образец — единственное, по чему выбирают: если он не меняется на тап,
    // группа выглядит такой же мёртвой, какими были ползунки.
    _phoneScreen(tester);

    final notifier = await _openSheet(
      tester,
      settings: const AppSettings(
        themePresetId: kCustomThemePresetId,
        customThemeSeed: '2EC4B6',
      ),
    );

    // Все заливки образца, а не одна роль: варианты расходятся на разных
    // ролях в зависимости от цвета и яркости — у бирюзы в светлой схеме
    // `primary` совпадает у всех трёх, а расходятся контейнеры.
    //
    // Миниатюра ищется по имени приватного класса: она живёт в
    // `settings_tab.dart` и снаружи не видна, а такие же миниатюры стоят в
    // сетке пресетов под шторкой — по типу их не различить.
    final mock = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_ThemeScreenMock',
      ),
    );

    List<Color?> mockColors() => tester
        .widgetList<DecoratedBox>(
          find.descendant(of: mock, matching: find.byType(DecoratedBox)),
        )
        .map((box) {
          final decoration = box.decoration;
          return decoration is ShapeDecoration
              ? decoration.color
              : (decoration as BoxDecoration).color;
        })
        .toList();

    final calm = mockColors();
    expect(calm, isNotEmpty);
    await tester.tap(find.text('Exact'));
    await _frames(tester);
    expect(mockColors(), isNot(calm));

    // И при этом в настройки ничего не уехало: правки живут в шторке до
    // «Применить», иначе каждый тап пересобирал бы всё дерево виджетов.
    expect(notifier.saved, isNull);
  });
}
