import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/auto_select_watchdog.dart';
import 'package:keqdroid/services/auto_server_select.dart';

/// Сторож автовыбора: когда он просыпается и когда меняет сервер.
///
/// Главное, что здесь сторожится: с рабочего сервера уйти нельзя. Прослушка
/// может разбудить судью сколько угодно раз, но решает всегда свежий замер —
/// текущий ответил, значит остаёмся, что бы ни показалось прослушке.
({String id, bool success, int? latencyMs}) _ok(String id, int ms) =>
    (id: id, success: true, latencyMs: ms);
({String id, bool success, int? latencyMs}) _dead(String id) =>
    (id: id, success: false, latencyMs: null);

void main() {
  group('судья: с рабочего сервера не уходим', () {
    test('текущий ответил — остаёмся, даже если соседи быстрее', () {
      final verdict = AutoServerSelect.judge(
        currentId: 'cur',
        results: [_ok('cur', 300), _ok('fast', 20)],
        batchComplete: true,
      );
      expect(verdict.decided, isTrue);
      expect(verdict.nextId, isNull);
    });

    test('ответил хоть на тишине в туннеле — всё равно остаёмся', () {
      // Тишина могла быть случайной; свежий замер сильнее догадки.
      final verdict = AutoServerSelect.judge(
        currentId: 'cur',
        results: [_ok('cur', 900)],
        batchComplete: false,
        currentPresumedDead: true,
      );
      expect(verdict.nextId, isNull);
      expect(verdict.decided, isTrue);
    });

    test('слабый сигнал и нет ответа от текущего — ждём его вердикта', () {
      // Одиночный отказ в логе — не повод уходить, пока сам сервер не
      // провалил замер: сосед ответил раньше, но это ничего не значит.
      final verdict = AutoServerSelect.judge(
        currentId: 'cur',
        results: [_ok('other', 40)],
        batchComplete: false,
      );
      expect(verdict.decided, isFalse);
    });
  });

  group('судья: уходим только на живой', () {
    test('текущий не ответил — самый быстрый из ответивших', () {
      final verdict = AutoServerSelect.judge(
        currentId: 'cur',
        results: [_dead('cur'), _ok('slow', 200), _ok('fast', 50), _dead('x')],
        batchComplete: true,
      );
      expect(verdict.nextId, 'fast');
    });

    test('мёртвые соседи со старым хорошим пингом не выбираются', () {
      // В замер они попадают, но не отвечают — и выбор их не видит.
      final verdict = AutoServerSelect.judge(
        currentId: 'cur',
        results: [_dead('cur'), _dead('old-best'), _ok('alive', 180)],
        batchComplete: true,
      );
      expect(verdict.nextId, 'alive');
    });

    test('на тишине не ждём таймаута мёртвого, если сосед уже ответил', () {
      final verdict = AutoServerSelect.judge(
        currentId: 'cur',
        results: [_ok('alive', 80)],
        batchComplete: false,
        currentPresumedDead: true,
      );
      expect(verdict.nextId, 'alive');
    });

    test('не ответил никто — остаёмся: это сеть или всё сразу', () {
      final verdict = AutoServerSelect.judge(
        currentId: 'cur',
        results: [_dead('cur'), _dead('a'), _dead('b')],
        batchComplete: true,
      );
      expect(verdict.decided, isTrue);
      expect(verdict.nextId, isNull);
    });
  });

  group('прослушка', () {
    test('первый же отказ ядра будит судью', () {
      // Живой тест: xray на Hysteria2 роняет отказы по одному раз в 16–50
      // секунд. Будить — не значит менять: решает замер.
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
      expect(AutoSelectWatchdog.isSilentSecond(sent: 0, received: 0), isFalse);
    });

    test('одна тихая секунда — ещё не повод', () {
      expect(AutoSelectWatchdog.trafficStalled(1), isFalse);
      expect(
        AutoSelectWatchdog.trafficStalled(
          AutoSelectWatchdog.silentSecondsBeforeCheck,
        ),
        isTrue,
      );
    });

    test('страховка верит только пришедшему', () {
      expect(
        AutoSelectWatchdog.shouldProbe(
          connected: true,
          autoSelectOn: true,
          trafficMoved: false,
        ),
        isTrue,
      );
      expect(
        AutoSelectWatchdog.shouldProbe(
          connected: true,
          autoSelectOn: true,
          trafficMoved: true,
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

  group('предохранитель от беготни по кругу', () {
    final t0 = DateTime(2026, 9, 23, 12);

    test('первые переезды разрешены', () {
      expect(AutoSelectWatchdog.switchAllowed(const [], t0), isTrue);
      expect(AutoSelectWatchdog.switchAllowed([t0], t0), isTrue);
    });

    test('лимит за окно — и сторож отходит в сторону', () {
      final recent = [
        for (var i = 0; i < AutoSelectWatchdog.maxSwitchesPerWindow; i++)
          t0.add(Duration(seconds: 10 * i)),
      ];
      expect(
        AutoSelectWatchdog.switchAllowed(
          recent,
          t0.add(const Duration(seconds: 40)),
        ),
        isFalse,
      );
    });

    test('после окна снова можно', () {
      final recent = [
        for (var i = 0; i < AutoSelectWatchdog.maxSwitchesPerWindow; i++) t0,
      ];
      expect(
        AutoSelectWatchdog.switchAllowed(
          recent,
          t0.add(AutoSelectWatchdog.switchWindow),
        ),
        isTrue,
      );
    });
  });

  test('замер судьи короче, чем обычный пинг, но не впритык', () {
    // Мерим «жив ли», а не «насколько быстр»: живой сервер отвечает за доли
    // секунды, но на загруженном LTE нужен запас, иначе рабочий сервер
    // выглядел бы мёртвым.
    expect(AutoSelectWatchdog.judgeTimeoutSeconds, greaterThanOrEqualTo(3));
    expect(AutoSelectWatchdog.judgeTimeoutSeconds, lessThanOrEqualTo(6));
  });
}
