import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/core/connections_poll_stats.dart';
import 'package:keqdroid/tunnel/connection_mode.dart';
import 'package:keqdroid/tunnel/desktop_traffic_stats.dart';
import 'package:keqdroid/tunnel/tunnel_state.dart';

import '../helpers/fake_clash_api.dart';

class _Stats with DesktopTrafficStats {
  int polls = 0;
  Completer<void>? hold;

  @override
  void emit(VpnState state) {}

  @override
  ConnectionMode? get activeMode => ConnectionMode.proxy;

  @override
  Future<void> pollTrafficStats(ConnectionMode mode, {bool force = false}) {
    polls++;
    return hold?.future ?? Future<void>.value();
  }
}

Future<void> _waitFor(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not reached in time');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  late StallingClashApi core;

  setUp(() async => core = await StallingClashApi.start());
  tearDown(() => core.close());

  test(
    'одна неудача снимает сотни висящих запросов без переполнения стека',
    () async {
      final stats = _Stats();
      final base = ConnectionsPollStats.instance.inFlight;
      const hung = 300;
      final requests = [
        for (var i = 0; i < hung; i++) stats.queryClashTraffic(core.port),
      ];
      await _waitFor(
        () => ConnectionsPollStats.instance.inFlight - base >= hung,
      );

      // Отказ на соединении: тот же клиент сбрасывается и рвёт висящие.
      expect(await stats.queryClashTraffic(await closedLoopbackPort()), isNull);

      final results = await Future.wait(
        requests,
      ).timeout(const Duration(seconds: 5));
      expect(results, everyElement(isNull));
      expect(ConnectionsPollStats.instance.inFlight, base);
      stats.stopStatsLoop();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'недосланное тело — отказ по сроку, а не вечное ожидание',
    () async {
      final stats = _Stats();
      final result = await stats
          .queryClashTraffic(core.port)
          .timeout(connectionsBodyTimeout + const Duration(seconds: 5));
      expect(result, isNull);
      stats.stopStatsLoop();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('секундный опрос ждёт прошлый, а не шлёт вдогонку', () async {
    final stats = _Stats()..hold = Completer<void>();
    stats.startStatsLoop(ConnectionMode.proxy);
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    expect(stats.polls, 1, reason: 'такты, пока первый опрос висит, пропущены');

    stats.hold!.complete();
    stats.hold = null;
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    expect(stats.polls, greaterThanOrEqualTo(2));
    stats.stopStatsLoop();
  });
}
