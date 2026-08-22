import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/go_build_info.dart';

/// Разбор ядра идёт на UI-изоляте, когда открывают панель «Внутренности».
/// Метка build info у libxray лежит под самый конец 39 МБ, то есть скан
/// проходит почти весь файл — этот тест сторожит, чтобы он не выродился в
/// секунды и не потребовал отдельного изолята.
void main() {
  test('разбор поставляемого ядра укладывается в бюджет кадра-другого', () async {
    final file = File('android/app/src/main/jniLibs/arm64-v8a/libxray.so');
    if (!file.existsSync()) {
      markTestSkipped('нет libxray.so');
      return;
    }

    final watch = Stopwatch()..start();
    final info = await GoBuildInfo.fromFile(file);
    watch.stop();

    expect(info, isNotNull);
    // Порог с большим запасом: на слабом телефоне медленнее, но не на порядок.
    // Если однажды упрётся — это сигнал уносить разбор в Isolate.run, а не
    // повод поднимать порог.
    expect(
      watch.elapsedMilliseconds,
      lessThan(2000),
      reason: 'разбор занял ${watch.elapsedMilliseconds} мс',
    );
    // ignore: avoid_print
    print('libxray.so (${file.lengthSync() ~/ 1048576} МБ): '
        '${watch.elapsedMilliseconds} мс');
  });
}
