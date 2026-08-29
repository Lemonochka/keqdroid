import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/app_settings.dart';
import '../tunnel/app_routing_mode.dart';
import '../tunnel/connection_mode.dart';
import '../tunnel/tunnel_session_request.dart';
import '../tunnel/vpn_backend.dart';
import '../utils/singbox_tun_config.dart';

/// собирает TunnelSessionRequest под платформу и режим proxy/tun
class TunnelSessionBuilder {
  /// Режим сессии из настроек — теперь и на Android.
  ///
  /// Раньше здесь стояло жёсткое `tun`: другого пути на Android не было, весь
  /// трафик забирал VpnService. Режим «прокси» его не поднимает вовсе — ядро
  /// слушает 127.0.0.1, а кого через него пускать, решает пользовательница в
  /// настройках приложений или Wi-Fi.
  ///
  /// AmneziaWG — исключение, и не по нашей воле: на Android его исполняет
  /// libwg-go, который сам владеет TUN и локального прокси не открывает вовсе
  /// (на десктопе эту роль играет wireproxy, которого в APK нет). Для таких
  /// серверов режим остаётся VPN, иначе подключение просто не к чему было бы
  /// подключить.
  /// [isAndroid] параметром, а не только из [Platform]: иначе ветку про AWG не
  /// проверить — тесты идут на хосте, где `Platform.isAndroid` всегда false.
  static ConnectionMode resolveMode(
    AppSettings settings, {
    VpnBackend vpnBackend = VpnBackend.xray,
    bool? isAndroid,
  }) {
    final android = isAndroid ?? Platform.isAndroid;
    if (android && vpnBackend == VpnBackend.awg) {
      return ConnectionMode.tun;
    }
    // Сохранённый режим на Android учитываем ТОЛЬКО если его выбирали руками.
    // До 0.13.0 поле там не читалось вовсе, и в настройках у всех лежит
    // десктопный дефолт `proxy`, которого никто не просил: уважить его молча —
    // значит выключить туннель всему, что обновилось.
    if (android && !settings.connectionModeChosen) return ConnectionMode.tun;
    return ConnectionMode.fromStorage(settings.connectionMode);
  }

  static TunnelSessionRequest build({
    required AppSettings settings,
    required String xrayConfig,
    VpnBackend vpnBackend = VpnBackend.xray,
    String? awgConfig,
    String? mihomoConfig,
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
    /// Есть ли у машины глобальный IPv6 — решает, забирать ли IPv6 в туннель
    /// (см. [TunSettings.blockIpv6Leak]). Считает вызывающий: здесь нельзя,
    /// метод синхронный, а перечисление интерфейсов — нет.
    bool hostHasIpv6 = false,
  }) {
    final mode = modeOverride ?? resolveMode(settings, vpnBackend: vpnBackend);
    final isAwg = vpnBackend == VpnBackend.awg;

    // TUN на Windows: sing-box оборачивает tun→локальный SOCKS.
    //  - xray: SOCKS с auth от xray.
    //  - AmneziaWG: SOCKS от wireproxy-awg (без auth).
    // В proxy-режиме sing-box не нужен (системный прокси).
    String? singboxConfig;
    if ((Platform.isWindows || Platform.isLinux) && mode == ConnectionMode.tun) {
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
        localSocksNoAuth: isAwg,
        appProcessName: p.basename(Platform.resolvedExecutable),
        hostHasIpv6: hostHasIpv6,
      );
    }

    return TunnelSessionRequest(
      mode: mode,
      vpnBackend: vpnBackend,
      xrayConfig: xrayConfig,
      awgConfig: awgConfig,
      mihomoConfig: mihomoConfig,
      socksPort: settings.localPort,
      httpPort: settings.httpPort,
      singboxConfig: singboxConfig,
      excludePackages: excludePackages,
      includePackages: includePackages,
      excludeProcesses: excludeProcesses,
      includeProcesses: includeProcesses,
      serverName: serverName,
      systemProxy: settings.systemProxyEnabled,
      killSwitch: settings.killSwitch,
      coreEngine: settings.coreEngine,
      debugMode: settings.debugMode,
    );
  }
}
