import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/vpn_engine.dart';

void main() {
  group('connectInFlightAction до старта сессии', () {
    test('«отключено» игнорируется: сервис ещё не поднят', () {
      // Именно это гасило анимацию на первом подключении.
      expect(
        connectInFlightAction(
          VpnStatus.disconnected,
          awaitingSessionStart: true,
        ),
        ConnectInFlightAction.ignore,
      );
    });

    test('«подключено» из плитки QS принимается сразу', () {
      expect(
        connectInFlightAction(VpnStatus.connected, awaitingSessionStart: true),
        ConnectInFlightAction.applyAndFinish,
      );
    });

    test('ошибка принимается, попытка продолжается', () {
      expect(
        connectInFlightAction(VpnStatus.error, awaitingSessionStart: true),
        ConnectInFlightAction.apply,
      );
    });
  });

  group('connectInFlightAction после старта сессии', () {
    test('«отключено» — исход попытки, а не шум', () {
      expect(
        connectInFlightAction(
          VpnStatus.disconnected,
          awaitingSessionStart: false,
        ),
        ConnectInFlightAction.applyAndFinish,
      );
    });

    test('«подключено» завершает попытку', () {
      expect(
        connectInFlightAction(VpnStatus.connected, awaitingSessionStart: false),
        ConnectInFlightAction.applyAndFinish,
      );
    });
  });

  test('промежуточные состояния не трогают state ни в одном окне', () {
    for (final awaiting in [true, false]) {
      for (final status in [VpnStatus.connecting, VpnStatus.disconnecting]) {
        expect(
          connectInFlightAction(status, awaitingSessionStart: awaiting),
          ConnectInFlightAction.ignore,
          reason: '$status при awaitingSessionStart=$awaiting',
        );
      }
    }
  });
}
