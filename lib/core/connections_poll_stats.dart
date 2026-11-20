const connectionsBodyTimeout = Duration(seconds: 10);

class ConnectionsPollStats {
  ConnectionsPollStats._();

  static final instance = ConnectionsPollStats._();

  int _inFlight = 0;
  int _maxInFlight = 0;
  int _requests = 0;
  int _failures = 0;
  int _slow = 0;
  int _maxBodyChars = 0;
  int _maxConnections = 0;

  static const slowAfter = Duration(seconds: 1);

  Stopwatch begin() {
    _inFlight++;
    _requests++;
    if (_inFlight > _maxInFlight) _maxInFlight = _inFlight;
    return Stopwatch()..start();
  }

  void end(
    Stopwatch started, {
    bool ok = true,
    int bodyChars = 0,
    int? connections,
  }) {
    _inFlight--;
    if (!ok) _failures++;
    if (started.elapsed > slowAfter) _slow++;
    if (bodyChars > _maxBodyChars) _maxBodyChars = bodyChars;
    if (connections != null && connections > _maxConnections) {
      _maxConnections = connections;
    }
  }

  int get inFlight => _inFlight;

  String takeSummary() {
    final summary =
        '$_requests requests, in flight $_inFlight '
        '(max $_maxInFlight), failed $_failures, slow $_slow, '
        'largest ${_kb(_maxBodyChars)} / $_maxConnections connections';
    _requests = 0;
    _failures = 0;
    _slow = 0;
    _maxInFlight = _inFlight;
    _maxBodyChars = 0;
    _maxConnections = 0;
    return summary;
  }

  static String _kb(int chars) =>
      chars < 1024 ? '$chars B' : '${(chars / 1024).round()} KB';
}
