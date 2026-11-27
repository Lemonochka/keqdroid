import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/ui/desktop/desktop_tab_switcher.dart';

// Вкладки ПК едут вдоль панели и при этом живут, как в IndexedStack: видна
// одна, скрытые не рисуются, не ловят нажатия и фокус и не крутят тикеры
// (гифки подписок на чужой вкладке).
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

class _Count extends Notifier<int> {
  @override
  int build() => 0;

  void set(int value) => state = value;
}

final _count = NotifierProvider<_Count, int>(_Count.new);

class _PaintLog extends CustomPainter {
  _PaintLog(this.i, this.log);
  final int i;
  final List<int> log;

  @override
  void paint(Canvas canvas, Size size) => log.add(i);

  @override
  bool shouldRepaint(_PaintLog old) => false;
}

Future<void> _show(WidgetTester tester, int index, {bool still = false}) async {
  await tester.pumpWidget(
    MaterialApp(
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
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

double _y(WidgetTester tester, String text) =>
    tester.getCenter(find.text(text, skipOffstage: false)).dy;

double _opacity(WidgetTester tester, String text) => tester
    .widget<Opacity>(
      find
          .ancestor(
            of: find.text(text, skipOffstage: false),
            matching: find.byType(Opacity),
          )
          .first,
    )
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

  testWidgets(
    'вниз по панели новая поднимается снизу, вверх опускается сверху',
    (tester) async {
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
    },
  );

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

  group('прогрев скрытых вкладок', () {
    late List<int> painted;

    setUp(() => painted = []);

    Future<void> pump(
      WidgetTester tester,
      int index, {
      bool hidden = false,
      Widget Function(int i)? extra,
    }) => tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: DesktopTabSwitcher(
              index: index,
              warmUpAfter: const Duration(seconds: 3),
              windowHidden: () => hidden,
              children: [
                for (var i = 0; i < 3; i++)
                  Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(painter: _PaintLog(i, painted)),
                      _Probe(i),
                      ?extra?.call(i),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    List<Key?> order(WidgetTester tester) => tester
        .widgetList<KeyedSubtree>(
          find.descendant(
            of: find.byType(DesktopTabSwitcher),
            matching: find.byType(KeyedSubtree),
          ),
        )
        .map((k) => k.key)
        .toList();

    ({double opacity, double dy}) pose(WidgetTester tester, int i) {
      final text = find.textContaining('tab $i:', skipOffstage: false);
      return (
        opacity: tester
            .widget<Opacity>(
              find
                  .ancestor(
                    of: text,
                    matching: find.byType(Opacity, skipOffstage: false),
                  )
                  .first,
            )
            .opacity,
        dy: tester
            .widget<Transform>(
              find
                  .ancestor(
                    of: text,
                    matching: find.byType(Transform, skipOffstage: false),
                  )
                  .first,
            )
            .transform
            .getTranslation()
            .y,
      );
    }

    testWidgets(
      'скрытые вкладки один раз рисуются под видимой, не тикают и не ловят нажатий',
      (tester) async {
        await pump(tester, 0);
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(painted.where((i) => i != 0), isEmpty, reason: 'рано');

        painted.clear();
        for (var i = 0; i < 20; i++) {
          final before = painted.length;
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text('tab 1: 0').hitTestable(), findsNothing);
          expect(find.text('tab 2: 0').hitTestable(), findsNothing);
          expect(_Probe.ticking[1], isFalse);
          expect(_Probe.ticking[2], isFalse);
          if (painted.skip(before).any((t) => t != 0)) {
            // слои в стопке идут снизу вверх: видимая последней, то есть поверх скрытых
            expect(order(tester).last, const ValueKey(0));
            expect(pose(tester, 0), (opacity: 1.0, dy: 0.0));
          }
        }
        expect(painted, contains(1));
        expect(painted, contains(2));

        painted.clear();
        tester.element(find.byType(DesktopTabSwitcher)).markNeedsBuild();
        await tester.pump(const Duration(seconds: 5));
        expect(
          painted.where((i) => i != 0),
          isEmpty,
          reason: 'прогрев повторился',
        );
      },
    );

    testWidgets(
      'скрытая вкладка рисуется со свежими данными, хотя её подписки на паузе',
      (tester) async {
        await pump(
          tester,
          0,
          extra: (i) => i == 1
              ? Consumer(
                  builder: (context, ref, _) {
                    return Text('count ${ref.watch(_count)}');
                  },
                )
              : const SizedBox(),
        );
        await tester.pump();
        ProviderScope.containerOf(
          tester.element(find.byType(DesktopTabSwitcher)),
        ).read(_count.notifier).set(5);
        await tester.pump();
        // пауза Riverpod под выключенным TickerMode: вкладка застряла на старом значении
        expect(find.text('count 0', skipOffstage: false), findsOneWidget);

        await tester.pump(const Duration(seconds: 3));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(find.text('count 5', skipOffstage: false), findsOneWidget);
        // после прогрева снова на паузе
        ProviderScope.containerOf(
          tester.element(find.byType(DesktopTabSwitcher)),
        ).read(_count.notifier).set(7);
        await tester.pump();
        expect(find.text('count 5', skipOffstage: false), findsOneWidget);
      },
    );

    for (final hidden in [false, true]) {
      testWidgets(
        hidden
            ? 'в трее прогон идёт и через позы перехода'
            : 'при видимом окне текущая вкладка во время прогрева стоит на месте',
        (tester) async {
          await pump(tester, 0, hidden: hidden);
          await tester.pump(const Duration(seconds: 3));
          final poses = <int, Set<({double opacity, double dy})>>{
            0: {},
            1: {},
            2: {},
          };
          for (var f = 0; f < 20; f++) {
            await tester.pump(const Duration(milliseconds: 16));
            for (var i = 0; i < 3; i++) {
              poses[i]!.add(pose(tester, i));
            }
          }
          if (hidden) {
            expect(
              poses[0]!.any((p) => p.dy != 0),
              isTrue,
              reason: '${poses[0]}',
            );
            expect(
              poses[1]!.any((p) => p.opacity < 1 && p.dy != 0),
              isTrue,
              reason: '${poses[1]}',
            );
            expect(
              poses[2]!.any((p) => p.opacity < 1 && p.dy != 0),
              isTrue,
              reason: '${poses[2]}',
            );
          } else {
            expect(poses[0], {(opacity: 1.0, dy: 0.0)});
          }
          expect(pose(tester, 0), (opacity: 1.0, dy: 0.0));
          expect(find.text('tab 0: 0').hitTestable(), findsOneWidget);
        },
      );
    }

    testWidgets(
      'нажатие посреди прогрева: обычный переход, прогрев бросается',
      (tester) async {
        await pump(tester, 0, hidden: true);
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(milliseconds: 16));
        await pump(tester, 2, hidden: true);
        await _settle(tester);
        expect(find.text('tab 2: 0').hitTestable(), findsOneWidget);
        expect(_Probe.ticking, {0: false, 1: false, 2: true});
        painted.clear();
        await _settle(tester);
        expect(painted.where((i) => i != 2), isEmpty);
      },
    );

    testWidgets('пока двигают мышь, прогрев ждёт покоя', (tester) async {
      await pump(tester, 0);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: const Offset(20, 20));
      for (var t = 0; t < 3600; t += 200) {
        await mouse.moveTo(Offset(20 + t / 100, 20));
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(painted.where((i) => i != 0), isEmpty);

      for (var t = 0; t < 2800; t += 100) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(painted, containsAll([1, 2]));
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
