/// Which native core backs the active VPN session.
///
/// `xray`   — обычный пайплайн (xray → локальный SOCKS5 → tun2socks/sing-box).
/// `mihomo` — то же место в схеме, но SOCKS5 поднимает mihomo: TUN по-прежнему
///            держит VpnService + tun2socks, ядро о туннеле не знает.
/// `awg`    — AmneziaWG: ядро само владеет TUN (amneziawg-go на Android,
///            amneziawg tunnel-сервис на Windows), без socks-обёртки.
enum VpnBackend {
  xray,
  mihomo,
  awg,
}

extension VpnBackendWire on VpnBackend {
  String get wireValue => switch (this) {
        VpnBackend.xray => 'xray',
        VpnBackend.mihomo => 'mihomo',
        VpnBackend.awg => 'awg',
      };

  static VpnBackend fromWire(String? raw) => switch (raw) {
        'awg' => VpnBackend.awg,
        'mihomo' => VpnBackend.mihomo,
        _ => VpnBackend.xray,
      };
}
