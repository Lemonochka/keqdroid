/// Which native core backs the active VPN session.
///
/// `xray`   — обычный пайплайн (xray читает туннель сам, на десктопе за ним sing-box).
/// `mihomo` — то же место в схеме, но SOCKS5 поднимает mihomo: TUN по-прежнему
///            держит VpnService, а читает его само ядро. Им же едет AmneziaWG.
enum VpnBackend {
  xray,
  mihomo,
}

extension VpnBackendWire on VpnBackend {
  String get wireValue => switch (this) {
        VpnBackend.xray => 'xray',
        VpnBackend.mihomo => 'mihomo',
      };

  static VpnBackend fromWire(String? raw) => switch (raw) {
        'mihomo' => VpnBackend.mihomo,
        _ => VpnBackend.xray,
      };
}
