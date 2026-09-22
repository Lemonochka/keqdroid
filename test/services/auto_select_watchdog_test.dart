import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/auto_select_watchdog.dart';

/// Правила сторожа: когда он вообще лезет в сеть и когда меняет сервер.
///
/// Смена сети в этих правилах не участвует вовсе — и это не забывчивость.
/// Переезд с Wi-Fi на LTE сам по себе не значит, что сервер перестал
/// работать; значит это только молчащий туннель.
void main() {
  group('когда идти в сеть', () {
    test('идёт только на молчащем туннеле', () {
      expect(
        AutoSelectWatchdog.shouldProbe(
          connected: true,
          autoSelectOn: true,
          trafficMoved: false,
        ),
        isTrue,
      );
    });

    test('прошедший трафик — уже доказательство жизни', () {
      // Байты прошли — сервер отвечает, и проба была бы тратой батареи на
      // доказательство доказанного.
      expect(
        AutoSelectWatchdog.shouldProbe(
          connected: true,
          autoSelectOn: true,
          trafficMoved: true,
        ),
        isFalse,
      );
    });

    test('без подключения и без автовыбора не просыпается', () {
      expect(
        AutoSelectWatchdog.shouldProbe(
          connected: false,
          autoSelectOn: true,
          trafficMoved: false,
        ),
        isFalse,
      );
      expect(
        AutoSelectWatchdog.shouldProbe(
          connected: true,
          autoSelectOn: false,
          trafficMoved: false,
        ),
        isFalse,
      );
    });
  });

  group('тихая прослушка', () {
    test('одиночный отказ дозвона — не повод идти в сеть', () {
      // Страница открывает десяток соединений, одно может и не пролезть:
      // это жизнь живого сервера, а не его смерть.
      expect(AutoSelectWatchdog.dialFailuresSuggestDeadServer(1), isFalse);
      expect(AutoSelectWatchdog.dialFailuresSuggestDeadServer(0), isFalse);
    });

    test('всплеск отказов — идём проверять', () {
      expect(
        AutoSelectWatchdog.dialFailuresSuggestDeadServer(
          AutoSelectWatchdog.failureBurst,
        ),
        isTrue,
      );
    });

    test('смотрит часто, потому что это не сеть', () {
      // Читается число в памяти процесса — радио от этого не просыпается,
      // поэтому интервал может быть коротким, а весь переезд — быстрым.
      expect(AutoSelectWatchdog.listenEvery.inSeconds, lessThanOrEqualTo(3));
    });

    test('после проверки без переезда молчит, но недолго', () {
      // Без сети вовсе собственные пробы будили бы проверку каждые две
      // секунды — а каждая проверка это запрос мимо туннеля.
      expect(
        AutoSelectWatchdog.quietAfterCheck,
        greaterThan(AutoSelectWatchdog.listenEvery * 3),
      );
      expect(AutoSelectWatchdog.quietAfterCheck.inSeconds, lessThanOrEqualTo(30));
    });
  });

  group('когда менять сервер', () {
    test('одного провала мало', () {
      // Секунда без сети в лифте не стоит разрыва соединения.
      expect(AutoSelectWatchdog.shouldSwitch(1), isFalse);
    });

    test('двух подряд достаточно', () {
      expect(AutoSelectWatchdog.shouldSwitch(2), isTrue);
    });
  });

  test('подтверждение стоит секунд, а не ещё одного тика', () {
    // Вторая проба идёт через короткую паузу внутри того же тика: ждать
    // полный интервал ради подтверждения того, что уже видно, — это те же
    // двадцать секунд без интернета.
    expect(
      AutoSelectWatchdog.retryAfterFailure,
      lessThan(AutoSelectWatchdog.probeEvery),
    );
    // Но и не мгновенно: моргнувшую сеть надо пережить, а не принять за
    // мёртвый сервер.
    expect(
      AutoSelectWatchdog.retryAfterFailure.inSeconds,
      greaterThanOrEqualTo(3),
    );

    // Худшее ожидание целиком: тик, две пробы по таймауту и пауза между
    // ними. Минута — потолок, за которым ожидание уже злит.
    final worst = AutoSelectWatchdog.probeEvery +
        AutoSelectWatchdog.probeTimeout * 2 +
        AutoSelectWatchdog.retryAfterFailure;
    expect(worst.inSeconds, lessThanOrEqualTo(60));
  });
}
