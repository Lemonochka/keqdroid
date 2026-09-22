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

    test('медленный ответ — всё равно ответ', () {
      final verdict = AutoServerSelect.judge(
        currentId: 'cur',
        results: [_ok('cur', 900)],
        batchComplete: false,
      );
      expect(verdict.nextId, isNull);
      expect(verdict.decided, isTrue);
    });

    test('пока текущий не ответил, соседи ничего не решают', () {
      // Результаты приходят по мере готовности. Сервер, который просто
      // дальше соседей, иначе проигрывал бы гонку и покидался живым.
      final verdict = AutoServerSelect.judge(
        currentId: 'cur',
        results: [_ok('a', 40), _ok('b', 60), _ok('c', 90)],
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

    test('отказ текущего и первый живой сосед — не ждём конца замера', () {
      // Живой тест: Vless отказал через 0,7 с, а замер ещё 3,7 с ждал
      // таймаута сервера, который к решению отношения не имел.
      final verdict = AutoServerSelect.judge(
        currentId: 'cur',
        results: [_dead('cur'), _ok('alive', 80)],
        batchComplete: false,
      );
      expect(verdict.nextId, 'alive');
    });

    test('отказ текущего, соседи ещё молчат — ждём соседей', () {
      final verdict = AutoServerSelect.judge(
        currentId: 'cur',
        results: [_dead('cur'), _dead('x')],
        batchComplete: false,
      );
      expect(verdict.decided, isFalse);
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
      // Только отказ и ловит сервер, отвечающий сбросом соединения: сброс —
      // пришедший байт, тишины нет. Будить — не значит менять: решает замер.
      expect(AutoSelectWatchdog.dialFailuresSuggestDeadServer(1), isTrue);
      expect(AutoSelectWatchdog.dialFailuresSuggestDeadServer(0), isFalse);
    });

    test('живой сервер тишины не набирает', () {
      // Отправленное подтверждается самое позднее в следующую секунду.
      var s = const SilenceStreak();
      for (var i = 0; i < 20; i++) {
        s = s.next(sent: 400, received: 0);
        expect(AutoSelectWatchdog.trafficStalled(s.silent), isFalse);
        s = s.next(sent: 0, received: 60);
      }
    });

    test('мёртвый сервер набирает тишину и через паузы повторов', () {
      // Приложения долбят мёртвый сервер не каждую секунду: между повторами
      // пустые секунды, и они счёт не сбрасывают.
      var s = const SilenceStreak();
      s = s.next(sent: 300, received: 0);
      s = s.next(sent: 0, received: 0);
      s = s.next(sent: 0, received: 0);
      expect(AutoSelectWatchdog.trafficStalled(s.silent), isFalse);
      s = s.next(sent: 300, received: 0);
      expect(AutoSelectWatchdog.trafficStalled(s.silent), isTrue);
    });

    test('далёкие тихие секунды в тревогу не складываются', () {
      var s = const SilenceStreak();
      s = s.next(sent: 300, received: 0);
      for (var i = 0; i <= AutoSelectWatchdog.streakGapSeconds; i++) {
        s = s.next(sent: 0, received: 0);
      }
      s = s.next(sent: 300, received: 0);
      expect(s.silent, 1);
    });

    test('любой пришедший байт — тишина с нуля', () {
      var s = const SilenceStreak();
      s = s.next(sent: 300, received: 0);
      s = s.next(sent: 300, received: 1);
      expect(s.silent, 0);
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

    test('страховка: ушло и ничего не пришло — зовём судью', () {
      expect(
        AutoSelectWatchdog.shouldProbe(
          connected: true,
          autoSelectOn: true,
          trafficMoved: false,
          trafficSent: true,
        ),
        isTrue,
      );
    });

    test('страховка: пришло — сервер отвечает', () {
      expect(
        AutoSelectWatchdog.shouldProbe(
          connected: true,
          autoSelectOn: true,
          trafficMoved: true,
          trafficSent: true,
        ),
        isFalse,
      );
    });

    test('страховка: телефон лежит — замер никто не просил', () {
      // Живой тест: без этого ядро замера поднималось раз в полминуты.
      expect(
        AutoSelectWatchdog.shouldProbe(
          connected: true,
          autoSelectOn: true,
          trafficMoved: false,
          trafficSent: false,
        ),
        isFalse,
      );
    });

    test('страховка молчит при выключенном автовыборе', () {
      expect(
        AutoSelectWatchdog.shouldProbe(
          connected: true,
          autoSelectOn: false,
          trafficMoved: false,
          trafficSent: true,
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
