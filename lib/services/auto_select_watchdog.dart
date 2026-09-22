import 'dart:io';

/// Сторож автовыбора: замечает, что текущий сервер перестал работать.
///
/// Смена сети сама по себе поводом для переезда не считается — она только
/// причина, по которой сервер может отвалиться (белые списки в чужом Wi-Fi,
/// мобильный оператор, домашний провайдер). Решает всегда одно: отвечает
/// туннель или нет.
///
/// Проба идёт через локальный инбаунд, то есть через живое соединение, а не
/// мимо него: пакет приложения исключён из TUN, и прямой запрос сказал бы
/// только «интернет у телефона есть», что к состоянию туннеля отношения не
/// имеет.
abstract final class AutoSelectWatchdog {
  /// Как часто сторож просыпается.
  ///
  /// Двадцать секунд — компромисс: минута ожидания на мёртвом сервере злит,
  /// а чаще будить радио незачем. Разбуженный тик почти всегда кончается
  /// ничем: трафик, прошедший с прошлого раза, и есть доказательство жизни,
  /// и тогда в сеть сторож не ходит вовсе (см. [shouldProbe]).
  static const probeEvery = Duration(seconds: 20);

  /// Сколько проб подряд должны провалиться, прежде чем менять сервер.
  ///
  /// Не одна: короткий провал бывает у живого сервера (переезд с Wi-Fi на
  /// LTE, спящее радио, секунда без сети в лифте), а смена сервера — это
  /// разрыв соединения, и платить им за каждую случайность нельзя.
  static const failuresBeforeSwitch = 2;

  /// Сколько ждём ответа от пробы.
  static const probeTimeout = Duration(seconds: 6);

  /// Идти ли в сеть на этом тике.
  ///
  /// [trafficMoved] — прошли ли байты через туннель с прошлого тика. Прошли —
  /// значит сервер отвечает, и проба была бы тратой батареи на доказательство
  /// уже доказанного.
  static bool shouldProbe({
    required bool connected,
    required bool autoSelectOn,
    required bool trafficMoved,
  }) =>
      connected && autoSelectOn && !trafficMoved;

  /// Пора ли съезжать на другой сервер.
  static bool shouldSwitch(int consecutiveFailures) =>
      consecutiveFailures >= failuresBeforeSwitch;

  /// Отвечает ли что-нибудь через локальный инбаунд туннеля.
  ///
  /// Ответ любого кода считается успехом: нам важно, что запрос дошёл и
  /// вернулся, а не что именно ответил сайт. Провал — это исключение:
  /// инбаунд не принял, ядро не дозвонилось, время вышло.
  static Future<bool> tunnelResponds({
    required int httpPort,
    required String testUrl,
    String username = '',
    String password = '',
    Duration timeout = probeTimeout,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      // `PROXY host:port` — единственное, что понимает findProxy у dart:io:
      // SOCKS он не умеет вовсе, поэтому ходим в HTTP-инбаунд.
      ..findProxy = (_) => 'PROXY 127.0.0.1:$httpPort';
    if (username.isNotEmpty) {
      client.addProxyCredentials(
        '127.0.0.1',
        httpPort,
        '',
        HttpClientBasicCredentials(username, password),
      );
    }
    try {
      final request = await client
          .getUrl(Uri.parse(testUrl))
          .timeout(timeout);
      final response = await request.close().timeout(timeout);
      await response.drain<void>();
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
