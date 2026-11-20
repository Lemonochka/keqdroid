part of 'providers.dart';

typedef _AutoTarget = ({ServerItem server, String subId, String ownerId});

class _AutoSelectMonitor {
  _AutoSelectMonitor({
    required Ref Function() ref,
    required VpnState? Function() vpnState,
    required Future<void> Function() reconnect,
    required DateTime Function() now,
  }) : _readRef = ref,
       _readVpnState = vpnState,
       _reconnect = reconnect,
       _now = now;

  // ref спрашиваем у уведомителя каждый раз: Riverpod 3 создаёт новый на каждой сборке, а уведомитель остаётся прежним
  final Ref Function() _readRef;
  final VpnState? Function() _readVpnState;
  final Future<void> Function() _reconnect;
  final DateTime Function() _now;

  Ref get ref => _readRef();

  VpnState? get _vpnState => _readVpnState();

  Timer? _probeTimer;
  Timer? _listenTimer;
  int _seenReceived = 0;
  int _seenSent = 0;
  int? _seenFailures;
  SilenceStreak _silence = const SilenceStreak();
  ({int down, int up})? _counters;
  final _switches = <DateTime>[];
  DateTime? _quietUntil;
  bool _busy = false;

  bool _listening = false;

  Timer? _recheckTimer;
  DateTime? _recheckAt;
  NeighbourHomePace _homePace = const NeighbourHomePace();
  int? _recheckSeenBytes;
  SubscriptionOutage _outage = const SubscriptionOutage();
  int _deadRounds = 0;
  int? _networkMark;

  void start() {
    _probeTimer?.cancel();
    _probeTimer = Timer.periodic(
      AutoSelectWatchdog.probeEvery,
      (_) => unawaited(probe()),
    );
    _listenTimer?.cancel();
    _listenTimer = Timer.periodic(
      AutoSelectWatchdog.listenEvery,
      (_) => unawaited(listenOnce()),
    );
    _recheckTimer?.cancel();
    _recheckTimer = Timer.periodic(
      NeighbourHomePace.every,
      (_) => unawaited(recheckTick()),
    );
  }

  void stop() {
    _probeTimer?.cancel();
    _listenTimer?.cancel();
    _recheckTimer?.cancel();
  }

  Future<_AutoTarget?> _target() async {
    if (_vpnState?.status != VpnStatus.connected) return null;
    final server = ref.read(serversProvider).activeServer;
    final subId = server?.subscriptionId;
    if (server == null || subId == null) return null;
    final subs =
        ref.read(subscriptionsProvider).value ?? const <Subscription>[];
    final own = subs.where((s) => s.id == subId).firstOrNull;
    if (own != null && own.autoSelect) {
      return (server: server, subId: subId, ownerId: subId);
    }
    final owner = subs.where((s) => s.autoSelect).firstOrNull;
    if (owner == null) return null;
    // в соседней подписке ведём только сервер, куда увёз сам автовыбор: выбранный из трея или горячей клавишей не наш
    final home = await AutoSelectHomeStore.load();
    if (home == null ||
        home.subscriptionId != owner.id ||
        home.pickedId != server.id ||
        !_family(owner.id).contains(subId)) {
      return null;
    }
    return (server: server, subId: subId, ownerId: owner.id);
  }

  List<String> _family(String ownerId) {
    final subs =
        ref.read(subscriptionsProvider).value ?? const <Subscription>[];
    return [
      ownerId,
      ...AutoServerSelect.neighbourSubscriptions(
        [for (final s in subs) s.id],
        ownerId: ownerId,
        withServers: {
          for (final s in ref.read(serversProvider).servers) ?s.subscriptionId,
        },
      ),
    ];
  }

  int _limit(_AutoTarget target) => _outage.suspects(target.subId)
      ? AutoSelectWatchdog.suspectLimit
      : AutoSelectWatchdog.candidateLimit;

  int _score(String id, int latencyMs) => AutoServerSelect.switchScore(
    ref.read(serversProvider).servers.where((s) => s.id == id).firstOrNull,
    latencyMs,
    _now(),
  );

  // Android знает, есть ли под туннелем сеть вообще: без неё замер только жжёт батарею
  Future<bool> _offline() async {
    final net = await VpnNativeBridge.physicalNetworks();
    if (net == null || net.count > 0) return false;
    AppLogger.instance.info(
      'Auto select: no network under the tunnel, not measuring',
    );
    _rest(net.changes);
    return true;
  }

  void _rest(int? networkMark) {
    _deadRounds++;
    _networkMark = networkMark;
    _quietUntil = _now().add(
      AutoSelectWatchdog.quietAfterRound(deadRounds: _deadRounds),
    );
  }

  // паузу мёртвой зоны кончает и новая сеть, а не только таймер
  Future<bool> _quiet() async {
    final until = _quietUntil;
    if (until == null || !_now().isBefore(until)) return false;
    final mark = _networkMark;
    if (_deadRounds == 0 || mark == null) return true;
    final net = await VpnNativeBridge.physicalNetworks();
    if (net == null || net.count == 0 || net.changes == mark) return true;
    AppLogger.instance.info(
      'Auto select: the network changed, checking right away',
    );
    _quietUntil = null;
    _deadRounds = 0;
    _networkMark = null;
    return false;
  }

  Future<String> _testUrl() async {
    final settings = await ref.read(storageProvider).getSettings();
    final custom = settings.pingTestUrlCustom.trim();
    return settings.pingTestTarget == 'custom' && custom.isNotEmpty
        ? custom
        : kDefaultPingTestUrl;
  }

  _AutoSelectMeasure _startMeasure(
    ServerItem current,
    String subId, {
    int limit = AutoSelectWatchdog.candidateLimit,
    Set<String> include = const {},
  }) => _measure(
    current.id,
    AutoServerSelect.candidatesToMeasure(
      ref.read(serversProvider).servers,
      subscriptionId: subId,
      current: current,
      limit: limit,
      include: include,
    ),
  );

  Future<void> _record(List<PingResult> results) =>
      ref.read(serversProvider.notifier).updatePingResults({
        for (final r in results)
          r.serverId: (
            pingMs: r.success ? r.latencyMs : null,
            lastPingType: PingService.pingTypeToStored(r.pingType),
          ),
      });

  _AutoSelectMeasure _measure(String currentId, List<ServerItem> servers) {
    final measure = _AutoSelectMeasure(currentId);
    ServerLatency entry(PingResult r) =>
        (id: r.serverId, success: r.success, latencyMs: r.latencyMs);
    measure.done = () async {
      try {
        final settings = await ref.read(storageProvider).getSettings();
        final results = await PingService.pingUrlBatch(
          servers,
          settings,
          testUrl: await _testUrl(),
          timeoutSeconds: AutoSelectWatchdog.judgeTimeoutSeconds,
          onResult: (r) => measure.add(entry(r)),
          templateServers: templateServerIds(
            servers,
            settings,
            ref.read(storageProvider).getClashTemplate,
          ),
        );
        for (final r in results) {
          measure.results[r.serverId] = entry(r);
        }
        measure.pings = results;
        unawaited(ref.read(serversProvider.notifier).refreshIpv6Exits(results));
        if (AutoServerSelect.worthRecording(measure.results.values)) {
          unawaited(_record(results));
        }
      } catch (e, st) {
        AppLogger.instance.debug(
          'Auto select measure failed',
          error: e,
          stackTrace: st,
        );
      } finally {
        measure.finish();
      }
    }();
    return measure;
  }

  // замер только после вызова судьи: трафик замера считается ответом сервера и сбивает счёт тишины
  Future<void> listenOnce() async {
    if (_listening) return;
    _listening = true;
    try {
      await _listen();
    } finally {
      _listening = false;
    }
  }

  Future<void> _listen() async {
    if (_busy) return;
    final target = await _target();
    if (target == null) {
      _seenFailures = null;
      _silence = const SilenceStreak();
      _counters = null;
      _outage = const SubscriptionOutage();
      _deadRounds = 0;
      return;
    }
    final quietUntil = _quietUntil;
    final deadZone = _deadRounds > 0;
    if (!deadZone && quietUntil != null && _now().isBefore(quietUntil)) {
      return;
    }

    final second = await _second();
    // трафик пошёл сам: из мёртвой зоны вышли, и следующую тишину проверяем сразу, а не через две минуты
    if (deadZone && (second?.received ?? 0) > 0) {
      _deadRounds = 0;
      _networkMark = null;
      _quietUntil = null;
    }
    if (await _quiet()) return;
    if (second != null) {
      _silence = _silence.next(sent: second.sent, received: second.received);
    }

    final failures = Platform.isAndroid
        ? await VpnNativeBridge.dialFailures()
        : CoreDialFailures.count;
    var newFailures = 0;
    if (failures != null) {
      final previous = _seenFailures;
      _seenFailures = failures;
      // первое чтение только точка отсчёта: счётчик копится с запуска процесса
      if (previous != null) newFailures = failures - previous;
    }

    final stalled = AutoSelectWatchdog.trafficStalled(
      _silence.silent,
      desktop: !Platform.isAndroid,
    );
    if (!stalled &&
        !AutoSelectWatchdog.dialFailuresSuggestDeadServer(newFailures)) {
      return;
    }
    if (await _offline()) return;
    await _decide(
      target,
      _startMeasure(target.server, target.subId, limit: _limit(target)),
      reason: stalled
          ? 'nothing came back for ${_silence.silent} s'
          : '$newFailures failed dial(s) in the core log',
    );
  }

  Future<({int sent, int received})?> _second() async {
    final engine = ref.read(vpnEngineProvider);
    if (Platform.isAndroid) {
      final now = await engine.getCurrentState();
      return (sent: now.uploadSpeed ?? 0, received: now.downloadSpeed ?? 0);
    }
    final counters = await engine.sessionTrafficCounters();
    final previous = _counters;
    _counters = counters;
    if (counters == null || previous == null) return null;
    if (counters.up < previous.up || counters.down < previous.down) return null;
    return (
      sent: counters.up - previous.up,
      received: counters.down - previous.down,
    );
  }

  Future<void> probe() async {
    if (_busy) return;
    final target = await _target();
    if (target == null) return;
    final received = _vpnState?.totalDownload ?? 0;
    final sent = _vpnState?.totalUpload ?? 0;
    // меньше прошлого бывает только у новой сессии, раньше такой сброс будил судью зря
    final newSession = received < _seenReceived || sent < _seenSent;
    final moved = newSession || received > _seenReceived;
    final wentOut = !newSession && sent > _seenSent;
    _seenReceived = received;
    _seenSent = sent;
    if (await _quiet()) return;
    if (!AutoSelectWatchdog.shouldProbe(
      connected: true,
      autoSelectOn: true,
      trafficMoved: moved,
      trafficSent: wentOut,
    )) {
      return;
    }
    if (await _offline()) return;
    await _decide(
      target,
      _startMeasure(target.server, target.subId, limit: _limit(target)),
      reason:
          'nothing received for ${AutoSelectWatchdog.probeEvery.inSeconds} s',
    );
  }

  Future<void> _decide(
    _AutoTarget target,
    _AutoSelectMeasure measure, {
    required String reason,
  }) async {
    if (_busy) return;
    _busy = true;
    final server = target.server;
    var switched = false;
    var dead = false;
    AppLogger.instance.info(
      'Auto select: checking ${server.displayName} — $reason',
    );
    try {
      var verdict = AutoServerSelect.judge(
        currentId: server.id,
        results: measure.results.values,
        batchComplete: measure.complete,
        score: _score,
      );
      while (!verdict.decided) {
        await measure.changed;
        verdict = AutoServerSelect.judge(
          currentId: server.id,
          results: measure.results.values,
          batchComplete: measure.complete,
          score: _score,
        );
      }
      var nextId = verdict.nextId;
      if (nextId == null) {
        if (measure.results[server.id]?.success == true) {
          _outage = const SubscriptionOutage();
          AppLogger.instance.info(
            'Auto select: ${server.displayName} answered, staying',
          );
          return;
        }
        final across = await _across(target, measure);
        dead = !across.answered;
        nextId = across.nextId;
        if (nextId == null) return;
      } else {
        _outage = const SubscriptionOutage();
      }
      if (_vpnState?.status != VpnStatus.connected) return;
      if (ref.read(serversProvider).activeServer?.id != server.id) return;

      final now = _now();
      _switches.removeWhere(
        (t) => now.difference(t) >= AutoSelectWatchdog.switchWindow,
      );
      if (!AutoSelectWatchdog.switchAllowed(_switches, now)) {
        AppLogger.instance.warn(
          'Auto select: ${AutoSelectWatchdog.maxSwitchesPerWindow} switches '
          'in ${AutoSelectWatchdog.switchWindow.inMinutes} min already, '
          'leaving ${server.displayName} alone for now',
        );
        return;
      }
      final next = ref
          .read(serversProvider)
          .servers
          .where((s) => s.id == nextId)
          .firstOrNull;
      if (next == null) return;
      AppLogger.instance.info(
        'Auto select: ${server.displayName} did not answer, '
        '${next.displayName} did — switching',
      );
      final previous = await AutoSelectHomeStore.load();
      await AutoSelectHomeStore.save(
        target.subId == target.ownerId
            ? AutoSelectHome.afterFailover(
                previous,
                subscriptionId: target.ownerId,
                fromId: server.id,
                toId: next.id,
              )
            : AutoSelectHome.afterNeighbourFailover(
                previous,
                subscriptionId: target.ownerId,
                fromId: server.id,
                toId: next.id,
              ),
      );
      switched = true;
      _switches.add(now);
      await ref.read(serversProvider.notifier).setActive(next);
      await _reconnect();
    } catch (e, st) {
      AppLogger.instance.debug(
        'Auto select decision failed',
        error: e,
        stackTrace: st,
      );
    } finally {
      // после переезда считаем заново: само переподключение даёт отказы и тихие секунды
      _seenFailures = null;
      _silence = const SilenceStreak();
      _counters = null;
      if (switched) _outage = const SubscriptionOutage();
      if (dead) {
        _rest((await VpnNativeBridge.physicalNetworks())?.changes);
      } else {
        _deadRounds = 0;
        // подписка под подозрением, а сеть жива: второй раунд нужен скоро, пользователь сидит без связи
        final soon = switched || _outage.suspects(target.subId);
        _quietUntil = _now().add(
          soon
              ? AutoSelectWatchdog.quietAfterSwitch
              : AutoSelectWatchdog.quietAfterCheck,
        );
      }
      _busy = false;
    }
  }

  // вся своя подписка молчит, и соседние по экрану служат контролем; если молчат и они, виновата сеть, а не серверы
  Future<({String? nextId, bool answered})> _across(
    _AutoTarget target,
    _AutoSelectMeasure own,
  ) async {
    final server = target.server;
    if (!own.results.containsKey(server.id)) {
      return (nextId: null, answered: true);
    }
    final controls = AutoServerSelect.controls(
      ref.read(serversProvider).servers,
      subscriptionIds: [
        for (final id in _family(target.ownerId))
          if (id != target.subId) id,
      ],
      perSubscription: AutoSelectWatchdog.controlsPerSubscription,
      skip: own.results.keys.toSet(),
    );
    if (controls.isEmpty) {
      AppLogger.instance.info(
        'Auto select: nobody answered, staying on ${server.displayName}',
      );
      return (nextId: null, answered: false);
    }
    AppLogger.instance.info(
      'Auto select: nobody in the subscription answered, '
      'asking ${controls.length} servers of the neighbouring ones',
    );
    final control = _measure(server.id, controls);
    await control.done;
    final answered = AutoServerSelect.worthRecording(control.results.values);
    _outage = _outage.afterRound(
      subscriptionId: target.subId,
      ownAnswered: false,
      othersAnswered: answered,
      now: _now(),
    );
    if (!answered) {
      AppLogger.instance.info(
        'Auto select: the neighbours are silent too, it is the network; '
        'staying on ${server.displayName}',
      );
      return (nextId: null, answered: false);
    }
    // сеть жива, поэтому отказы своей подписки настоящие
    unawaited(_record(own.pings));
    if (!_outage.shouldJump) {
      AppLogger.instance.info(
        'Auto select: the subscription is silent while a neighbour answers '
        '(${_outage.rounds} of ${SubscriptionOutage.roundsBeforeJump}), '
        'staying on ${server.displayName} for now',
      );
      return (nextId: null, answered: true);
    }
    final verdict = AutoServerSelect.judge(
      currentId: server.id,
      results: [
        (id: server.id, success: false, latencyMs: null),
        ...control.results.values,
      ],
      batchComplete: true,
      score: _score,
    );
    AppLogger.instance.info(
      'Auto select: the subscription stayed silent '
      '${_outage.rounds} rounds while a neighbour answered, moving there',
    );
    return (nextId: verdict.nextId, answered: true);
  }

  // один таймер на обе: два одновременных накладывали бы замеры каждые 5 минут
  Future<void> recheckTick() {
    final now = _now();
    final last = _recheckAt ??= now;
    final scheduled =
        now.difference(last) >=
        AutoSelectWatchdog.recheckEvery - NeighbourHomePace.every ~/ 2;
    if (scheduled) _recheckAt = now;
    return _recheck(homeOnly: !scheduled);
  }

  Future<void> _recheck({bool homeOnly = false}) async {
    if (_busy) return;
    final target = await _target();
    var home = await AutoSelectHomeStore.load();
    if (target == null) {
      final subs =
          ref.read(subscriptionsProvider).value ?? const <Subscription>[];
      if (home != null &&
          !subs.any((s) => s.id == home!.subscriptionId && s.autoSelect)) {
        await AutoSelectHomeStore.save(null);
      }
      _recheckSeenBytes = null;
      _homePace = const NeighbourHomePace();
      return;
    }
    if (home != null) {
      final waiting = home.stillWaiting(
        activeId: target.server.id,
        autoSubscriptionId: target.ownerId,
        homeExists: AutoServerSelect.canPick(
          ref.read(serversProvider).servers,
          home.homeId,
        ),
      );
      if (waiting == null) await AutoSelectHomeStore.save(null);
      home = waiting;
    }
    final away = home != null && target.subId != target.ownerId;
    if (!away) _homePace = const NeighbourHomePace();
    if (homeOnly && (!away || !_homePace.due(_now()))) {
      return;
    }

    final bytes = await _totalBytes();
    final seen = _recheckSeenBytes;
    _recheckSeenBytes = bytes;
    if (bytes != null && (seen == null || bytes <= seen)) return;

    final quietUntil = _quietUntil;
    if (quietUntil != null && _now().isBefore(quietUntil)) return;

    final homeId = home?.homeId;
    final measure = _startMeasure(
      target.server,
      target.subId,
      limit: homeOnly
          ? NeighbourHomePace.measureLimit
          : AutoSelectWatchdog.recheckLimit,
      include: {?homeId},
    );
    await _decide(
      target,
      measure,
      reason: homeOnly ? 'checking the own subscription' : 'scheduled check',
    );
    if (home == null) return;

    _busy = true;
    try {
      await measure.done;
      if (_vpnState?.status != VpnStatus.connected) return;
      if (ref.read(serversProvider).activeServer?.id != target.server.id) {
        return;
      }
      final homeAnswered = measure.results[home.homeId]?.success == true;
      if (homeOnly) {
        _homePace = _homePace.afterCheck(
          homeAnswered: homeAnswered,
          now: _now(),
        );
        if (_homePace.pausedUntil != null) {
          AppLogger.instance.info(
            'Auto select: the own subscription did not answer '
            '${NeighbourHomePace.missesBeforePause} checks in a row, '
            'next tries in ${NeighbourHomePace.pause.inMinutes} min',
          );
        }
      }
      home = home.afterCheck(homeAnswered: homeAnswered);
      if (!home.shouldReturn) {
        await AutoSelectHomeStore.save(home);
        return;
      }
    } finally {
      _busy = false;
    }
    await _returnHome(target.server, home);
  }

  Future<void> _returnHome(ServerItem from, AutoSelectHome home) async {
    final back = ref
        .read(serversProvider)
        .servers
        .where((s) => s.id == home.homeId)
        .firstOrNull;
    if (back == null) {
      await AutoSelectHomeStore.save(null);
      return;
    }
    final now = _now();
    _switches.removeWhere(
      (t) => now.difference(t) >= AutoSelectWatchdog.switchWindow,
    );
    if (!AutoSelectWatchdog.switchAllowed(_switches, now)) {
      await AutoSelectHomeStore.save(home);
      return;
    }
    AppLogger.instance.info(
      'Auto select: ${back.displayName} answered ${home.aliveStreak} checks '
      'in a row — returning from ${from.displayName}',
    );
    await AutoSelectHomeStore.save(null);
    _busy = true;
    _switches.add(now);
    try {
      await ref.read(serversProvider.notifier).setActive(back);
      await _reconnect();
    } catch (e, st) {
      AppLogger.instance.debug(
        'Auto select return failed',
        error: e,
        stackTrace: st,
      );
    } finally {
      _seenFailures = null;
      _silence = const SilenceStreak();
      _counters = null;
      _quietUntil = _now().add(AutoSelectWatchdog.quietAfterSwitch);
      _busy = false;
    }
  }

  Future<int?> _totalBytes() async {
    final engine = ref.read(vpnEngineProvider);
    try {
      if (Platform.isAndroid) {
        final now = await engine.getCurrentState();
        final down = now.totalDownload;
        final up = now.totalUpload;
        if (down == null && up == null) return null;
        return (down ?? 0) + (up ?? 0);
      }
      final counters = await engine.sessionTrafficCounters();
      return counters == null ? null : counters.down + counters.up;
    } catch (_) {
      return null;
    }
  }
}

class _AutoSelectMeasure {
  _AutoSelectMeasure(this.serverId);

  final String serverId;

  final results = <String, ServerLatency>{};
  List<PingResult> pings = const [];
  bool complete = false;
  Future<void> done = Future<void>.value();
  var _changed = Completer<void>();

  Future<void> get changed => complete ? Future<void>.value() : _changed.future;

  void add(ServerLatency result) {
    results[result.id] = result;
    _signal();
  }

  void finish() {
    complete = true;
    _signal();
  }

  void _signal() {
    final fired = _changed;
    _changed = Completer<void>();
    fired.complete();
  }
}
