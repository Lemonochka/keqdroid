import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/shared/ui/liquid_toast.dart';

Future<BuildContext> _pump(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => LiquidToastHost(child: child!),
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
}
