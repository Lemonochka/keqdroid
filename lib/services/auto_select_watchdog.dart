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
  /// Как часто приложение смотрит на счётчик отказов ядра.
  ///
  /// Это не проба и не сеть: читается число в памяти процесса, которое натив
  /// насчитал по логу ядра (оба ядра сами пишут о неудачном дозвоне до
  /// сервера). Поэтому и часто — радио от этого не просыпается.
  static const listenEvery = Duration(seconds: 2);

  /// Сколько отказов дозвона между двумя взглядами — повод проверить сервер
  /// по-настоящему.
  ///
  /// Не один: отдельный отказ бывает и у живого сервера (страница открыла
  /// десяток соединений, одно не пролезло). Три за пару секунд — это уже
  /// браузер, у которого не открывается ничего.
  static const failureBurst = 3;

  /// Сколько молчать после проверки, которая сервер не сменила.
  ///
  /// Иначе без сети вовсе (метро, самолёт) собственные пробы сторожа и
  /// отказы приложений будили бы проверку каждые две секунды, а каждая
  /// проверка — это запрос мимо туннеля.
  static const quietAfterCheck = Duration(seconds: 15);

  /// Страховка на случай, которого прослушка не видит.
  ///
  /// Отказ дозвона ядро пишет в лог, а вот соединение, которое открылось и
  /// повисло без единого байта, — нет. Такое бывает, когда провайдер душит
  /// уже установленные соединения. Раз в полминуты сторож смотрит, прошёл ли
  /// через туннель хоть байт, и только если нет — идёт проверять (см.
  /// [shouldProbe]).
  static const probeEvery = Duration(seconds: 30);

  /// Сколько проб подряд должны провалиться, прежде чем менять сервер.
  ///
  /// Не одна: короткий провал бывает у живого сервера (переезд с Wi-Fi на
  /// LTE, спящее радио, секунда без сети в лифте), а смена сервера — это
  /// разрыв соединения, и платить им за каждую случайность нельзя.
  static const failuresBeforeSwitch = 2;

  /// Пауза между первой неудачной пробой и второй.
  ///
  /// Не целый тик: ждать двадцать секунд ради подтверждения того, что уже
  /// видно, — это те же двадцать секунд без интернета у человека. Пяти
  /// достаточно, чтобы пережить моргнувшую сеть, и вдвое сокращает всё
  /// ожидание.
  static const retryAfterFailure = Duration(seconds: 5);

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

  /// Похож ли всплеск отказов дозвона на мёртвый сервер.
  static bool dialFailuresSuggestDeadServer(int newFailures) =>
      newFailures >= failureBurst;

  /// Пора ли съезжать на другой сервер.
  static bool shouldSwitch(int consecutiveFailures) =>
      consecutiveFailures >= failuresBeforeSwitch;

  /// Есть ли у устройства сеть вообще, мимо туннеля.
  ///
  /// Нужно, чтобы не винить сервер в том, чего он не делал: в метро, в
  /// самолёте и на нулевом сигнале не отвечает никто, и перебор серверов там
  /// означал бы разрыв за разрывом на ровном месте. Запрос идёт напрямую —
  /// пакет приложения и так исключён из туннеля.
  static Future<bool> networkResponds({
    required String testUrl,
    Duration timeout = probeTimeout,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    // Явный отказ от прокси: findProxy по умолчанию читает переменные
    // окружения, и на десктопе системный прокси увёл бы пробу не туда.
    client.findProxy = (_) => 'DIRECT';
    try {
      final request = await client.getUrl(Uri.parse(testUrl)).timeout(timeout);
      final response = await request.close().timeout(timeout);
      await response.drain<void>();
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

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
