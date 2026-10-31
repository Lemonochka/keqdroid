import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/shared/ui/liquid_toast.dart';

Future<BuildContext> _pump(
  WidgetTester tester, {
  TextDirection direction = TextDirection.ltr,
}) async {
  late BuildContext captured;
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => Directionality(
      textDirection: direction,
      child: LiquidToastHost(child: child!),
    ),
    home: Scaffold(
      body: Builder(builder: (context) {
        captured = context;
        return const SizedBox.expand();
      }),
    ),
  ));
  return captured;
}

void main() {
  tearDown(() {
    LiquidToast.enabled = false;
    LiquidToast.current.value = null;
  });

  testWidgets('outside Modern the usual snack bar shows', (tester) async {
    final context = await _pump(tester);
    AppSnack.of(context).showSnackBar(const SnackBar(content: Text('готово')));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(LiquidToast.current.value, isNull);
  });

  testWidgets('in Modern the drop shows instead and leaves by itself', (tester) async {
    LiquidToast.enabled = true;
    final context = await _pump(tester);
    AppSnack.of(context).showSnackBar(const SnackBar(
      content: Text('готово'),
      duration: Duration(seconds: 2),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('готово'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(LiquidToast.current.value, isNull);
    expect(find.text('готово'), findsNothing);
  });

  testWidgets('a coloured snack bar keeps its colour and gets readable text', (tester) async {
    LiquidToast.enabled = true;
    final context = await _pump(tester);
    AppSnack.of(context).showSnackBar(const SnackBar(
      content: Text('ошибка'),
      backgroundColor: Color(0xFF8C1D18),
    ));
    final toast = LiquidToast.current.value!;
    expect(toast.color, const Color(0xFF8C1D18));
    expect(toast.ink, Colors.white);
  });

  testWidgets('the action button runs and closes the drop', (tester) async {
    LiquidToast.enabled = true;
    final context = await _pump(tester);
    var undone = 0;
    AppSnack.of(context).showSnackBar(SnackBar(
      content: const Text('удалено'),
      action: SnackBarAction(label: 'Вернуть', onPressed: () => undone++),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Вернуть'));
    await tester.pumpAndSettle();
    expect(undone, 1);
    expect(LiquidToast.current.value, isNull);
  });

  group('swipe', () {
    Future<Finder> showDrop(WidgetTester tester,
        {TextDirection direction = TextDirection.ltr}) async {
      LiquidToast.enabled = true;
      final context = await _pump(tester, direction: direction);
      AppSnack.of(context).showSnackBar(const SnackBar(content: Text('готово')));
      await tester.pumpAndSettle();
      return find.text('готово');
    }

    Future<void> expectGone(WidgetTester tester) async {
      await tester.pumpAndSettle();
      expect(LiquidToast.current.value, isNull);
      expect(find.text('готово'), findsNothing);
    }

    testWidgets('pulled toward the edge it came from, it leaves', (tester) async {
      final drop = await showDrop(tester);
      await tester.drag(drop, const Offset(-300, 0));
      await expectGone(tester);
    });

    testWidgets('a quick flick toward the edge is enough', (tester) async {
      final drop = await showDrop(tester);
      await tester.fling(drop, const Offset(-60, 0), 1000);
      await expectGone(tester);
    });

    testWidgets('down or away from the edge it stays, and still leaves on time',
        (tester) async {
      final drop = await showDrop(tester);
      final rest = tester.getTopLeft(drop);
      await tester.fling(drop, const Offset(0, 300), 1000);
      await tester.pumpAndSettle();
      await tester.fling(drop, const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
      expect(LiquidToast.current.value, isNotNull);
      expect(tester.getTopLeft(drop), rest);
      await tester.pump(const Duration(seconds: 4));
      await expectGone(tester);
    });

    testWidgets('a short slow pull springs back and the timer starts over',
        (tester) async {
      final drop = await showDrop(tester);
      final rest = tester.getTopLeft(drop);
      await tester.pump(const Duration(seconds: 3));
      await tester.timedDrag(
          drop, const Offset(-60, 0), const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(drop).dx, closeTo(rest.dx, 0.5));
      await tester.pump(const Duration(seconds: 2));
      expect(LiquidToast.current.value, isNotNull);
      await tester.pump(const Duration(seconds: 2));
      await expectGone(tester);
    });

    testWidgets('in right-to-left text it goes to the right edge', (tester) async {
      final drop = await showDrop(tester, direction: TextDirection.rtl);
      await tester.drag(drop, const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(LiquidToast.current.value, isNotNull);
      await tester.drag(drop, const Offset(300, 0));
      await expectGone(tester);
    });
  });
}
