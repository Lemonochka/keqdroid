import 'dart:math';

/// локальные socks5-credentials (windows/desktop)
class SocksCredentialGenerator {
  static final _rng = Random.secure();
  static const _chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  static String randomToken(int length) {
    return List.generate(
      length,
      (_) => _chars[_rng.nextInt(_chars.length)],
    ).join();
  }

  static ({String username, String password}) generatePair() {
    return (
      username: randomToken(16),
      password: randomToken(24),
    );
  }
}
