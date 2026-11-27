import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/probe_results.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/auto_select_home.dart';
import 'package:keqdroid/services/core_dial_failures.dart';
import 'package:keqdroid/services/names_fallback.dart';
import 'package:keqdroid/services/ping_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/tunnel/tunnel_backend.dart';
import 'package:keqdroid/tunnel/vpn_backend.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

// Сторож автовыбора целиком, через VpnStateNotifier: когда просыпается, когда меняет
// сервер и что делает, когда замер никто не прошёл. Тесты идут на ПК-ветке кода
// (Platform.isAndroid ложно), поэтому порог тишины здесь пять секунд, а не две.

const _hosts = {'own1': 11, 'own2': 12, 'own3': 13, 'nb1': 21, 'nb2': 22};

String _ip(String id) => '198.51.100.${_hosts[id]}';

ServerItem _server(String id, String subscriptionId) => ServerItem(
  id: id,
  type: ServerItemType.subscription,
  subscriptionId: subscriptionId,
  config:
      'vless://00000000-0000-4000-8000-000000000000@${_ip(id)}:443'
      '?type=tcp&security=tls&sni=example.com#$id',
);

final _own = [
  _server('own1', 'own'),
  _server('own2', 'own'),
  _server('own3', 'own'),
];
final _neighbours = [_server('nb1', 'nb'), _server('nb2', 'nb')];

late DateTime _now;

void _wait(Duration d) => _now = _now.add(d);

Future<void> _drain() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _Backend extends FakeTunnelBackend {
  final _states = StreamController<VpnState>.broadcast();
  VpnState current = VpnState.disconnected;
  final sessions = <String?>[];

  // задержка ответа в мс; кого здесь нет, тот молчит
  final latency = <String, int>{};
  final measured = <String>[];
  Completer<void>? hold;
  bool held = false;

  int down = 0;
  int up = 0;
  int counterReads = 0;

  void emit(VpnState state) => _states.add(state);

  @override
  Stream<VpnState> get stateStream => _states.stream;

  @override
  Future<VpnState> getCurrentState() async => current;

  @override
  Future<void> startSession(TunnelSessionRequest request) async {
    sessions.add(request.serverName);
    current = const VpnState(status: VpnStatus.connected);
  }

  @override
  Future<void> stopSession() async {
    current = VpnState.disconnected;
    _states.add(VpnState.disconnected);
  }

  @override
  Future<({int down, int up})?> sessionTrafficCounters() async {
    counterReads++;
    return (down: down, up: up);
  }

  ServerUrlTestResult _answer(String serverId, String resultId) {
    measured.add(serverId);
    final ms = latency[serverId];
    return (
      id: resultId,
      success: ms != null,
      latencyMs: ms,
      error: ms == null ? 'timeout' : '',
      httpStatus: ms == null ? null : 204,
    );
  }

  @override
  Future<List<ServerUrlTestResult>?> xrayUrlTestMulti({
    required String config,
    required List<(String id, int port)> probes,
    VpnBackend core = VpnBackend.xray,
    String testUrl = 'https://connectivitycheck.gstatic.com/generate_204',
    int timeoutMs = 15000,
    bool keepAlive = true,
    int concurrency = 16,
    UrlTestProgress? onEach,
  }) async {
    final gate = hold;
    if (gate != null) {
      held = true;
      await gate.future;
    }
    return [for (final (id, _) in probes) _answer(id, id)];
  }

  // одиночный замер приходит с id single, сервер узнаём по адресу в конфиге
  @override
  Future<List<ServerUrlTestResult>> xrayUrlTestBatch({
    required List<(String id, String xrayConfig)> items,
    required int socksPort,
    VpnBackend core = VpnBackend.xray,
    String testUrl = 'https://connectivitycheck.gstatic.com/generate_204',
    int timeoutMs = 15000,
    bool keepAlive = true,
  }) async => [
    for (final (id, config) in items)
      _answer(
        _hosts.keys.firstWhere((s) => config.contains('"${_ip(s)}"')),
        id,
      ),
  ];

  @override
  void dispose() {
    unawaited(_states.close());
    super.dispose();
  }
}

class _CapturedTimer implements Timer {
  _CapturedTimer(this.period, this._callback);

  final Duration period;
  final void Function(Timer) _callback;

  @override
  bool isActive = true;

  @override
  int tick = 0;

  void fire() {
    tick++;
    _callback(this);
  }

  @override
  void cancel() => isActive = false;
}

class _Rig {
  _Rig(
    this.container,
    this.backend,
    this._capturedTimers,
    this._otherTimers,
    this._timerZone,
  );

  final ProviderContainer container;
  final _Backend backend;
  final List<_CapturedTimer> _capturedTimers;
  final List<_CapturedTimer> _otherTimers;
  final Zone _timerZone;

  List<_CapturedTimer> get timers =>
      _capturedTimers.where((t) => !_otherTimers.contains(t)).toList();

  VpnStateNotifier get vpn => container.read(vpnStateProvider.notifier);

  String? get active => container.read(serversProvider).activeServerId;

  Future<T> capture<T>(Future<T> Function() action) => _timerZone.run(action);

  ServerItem server(String id) =>
      container.read(serversProvider).servers.firstWhere((s) => s.id == id);

  Future<void> second({int sent = 1000, int received = 0}) async {
    backend
      ..up += sent
      ..down += received;
    await vpn.debugAutoSelectListen();
  }

  // первое чтение счётчиков только точка отсчёта, дальше пять тихих секунд
  Future<void> stall() async {
    for (var i = 0; i < 6; i++) {
      await second();
    }
  }

  Future<void> totals({required int sent, required int received}) async {
    backend.emit(
      VpnState(
        status: VpnStatus.connected,
        totalUpload: sent,
        totalDownload: received,
      ),
    );
    await _drain();
  }

  Future<void> recheckAfter(Duration d) async {
    _wait(d);
    backend.down += 1000;
    await vpn.debugAutoSelectRecheck();
  }
}

Future<_Rig> _rig({bool neighbours = false, bool autoSelect = true}) async {
  final servers = [..._own, if (neighbours) ..._neighbours];
  final storage = await buildStorageService();
  await storage.saveSubscriptions([
    Subscription(
      id: 'own',
      name: 'own',
      url: 'https://own.example/sub',
      autoSelectVisible: true,
      autoSelect: autoSelect,
    ),
    if (neighbours)
      const Subscription(id: 'nb', name: 'nb', url: 'https://nb.example/sub'),
  ]);
  await storage.saveServers(servers);
  await storage.setActiveServerId('own1');

  final backend = _Backend();
  PingService.debugEngine = VpnEngine.withBackend(backend);
  final container = ProviderContainer(
    overrides: [
      storageProvider.overrideWithValue(storage),
      vpnEngineProvider.overrideWithValue(VpnEngine.withBackend(backend)),
    ],
  );
  addTearDown(container.dispose);
  await container.read(subscriptionsProvider.future);

  // настоящие таймеры тикали бы сами посреди теста: ловим их и зовём вручную
  final timers = <_CapturedTimer>[];
  return runZoned(
    () async {
      container.read(vpnStateProvider);
      expect(timers, isEmpty, reason: 'до подключения сторож не нужен');

      container.read(serversProvider);
      await container.read(vpnStateProvider.future);
      await _until(
        () => container.read(serversProvider).servers.length == servers.length,
      );
      await container.read(vpnStateProvider.notifier).connect();
      expect(
        container.read(vpnStateProvider).value?.status,
        VpnStatus.connected,
      );
      expect(
        [for (final t in timers) t.period],
        [
          if (autoSelect) ...const [
            Duration(seconds: 30),
            Duration(seconds: 1),
            Duration(minutes: 1),
          ],
          NamesFallback.checkEvery,
        ],
      );
      final otherTimers = autoSelect ? timers.sublist(3) : [...timers];
      // хвосты замера пишут пинги через ref, закрытый контейнер их уронил бы
      addTearDown(_drain);
      return _Rig(container, backend, timers, otherTimers, Zone.current);
    },
    zoneSpecification: ZoneSpecification(
      createPeriodicTimer: (self, parent, zone, period, callback) {
        final timer = _CapturedTimer(period, callback);
        timers.add(timer);
        return timer;
      },
    ),
  );
}

Future<void> _jumpToNeighbour(_Rig rig) async {
  rig.backend.latency.addAll({'nb1': 50, 'nb2': 70});
  await rig.stall();
  _wait(const Duration(seconds: 5));
  await rig.stall();
  expect(rig.active, 'nb1');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _now = DateTime.now();
    VpnStateNotifier.debugAutoSelectClock = () => _now;
    PingService.debugMultiPingSupported = true;
  });

  tearDown(() {
    VpnStateNotifier.debugAutoSelectClock = null;
    PingService.debugMultiPingSupported = null;
    PingService.debugEngine = null;
  });

  group('когда просыпается', () {
    test('таймеры: прослушка читает счётчики, перепроверка раз в 5 минут, '
        'проверка на 30 с меряет; закрытие провайдера гасит все три', () async {
      final rig = await _rig();
      rig.backend.latency['own1'] = 100;
      final [probe, listen, recheck] = rig.timers;
      final reads = rig.backend.counterReads;

      listen.fire();
      await _drain();
      expect(rig.backend.counterReads, reads + 1);

      recheck.fire();
      await _drain();
      _wait(const Duration(minutes: 4, seconds: 30));
      recheck.fire();
      await _drain();
      expect(rig.backend.counterReads, reads + 2);
      expect(rig.backend.measured, isEmpty);

      await rig.totals(sent: 1000, received: 0);
      probe.fire();
      await _until(() => rig.backend.measured.isNotEmpty);
      await _drain();
      expect(rig.backend.measured, contains('own1'));

      rig.container.dispose();
      expect([for (final t in rig.timers) t.isActive], [false, false, false]);
    });

    test(
      'автовыбор выключен: ни тишина, ни отказы, ни сроки замер не будят',
      () async {
        final rig = await _rig(autoSelect: false);
        await rig.stall();
        await rig.stall();
        CoreDialFailures.observe('failed to find an available destination');
        await rig.second(received: 1000);
        await rig.totals(sent: 1000, received: 0);
        await rig.vpn.debugAutoSelectProbe();
        await rig.vpn.debugAutoSelectRecheck();
        await rig.recheckAfter(const Duration(minutes: 5));
        await rig.recheckAfter(const Duration(minutes: 5));
        expect(rig.backend.measured, isEmpty);
      },
    );

    test('VPN выключен: таймеры остановлены, сторож молчит', () async {
      final rig = await _rig();
      rig.backend.latency['own1'] = 100;
      await rig.vpn.disconnect();
      await _drain();
      expect(
        rig.container.read(vpnStateProvider).value?.status,
        VpnStatus.disconnected,
      );
      expect(rig.timers.every((t) => !t.isActive), isTrue);
      await rig.stall();
      await rig.stall();
      await rig.vpn.debugAutoSelectProbe();
      await rig.vpn.debugAutoSelectRecheck();
      await rig.recheckAfter(const Duration(minutes: 5));
      await rig.recheckAfter(const Duration(minutes: 5));
      expect(rig.backend.measured, isEmpty);

      await rig.capture(() => rig.vpn.connect());
      expect(
        rig.container.read(vpnStateProvider).value?.status,
        VpnStatus.connected,
      );
      expect(rig.timers, hasLength(6));
      expect(rig.timers.sublist(3).every((t) => t.isActive), isTrue);
    });

    test('выключение автовыбора гасит таймеры и очищает дом, '
        'включение запускает их заново', () async {
      final rig = await _rig();
      await AutoSelectHomeStore.save(
        const AutoSelectHome(
          subscriptionId: 'own',
          homeId: 'own1',
          pickedId: 'own3',
        ),
      );

      await rig.container
          .read(subscriptionsProvider.notifier)
          .editMeta('own', autoSelect: false);
      await _drain();
      expect(rig.timers.every((t) => !t.isActive), isTrue);
      expect(await AutoSelectHomeStore.load(), isNull);

      await rig.capture(
        () => rig.container
            .read(subscriptionsProvider.notifier)
            .handAutoSelectTo('own'),
      );
      await _drain();
      expect(rig.timers, hasLength(6));
      expect(rig.timers.sublist(3).every((t) => t.isActive), isTrue);
    });

    test('обновления телеметрии не пересоздают работающие таймеры', () async {
      final rig = await _rig();
      final initial = [...rig.timers];

      await rig.totals(sent: 1000, received: 500);
      await rig.totals(sent: 2000, received: 1000);

      expect(rig.timers, hasLength(3));
      for (var i = 0; i < initial.length; i++) {
        expect(identical(rig.timers[i], initial[i]), isTrue);
        expect(rig.timers[i].isActive, isTrue);
      }
    });

    test(
      'сервер соседней подписки, выбранный вручную, сторож не ведёт',
      () async {
        final rig = await _rig(neighbours: true);
        Future<void> pick(String id) async {
          await rig.container
              .read(serversProvider.notifier)
              .setActive(rig.server(id));
          await rig.vpn.reconnectToActiveServer();
          rig.backend.measured.clear();
        }

        Future<void> wakeAll() async {
          _wait(const Duration(seconds: 15));
          await rig.stall();
          await rig.stall();
          await rig.totals(sent: rig.backend.up, received: 0);
          await rig.vpn.debugAutoSelectProbe();
        }

        await pick('nb1');
        await wakeAll();
        expect(rig.backend.measured, isEmpty);

        // туда, куда увёз сам автовыбор, а потом соседний сменили руками
        await pick('own1');
        await _jumpToNeighbour(rig);
        await pick('nb2');
        await wakeAll();
        expect(rig.backend.measured, isEmpty);
      },
    );

    test('на ПК проверку будят пять тихих секунд подряд, четыре нет', () async {
      final rig = await _rig();
      rig.backend.latency.addAll({'own1': 100, 'own2': 120, 'own3': 140});

      for (var i = 0; i < 5; i++) {
        await rig.second();
      }
      expect(rig.backend.measured, isEmpty);

      await rig.second();
      expect(rig.backend.measured, unorderedEquals(['own1', 'own2', 'own3']));
      expect(rig.active, 'own1');
      expect(rig.backend.sessions, ['own1']);
    });

    test('пришедший ответ обнуляет счёт тишины', () async {
      final rig = await _rig();
      rig.backend.latency['own1'] = 100;

      for (var i = 0; i < 5; i++) {
        await rig.second();
      }
      await rig.second(received: 500);
      for (var i = 0; i < 4; i++) {
        await rig.second();
      }
      expect(rig.backend.measured, isEmpty);

      await rig.second();
      expect(rig.backend.measured, contains('own1'));
    });

    test('после долгого простоя без трафика тишина считается заново', () async {
      final rig = await _rig();
      rig.backend.latency['own1'] = 100;

      for (var i = 0; i < 5; i++) {
        await rig.second();
      }
      for (var i = 0; i < 6; i++) {
        await rig.second(sent: 0);
      }
      for (var i = 0; i < 4; i++) {
        await rig.second();
      }
      expect(rig.backend.measured, isEmpty);

      await rig.second();
      expect(rig.backend.measured, contains('own1'));
    });

    test('новый отказ в журнале ядра будит проверку, а первое чтение счётчика '
        'отказов только точка отсчёта', () async {
      final rig = await _rig();
      rig.backend.latency['own1'] = 100;

      CoreDialFailures.observe('failed to find an available destination');
      await rig.second(received: 1000);
      expect(rig.backend.measured, isEmpty);

      CoreDialFailures.observe('failed to find an available destination');
      await rig.second(received: 1000);
      expect(rig.backend.measured, contains('own1'));
    });

    test('проверка на 30 с: ушло и ничего не пришло будит, пришедшее, новая '
        'сессия и покой нет', () async {
      final rig = await _rig();
      rig.backend.latency['own1'] = 100;

      await rig.totals(sent: 1000, received: 0);
      await rig.vpn.debugAutoSelectProbe();
      expect(rig.backend.measured, contains('own1'));
      rig.backend.measured.clear();

      // 15 с покоя после проверки
      await rig.totals(sent: 2000, received: 0);
      await rig.vpn.debugAutoSelectProbe();
      expect(rig.backend.measured, isEmpty);

      _wait(const Duration(seconds: 15));
      await rig.totals(sent: 3000, received: 0);
      await rig.vpn.debugAutoSelectProbe();
      expect(rig.backend.measured, contains('own1'));
      rig.backend.measured.clear();

      _wait(const Duration(seconds: 15));
      await rig.totals(sent: 4000, received: 500);
      await rig.vpn.debugAutoSelectProbe();
      expect(rig.backend.measured, isEmpty, reason: 'пришёл ответ');

      await rig.totals(sent: 10, received: 0);
      await rig.vpn.debugAutoSelectProbe();
      expect(rig.backend.measured, isEmpty, reason: 'счётчики новой сессии');

      await rig.vpn.debugAutoSelectProbe();
      expect(rig.backend.measured, isEmpty, reason: 'трафика не было');
    });

    test(
      'одна проверка за раз: пока идёт замер, остальные входы молчат',
      () async {
        final rig = await _rig();
        rig.backend.latency.addAll({'own1': 100, 'own2': 120, 'own3': 140});
        rig.backend.hold = Completer<void>();

        for (var i = 0; i < 5; i++) {
          await rig.second();
        }
        final checking = rig.second();
        await _until(() => rig.backend.held);

        await rig.totals(sent: 1000, received: 0);
        await rig.vpn.debugAutoSelectProbe();
        await rig.second();
        await rig.second();

        rig.backend.hold!.complete();
        rig.backend.hold = null;
        await checking;
        // второй замер, если бы его начали, дошёл бы до бэкенда через настоящие сокеты
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await _drain();
        expect(rig.backend.measured, unorderedEquals(['own1', 'own2', 'own3']));
      },
    );
  });

  group('когда меняет сервер', () {
    test(
      'текущий ответил: остаётся, и 15 с тишина проверку не будит',
      () async {
        final rig = await _rig();
        rig.backend.latency.addAll({'own1': 300, 'own2': 50, 'own3': 60});

        await rig.stall();
        expect(rig.backend.measured, contains('own1'));
        expect(rig.active, 'own1');
        expect(rig.backend.sessions, ['own1']);
        expect(await AutoSelectHomeStore.load(), isNull);
        rig.backend.measured.clear();

        _wait(const Duration(seconds: 10));
        for (var i = 0; i < 10; i++) {
          await rig.second();
        }
        expect(rig.backend.measured, isEmpty);

        // после покоя счёт начинается заново, с точки отсчёта
        _wait(const Duration(seconds: 5));
        for (var i = 0; i < 5; i++) {
          await rig.second();
        }
        expect(rig.backend.measured, isEmpty);
        await rig.second();
        expect(rig.backend.measured, contains('own1'));
        expect(rig.active, 'own1');
      },
    );

    test('текущий молчит: переезд на самого быстрого из ответивших, дом '
        'запомнен, следующая проверка не раньше чем через 5 с', () async {
      final rig = await _rig();
      rig.backend.latency.addAll({'own2': 120, 'own3': 80});

      await rig.stall();
      expect(rig.active, 'own3');
      expect(rig.backend.sessions, ['own1', 'own3']);
      final home = await AutoSelectHomeStore.load();
      expect(
        (home?.subscriptionId, home?.homeId, home?.pickedId),
        ('own', 'own1', 'own3'),
      );
      rig.backend.measured.clear();

      await rig.stall();
      expect(rig.backend.measured, isEmpty);

      _wait(const Duration(seconds: 5));
      await rig.stall();
      expect(rig.backend.measured, contains('own3'));
      expect(rig.active, 'own3');
    });

    test('не больше трёх переездов за три минуты', () async {
      final rig = await _rig();
      final latency = rig.backend.latency;

      latency.addAll({'own2': 100});
      await rig.stall();
      expect(rig.active, 'own2');

      _wait(const Duration(seconds: 5));
      latency
        ..clear()
        ..addAll({'own3': 100});
      await rig.stall();
      expect(rig.active, 'own3');

      _wait(const Duration(seconds: 5));
      latency
        ..clear()
        ..addAll({'own1': 100});
      await rig.stall();
      expect(rig.active, 'own1');

      _wait(const Duration(seconds: 5));
      latency
        ..clear()
        ..addAll({'own2': 100});
      rig.backend.measured.clear();
      await rig.stall();
      expect(rig.backend.measured, isNotEmpty);
      expect(rig.active, 'own1', reason: 'четвёртый переезд за три минуты');
      expect(rig.backend.sessions, hasLength(4));

      // первый переезд выпал из окна
      _wait(const Duration(minutes: 2, seconds: 45));
      await rig.stall();
      expect(rig.active, 'own2');
      expect(rig.backend.sessions, hasLength(5));
    });
  });

  group('что делает, когда замер никто не прошёл', () {
    test('соседей нет: виновата сеть, сервер прежний, отказы не пишутся, '
        'пауза растёт 15, 30 с, а пошедший трафик её снимает', () async {
      final rig = await _rig();

      await rig.stall();
      expect(rig.backend.measured, unorderedEquals(['own1', 'own2', 'own3']));
      expect(rig.active, 'own1');
      expect(rig.backend.sessions, ['own1']);
      await _drain();
      for (final s in _own) {
        expect(rig.server(s.id).lastTestedAt, isNull, reason: s.id);
      }
      rig.backend.measured.clear();

      await rig.stall();
      expect(rig.backend.measured, isEmpty, reason: 'пауза 15 с');

      _wait(const Duration(seconds: 15));
      await rig.stall();
      expect(rig.backend.measured, isNotEmpty, reason: 'второй раунд');
      rig.backend.measured.clear();

      _wait(const Duration(seconds: 15));
      await rig.stall();
      expect(rig.backend.measured, isEmpty, reason: 'пауза уже 30 с');

      _wait(const Duration(seconds: 15));
      await rig.stall();
      expect(rig.backend.measured, isNotEmpty, reason: 'третий раунд');
      rig.backend.measured.clear();

      // пауза теперь минута, но ответ из сети заканчивает мёртвую зону сразу
      await rig.second(received: 1000);
      await rig.stall();
      expect(rig.backend.measured, isNotEmpty);
      expect(rig.active, 'own1');
    });

    test('свои молчат, соседняя подписка отвечает: свои отказы пишутся, '
        'переезд к соседу на втором раунде, дом остаётся своим', () async {
      final rig = await _rig(neighbours: true);
      rig.backend.latency.addAll({'nb1': 50, 'nb2': 70});

      await rig.stall();
      expect(
        rig.backend.measured,
        unorderedEquals(['own1', 'own2', 'own3', 'nb1', 'nb2']),
      );
      expect(rig.active, 'own1');
      expect(rig.backend.sessions, ['own1']);
      await _drain();
      expect(rig.server('own1').lastTestedAt, isNotNull);

      // подписка под подозрением: второй раунд через 5 с, а не через 15
      _wait(const Duration(seconds: 5));
      await rig.stall();
      expect(rig.active, 'nb1');
      expect(rig.backend.sessions, ['own1', 'nb1']);
      final home = await AutoSelectHomeStore.load();
      expect(
        (home?.subscriptionId, home?.homeId, home?.pickedId),
        ('own', 'own1', 'nb1'),
      );
    });

    test('молчат и свои, и соседи: виновата сеть, отказы не пишутся, и такой '
        'раунд не засчитывается подписке', () async {
      final rig = await _rig(neighbours: true);

      await rig.stall();
      expect(rig.backend.measured, containsAll(['own1', 'nb1', 'nb2']));
      expect(rig.active, 'own1');
      await _drain();
      for (final s in [..._own, ..._neighbours]) {
        expect(rig.server(s.id).lastTestedAt, isNull, reason: s.id);
      }

      _wait(const Duration(seconds: 15));
      rig.backend.latency.addAll({'nb1': 50, 'nb2': 70});
      await rig.stall();
      expect(
        rig.active,
        'own1',
        reason: 'это первый раунд подписки, не второй',
      );

      _wait(const Duration(seconds: 5));
      await rig.stall();
      expect(rig.active, 'nb1');
    });
  });

  group('перепроверка и возврат домой', () {
    test('плановая раз в 5 минут и только когда шёл трафик', () async {
      final rig = await _rig();
      rig.backend.latency.addAll({'own1': 100, 'own2': 120, 'own3': 140});

      await rig.vpn.debugAutoSelectRecheck();
      await rig.recheckAfter(const Duration(minutes: 1));
      // первая плановая только запоминает счётчик байтов
      await rig.recheckAfter(const Duration(minutes: 3, seconds: 30));
      expect(rig.backend.measured, isEmpty);

      await rig.recheckAfter(const Duration(minutes: 4, seconds: 30));
      expect(rig.backend.measured, unorderedEquals(['own1', 'own2', 'own3']));
      expect(rig.active, 'own1');
      rig.backend.measured.clear();

      _wait(const Duration(minutes: 4, seconds: 30));
      await rig.vpn.debugAutoSelectRecheck();
      expect(rig.backend.measured, isEmpty, reason: 'трафика не было');
    });

    test('после переезда внутри подписки домой возвращает плановая, когда дом '
        'ответил два раза подряд', () async {
      final rig = await _rig();
      rig.backend.latency.addAll({'own2': 100});
      await rig.stall();
      expect(rig.active, 'own2');
      rig.backend.measured.clear();

      rig.backend.latency['own1'] = 50;
      await rig.vpn.debugAutoSelectRecheck();
      await rig.recheckAfter(const Duration(minutes: 4, seconds: 30));
      expect(rig.backend.measured, isEmpty);

      rig.backend.measured.clear();
      await rig.recheckAfter(const Duration(minutes: 4, seconds: 30));
      expect(rig.backend.measured, containsAll(['own2', 'own1']));
      expect(rig.active, 'own2');
      expect((await AutoSelectHomeStore.load())?.aliveStreak, 1);

      await rig.recheckAfter(const Duration(minutes: 4, seconds: 30));
      expect(rig.active, 'own1');
      expect(rig.backend.sessions, ['own1', 'own2', 'own1']);
      expect(await AutoSelectHomeStore.load(), isNull);
    });

    test('на сервере соседней подписки свой проверяют каждую минуту и '
        'возвращаются после двух ответов подряд', () async {
      final rig = await _rig(neighbours: true);
      await _jumpToNeighbour(rig);

      rig.backend.latency['own1'] = 60;
      await rig.vpn.debugAutoSelectRecheck();
      rig.backend.measured.clear();

      await rig.recheckAfter(const Duration(minutes: 1));
      expect(rig.backend.measured, unorderedEquals(['nb1', 'own1']));
      expect(rig.active, 'nb1');

      await rig.recheckAfter(const Duration(minutes: 1));
      expect(rig.active, 'own1');
      expect(rig.backend.sessions, ['own1', 'nb1', 'own1']);
      expect(await AutoSelectHomeStore.load(), isNull);
    });

    test('свой не ответил пять минутных проверок подряд: пауза 15 минут, '
        'плановая идёт своим чередом', () async {
      final rig = await _rig(neighbours: true);
      await _jumpToNeighbour(rig);
      await rig.vpn.debugAutoSelectRecheck();

      Future<bool> minute() async {
        rig.backend.measured.clear();
        await rig.recheckAfter(const Duration(minutes: 1));
        return rig.backend.measured.isNotEmpty;
      }

      // пятая минута плановая, она в счёт промахов не идёт
      expect(
        [for (var i = 0; i < 7; i++) await minute()],
        [true, true, true, true, true, true, false],
      );

      rig.backend.measured.clear();
      await rig.recheckAfter(const Duration(minutes: 13));
      expect(rig.backend.measured, isNotEmpty, reason: 'плановая');

      expect(await minute(), isTrue, reason: 'пауза кончилась');
      expect(rig.backend.measured, unorderedEquals(['nb1', 'own1']));
      expect(rig.active, 'nb1');
    });
  });
}
