import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/app_settings.dart';
import '../tunnel/app_routing_mode.dart';
import '../tunnel/connection_mode.dart';
import '../tunnel/tunnel_session_request.dart';
import '../tunnel/vpn_backend.dart';
import '../utils/singbox_kphttp_proxy_config.dart';
import '../utils/singbox_tun_config.dart';

/// собирает TunnelSessionRequest под платформу и режим proxy/tun
class TunnelSessionBuilder {
  static ConnectionMode resolveMode(AppSettings settings) {
    if (Platform.isAndroid) return ConnectionMode.tun;
    return ConnectionMode.fromStorage(settings.connectionMode);
  }

  static TunnelSessionRequest build({
    required AppSettings settings,
    required String xrayConfig,
    String? kphttpTomlConfig,
    VpnBackend vpnBackend = VpnBackend.xray,
    required String resolvedServerIp,
    required String socksUsername,
    required String socksPassword,
    List<String> excludePackages = const [],
    List<String> includePackages = const [],
    List<String> excludeProcesses = const [],
    List<String> includeProcesses = const [],
    String? serverName,
    AppRoutingMode routingMode = AppRoutingMode.allProxy,
    ConnectionMode? modeOverride,
  }) {
    final mode = modeOverride ?? resolveMode(settings);
    final isKphttp = vpnBackend == VpnBackend.kphttp;

    String? singboxConfig;
    if (Platform.isWindows) {
      if (mode == ConnectionMode.tun) {
        final managed = switch (routingMode) {
          AppRoutingMode.onlySelected => includeProcesses,
          AppRoutingMode.allExceptSelected => excludeProcesses,
          AppRoutingMode.allProxy => const <String>[],
        };
        singboxConfig = SingBoxTunConfigGen.generate(
          localSocksPort: settings.localPort,
          socksUsername: socksUsername,
          socksPassword: socksPassword,
          serverIpToExclude: resolvedServerIp,
          settings: settings,
          managedProcessNames: managed,
          routingMode: routingMode,
          localSocksNoAuth: isKphttp,
          appProcessName: p.basename(Platform.resolvedExecutable),
        );
      } else if (isKphttp) {
        singboxConfig = SingBoxKphttpProxyConfigGen.generate(
          kphttpSocksPort: settings.localPort,
          httpPort: settings.httpPort,
        );
      }
    }

    return TunnelSessionRequest(
      mode: mode,
      vpnBackend: vpnBackend,
      xrayConfig: xrayConfig,
      kphttpTomlConfig: kphttpTomlConfig,
      socksPort: settings.localPort,
      httpPort: settings.httpPort,
      singboxConfig: singboxConfig,
      excludePackages: excludePackages,
      includePackages: includePackages,
      excludeProcesses: excludeProcesses,
      includeProcesses: includeProcesses,
      serverName: serverName,
      systemProxy: Platform.isWindows && mode == ConnectionMode.proxy
          ? true
          : settings.systemProxyEnabled,
      killSwitch: settings.killSwitch,
    );
  }
}
