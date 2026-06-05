import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/app_logger.dart';
import '../core/exceptions.dart';
import 'tunnel_backend.dart';
import 'tunnel_session_request.dart';
import 'tunnel_state.dart';

class AndroidTunnelBackend implements TunnelBackend {
  static const _method = MethodChannel('keqdis_vpn_channel');
  static const _event = EventChannel('keqdis_vpn_status');

  StreamSubscription<dynamic>? _eventSub;
  final _stateCtrl = StreamController<VpnState>.broadcast();

  @override
  Stream<VpnState> get stateStream => _stateCtrl.stream;

  @override
  void init() {
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

  @override
  Future<void> startSession(TunnelSessionRequest request) async {
    try {
      await _method.invokeMethod<void>('startVpn', {
        'vpnBackend': 'xray',
        'xrayConfig': request.xrayConfig,
        'socksPort': request.socksPort,
        'excludePackages': request.excludePackages,
        'includePackages': request.includePackages,
        if (request.serverName != null && request.serverName!.isNotEmpty)
          'serverName': request.serverName,
      });
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
  }) async {
    if (items.isEmpty) return [];
    try {
      final result = await _method.invokeMethod<List>('xrayUrlTestBatch', {
        'socksPort': socksPort,
        'testUrl': testUrl,
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
    String downloadUrl = kDefaultSpeedTestUrl,
    int timeoutMs = 20000,
  }) async =>
      items
          .map(
            (e) => (
              id: e.$1,
              success: false,
              kbps: null,
              error: 'Speed test is not available on this platform',
            ),
          )
          .toList();

  AppException _wrap(PlatformException e, String method) => switch (e.code) {
        'PERMISSION_DENIED' => const VpnPermissionDeniedException(),
        'VPN_START_FAILED' =>
          VpnStartException(e.message ?? 'Failed to start VPN'),
        _ => PlatformChannelException(
            '[$method] ${e.code}: ${e.message}',
            channel: 'keqdis_vpn_channel',
            cause: e,
          ),
      };
}
