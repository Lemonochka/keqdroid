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
