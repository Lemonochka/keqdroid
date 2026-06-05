// фасад над TunnelBackend: android (VpnService) и windows (Xray / Xray→sing-box).

import '../tunnel/connection_mode.dart';
import '../tunnel/tunnel_backend.dart';
import '../tunnel/tunnel_backend_factory.dart';
import '../tunnel/tunnel_session_request.dart';
import '../tunnel/tunnel_state.dart';

export '../tunnel/connection_mode.dart';
export '../tunnel/tunnel_session_request.dart';
export '../tunnel/tunnel_state.dart';

class VpnEngine {
  final TunnelBackend _backend;

  static final VpnEngine _instance = VpnEngine._internal();
  factory VpnEngine() => _instance;

  VpnEngine._internal({TunnelBackend? backend})
      : _backend = backend ?? createTunnelBackend();

  /// For tests / dependency injection via [vpnEngineProvider] override.
  factory VpnEngine.withBackend(TunnelBackend backend) =>
      VpnEngine._internal(backend: backend);

  Stream<VpnState> get stateStream => _backend.stateStream;

  void init() => _backend.init();

  void dispose() => _backend.dispose();

  Future<({String username, String password})> fetchSocksCredentials() =>
      _backend.fetchSocksCredentials();

  Future<void> startSession(TunnelSessionRequest request) =>
      _backend.startSession(request);

  /// Android: TUN через VpnService + Xray + tun2socks.
  Future<void> startVpn(
    String xrayConfig, {
    int socksPort = 2080,
    List<String> excludePackages = const [],
    List<String> includePackages = const [],
    String? serverName,
  }) =>
      startSession(
        TunnelSessionRequest(
          mode: ConnectionMode.tun,
          xrayConfig: xrayConfig,
          socksPort: socksPort,
          excludePackages: excludePackages,
          includePackages: includePackages,
          serverName: serverName,
        ),
      );

  Future<void> stopVpn() => _backend.stopSession();

  Future<bool> requestVpnPermission() => _backend.requestTunnelPermission();

  Future<
      List<({
        String id,
        bool success,
        int? latencyMs,
        String error,
        int? httpStatus,
      })>> xrayUrlTestBatch({
    required List<(String id, String xrayConfig)> items,
    required int socksPort,
    String testUrl = 'https://connectivitycheck.gstatic.com/generate_204',
    int timeoutMs = 15000,
  }) =>
      _backend.xrayUrlTestBatch(
        items: items,
        socksPort: socksPort,
        testUrl: testUrl,
        timeoutMs: timeoutMs,
      );

  Future<({bool success, int? latencyMs, String error, int? httpStatus})>
      xrayUrlTest({
    required String xrayConfig,
    required int socksPort,
    String testUrl = 'https://connectivitycheck.gstatic.com/generate_204',
    int timeoutMs = 15000,
  }) async {
    final batch = await xrayUrlTestBatch(
      items: [('single', xrayConfig)],
      socksPort: socksPort,
      testUrl: testUrl,
      timeoutMs: timeoutMs,
    );
    if (batch.isEmpty) {
      return (success: false, latencyMs: null, error: 'null response', httpStatus: null);
    }
    final r = batch.first;
    return (
      success: r.success,
      latencyMs: r.latencyMs,
      error: r.error,
      httpStatus: r.httpStatus,
    );
  }

  Future<
      List<({
        String id,
        bool success,
        int? kbps,
        String error,
      })>> xraySpeedTestBatch({
    required List<(String id, String xrayConfig)> items,
    required int socksPort,
    String downloadUrl = kDefaultSpeedTestUrl,
    int timeoutMs = 20000,
  }) =>
      _backend.xraySpeedTestBatch(
        items: items,
        socksPort: socksPort,
        downloadUrl: downloadUrl,
        timeoutMs: timeoutMs,
      );

  Future<({bool success, int? kbps, String error})> xraySpeedTest({
    required String xrayConfig,
    required int socksPort,
    String downloadUrl = kDefaultSpeedTestUrl,
    int timeoutMs = 20000,
  }) async {
    final batch = await xraySpeedTestBatch(
      items: [('single', xrayConfig)],
      socksPort: socksPort,
      downloadUrl: downloadUrl,
      timeoutMs: timeoutMs,
    );
    if (batch.isEmpty) {
      return (success: false, kbps: null, error: 'null response');
    }
    final r = batch.first;
    return (success: r.success, kbps: r.kbps, error: r.error);
  }

  Future<int?> getPing(String address, int port) =>
      _backend.getPing(address, port);

  Future<List<Map<String, dynamic>>> getInstalledApps({
    bool includeSystem = false,
  }) =>
      _backend.getInstalledApps(includeSystem: includeSystem);

  Future<String?> getAppIcon(String path) => _backend.getAppIcon(path);

  Future<VpnState> getCurrentState() => _backend.getCurrentState();
}
