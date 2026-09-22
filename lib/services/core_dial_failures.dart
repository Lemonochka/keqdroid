/// Отказы дозвона ядра сессии до своего сервера — тихая прослушка автовыбора.
///
/// Каждое ядро само пишет в лог, что не дозвонилось до сервера:
///
/// mihomo — `[TCP] dial <прокси> (match …) … error: …`, уровень warning;
/// xray — `failed to find an available destination`, а у XHTTP, который
/// дозванивается лениво, — строки самого транспорта `splithttp: failed to …`
/// и `splithttp: unexpected status …`; всё это только на уровне info, поэтому
/// на Android сессию xray поднимают до info (sessionConfigFor в
/// KeqdisVpnService);
/// sing-box (десктопный TUN в keqrnel) — `open connection to … using
/// outbound/<тип>[<тег>]: …`.
///
/// На Android строки считает нативный читатель лога (forkexec.c,
/// `is_server_dial_failure`), здесь — двойник для десктопа, где вывод ядра
/// читает сам Dart. Правила у них обязаны совпадать; тесты держат этот.
abstract final class CoreDialFailures {
  static int _count = 0;

  /// Сколько отказов насчитано с запуска процесса. Монотонно: вызывающему
  /// важна только разница между двумя чтениями.
  static int get count => _count;

  /// Строка вывода ядра сессии: если это отказ дозвона до сервера — считаем.
  static void observe(String line) {
    if (isServerDialFailure(line)) _count++;
  }

  /// Отказ ли это дозвона именно до сервера.
  ///
  /// Прямые соединения и блокировки не считаются: мёртвый сайт — не мёртвый
  /// сервер. UDP не считается тоже: сервер без UDP отвечает отказом на каждый
  /// QUIC-запрос и сыпал бы «отказами» от одного открытого ютуба, а проба,
  /// которой потом проверяют сервер, всё равно идёт по TCP.
  static bool isServerDialFailure(String line) {
    if (line.contains('failed to find an available destination')) return true;

    final xhttp = line.indexOf('splithttp: ');
    if (xhttp >= 0) {
      final what = line.substring(xhttp + 'splithttp: '.length);
      if (what.startsWith('failed to create')) return false;
      return what.startsWith('failed to ') ||
          what.startsWith('unexpected status ');
    }

    final dial = line.indexOf('[TCP] dial ');
    if (dial >= 0) {
      if (!line.contains(' error: ')) return false;
      final target = line.substring(dial + '[TCP] dial '.length);
      return !target.startsWith('DIRECT') && !target.startsWith('REJECT');
    }

    if (line.contains('open connection to ') &&
        line.contains(' using outbound/')) {
      return !line.contains('outbound/direct[') &&
          !line.contains('outbound/block[');
    }
    return false;
  }
}
