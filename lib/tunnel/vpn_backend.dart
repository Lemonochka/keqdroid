enum VpnBackend { xray, mihomo }

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
