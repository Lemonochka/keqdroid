import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/shared/ui/shape_loading_indicator.dart';
import 'package:keqdroid/shared/ui/shape_morph.dart';

// кадры по 16 мс: фаза цикла идёт от часов планировщика
Future<void> _run(WidgetTester tester, Duration total) async {
  const frame = Duration(milliseconds: 16);
  for (var left = total; left > Duration.zero; left -= frame) {
    await tester.pump(frame);
  }
}

Object _morph(WidgetTester tester) => (tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(ShapeLoadingIndicator),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter! as MorphPainter)
    .morph;

void main() {
  final ticking = ValueNotifier(true);

  setUp(() => ticking.value = true);

  Future<void> host(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: ticking,
            builder: (_, on, child) => TickerMode(enabled: on, child: child!),
            child: const Center(child: ShapeLoadingIndicator()),
          ),
        ),
      );

  testWidgets('на виду фигуры меняются', (tester) async {
    await host(tester);
    final before = _morph(tester);

    await _run(tester, const Duration(seconds: 2));

    expect(_morph(tester), isNot(same(before)));
  });

  testWidgets('на чужой вкладке индикатор спит, а вернувшись идёт дальше', (
    tester,
  ) async {
    await host(tester);
    ticking.value = false;
    await tester.pump();
    final asleep = _morph(tester);

    await _run(tester, const Duration(seconds: 5));
    expect(_morph(tester), same(asleep));

    ticking.value = true;
    await _run(tester, const Duration(seconds: 2));
    expect(_morph(tester), isNot(same(asleep)));
  });

  testWidgets('в свёрнутом приложении индикатор спит', (tester) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await host(tester);
    for (final s in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump();
    final asleep = _morph(tester);

    await _run(tester, const Duration(seconds: 5));
    expect(_morph(tester), same(asleep));

    for (final s in const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await _run(tester, const Duration(seconds: 2));
    expect(_morph(tester), isNot(same(asleep)));
  });
}
