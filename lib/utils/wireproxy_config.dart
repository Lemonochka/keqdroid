/// Builds a wireproxy-awg config from an AmneziaWG `.conf`.
///
/// wireproxy-awg reads a standard WG/AWG `[Interface]`/`[Peer]` config (including
/// the AmneziaWG obfuscation keys) plus `[Socks5]` / `[http]` sections that expose
/// the tunnel as local proxies. Used for AmneziaWG **proxy mode** on Windows:
/// wireproxy → local SOCKS5/HTTP → Windows system proxy (no admin, no TUN).
class WireproxyConfigGen {
  static String generate(
    String awgConf, {
    required int socksPort,
    int? httpPort,
    bool withHttp = true,
  }) {
    final buffer = StringBuffer(awgConf.trimRight())
      ..writeln()
      ..writeln()
      ..writeln('[Socks5]')
      ..writeln('BindAddress = 127.0.0.1:$socksPort');
    if (withHttp && httpPort != null) {
      buffer
        ..writeln()
        ..writeln('[http]')
        ..writeln('BindAddress = 127.0.0.1:$httpPort');
    }
    return buffer.toString();
  }
}
