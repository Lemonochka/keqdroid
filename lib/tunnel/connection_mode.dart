/// desktop: только xray (прокси) или tun через xray → sing-box
enum ConnectionMode {
  /// Локальный SOCKS/HTTP Xray + опционально системный прокси Windows.
  proxy,

  /// sing-box TUN → SOCKS5 (с auth) на локальный Xray → upstream протоколы Xray.
  tun;

  static const storageKey = 'connectionMode';

  static ConnectionMode fromStorage(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'proxy':
        return ConnectionMode.proxy;
      case 'tun':
        return ConnectionMode.tun;
      default:
        return ConnectionMode.tun;
    }
  }

  String get storageValue => name;

  /// На Android пока всегда TUN через VpnService + Xray + tun2socks.
  static ConnectionMode platformDefault() {
    return ConnectionMode.tun;
  }
}
