import 'tunnel_session_request.dart';
import 'vpn_backend.dart';
import 'tunnel_state.dart';

/// Результат одной пробы общего замера, пока остальные ещё идут.
typedef UrlTestProgress = void Function(
  ({String id, bool success, int? latencyMs, String error, int? httpStatus})
      result,
);

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
    /// Ядро, которое поднимут на замер. Тем же, каким сервер поедет на самом
    /// деле: иначе замер отвечает про чужое ядро — сервер, живой на mihomo,
    /// краснел из-за того, что его не понял xray.
    VpnBackend core = VpnBackend.xray,
    String testUrl = 'https://connectivitycheck.gstatic.com/generate_204',
    int timeoutMs = 15000,
    /// два запроса по одному соединению, берём лучший: первый оплачивает DNS и
    /// TLS, второй меряет чистый ответ. Выключенный — один запрос, «как было».
    bool keepAlive = true,
  });

  /// Кумулятивные счётчики трафика сессии в обход экранного опроса.
  ///
  /// Сторож автовыбора читает их сам раз в секунду, в том числе при окне в
  /// трее, когда опрос для экрана стоит. null — источника нет: на Android
  /// скорости за секунду считает сервис.
  Future<({int down, int up})?> sessionTrafficCounters() async => null;

  /// Замер всего батча ОДНИМ ядром: конфиг несёт инбаунд на каждый сервер, а
  /// проба ходит на свой порт. `null` — платформа так не умеет, и вызывающий
  /// остаётся на поштучном пути.
  ///
  /// Батч падает целиком: негодный сервер уносит с собой весь конфиг, и
  /// выяснять, какой именно, дешевле делением батча, чем догадками.
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

/// cloudflare отдаёт ровно N байт на __down?bytes=N — стабильный payload для speed test
const int kSpeedTestBytes = 2000000;
const String kDefaultSpeedTestUrl =
    'https://speed.cloudflare.com/__down?bytes=$kSpeedTestBytes';
