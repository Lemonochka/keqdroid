import 'tunnel_session_request.dart';
import 'vpn_backend.dart';
import 'tunnel_state.dart';

typedef UrlTestProgress = void Function(
  ({String id, bool success, int? latencyMs, String error, int? httpStatus})
      result,
);

abstract class TunnelBackend {
  Stream<VpnState> get stateStream;

  void init();
  void dispose();

  Future<({String username, String password})> fetchSocksCredentials();

  // креды, с которыми поднято работающее ядро; на ПК их держит само приложение
  Future<({String username, String password})?>
      fetchActiveSocksCredentials() async => null;

  Future<void> startSession(TunnelSessionRequest request);

  Future<void> stopSession();

  Future<bool> requestTunnelPermission();

  void setTrafficStatsPollingEnabled(bool enabled) {}

  Future<VpnState> getCurrentState();

  Future<int?> getPing(String address, int port);

  Future<List<Map<String, dynamic>>> getInstalledApps({
    bool includeSystem = false,
  });

  Future<String?> getAppIcon(String path) async => null;

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
    VpnBackend core = VpnBackend.xray,
    String testUrl = 'https://connectivitycheck.gstatic.com/generate_204',
    int timeoutMs = 15000,
    bool keepAlive = true,
  });

  Future<({int down, int up})?> sessionTrafficCounters() async => null;

  Future<List<({
        String id,
        bool success,
        int? latencyMs,
        String error,
        int? httpStatus,
      })>?> xrayUrlTestMulti({
    required String config,
    required List<(String id, int port)> probes,
    VpnBackend core = VpnBackend.xray,
    String testUrl = 'https://connectivitycheck.gstatic.com/generate_204',
    int timeoutMs = 15000,
    bool keepAlive = true,
    int concurrency = 16,
    UrlTestProgress? onEach,
  }) async =>
      null;

  Future<
      List<({
        String id,
        bool success,
        int? kbps,
        String error,
      })>> xraySpeedTestBatch({
    required List<(String id, String xrayConfig)> items,
    required int socksPort,
    VpnBackend core = VpnBackend.xray,
    String downloadUrl = kDefaultSpeedTestUrl,
    int timeoutMs = 20000,
  }) async =>
      items
          .map(
            (e) => (
              id: e.$1,
              success: false,
              kbps: null,
              error: 'Speed test is only available on desktop',
            ),
          )
          .toList();
}

// cloudflare отдаёт ровно N байт на __down?bytes=N
const int kSpeedTestBytes = 2000000;
const String kDefaultSpeedTestUrl =
    'https://speed.cloudflare.com/__down?bytes=$kSpeedTestBytes';
