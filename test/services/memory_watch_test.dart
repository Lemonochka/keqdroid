import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/core/connections_poll_stats.dart';
import 'package:keqdroid/services/memory_watch.dart';

const _mb = 1024 * 1024;

void main() {
  group('когда снимать слепок', () {
    final t0 = DateTime(2026, 9, 27, 20, 0);
    DateTime at(int minutes) => t0.add(Duration(minutes: minutes));

    test('раз в десять минут, если ничего не происходит', () {
      final schedule = MemoryWatchSchedule();
      final reasons = [
        for (var m = 1; m <= 20; m++) schedule.onBeat(at(m)).reason,
      ];
      expect(reasons.whereType<String>(), ['periodic', 'periodic']);
      expect(reasons[9], 'periodic');
      expect(reasons[19], 'periodic');
    });

    test('после сна — сразу, через минуту и через пять', () {
      final schedule = MemoryWatchSchedule();
      schedule.onBeat(at(1));
      schedule.onBeat(at(2));
      // Такт пришёл через 45 минут: система спала.
      final wake = schedule.onBeat(at(47));
      expect(wake.slept, const Duration(minutes: 45));
      expect(wake.reason, 'after sleep');

      final after = [
        for (var m = 48; m <= 53; m++) schedule.onBeat(at(m)).reason,
      ];
      expect(after, [
        '1 min after sleep',
        null,
        null,
        null,
        '5 min after sleep',
        null,
      ]);
    });

    test('опоздание такта меньше трёх минут сном не считается', () {
      final schedule = MemoryWatchSchedule();
      schedule.onBeat(at(1));
      expect(schedule.onBeat(at(3)).slept, isNull);
    });

    test('при скачке — каждую минуту, пока растёт', () {
      final schedule = MemoryWatchSchedule();
      expect(schedule.onSize(300 * _mb), isNull);
      expect(schedule.onSize(700 * _mb), contains('grew by 400 MB'));
      expect(schedule.onBeat(at(1)).reason, 'growing');
      expect(schedule.onSize(760 * _mb), isNull); // +60 MB, ещё растёт
      expect(schedule.onBeat(at(2)).reason, 'growing');
      expect(schedule.onSize(765 * _mb), isNull); // +5 MB, успокоилось
      expect(schedule.onBeat(at(3)).reason, isNull);
    });

    test('медленный рост ловится порогами 1, 2, 4 ГБ', () {
      final schedule = MemoryWatchSchedule();
      expect(schedule.onSize(900 * _mb), isNull);
      expect(schedule.onSize(1030 * _mb), 'now above 1024 MB');
      expect(schedule.onSize(1200 * _mb), isNull);
      expect(schedule.onSize(2100 * _mb), contains('now above 2048 MB'));
      // Перепрыгнул сразу два порога: сказать надо о последнем.
      expect(schedule.onSize(9000 * _mb), contains('now above 8192 MB'));
    });
  });

  group('строка слепка', () {
    test('Windows: выделенная память, ресурсы, опросы и ядра', () {
      const sample = MemorySample(
        rss: 400 * _mb,
        peakRss: 600 * _mb,
        privateBytes: 530 * _mb,
        threads: 34,
        handles: 812,
        gdiObjects: 45,
        userObjects: 60,
        liveImages: 12,
        imageBytes: 3 * _mb,
        polls: '600 requests, in flight 0 (max 1)',
        cores: {'keqrnel': 120 * _mb},
      );
      expect(sample.size, 530 * _mb);
      expect(
        sample.describe(),
        'private 530 MB, resident 400 MB (peak 600 MB), threads 34, '
        'handles 812, gdi 45, user 60; images 12 live, 3 MB cached; '
        '/connections: 600 requests, in flight 0 (max 1); cores keqrnel 120 MB',
      );
    });

    test(
      'без выделенной памяти растёт резидентная, без ядра так и сказано',
      () {
        const sample = MemorySample(rss: 200 * _mb, peakRss: 250 * _mb);
        expect(sample.size, 200 * _mb);
        expect(sample.describe(), contains('no core running'));
        expect(sample.describe(), isNot(contains('private')));
      },
    );

    test(
      'ядро службы TUN без доступа к счётчикам не притворяется выключенным',
      () {
        const sample = MemorySample(
          rss: 240 * _mb,
          peakRss: 260 * _mb,
          privateBytes: 235 * _mb,
          serviceCores: {'xray'},
        );
        expect(sample.describe(), contains('cores xray (service)'));
        expect(sample.describe(), isNot(contains('no core running')));
      },
    );
  });

  test('сводка опросов /connections: максимумы за период, висящие — как есть', () {
    final stats = ConnectionsPollStats.instance..takeSummary();
    final hanging = stats.begin();
    final done = stats.begin();
    stats.end(done, bodyChars: 4096, connections: 7);
    final failed = stats.begin();
    stats.end(failed, ok: false);

    expect(
      stats.takeSummary(),
      '3 requests, in flight 1 (max 2), failed 1, slow 0, largest 4 KB / 7 connections',
    );
    // Новый период: счёт сначала, а зависший запрос по-прежнему в полёте.
    expect(
      stats.takeSummary(),
      '0 requests, in flight 1 (max 1), failed 0, slow 0, largest 0 B / 0 connections',
    );
    stats.end(hanging, ok: false);
  });
}
