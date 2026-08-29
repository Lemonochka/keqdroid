import 'dart:math';

class Socks5Credentials {
  static final Socks5Credentials _instance = Socks5Credentials._internal();

  factory Socks5Credentials() => _instance;
  Socks5Credentials._internal();

  String _username = '';
  String _password = '';

  String get username => _username;
  String get password => _password;

  void init(String user, String pass) {
    _username = user;
    _password = pass;
  }

  bool get isInitialized => _username.isNotEmpty && _password.isNotEmpty;
}
/// Токен для постоянных кред локального прокси (режим «Прокси»).
///
/// Отдельно от сессионных, которые генерирует натив: те живут одно
/// подключение, эти вписывают руками в стороннее приложение.
String randomProxyToken(int length) {
  const alphabet = 'abcdefghijkmnpqrstuvwxyz23456789';
  final rnd = Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < length; i++)
      alphabet.codeUnitAt(rnd.nextInt(alphabet.length)),
  ]);
}
