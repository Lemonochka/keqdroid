import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/app_logger.dart';
import '../core/exceptions.dart';
import 'tunnel_backend.dart';
import 'tunnel_session_request.dart';
import 'tunnel_state.dart';
import 'vpn_backend.dart';

class AndroidTunnelBackend implements TunnelBackend {
  static const _method = MethodChannel('keqdroid_vpn_channel');
  static const _event = EventChannel('keqdroid_vpn_status');

  StreamSubscription<dynamic>? _eventSub;
  final _stateCtrl = StreamController<VpnState>.broadcast();

  @override
  Stream<VpnState> get stateStream => _stateCtrl.stream;

  @override
  void init() {
    reconnectEventStream();
  }

  void reconnectEventStream() {
    _eventSub?.cancel();
    _eventSub = _event.receiveBroadcastStream().listen(
      (e) {
        if (e is Map) {
          _stateCtrl.add(VpnState.fromMap(e.cast<Object?, Object?>()));
        } else if (e is String) {
          _stateCtrl.add(VpnState(status: VpnStatus.fromString(e)));
        }
      },
      onError: (e) => _stateCtrl.add(
        VpnState(status: VpnStatus.error, errorMessage: e.toString()),
      ),
      cancelOnError: false,
    );
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _stateCtrl.close();
  }

  @override
  void setTrafficStatsPollingEnabled(bool enabled) {}

  @override
  Future<({String username, String password})> fetchSocksCredentials() async {
    try {
      final result = await _method.invokeMethod<Map>('getSocksCredentials');
      if (result == null) {
        throw const VpnException('getSocksCredentials returned null');
      }
      final username = result['username'] as String? ?? '';
      final password = result['password'] as String? ?? '';
      if (username.isEmpty || password.isEmpty) {
        throw const VpnException('Native service returned empty SOCKS5 credentials');
      }
      return (username: username, password: password);
    } on PlatformException catch (e) {
      throw _wrap(e, 'getSocksCredentials');
    }
  }

  Future<({String username, String password})?>
      fetchActiveSocksCredentials() async {
    try {
      final result =
          await _method.invokeMethod<Map>('getActiveSocksCredentials');
      final username = result?['username'] as String? ?? '';
      final password = result?['password'] as String? ?? '';
      if (username.isEmpty || password.isEmpty) return null;
      return (username: username, password: password);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> startSession(TunnelSessionRequest request) async {
    try {
      final coreConfig = request.xrayConfig;

      final args = <String, dynamic>{
        'vpnBackend': request.vpnBackend.wireValue,
        'xrayConfig': coreConfig,
        if (request.mihomoConfig != null && request.mihomoConfig!.isNotEmpty)
          'mihomoConfig': request.mihomoConfig,
        'coreEngine': 'chain',
        'tunnelMode': request.mode.storageValue,
        'socksPort': request.socksPort,
        'excludePackages': request.excludePackages,
        'includePackages': request.includePackages,
        if (request.serverName != null && request.serverName!.isNotEmpty)
          'serverName': request.serverName,
      };

      await _method.invokeMethod<void>('startVpn', args);
    } on PlatformException catch (e) {
      throw _wrap(e, 'startVpn');
    }
  }

  @override
  Future<void> stopSession() async {
    try {
      await _method.invokeMethod<void>('stopVpn');
    } on PlatformException catch (e) {
      throw _wrap(e, 'stopVpn');
    }
  }

  @override
  Future<bool> requestTunnelPermission() async {
    try {
      final result = await _method.invokeMethod<bool>('requestVpnPermission');
      return result ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        throw const VpnPermissionDeniedException();
      }
      if (e.code == 'PERMISSION_IN_PROGRESS') {
        throw VpnException(
          'VPN permission dialog is already shown',
          cause: e,
        );
      }
      throw _wrap(e, 'requestVpnPermission');
    }
  }

  @override
  Future<({int down, int up})?> sessionTrafficCounters() async => null;

  @override
  Future<VpnState> getCurrentState() async {
    try {
      final result = await _method.invokeMethod<Map>('getStatus');
      if (result == null) return VpnState.disconnected;
      return VpnState.fromMap(result.cast<Object?, Object?>());
    } on PlatformException catch (e) {
      throw _wrap(e, 'getStatus');
    }
  }

  @override
  Future<int?> getPing(String address, int port) async {
    try {
      return await _method.invokeMethod<int>('getPing', {
        'address': address,
        'port': port,
        'timeoutMs': 5000,
      });
    } on PlatformException {
      return _tcpPingDart(address, port);
    }
  }

  Future<int?> _tcpPingDart(String address, int port) async {
    final sw = Stopwatch()..start();
    try {
      final s = await Socket.connect(
        address,
        port,
        timeout: const Duration(seconds: 5),
      );
      sw.stop();
      await s.close();
      return sw.elapsedMilliseconds;
    } catch (_) {
      AppLogger.instance.debug('TCP ping failed for $address:$port');
      return null;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getInstalledApps({
    bool includeSystem = false,
  }) async {
    try {
      final result = await _method.invokeMethod<List<dynamic>>(
        'getInstalledApps',
        {'includeSystem': includeSystem},
      );
      return result
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
    } on PlatformException catch (e) {
      throw _wrap(e, 'getInstalledApps');
    }
  }

  @override
  Future<String?> getAppIcon(String path) async => null;

  @override
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
  }) async {
    if (probes.isEmpty) return const [];
    String? batchId;
    if (onEach != null) {
      _listenPingProgress();
      batchId = 'batch-${_pingBatchSeq++}';
      _pingProgressListeners[batchId] = (map) => onEach(_urlTestResult(map));
    }
    try {
      final result = await _method.invokeMethod<List>('xrayUrlTestMulti', {
        'config': config,
        'core': core.wireValue,
        'testUrl': testUrl,
        'timeoutMs': timeoutMs,
        'keepAlive': keepAlive,
        'concurrency': concurrency,
        'probes': probes.map((e) => {'id': e.$1, 'port': e.$2}).toList(),
        'batchId': ?batchId,
      });
      if (result == null || result.isEmpty) return null;
      return [
        for (final raw in result)
          _urlTestResult(Map<Object?, Object?>.from(raw as Map)),
      ];
    } on PlatformException {
      return null;
    } finally {
      if (batchId != null) _pingProgressListeners.remove(batchId);
    }
  }

  static ({String id, bool success, int? latencyMs, String error, int? httpStatus})
      _urlTestResult(Map<Object?, Object?> map) => (
            id: map['id'] as String? ?? '',
            success: map['success'] as bool? ?? false,
            latencyMs: (map['latencyMs'] as num?)?.toInt(),
            error: map['error'] as String? ?? '',
            httpStatus: (map['httpStatus'] as num?)?.toInt(),
          );

  // подписка заводится до первого вызова: канал шлёт в никуда, пока его не слушают
  static const _pingProgress = EventChannel('keqdroid_ping_progress');
  static StreamSubscription<dynamic>? _pingProgressSub;
  static final _pingProgressListeners =
      <String, void Function(Map<Object?, Object?>)>{};
  static var _pingBatchSeq = 0;

  static void _listenPingProgress() {
    _pingProgressSub ??= _pingProgress.receiveBroadcastStream().listen(
      (event) {
        if (event is! Map) return;
        final batch = event['batch'];
        if (batch is! String) return;
        _pingProgressListeners[batch]?.call(Map<Object?, Object?>.from(event));
      },
      onError: (_) {},
    );
  }

  @override
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
  }) async {
    if (items.isEmpty) return [];
    try {
      final result = await _method.invokeMethod<List>('xrayUrlTestBatch', {
        'socksPort': socksPort,
        'core': core.wireValue,
        'testUrl': testUrl,
        'timeoutMs': timeoutMs,
        'keepAlive': keepAlive,
        'items': items
            .map(
              (e) => {
                'id': e.$1,
                'xrayConfig': e.$2,
              },
            )
            .toList(),
      });
      if (result == null) return [];
      return result.map((raw) {
        final map = Map<Object?, Object?>.from(raw as Map);
        return (
          id: map['id'] as String? ?? '',
          success: map['success'] as bool? ?? false,
          latencyMs: (map['latencyMs'] as num?)?.toInt(),
          error: map['error'] as String? ?? '',
          httpStatus: (map['httpStatus'] as num?)?.toInt(),
        );
      }).toList();
    } on PlatformException catch (e) {
      return items
          .map(
            (item) => (
              id: item.$1,
              success: false,
              latencyMs: null,
              error: e.message ?? e.code,
              httpStatus: null,
            ),
          )
          .toList();
    }
  }

  @override
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
  }) async {
    if (items.isEmpty) return [];
    try {
      final result = await _method.invokeMethod<List>('xraySpeedTestBatch', {
        'socksPort': socksPort,
        'core': core.wireValue,
        'downloadUrl': downloadUrl,
        'timeoutMs': timeoutMs,
        'items': items
            .map(
              (e) => {
                'id': e.$1,
                'xrayConfig': e.$2,
              },
            )
            .toList(),
      });
      if (result == null) return [];
      return result.map((raw) {
        final map = Map<Object?, Object?>.from(raw as Map);
        return (
          id: map['id'] as String? ?? '',
          success: map['success'] as bool? ?? false,
          kbps: (map['kbps'] as num?)?.toInt(),
          error: map['error'] as String? ?? '',
        );
      }).toList();
    } on PlatformException catch (e) {
      return items
          .map(
            (item) => (
              id: item.$1,
              success: false,
              kbps: null,
              error: e.message ?? e.code,
            ),
          )
          .toList();
    }
  }

  AppException _wrap(PlatformException e, String method) => switch (e.code) {
        'PERMISSION_DENIED' => const VpnPermissionDeniedException(),
        'VPN_START_FAILED' =>
          VpnStartException(e.message ?? 'Failed to start VPN'),
        _ => PlatformChannelException(
            '[$method] ${e.code}: ${e.message}',
            channel: 'keqdroid_vpn_channel',
            cause: e,
          ),
      };
}
