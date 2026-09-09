/// Which native core backs the active VPN session.
///
/// `xray`   — обычный пайплайн (xray читает туннель сам, на десктопе за ним sing-box).
/// `mihomo` — то же место в схеме, но SOCKS5 поднимает mihomo: TUN по-прежнему
///            держит VpnService, а читает его само ядро.
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
