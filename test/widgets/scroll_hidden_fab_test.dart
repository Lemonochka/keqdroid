import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/shared/ui/scroll_hidden_fab.dart';

/// Кнопка «+» над списком серверов.
///
/// Она стоит ровно над последней видимой строкой и закрывает её, поэтому уходит
/// на время прокрутки к концу списка. Возврат — по прокрутке обратно, а не по
/// остановке: иначе кнопка мигала бы на каждом свайпе. И отдельно: скрытая
/// кнопка не должна ловить тапы, иначе она перехватывает нажатие по строке под
/// собой, будучи невидимой.
Finder get _fab => find.byIcon(Icons.add_rounded);

double _opacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.ancestor(of: _fab, matching: find.byType(AnimatedOpacity)),
    )
    .opacity;

/// Материал самой кнопки навешивает свои IgnorePointer, поэтому ищем наш — тот,
/// что оборачивает анимацию ухода.
bool _ignoring(WidgetTester tester) => tester
    .widget<IgnorePointer>(
      find
          .ancestor(
            of: find.byType(AnimatedScale),
            matching: find.byType(IgnorePointer),
          )
          .first,
    )
    .ignoring;

Future<ScrollController> _pump(WidgetTester tester, {int items = 60}) async {
  final controller = ScrollController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ScrollHiddenFab(
          fab: FloatingActionButton(
            onPressed: () {},
            child: const Icon(Icons.add_rounded),
          ),
          child: ListView.builder(
            controller: controller,
            itemCount: items,
            itemBuilder: (context, i) =>
                SizedBox(height: 60, child: Text('item $i')),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

/// Прокрутка пальцем: кнопка обязана реагировать на НАСТОЯЩЕЕ движение, а не
/// на программный jumpTo, который уведомления о направлении не рассылает.
Future<void> _drag(WidgetTester tester, double dy) async {
  await tester.drag(find.byType(ListView), Offset(0, dy));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('на месте, пока список не трогали', (tester) async {
    await _pump(tester);

    expect(_opacity(tester), 1);
    expect(_ignoring(tester), isFalse);
  });

  testWidgets('уходит на прокрутке к концу списка', (tester) async {
    await _pump(tester);

    await _drag(tester, -300);

    expect(_opacity(tester), 0);
    // Невидимая кнопка не должна перехватывать тап по строке под ней.
    expect(_ignoring(tester), isTrue);
  });

  testWidgets('возвращается на прокрутке обратно', (tester) async {
    await _pump(tester);

    await _drag(tester, -300);
    expect(_opacity(tester), 0);

    await _drag(tester, 120);

    expect(_opacity(tester), 1);
    expect(_ignoring(tester), isFalse);
  });

  testWidgets('у начала списка возвращается сама', (tester) async {
    final controller = await _pump(tester);

    await _drag(tester, -300);
    expect(_opacity(tester), 0);

    // Прыжок к началу — так делает переход к активному серверу; прокрутки
    // «вверх» при этом нет, и без отдельной ветки кнопка осталась бы скрытой.
    controller.jumpTo(0);
    await tester.pumpAndSettle();

    expect(_opacity(tester), 1);
  });

  testWidgets('короткий список кнопку не прячет', (tester) async {
    await _pump(tester, items: 2);

    await _drag(tester, -300);

    expect(_opacity(tester), 1);
  });
}
