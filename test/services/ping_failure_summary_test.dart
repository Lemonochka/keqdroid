import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/ping_service.dart';

/// Строка в журнал о том, почему серверы не ответили на замер.
///
/// #18, 13.11.2026: «пинг всех» на Windows давал N/A всей подписке, а журнал
/// человека не сказал о пинге ни слова, и причину пришлось угадывать по коду.
/// Строка одна на замер, иначе подписка на сотню серверов съест журнал.
void main() {
  PingResult ok(String id) => PingResult(
        serverId: id,
        serverName: id,
        latencyMs: 120,
        success: true,
        pingType: PingType.url,
      );

  PingResult fail(String id, String error) => PingResult(
        serverId: id,
        serverName: id,
        success: false,
        error: error,
        pingType: PingType.url,
      );

  test('все ответили: строки нет', () {
    expect(PingService.failureSummary(PingType.url, [ok('a'), ok('b')]), isNull);
    expect(PingService.failureSummary(PingType.url, const []), isNull);
  });

  test('причины сгруппированы, частая первой, номер порта причину не дробит', () {
    final line = PingService.failureSummary(PingType.url, [
      ok('a'),
      fail('b', 'Timeout'),
      fail('c', 'Core did not open port 51234 in time'),
      fail('d', 'Core did not open port 51999 in time'),
      fail('e', 'Core did not open port 50001 in time'),
    ]);

    expect(
      line,
      'Ping url: 1 of 5 answered; '
      'Core did not open port in time x3; Timeout x1',
    );
  });

  test('при равенстве порядок как в замере', () {
    final line = PingService.failureSummary(PingType.tcp, [
      fail('a', 'HTTP 403'),
      fail('b', 'Timeout'),
    ]);

    expect(line, 'Ping tcp: 0 of 2 answered; HTTP 403 x1; Timeout x1');
  });

  test('пустая причина названа, а не пропущена', () {
    expect(
      PingService.failureSummary(PingType.url, [fail('a', '  ')]),
      'Ping url: 0 of 1 answered; no reason x1',
    );
  });

  test('редкие причины не раздувают строку', () {
    final line = PingService.failureSummary(PingType.url, [
      for (var i = 0; i < 6; i++) fail('$i', 'reason $i'),
    ])!;

    expect(line, endsWith('reason 3 x1; and 2 more'));
    expect(line, isNot(contains('reason 4')));
  });

  test('длинный хвост лога ядра обрезан', () {
    final line = PingService.failureSummary(PingType.url, [
      fail('a', 'Core exited with code 23 before opening port 4000: ${'x' * 500}'),
    ])!;

    expect(line.length, lessThan(260));
  });
}
