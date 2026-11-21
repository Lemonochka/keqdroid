part of 'providers.dart';

// включается сразу, как только по имени не идёт, а по адресу идёт; снимается сроком, при следующем подключении
class _NamesFallbackMonitor {
  _NamesFallbackMonitor({
    required Ref Function() ref,
    required _LiveSession? Function() live,
    required VpnState? Function() vpnState,
    required Future<void> Function() reconnect,
    required DateTime Function() now,
    required Future<NamesVerdict> Function(int httpPort) probe,
  }) : _readRef = ref,
       _readLive = live,
       _readVpnState = vpnState,
       _reconnect = reconnect,
       _now = now,
       _probe = probe;

  final Ref Function() _readRef;
  final _LiveSession? Function() _readLive;
  final VpnState? Function() _readVpnState;
  final Future<void> Function() _reconnect;
  final DateTime Function() _now;
  final Future<NamesVerdict> Function(int httpPort) _probe;

  Ref get ref => _readRef();

  Timer? _timer;
  Timer? _soon;
  int _misses = 0;
  bool _busy = false;

  void stop() {
    _timer?.cancel();
    _timer = null;
    _soon?.cancel();
    _misses = 0;
  }

  // таймер заводится с первым подключением: без VPN проверять нечего
  void connected() {
    _misses = 0;
    _timer ??= Timer.periodic(
      NamesFallback.checkEvery,
      (_) => unawaited(check()),
    );
    _later(NamesFallback.firstCheckAfter);
  }

  void _later(Duration after) {
    _soon?.cancel();
    _soon = Timer(after, () => unawaited(check()));
  }

  Future<void> check() async {
    if (_busy) return;
    final live = _readLive();
    if (_readVpnState()?.status != VpnStatus.connected ||
        live == null ||
        !live.namesCheck ||
        live.resolvesTargets) {
      _misses = 0;
      return;
    }
    final server = ref.read(serversProvider).activeServer;
    if (server == null || server.id != live.serverId) return;
    _busy = true;
    try {
      final verdict = await _probe(live.request.httpPort);
      if (!identical(_readLive(), live)) return;
      if (verdict != NamesVerdict.namesBroken) {
        _misses = 0;
        return;
      }
      _misses++;
      if (_misses < NamesFallback.missesToSwitch) {
        _later(NamesFallback.confirmAfter);
        return;
      }
      _misses = 0;
      await ref
          .read(serversProvider.notifier)
          .setNamesFallback(server.id, _now());
      // пока пишется пометка, могли нажать Отключить: reconnectToActiveServer подключил бы заново
      if (!identical(_readLive(), live)) return;
      AppLogger.instance.warn(
        'Server "${server.displayName}" opens sites by address but not by '
        'name: its exit does not look names up. For a day the core finds '
        'addresses itself for this server; reconnecting.',
      );
      await _reconnect();
    } finally {
      _busy = false;
    }
  }
}
