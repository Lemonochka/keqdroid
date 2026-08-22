/// Прогоняет [items] через [action] пулом воркеров.
///
/// Зачем не `Future.wait` по всему списку: за каждым элементом здесь стоит
/// процесс ядра или сетевой замер, и «все разом» — это десятки процессов на
/// телефоне. Зачем не последовательный цикл: замер ждёт сеть, а не процессор,
/// и сумма ожиданий складывается в минуты.
///
/// Порядок результата — входной, кто бы в каком порядке ни ответил: вызывающий
/// раскладывает результаты обратно по элементам. Для прогресса по мере
/// готовности достаточно сделать что-нибудь в конце самого [action].
///
/// Исключение из [action] всплывает наружу, как у `Future.wait`; уже
/// запущенные воркеры при этом доработают свой текущий элемент.
Future<List<R>> mapPooled<T, R>(
  List<T> items,
  int concurrency,
  Future<R> Function(T item) action,
) async {
  if (items.isEmpty) return <R>[];

  final results = List<R?>.filled(items.length, null);

  // Курсор один на всех воркеров, и синхронизировать его нечем — да и незачем:
  // Dart однопоточен, а `next++` синхронный, без await внутри, так что между
  // чтением и записью воркера никто не перебьёт.
  var next = 0;
  Future<void> worker() async {
    while (true) {
      final index = next++;
      if (index >= items.length) return;
      results[index] = await action(items[index]);
    }
  }

  final workers = concurrency < 1
      ? 1
      : (concurrency < items.length ? concurrency : items.length);
  await Future.wait([for (var i = 0; i < workers; i++) worker()]);

  return [for (final r in results) r as R];
}
