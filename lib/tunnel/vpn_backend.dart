/// Which native core backs the active VPN session.
///
/// `xray` — обычный пайплайн (xray → локальный SOCKS5 → tun2socks/sing-box).
/// `awg`  — AmneziaWG: ядро само владеет TUN (amneziawg-go на Android,
///          amneziawg tunnel-сервис на Windows), без socks-обёртки.
enum VpnBackend {
  xray,
  awg,
}

extension VpnBackendWire on VpnBackend {
  String get wireValue => switch (this) {
        VpnBackend.xray => 'xray',
        VpnBackend.awg => 'awg',
      };

  static VpnBackend fromWire(String? raw) => switch (raw) {
        'awg' => VpnBackend.awg,
        _ => VpnBackend.xray,
      };
}
