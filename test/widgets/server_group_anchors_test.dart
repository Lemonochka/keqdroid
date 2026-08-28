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

  /// Прыжок к СТРОКЕ активного сервера — тап по чипу «подключено к…».
  ///
  /// Строки списка строятся лениво, поэтому у сервера за экраном нет ни
  /// контекста, ни render object: `ensureVisible` по нему невозможен, и
  /// цель считается смещением от шапки группы. Смещение приносит сама группа —
  /// только она знает свою сортировку, число колонок и высоту шапки.
  group('строка активного сервера', () {
    testWidgets('прыжок доезжает до строки, а не до шапки группы', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pump(tester, _list(controller: controller));

      ServerGroupAnchors.instance.registerActiveServer(
        serverId: 'srv-row',
        groupKey: 'g3',
        offsetInGroup: 152,
      );

      final jump = ServerGroupAnchors.instance.jumpToServer(
        'srv-row',
        duration: const Duration(milliseconds: 20),
      );
      await tester.pumpAndSettle();

      expect(await jump, isTrue);
      // g3 начинается на 1200, строка — двумя рядами ниже.
      expect(controller.offset, closeTo(1352, 1));
    });

    testWidgets('отступ шапки списка учитывается и здесь', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pump(tester, _list(controller: controller), leadingInset: 34);

      ServerGroupAnchors.instance.registerActiveServer(
        serverId: 'srv-inset',
        groupKey: 'g2',
        offsetInGroup: 76,
      );

      final jump = ServerGroupAnchors.instance.jumpToServer(
        'srv-inset',
        duration: const Duration(milliseconds: 20),
      );
      await tester.pumpAndSettle();

      expect(await jump, isTrue);
      expect(controller.offset, closeTo(800 + 76 - 34, 1));
    });

    testWidgets('у свёрнутой группы строки нет — прыжка тоже', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pump(tester, _list(controller: controller));

      ServerGroupAnchors.instance.registerActiveServer(
        serverId: 'srv-collapsed',
        groupKey: 'g3',
        offsetInGroup: null,
      );

      final place = ServerGroupAnchors.instance.placeOfServer('srv-collapsed');
      expect(place?.groupKey, 'g3');
      // Вызывающий по этому и понимает, что группу надо сперва развернуть.
      expect(place?.collapsed, isTrue);
      expect(
        await ServerGroupAnchors.instance.jumpToServer('srv-collapsed'),
        isFalse,
      );
      expect(controller.offset, 0);
    });

    testWidgets('группа снимает свою протухшую запись, но не чужую', (
      tester,
    ) async {
      await _pump(tester, const SizedBox());
      final anchors = ServerGroupAnchors.instance;

      anchors.registerActiveServer(
        serverId: 'srv-gone',
        groupKey: 'g1',
        offsetInGroup: 76,
      );

      // Чужая группа перестроилась и активного сервера у себя не нашла —
      // запись группы g1 её не касается.
      anchors.unregisterActiveServer('g4');
      expect(anchors.placeOfServer('srv-gone')?.groupKey, 'g1');

      // А своя — касается: иначе остался бы отступ до строки, которой в
      // группе больше нет.
      anchors.unregisterActiveServer('g1');
      expect(anchors.placeOfServer('srv-gone'), isNull);
    });

    testWidgets('про чужой сервер реестр молчит', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pump(tester, _list(controller: controller));

      ServerGroupAnchors.instance.registerActiveServer(
        serverId: 'srv-known',
        groupKey: 'g1',
        offsetInGroup: 0,
      );

      // Сервер сменили, а список ещё не перестроился — увозить экран к строке
      // прошлого хуже, чем не увозить никуда.
      expect(ServerGroupAnchors.instance.placeOfServer('srv-other'), isNull);
      expect(
        await ServerGroupAnchors.instance.jumpToServer('srv-other'),
        isFalse,
      );
      expect(controller.offset, 0);
    });
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
