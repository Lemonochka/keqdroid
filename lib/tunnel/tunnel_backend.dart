import 'tunnel_session_request.dart';
import 'tunnel_state.dart';

/// бэкенд туннеля: android VpnService, windows процессы + tun
abstract class TunnelBackend {
  Stream<VpnState> get stateStream;

  void init();
  void dispose();

  Future<({String username, String password})> fetchSocksCredentials();

  Future<void> startSession(TunnelSessionRequest request);

  Future<void> stopSession();

  /// VPN permission (Android). Desktop: admin/TUN prerequisites.
  Future<bool> requestTunnelPermission();

  /// Пауза/возобновление секундного опроса счётчиков трафика (десктоп).
  /// Окно скрыто/свёрнуто — телеметрию никто не видит, поллинг зря жжёт CPU
  /// в фоне (окно может жить в трее неделями). Статус-события (ошибки,
  /// disconnect от вотчдога) не зависят от этого и эмитятся всегда.
  /// Android получает статистику пушем из нативного сервиса — там no-op.
  void setTrafficStatsPollingEnabled(bool enabled) {}

  Future<VpnState> getCurrentState();

  Future<int?> getPing(String address, int port);

  Future<List<Map<String, dynamic>>> getInstalledApps({
    bool includeSystem = false,
  });

  /// Windows: lazy PNG icon for one exe path. Other platforms return null.
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
    String testUrl = 'https://connectivitycheck.gstatic.com/generate_204',
    int timeoutMs = 15000,
    /// два запроса по одному соединению, берём лучший: первый оплачивает DNS и
    /// TLS, второй меряет чистый ответ. Выключенный — один запрос, «как было».
    bool keepAlive = true,
  });

  /// downloads a fixed payload through the core and reports kbps per server.
  /// implemented on windows (dart) and android (native); elsewhere returns success=false.
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

/// cloudflare отдаёт ровно N байт на __down?bytes=N — стабильный payload для speed test
const int kSpeedTestBytes = 2000000;
const String kDefaultSpeedTestUrl =
    'https://speed.cloudflare.com/__down?bytes=$kSpeedTestBytes';
