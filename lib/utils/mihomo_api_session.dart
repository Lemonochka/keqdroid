import 'dart:io';

import '../tunnel/socks_credential_generator.dart';

/// Координаты RESTful API работающего ядра mihomo: порт и `secret`.
///
/// Существует ровно ради экрана «Соединения»: у mihomo, в отличие от xray,
/// список сессий отдаёт само ядро, но постучаться в него можно только зная
/// порт и токен, которые мы же и записали в конфиг.
///
/// Живёт синглтоном по образцу [Socks5Credentials]: конфиг собирает Dart, он
/// же придумывает порт с токеном, и оба должны пережить ровно одну сессию
/// ядра. Пересоздание Flutter-движка при живом VpnService синглтон не
/// переживает — восстанавливает его [restore] из нативного сервиса, который
/// хранит ту же пару вместе с путём к конфигу.
class MihomoApiSession {
  static final MihomoApiSession _instance = MihomoApiSession._internal();

  factory MihomoApiSession() => _instance;
  MihomoApiSession._internal();

  int? _port;
  String _secret = '';

  int? get port => _port;
  String get secret => _secret;
  bool get isActive => _port != null && _secret.isNotEmpty;

  /// Свободный порт на петле + свежий токен под новую сессию.
  ///
  /// Порт выбираем так же, как под эфемерные ядра пингов: слушающий сокет
  /// закрываем сразу, поэтому теоретически его может перехватить кто-то ещё —
  /// на практике окно в миллисекунды, а неудача стоит лишь пустого экрана
  /// «Соединения», не подключения.
  Future<void> renew() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _port = socket.port;
    await socket.close();
    _secret = SocksCredentialGenerator.randomToken(32);
  }

  /// Пара от уже работающей сессии — из нативного сервиса.
  void restore({required int? port, required String secret}) {
    if (port == null || port <= 0 || secret.isEmpty) return;
    _port = port;
    _secret = secret;
  }

  /// Сессия кончилась: в мёртвый порт стучаться незачем, а токен от неё
  /// больше ничего не открывает.
  void clear() {
    _port = null;
    _secret = '';
  }
}
