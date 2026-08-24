import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/shared/ui/server_group_anchors.dart';

/// Прыжок к группе из бокового навигатора.
///
/// Сайдбар и список серверов — разные ветки дерева, поэтому цель прыжка живёт
/// в реестре якорей. Два условия, без которых он молча перестаёт работать:
/// смещение должно считаться и для группы ЗА экраном (шапки строятся всегда,
/// тайлы — лениво), а уходящее при кросс-фейде раскладки поддерево не должно
/// уносить с собой чужую регистрацию.
Widget _list({
  required ScrollController controller,
  int groups = 6,
  double height = 400,
}) {
  return CustomScrollView(
    controller: controller,
    slivers: [
      for (var i = 0; i < groups; i++)
        SliverToBoxAdapter(
          child: ServerGroupAnchor(
            groupKey: 'g$i',
            child: SizedBox(height: height, child: Text('group $i')),
          ),
        ),
    ],
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double leadingInset = 0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 300,
          child: ServerGroupAnchorScope(
            leadingInset: leadingInset,
            child: child,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    ServerGroupAnchors.instance
      ..leadingInset = 0
      ..currentGroup.value = null;
  });

  testWidgets('прыгает к группе далеко за экраном', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await _pump(tester, _list(controller: controller));

    expect(controller.offset, 0);

    final jump = ServerGroupAnchors.instance.jumpTo(
      'g3',
      duration: const Duration(milliseconds: 20),
    );
    await tester.pumpAndSettle();

    expect(await jump, isTrue);
    expect(controller.offset, closeTo(1200, 1));
  });

  testWidgets('отступ шапки списка не даёт группе уехать под градиент', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await _pump(tester, _list(controller: controller), leadingInset: 34);

    final jump = ServerGroupAnchors.instance.jumpTo(
      'g2',
      duration: const Duration(milliseconds: 20),
    );
    await tester.pumpAndSettle();

    expect(await jump, isTrue);
    expect(controller.offset, closeTo(800 - 34, 1));
  });

  testWidgets('дальше конца списка не улетает', (tester) async {
    // Последняя группа коротка, и «выровнять её по верху» означало бы уехать
    // за конец содержимого: без ограничения это ошибка ScrollPosition.
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await _pump(tester, _list(controller: controller, groups: 3, height: 120));

    final jump = ServerGroupAnchors.instance.jumpTo(
      'g2',
      duration: const Duration(milliseconds: 20),
    );
    await tester.pumpAndSettle();

    expect(await jump, isTrue);
    expect(controller.offset, controller.position.maxScrollExtent);
    expect(
      controller.offset,
      lessThan(240),
      reason: 'g2 начинается на 240 — значит ограничение сработало',
    );
  });

  testWidgets('кросс-фейд раскладки не уносит живой якорь', (tester) async {
    // AnimatedSwitcher держит оба поддерева на время перехода: новая группа
    // регистрируется РАНЬШЕ, чем диспоузится прежняя. Безусловное снятие
    // регистрации в dispose стёрло бы живой якорь, и прыжок молча перестал бы
    // работать после первой же смены числа колонок.
    final controller = ScrollController();
    addTearDown(controller.dispose);

    Widget tree(bool alt) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: KeyedSubtree(
                  key: ValueKey(alt),
                  child: _list(controller: alt ? ScrollController() : controller),
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(tree(false));
    await tester.pumpAndSettle();
    await tester.pumpWidget(tree(true));
    // Середина перехода: в дереве оба списка.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    final jump = ServerGroupAnchors.instance.jumpTo(
      'g2',
      duration: const Duration(milliseconds: 20),
    );
    await tester.pumpAndSettle();

    expect(
      await jump,
      isTrue,
      reason: 'якорь новой раскладки обязан пережить dispose прежней',
    );
  });

  testWidgets('нет якоря — нет и прыжка, без исключений', (tester) async {
    await _pump(tester, const SizedBox());

    expect(await ServerGroupAnchors.instance.jumpTo('missing'), isFalse);
  });

  group('текущая группа', () {
    testWidgets('в начале списка — первая', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pump(tester, _list(controller: controller));

      expect(ServerGroupAnchors.instance.currentGroup.value, 'g0');
    });

    testWidgets('после прыжка — та, куда прыгнули', (tester) async {
      // Ровно та жалоба: список уезжал правильно, а метка навигатора оставалась
      // на первой группе, потому что показывала группу активного сервера.
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pump(tester, _list(controller: controller), leadingInset: 34);

      final jump = ServerGroupAnchors.instance.jumpTo(
        'g4',
        duration: const Duration(milliseconds: 20),
      );
      await tester.pumpAndSettle();
      await jump;

      expect(ServerGroupAnchors.instance.currentGroup.value, 'g4');
    });

    testWidgets('обычная прокрутка тоже двигает метку', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pump(tester, _list(controller: controller));

      await tester.drag(find.text('group 0'), const Offset(0, -900));
      await tester.pumpAndSettle();

      expect(ServerGroupAnchors.instance.currentGroup.value, 'g2');
    });

    testWidgets('в самом низу — последняя', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pump(tester, _list(controller: controller));

      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();

      expect(ServerGroupAnchors.instance.currentGroup.value, 'g5');
    });
  });
}
