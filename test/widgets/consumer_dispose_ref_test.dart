import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ловушка, из-за которой лог на десктопе заваливало ассертами
/// `'_lifecycleState != _ElementLifecycle.defunct': is not true` — причём при
/// подключении, отключении и смене режима, то есть там, где никакого отношения
/// к виновному экрану уже нет.
///
/// `ConsumerStatefulElement.unmount()` сначала зовёт `super.unmount()`, а тот
/// обнуляет `_widget` (значит `context.mounted == false`), ставит элементу
/// `defunct` и только потом выполняет `State.dispose()`. Watch-подписки Riverpod
/// закрывает ПОСЛЕ этого. Любой `ref.*` в `dispose()` бросает StateError, unmount
/// обрывается на полпути — и подписка остаётся жить на мёртвом элементе, дёргая
/// `markNeedsBuild()` на каждое последующее изменение любого провайдера.
///
/// Тест сторожит границу: `ref` в `dispose()` рвёт unmount, снимок из `build()`
/// — нет. Экраны с сохранением по уходу (локальные порты, хоткеи) обязаны
/// пользоваться вторым способом.
final _counter = NotifierProvider<_Counter, int>(_Counter.new);

class _Counter extends Notifier<int> {
  @override
  int build() => 0;
}

/// Как было: `ref` в dispose().
class _RefInDispose extends ConsumerStatefulWidget {
  const _RefInDispose();

  @override
  ConsumerState<_RefInDispose> createState() => _RefInDisposeState();
}

class _RefInDisposeState extends ConsumerState<_RefInDispose> {
  @override
  void dispose() {
    ref.read(_counter);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('${ref.watch(_counter)}');
}

/// Как стало: всё нужное снято в build, dispose к `ref` не прикасается.
class _SnapshotInBuild extends ConsumerStatefulWidget {
  const _SnapshotInBuild({required this.onDispose});

  final ValueChanged<int> onDispose;

  @override
  ConsumerState<_SnapshotInBuild> createState() => _SnapshotInBuildState();
}

class _SnapshotInBuildState extends ConsumerState<_SnapshotInBuild> {
  int _last = -1;

  @override
  void dispose() {
    widget.onDispose(_last);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _last = ref.watch(_counter);
    return Text('$_last');
  }
}

void main() {
  /// Монтирует [child], затем убирает его из того же контейнера — как уход с
  /// экрана настроек не трогает ProviderScope приложения.
  Future<void> pumpThenDrop(WidgetTester tester, Widget child) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    Widget scope(Widget body) => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: Scaffold(body: body)),
        );
    await tester.pumpWidget(scope(child));
    await tester.pumpWidget(scope(const SizedBox.shrink()));
  }

  testWidgets('ref in dispose aborts unmount before Riverpod closes its subs',
      (tester) async {
    await pumpThenDrop(tester, const _RefInDispose());

    // StateError вылетает ИЗ unmount(): всё, что Riverpod делает после
    // super.unmount() — включая закрытие watch-подписок — уже не выполнится,
    // и подписка остаётся висеть на defunct-элементе.
    final error = tester.takeException();
    expect(error, isStateError);
    expect('$error', contains('unmounted is unsafe'));
  });

  testWidgets('snapshot taken in build keeps unmount clean', (tester) async {
    var seen = -1;
    await pumpThenDrop(tester, _SnapshotInBuild(onDispose: (v) => seen = v));

    // dispose получил актуальное значение и ничего не сломал.
    expect(seen, 0);
    expect(tester.takeException(), isNull);
  });
}
