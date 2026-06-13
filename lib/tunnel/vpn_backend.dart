/// Which native core backs the active VPN session.
enum VpnBackend {
  xray,
  kphttp,
}

extension VpnBackendWire on VpnBackend {
  String get wireValue => switch (this) {
        VpnBackend.xray => 'xray',
        VpnBackend.kphttp => 'kphttp',
      };

  static VpnBackend fromWire(String? raw) => switch (raw) {
        'kphttp' => VpnBackend.kphttp,
        _ => VpnBackend.xray,
      };
}
