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

  test('цена ожидания измерима и невелика', () {
    // Минута на мёртвом сервере злит, поэтому порог держим около сорока
    // секунд: два тика по двадцать.
    final worstCase = AutoSelectWatchdog.probeEvery.inSeconds *
        AutoSelectWatchdog.failuresBeforeSwitch;
    expect(worstCase, lessThanOrEqualTo(60));
    expect(worstCase, greaterThanOrEqualTo(20));
  });
}
