import 'dart:math';

class Socks5Credentials {
  static final Socks5Credentials _instance = Socks5Credentials._internal();

  factory Socks5Credentials() => _instance;
  Socks5Credentials._internal();

  String _username = '';
  String _password = '';
  int _generation = 0;

  String get username => _username;
  String get password => _password;

  // растёт на каждой смене: повтор после 407 нужен, только если креды сменились
  int get generation => _generation;

  void init(String user, String pass) {
    if (user == _username && pass == _password) return;
    _username = user;
    _password = pass;
    _generation++;
  }

  bool get isInitialized => _username.isNotEmpty && _password.isNotEmpty;
}
String randomProxyToken(int length) {
  const alphabet = 'abcdefghijkmnpqrstuvwxyz23456789';
  final rnd = Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < length; i++)
      alphabet.codeUnitAt(rnd.nextInt(alphabet.length)),
  ]);
}
