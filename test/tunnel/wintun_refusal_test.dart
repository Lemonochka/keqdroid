import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/core/exceptions.dart';
import 'package:keqdroid/tunnel/tun_failure_hints.dart';
import 'package:keqdroid/tunnel/wintun_retry.dart';

/// 27.10.2026 Windows раз за разом отказывала в TUN-адаптере (код 31 в
/// диспетчере устройств) обоим ядрам, а со следующей попытки пускала. Строки
/// ниже взяты из её журнала как есть.
const _xrayLog = '''
Xray 26.10.10 (Xray, Penetrates Everything.) Custom (go1.27.0 windows/amd64)
2026/10/27 23:58:36.631609 Failed to find matching adapter name: Элемент не найден. (Code 0x00000490)
2026/10/27 23:58:36.677716 Using existing driver 0.14
2026/10/27 23:58:36.684346 Creating adapter
2026/10/27 23:58:51.709397 Timed out waiting for device query: Время ожидания операции истекло. (Code 0x00000102)
2026/10/27 23:58:51.709879 Failed to setup adapter (problem code: 0x1F, ntstatus: 0xC00002F0): Не удается найти указанный файл. (Code 0x00000002)
Failed to start: app/proxyman/inbound: failed to start proxy > The system cannot find the file specified.
''';

const _mihomoLog = '''
time="2026-10-28T00:20:05.694386500+04:00" level=info msg="SOCKS proxy listening at: 127.0.0.1:2080"
time="2026-10-28T00:20:05.704784000+04:00" level=warning msg="[TUN] default interface changed by monitor, => Ethernet"
time="2026-10-28T00:20:20.795632200+04:00" level=warning msg="Start Tun interface timeout: The system cannot find the file specified. [retrying 1/3]"
''';

void main() {
  group('признак отказа', () {
    test('xray и mihomo опознаются по своему выводу', () {
      expect(isWintunAdapterRefused(_xrayLog), isTrue);
      expect(isWintunAdapterRefused(_mihomoLog), isTrue);
    });

    test('чужие отказы TUN сюда не попадают', () {
      expect(
        isWintunAdapterRefused(
          'create adapter: Failed to load wintun.dll: The specified module '
          'could not be found.',
        ),
        isFalse,
      );
      expect(
        isWintunAdapterRefused(
          'create adapter: error creating adapter: Object already exists',
        ),
        isFalse,
      );
      expect(isWintunAdapterRefused('dial tcp: i/o timeout'), isFalse);
    });
  });

  group('повтор', () {
    var output = '';

    Future<void> run({
      required List<Object?> outcomes,
      bool Function()? cancelled,
      List<int>? retries,
      void Function()? onReset,
    }) {
      var i = 0;
      return retryWhileWintunRefused(
        attempt: () async {
          final outcome = outcomes[i++];
          if (outcome is String) {
            output = outcome;
            throw const VpnStartException('xray exited with code -1');
          }
          if (outcome != null) throw outcome;
        },
        coreOutput: () => output,
        resetAttempt: () async {
          output = '';
          onReset?.call();
        },
        cancelled: cancelled ?? () => false,
        onRetry: retries?.add,
        pause: Duration.zero,
      );
    }

    test('после отказа Windows вторая попытка поднимает TUN', () async {
      final retries = <int>[];
      var resets = 0;
      await run(
        outcomes: [_xrayLog, null],
        retries: retries,
        onReset: () => resets++,
      );
      expect(retries, [1]);
      expect(resets, 1, reason: 'упавшее ядро снимается до новой попытки');
    });

    test('после трёх отказов наружу уходит ошибка', () async {
      final retries = <int>[];
      await expectLater(
        run(outcomes: [_xrayLog, _xrayLog, _xrayLog], retries: retries),
        throwsA(isA<VpnStartException>()),
      );
      expect(retries, [1, 2]);
    });

    test('другую ошибку не повторяем', () async {
      final retries = <int>[];
      await expectLater(
        run(outcomes: ['bind: address already in use'], retries: retries),
        throwsA(isA<VpnStartException>()),
      );
      expect(retries, isEmpty);
    });

    test('Отключить в паузе останавливает повтор', () async {
      var cancelled = false;
      final outcomes = <Object?>[_xrayLog, null];
      await expectLater(
        run(
          outcomes: outcomes,
          cancelled: () => cancelled,
          onReset: () => cancelled = true,
        ),
        throwsA(isA<VpnStartException>()),
      );
    });
  });
}
