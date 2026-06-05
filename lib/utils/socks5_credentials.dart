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