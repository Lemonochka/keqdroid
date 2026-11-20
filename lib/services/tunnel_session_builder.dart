import 'dart:io';

import '../models/app_settings.dart';
import '../tunnel/connection_mode.dart';
import '../tunnel/tunnel_session_request.dart';
import '../tunnel/vpn_backend.dart';

class TunnelSessionBuilder {
  static ConnectionMode resolveMode(AppSettings settings, {bool? isAndroid}) {
    final android = isAndroid ?? Platform.isAndroid;
    // на Android сохранённый режим только если выбран руками, до 0.13.0 у всех лежит proxy
    if (android && !settings.connectionModeChosen) return ConnectionMode.tun;
    return ConnectionMode.fromStorage(settings.connectionMode);
  }

  static TunnelSessionRequest build({
    required AppSettings settings,
    required String xrayConfig,
    VpnBackend vpnBackend = VpnBackend.xray,
    String? mihomoConfig,
    List<String> excludePackages = const [],
    List<String> includePackages = const [],
    List<String> excludeProcesses = const [],
    List<String> includeProcesses = const [],
    String? serverName,
    ConnectionMode? modeOverride,
  }) {
    return TunnelSessionRequest(
      mode: modeOverride ?? resolveMode(settings),
      vpnBackend: vpnBackend,
      xrayConfig: xrayConfig,
      mihomoConfig: mihomoConfig,
      socksPort: settings.localPort,
      httpPort: settings.httpPort,
      excludePackages: excludePackages,
      includePackages: includePackages,
      excludeProcesses: excludeProcesses,
      includeProcesses: includeProcesses,
      serverName: serverName,
      systemProxy: settings.systemProxyEnabled,
      coreEngine: settings.coreEngine,
      debugMode: settings.debugMode,
    );
  }
}
