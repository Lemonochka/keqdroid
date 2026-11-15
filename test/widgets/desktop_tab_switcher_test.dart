import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/ui/desktop/desktop_tab_switcher.dart';

/// Вкладки ПК едут вдоль панели и при этом живут, как в IndexedStack: видна
/// одна, скрытые не рисуются, не ловят нажатия и фокус и не крутят тикеры
/// (гифки подписок на чужой вкладке).
class _Probe extends StatefulWidget {
  const _Probe(this.i);
  final int i;

  static final ticking = <int, bool>{};
  static final nodes = <int, FocusNode>{};

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int taps = 0;
  late final node = _Probe.nodes[widget.i] = FocusNode();

  @override
  void dispose() {
    node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _Probe.ticking[widget.i] = TickerMode.valuesOf(context).enabled;
    return Focus(
      focusNode: node,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => taps++),
        child: Center(child: Text('tab ${widget.i}: $taps')),
      ),
    );
  }
}

class _PaintLog extends CustomPainter {
  _PaintLog(this.i, this.log);
  final int i;
  final List<int> log;

  @override
  void paint(Canvas canvas, Size size) => log.add(i);

  @override
  bool shouldRepaint(_PaintLog old) => false;
}

Future<void> _show(
  WidgetTester tester,
  int index, {
  bool still = false,
}) async {
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: still),
      child: child!,
    ),
    home: Scaffold(
      body: DesktopTabSwitcher(
        index: index,
        children: const [_Probe(0), _Probe(1), _Probe(2)],
      ),
    ),
  ));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

double _y(WidgetTester tester, String text) =>
    tester.getCenter(find.text(text, skipOffstage: false)).dy;

double _opacity(WidgetTester tester, String text) => tester
    .widget<Opacity>(find
        .ancestor(
          of: find.text(text, skipOffstage: false),
          matching: find.byType(Opacity),
        )
        .first)
    .opacity;

// вкладки непрозрачные, фон просвечивает сквозь стопку на (1 - a1)(1 - a2)...
double _cover(WidgetTester tester) {
  var through = 1.0;
  for (var i = 0; i < 3; i++) {
    final text = find.textContaining('tab $i:');
    if (text.evaluate().isEmpty) continue;
    through *= 1 - _opacity(tester, tester.widget<Text>(text).data!);
  }
  return 1 - through;
}

double _middle(WidgetTester tester) =>
    tester.view.physicalSize.height / tester.view.devicePixelRatio / 2;

void main() {
  setUp(() {
    _Probe.ticking.clear();
    _Probe.nodes.clear();
  });

  testWidgets('видна одна вкладка, остальные живут, но не рисуются', (
    tester,
  ) async {
    await _show(tester, 0);
    await tester.tap(find.text('tab 0: 0'));
    await tester.pump();
    expect(find.text('tab 0: 1'), findsOneWidget);

    await _show(tester, 2);
    await _settle(tester);
    expect(find.text('tab 2: 0').hitTestable(), findsOneWidget);
    expect(find.text('tab 0: 1').hitTestable(), findsNothing);
    expect(find.text('tab 1: 0').hitTestable(), findsNothing);
    // состояние ушедшей вкладки не сброшено
    expect(find.text('tab 0: 1', skipOffstage: false), findsOneWidget);

    await _show(tester, 0);
    await _settle(tester);
    expect(find.text('tab 0: 1').hitTestable(), findsOneWidget);
  });

  testWidgets('тикеры и фокус только у видимой вкладки', (tester) async {
    await _show(tester, 0);
    await _show(tester, 1);
    await _settle(tester);
    expect(_Probe.ticking, {0: false, 1: true, 2: false});
    expect(_Probe.nodes[0]!.canRequestFocus, isFalse);
    expect(_Probe.nodes[1]!.canRequestFocus, isTrue);
    expect(_Probe.nodes[2]!.canRequestFocus, isFalse);
  });

  testWidgets('нажатие попадает в видимую вкладку', (tester) async {
    await _show(tester, 0);
    await _show(tester, 1);
    await _settle(tester);
    await tester.tapAt(tester.getCenter(find.byType(Scaffold)));
    await tester.pump();
    expect(find.text('tab 1: 1'), findsOneWidget);
    expect(find.text('tab 0: 0', skipOffstage: false), findsOneWidget);
    expect(find.text('tab 2: 0', skipOffstage: false), findsOneWidget);
  });

  testWidgets('вниз по панели новая поднимается снизу, вверх опускается сверху', (
    tester,
  ) async {
    final middle = _middle(tester);
    await _show(tester, 0);
    await _show(tester, 2);
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('tab 0: 0'), findsOneWidget);
    expect(find.text('tab 1: 0'), findsNothing);
    expect(_y(tester, 'tab 2: 0'), greaterThan(middle));
    expect(_y(tester, 'tab 0: 0'), lessThan(middle));
    // уходящая не ловит нажатие и там, где новая ещё не доехала
    await tester.tapAt(const Offset(400, 10));
    await tester.tapAt(Offset(400, middle));
    await tester.pump();
    expect(find.text('tab 2: 1', skipOffstage: false), findsOneWidget);
    expect(find.text('tab 0: 0', skipOffstage: false), findsOneWidget);

    await _settle(tester);
    expect(find.text('tab 0: 0'), findsNothing);
    expect(_y(tester, 'tab 2: 1'), closeTo(middle, 0.5));

    await _show(tester, 0);
    await tester.pump(const Duration(milliseconds: 40));
    expect(_y(tester, 'tab 0: 0'), lessThan(middle));
    expect(_y(tester, 'tab 2: 1'), greaterThan(middle));
  });

  testWidgets('перебитый на ходу переход не дёргает то, что было видно', (
    tester,
  ) async {
    await _show(tester, 0);
    await _show(tester, 1);
    await tester.pump(const Duration(milliseconds: 60));
    final opacity = _opacity(tester, 'tab 1: 0');
    final y = _y(tester, 'tab 1: 0');
    expect(opacity, inExclusiveRange(0, 1));
    expect(_opacity(tester, 'tab 0: 0'), 1);

    await _show(tester, 2);
    expect(_opacity(tester, 'tab 1: 0'), opacity);
    expect(_y(tester, 'tab 1: 0'), y);
    expect(_opacity(tester, 'tab 0: 0'), 1);

    await _settle(tester);
    expect(find.text('tab 2: 0').hitTestable(), findsOneWidget);
    expect(find.text('tab 0: 0'), findsNothing);
    expect(find.text('tab 1: 0'), findsNothing);
  });

  // через ноль, как в спеке M3, экран 75 мс был темнее половины, в худшем кадре 9%, и это било по глазам
  testWidgets('экран не проваливается в фон ни на одном кадре', (tester) async {
    Future<void> watch(int ms) async {
      for (var t = 0; t < ms; t += 4) {
        await tester.pump(const Duration(milliseconds: 4));
        expect(_cover(tester), greaterThan(0.99), reason: '$t мс');
      }
    }

    await _show(tester, 0);
    await _show(tester, 2);
    await watch(600);
    await _show(tester, 1);
    await watch(36);
    await _show(tester, 0);
    await watch(600);
  });

  group('подготовка новой вкладки', () {
    late List<int> painted;
    late List<int> prepared;

    setUp(() {
      painted = [];
      prepared = [];
    });

    Future<void> pump(WidgetTester tester, int index, {int? preparing}) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: DesktopTabSwitcher(
              index: index,
              preparing: preparing,
              onPrepared: prepared.add,
              children: [
                for (var i = 0; i < 3; i++)
                  Stack(fit: StackFit.expand, children: [
                    CustomPaint(painter: _PaintLog(i, painted)),
                    _Probe(i),
                  ]),
              ],
            ),
          ),
        ));

    List<Key?> order(WidgetTester tester) => tester
        .widgetList<KeyedSubtree>(find.descendant(
          of: find.byType(DesktopTabSwitcher),
          matching: find.byType(KeyedSubtree),
        ))
        .map((k) => k.key)
        .toList();

    testWidgets('рисуется под текущей с тикерами, и только через два кадра её открывают', (
      tester,
    ) async {
      await pump(tester, 0);
      painted.clear();

      await pump(tester, 0, preparing: 1);
      expect(painted, contains(1));
      expect(painted, isNot(contains(2)));
      // данные провайдеров приходят только с тикерами: без них Riverpod держит подписки на паузе
      expect(_Probe.ticking, {0: true, 1: true, 2: false});
      // слои в стопке идут снизу вверх: видимая последней, то есть поверх готовящейся
      expect(order(tester).last, const ValueKey(0));
      expect(find.text('tab 1: 0').hitTestable(), findsNothing);
      expect(_Probe.nodes[1]!.canRequestFocus, isFalse);
      expect(prepared, isEmpty, reason: 'переход не дождался тяжёлого кадра');

      await tester.pump();
      expect(prepared, [1]);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(prepared, [1], reason: 'готовность сообщают один раз');

      await pump(tester, 1);
      await _settle(tester);
      expect(find.text('tab 1: 0').hitTestable(), findsOneWidget);
      expect(_Probe.ticking, {0: false, 1: true, 2: false});
    });

    testWidgets('пока идёт переход, не готовят: её было бы видно снизу', (
      tester,
    ) async {
      await pump(tester, 0);
      await pump(tester, 2);
      await tester.pump(const Duration(milliseconds: 40));
      painted.clear();

      await pump(tester, 2, preparing: 1);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(painted, isNot(contains(1)));
      expect(_Probe.ticking[1], isFalse);
      expect(prepared, isEmpty);

      await _settle(tester);
      expect(painted, contains(1));
      expect(prepared, [1]);
    });

    testWidgets('передумали: подготовку сняли, вкладка снова не рисуется и не тикает', (
      tester,
    ) async {
      await pump(tester, 0);
      await pump(tester, 0, preparing: 1);
      await pump(tester, 0);
      painted.clear();

      await _settle(tester);
      expect(prepared, isEmpty);
      expect(painted.where((i) => i != 0), isEmpty);
      expect(_Probe.ticking[1], isFalse);
    });
  });

  testWidgets('с выключенными анимациями системы вкладка меняется сразу', (
    tester,
  ) async {
    await _show(tester, 0, still: true);
    await _show(tester, 2, still: true);
    expect(find.text('tab 0: 0'), findsNothing);
    expect(find.text('tab 2: 0').hitTestable(), findsOneWidget);
  });
}
