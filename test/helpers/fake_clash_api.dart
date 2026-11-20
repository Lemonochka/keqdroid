import 'dart:convert';
import 'dart:io';

/// Поддельный RESTful API ядра для тестов опросов `/connections`: ядро, которое
/// отдаёт заголовки и начало ответа, а дальше молчит, не закрывая соединение.
///
/// Настоящие mihomo и sing-box так не делают, но код опроса обязан это
/// переживать: такой ответ без срока на тело висел вечно, а сброс клиента с
/// сотнями таких запросов уходил в рекурсию.
class StallingClashApi {
  StallingClashApi._(this._server) {
    _server.listen(_handle);
  }

  final ServerSocket _server;
  final _sockets = <Socket>{};

  int get port => _server.port;

  static Future<StallingClashApi> start() async => StallingClashApi._(
    await ServerSocket.bind(InternetAddress.loopbackIPv4, 0, backlog: 1024),
  );

  void _handle(Socket socket) {
    _sockets.add(socket);
    final request = <int>[];
    var answered = false;
    socket.listen(
      (data) {
        if (answered) return;
        request.addAll(data);
        if (!latin1.decode(request).contains('\r\n\r\n')) return;
        answered = true;
        socket.add(
          latin1.encode(
            'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n'
            'Content-Length: 100000\r\n\r\n{"downloadTotal":1,"connections":[',
          ),
        );
      },
      onDone: () => _sockets.remove(socket..destroy()),
      onError: (_) => _sockets.remove(socket..destroy()),
      cancelOnError: true,
    );
  }

  Future<void> close() async {
    for (final socket in _sockets.toList()) {
      socket.destroy();
    }
    await _server.close();
  }
}

/// Порт на петле, где никто не слушает: запрос туда падает на соединении.
Future<int> closedLoopbackPort() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  await server.close();
  return port;
}
