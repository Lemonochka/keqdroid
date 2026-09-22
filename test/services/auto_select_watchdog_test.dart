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
    test('первый же отказ ядра — повод проверить', () {
      // Живой тест: xray на Hysteria2 роняет отказы по одному раз в 16–50
      // секунд, каждый ждёт таймаут QUIC. Правило «три за секунду» не
      // сработало бы никогда. От ложной тревоги защищает проба.
      expect(AutoSelectWatchdog.dialFailuresSuggestDeadServer(1), isTrue);
      expect(AutoSelectWatchdog.dialFailuresSuggestDeadServer(0), isFalse);
    });

    test('ушло, но ничего не пришло — тихая секунда', () {
      expect(
        AutoSelectWatchdog.isSilentSecond(sent: 1200, received: 0),
        isTrue,
      );
      // Живой сервер отвечает хоть чем-то, даже на чистую выгрузку —
      // TCP-подтверждениями.
      expect(
        AutoSelectWatchdog.isSilentSecond(sent: 50000, received: 60),
        isFalse,
      );
      // Телефон просто молчит — это не тишина в ответ.
      expect(AutoSelectWatchdog.isSilentSecond(sent: 0, received: 0), isFalse);
    });

    test('одна тихая секунда — ещё не смерть', () {
      // Спящее радио или переезд сети дают секунду без ответа и у живого
      // сервера.
      expect(AutoSelectWatchdog.trafficStalled(1), isFalse);
      expect(
        AutoSelectWatchdog.trafficStalled(
          AutoSelectWatchdog.silentSecondsBeforeCheck,
        ),
        isTrue,
      );
      expect(AutoSelectWatchdog.silentSecondsBeforeCheck, lessThanOrEqualTo(5));
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
