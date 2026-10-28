import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/ping_sample.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/services/auto_select_watchdog.dart';
import 'package:keqdroid/services/auto_server_select.dart';

/// Кого выбирает «Авто».
///
/// Неудачный замер обнуляет `pingMs`, поэтому «красный» сервер и «ни разу не
/// меренный» в списке выглядят одинаково — различает их `lastTestedAt`, и
/// путать их нельзя: первый не работал, а про второй мы просто не знаем.
ServerItem _server(
  String id, {
  required String sub,
  int? ping,
  DateTime? tested,
  String? type,
  List<PingSample> samples = const [],
}) =>
    ServerItem(
      id: id,
      config: 'vless://uuid@$id.example.com:443?type=tcp&security=none#$id',
      type: ServerItemType.subscription,
      subscriptionId: sub,
      addedAt: DateTime(2026),
      pingMs: ping,
      lastTestedAt: tested,
      lastPingType: type,
      pingSamples: samples,
    );

void main() {
  final tested = DateTime(2026, 9, 22);

  test('берёт лучший по замеру внутри своей подписки', () {
    final servers = [
      _server('a', sub: 's1', ping: 120, tested: tested),
      _server('b', sub: 's1', ping: 40, tested: tested),
      // Чужая подписка быстрее, но она не наше дело.
      _server('c', sub: 's2', ping: 10, tested: tested),
    ];

    expect(
      AutoServerSelect.pick(servers, subscriptionId: 's1')?.id,
      'b',
    );
  });

  test('сервер, с которого съехали, второй раз не берём', () {
    final servers = [
      _server('a', sub: 's1', ping: 40, tested: tested),
      _server('b', sub: 's1', ping: 90, tested: tested),
    ];

    expect(
      AutoServerSelect.pick(servers, subscriptionId: 's1', exclude: 'a')?.id,
      'b',
    );
  });

  test('соседей умершего по адресу обходим', () {
    // Живой тест: погасили VPS, а его же Vless остался в списке со старым
    // хорошим пингом. Протоколы на одной машине умирают вместе.
    final servers = [
      _server('pl-hy2', sub: 's1', ping: 38, tested: tested),
      _server('pl-vless', sub: 's1', ping: 40, tested: tested),
      _server('ru-hy2', sub: 's1', ping: 90, tested: tested),
    ];
    // У обоих польских один адрес — как у двух протоколов на одном VPS.
    final samehost = [
      for (final s in servers)
        s.id.startsWith('pl')
            ? ServerItem(
                id: s.id,
                config: 'vless://uuid@pl.example.com:443?type=tcp&security=none#${s.id}',
                type: ServerItemType.subscription,
                subscriptionId: 's1',
                addedAt: DateTime(2026),
                pingMs: s.pingMs,
                lastTestedAt: tested,
              )
            : s,
    ];

    expect(
      AutoServerSelect.pick(
        samehost,
        subscriptionId: 's1',
        exclude: 'pl-hy2',
        excludeHost: 'pl.example.com',
      )?.id,
      'ru-hy2',
    );
  });

  test('если на других адресах никого, сосед лучше пустоты', () {
    final servers = [
      _server('a', sub: 's1', ping: 40, tested: tested),
      _server('b', sub: 's1', ping: 60, tested: tested),
    ];

    expect(
      AutoServerSelect.pick(
        servers,
        subscriptionId: 's1',
        exclude: 'a',
        excludeHost: 'b.example.com',
      )?.id,
      'b',
    );
  });

  test('единственный сервер берём даже после отказа', () {
    // «Совсем никого» и «один и тот же» — разные вещи: во втором случае
    // честнее попробовать ещё раз, чем не подключаться вовсе.
    final servers = [_server('a', sub: 's1', ping: 40, tested: tested)];

    expect(
      AutoServerSelect.pick(servers, subscriptionId: 's1', exclude: 'a')?.id,
      'a',
    );
  });

  test('непомеренный идёт раньше того, чей замер провалился', () {
    final servers = [
      _server('failed', sub: 's1', tested: tested),
      _server('unknown', sub: 's1'),
    ];

    expect(
      AutoServerSelect.pick(servers, subscriptionId: 's1')?.id,
      'unknown',
    );
  });

  test('когда все красные — всё равно кто-то, а не пустота', () {
    final servers = [
      _server('a', sub: 's1', tested: tested),
      _server('b', sub: 's1', tested: tested),
    ];

    expect(AutoServerSelect.pick(servers, subscriptionId: 's1'), isNotNull);
  });

  test('подписка без серверов не выбирает никого', () {
    expect(
      AutoServerSelect.pick(
        [_server('a', sub: 's2', ping: 10, tested: tested)],
        subscriptionId: 's1',
      ),
      isNull,
    );
  });

  test('в замер идут текущий и лучшие соседи, не вся подписка', () {
    final servers = [
      for (var i = 0; i < 15; i++)
        _server('s$i', sub: 's1', ping: 10 + i, tested: tested),
      _server('other-sub', sub: 's2', ping: 1, tested: tested),
    ];
    final current = servers[7];

    final picked = AutoServerSelect.candidatesToMeasure(
      servers,
      subscriptionId: 's1',
      current: current,
      limit: 5,
    );

    // Сам текущий — первым: уйти с него можно только по его же замеру.
    expect(picked.first.id, 's7');
    expect(picked.length, 5);
    expect(picked.map((s) => s.id), isNot(contains('other-sub')));
    // Соседи — по старым замерам, лучшие первыми.
    expect(picked.skip(1).map((s) => s.id), ['s0', 's1', 's2', 's3']);
  });

  group('оценка по истории замеров', () {
    final now = DateTime(2026, 10, 6, 12);
    List<PingSample> history(List<int?> values, {String type = 'url'}) => [
          for (var i = 0; i < values.length; i++)
            PingSample(
              at: now.subtract(Duration(minutes: 5 * (values.length - i))),
              ms: values[i],
              type: type,
            ),
        ];

    test('ровный сервер обходит того, у кого пинг скачет', () {
      final servers = [
        _server('jumpy', sub: 's1', ping: 90, tested: now, type: 'url',
            samples: history([80, 400, 90])),
        _server('steady', sub: 's1', ping: 155, tested: now, type: 'url',
            samples: history([150, 160, 155])),
      ];

      expect(AutoServerSelect.pick(servers, subscriptionId: 's1', now: now)?.id,
          'steady');
    });

    test('недавний провал опускает сервер ниже живых без провалов', () {
      final servers = [
        _server('flaky', sub: 's1', ping: 60, tested: now, type: 'url',
            samples: history([70, null, 60])),
        _server('calm', sub: 's1', ping: 210, tested: now, type: 'url',
            samples: history([200, 210])),
      ];

      expect(AutoServerSelect.pick(servers, subscriptionId: 's1', now: now)?.id,
          'calm');
    });

    test('замеры старше суток не считаются', () {
      final old = PingSample(
        at: now.subtract(const Duration(days: 2)),
        ms: null,
        type: 'url',
      );
      final server = _server('a', sub: 's1', ping: 100, tested: now,
          type: 'url', samples: [old, ...history([100])]);

      expect(AutoServerSelect.latencyScore(server, now), 100);
    });

    test('замеры другим методом с текущими не смешиваются', () {
      final server = _server('a', sub: 's1', ping: 100, tested: now,
          type: 'url',
          samples: [...history([5, 900], type: 'tcp'), ...history([100])]);

      expect(AutoServerSelect.latencyScore(server, now), 100);
    });

    test('без истории оценка — последний замер, как раньше', () {
      final server = _server('a', sub: 's1', ping: 120, tested: now);

      expect(AutoServerSelect.latencyScore(server, now), 120);
    });
  });

  test('после теста скорости выбирается самый быстрый, а не самый медленный',
      () {
    // У теста скорости в поле пинга кбит/с, и больше — лучше.
    final servers = [
      _server('slow', sub: 's1', ping: 3000, tested: tested, type: 'speed'),
      _server('fast', sub: 's1', ping: 90000, tested: tested, type: 'speed'),
    ];

    expect(AutoServerSelect.pick(servers, subscriptionId: 's1')?.id, 'fast');
  });

  test('свой сервер автовыбора попадает в замер, даже если он в хвосте', () {
    final servers = [
      for (var i = 0; i < 6; i++)
        _server('s$i', sub: 's1', ping: 10 + i, tested: tested),
      _server('home', sub: 's1', tested: tested),
    ];

    final picked = AutoServerSelect.candidatesToMeasure(
      servers,
      subscriptionId: 's1',
      current: servers[3],
      limit: 4,
      include: {'home'},
    );

    expect(picked.map((s) => s.id), ['s3', 'home', 's0', 's1']);
  });

  test('свой сервер из соседней подписки тоже попадает в замер', () {
    // Автовыбор уехал в соседнюю подписку и ждёт свой сервер в родной.
    final servers = [
      _server('b1', sub: 'neighbour', ping: 50, tested: tested),
      _server('b2', sub: 'neighbour', ping: 60, tested: tested),
      _server('home', sub: 'own', ping: 40, tested: tested),
    ];

    final picked = AutoServerSelect.candidatesToMeasure(
      servers,
      subscriptionId: 'neighbour',
      current: servers[0],
      limit: 4,
      include: {'home'},
    );

    expect(picked.map((s) => s.id), ['b1', 'home', 'b2']);
  });

  test('ежеминутная проверка из соседней подписки меряет только текущий и свой', () {
    final servers = [
      _server('b1', sub: 'neighbour', ping: 50, tested: tested),
      _server('b2', sub: 'neighbour', ping: 10, tested: tested),
      _server('home', sub: 'own', ping: 40, tested: tested),
    ];

    final picked = AutoServerSelect.candidatesToMeasure(
      servers,
      subscriptionId: 'neighbour',
      current: servers[0],
      limit: NeighbourHomePace.measureLimit,
      include: {'home'},
    );

    expect(picked.map((s) => s.id), ['b1', 'home']);
  });

  group('записывать ли замер', () {
    ({String id, bool success, int? latencyMs}) ok(String id) =>
        (id: id, success: true, latencyMs: 100);
    ({String id, bool success, int? latencyMs}) dead(String id) =>
        (id: id, success: false, latencyMs: null);

    test('не ответил никто — не пишем: это сеть, а не серверы', () {
      // Лифт или метро: иначе лучшие серверы сутки висели бы красными
      // и уходили в конец очереди замеров.
      expect(
        AutoServerSelect.worthRecording([dead('a'), dead('b'), dead('c')]),
        isFalse,
      );
      expect(AutoServerSelect.worthRecording(const []), isFalse);
    });

    test('ответил хоть один — сеть жива, отказы остальных правда', () {
      expect(
        AutoServerSelect.worthRecording([dead('a'), ok('b'), dead('c')]),
        isTrue,
      );
    });
  });

  group('соседние подписки', () {
    const order = ['top', 'empty', 'own', 'below', 'bottom'];
    const withServers = {'top', 'own', 'below', 'bottom'};

    test('ближайшая выше и ближайшая ниже, пустую пропускаем', () {
      // Пустую подписку на экране не видно, соседом она не считается.
      expect(
        AutoServerSelect.neighbourSubscriptions(
          order,
          ownerId: 'own',
          withServers: withServers,
        ),
        ['top', 'below'],
      );
    });

    test('у верхней подписки сосед только снизу', () {
      expect(
        AutoServerSelect.neighbourSubscriptions(
          order,
          ownerId: 'top',
          withServers: withServers,
        ),
        ['own'],
      );
    });

    test('единственная подписка соседей не имеет', () {
      expect(
        AutoServerSelect.neighbourSubscriptions(
          const ['own'],
          ownerId: 'own',
          withServers: const {'own'},
        ),
        isEmpty,
      );
    });

    test('контроль — по два лучших из каждой соседней', () {
      final servers = [
        _server('t1', sub: 'top', ping: 300, tested: tested),
        _server('t2', sub: 'top', ping: 100, tested: tested),
        _server('t3', sub: 'top', ping: 200, tested: tested),
        _server('b1', sub: 'below', ping: 90, tested: tested),
        _server('o1', sub: 'own', ping: 10, tested: tested),
      ];

      final picked = AutoServerSelect.controls(
        servers,
        subscriptionIds: const ['top', 'below'],
        perSubscription: 2,
        skip: const {'t2'},
      );

      expect(picked.map((s) => s.id), ['t3', 't1', 'b1']);
    });
  });

  group('на кого переезжать', () {
    final now = DateTime(2026, 10, 28, 12);
    List<PingSample> history(List<int?> values) => [
          for (var i = 0; i < values.length; i++)
            PingSample(
              at: now.subtract(Duration(minutes: 5 * (values.length - i))),
              ms: values[i],
              type: 'url',
            ),
        ];

    test('ровный обходит того, кто сегодня скакал и падал', () {
      final jumpy = _server('jumpy', sub: 's1',
          samples: history([80, null, 400]));
      final steady = _server('steady', sub: 's1',
          samples: history([150, 160]));

      expect(
        AutoServerSelect.switchScore(jumpy, 70, now),
        greaterThan(AutoServerSelect.switchScore(steady, 155, now)),
      );
    });

    test('без истории решает сам ответ', () {
      expect(
        AutoServerSelect.switchScore(_server('a', sub: 's1'), 120, now),
        120,
      );
      expect(AutoServerSelect.switchScore(null, 120, now), 120);
    });

    test('судья берёт ровного, даже если тот ответил медленнее', () {
      final servers = {
        'jumpy': _server('jumpy', sub: 's1', samples: history([80, null, 400])),
        'steady': _server('steady', sub: 's1', samples: history([150, 160])),
      };
      final verdict = AutoServerSelect.judge(
        currentId: 'cur',
        results: [
          (id: 'cur', success: false, latencyMs: null),
          (id: 'jumpy', success: true, latencyMs: 70),
          (id: 'steady', success: true, latencyMs: 155),
        ],
        batchComplete: true,
        score: (id, ms) =>
            AutoServerSelect.switchScore(servers[id], ms, now),
      );

      expect(verdict.nextId, 'steady');
    });
  });
}
