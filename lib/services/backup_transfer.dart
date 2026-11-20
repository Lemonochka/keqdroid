import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'backup_crypto.dart';
import 'tv_handoff.dart' show isPrivateIpv4;

// receive: показавший код принимает копию; give: показавший отдаёт свою
enum BackupTransferDirection { receive, give }

// ключ живёт только в коде на экране: по сети идёт уже зашифрованная им копия
class BackupTransferLink {
  const BackupTransferLink({
    required this.host,
    required this.port,
    required this.direction,
    required this.key,
  });

  final String host;
  final int port;
  final BackupTransferDirection direction;
  final List<int> key;

  static const _linkHost = 'backup';

  String toLink() => Uri(
    scheme: 'keqdroid',
    host: _linkHost,
    queryParameters: {
      'h': host,
      'p': '$port',
      'd': direction == BackupTransferDirection.receive ? 'r' : 'g',
      'k': base64Url.encode(key).replaceAll('=', ''),
    },
  ).toString();

  // только частный IPv4: подложенный код иначе увёл бы копию на любой сервер
  static BackupTransferLink? parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        !const {'keqdroid', 'keqdis'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.toLowerCase() != _linkHost) {
      return null;
    }
    final q = uri.queryParameters;
    final host = q['h'] ?? '';
    final port = int.tryParse(q['p'] ?? '');
    final direction = switch (q['d']) {
      'r' => BackupTransferDirection.receive,
      'g' => BackupTransferDirection.give,
      _ => null,
    };
    final key = _decodeKey(q['k'] ?? '');
    if (!isPrivateIpv4(host) ||
        port == null ||
        port < 1 ||
        port > 65535 ||
        direction == null ||
        key == null) {
      return null;
    }
    return BackupTransferLink(
      host: host,
      port: port,
      direction: direction,
      key: key,
    );
  }

  static List<int>? _decodeKey(String text) {
    try {
      final key = base64Url.decode(base64Url.normalize(text));
      return key.length == 32 ? key : null;
    } on FormatException {
      return null;
    }
  }

  static List<int> newKey() {
    final random = Random.secure();
    return List<int>.generate(32, (_) => random.nextInt(256));
  }
}

Future<Uint8List> sealForTransfer(List<int> plain, List<int> key) =>
    BackupCrypto.seal(plain, keyId: BackupCrypto.keyTransfer, key: key);

Future<Uint8List> openFromTransfer(List<int> sealed, List<int> key) =>
    BackupCrypto.open(
      sealed,
      keyFor: (id) => id == BackupCrypto.keyTransfer
          ? key
          : throw const FormatException('Not a transfer backup'),
    );

typedef BackupReceiveHandler = Future<void> Function(Uint8List plain);
typedef BackupProvider = Future<List<int>> Function();

// один успешный обмен, дальше код недействителен
class BackupTransferServer {
  BackupTransferServer._(
    this._server,
    this.link, {
    BackupReceiveHandler? onReceived,
    BackupProvider? provide,
    void Function()? onGiven,
  }) : _onReceived = onReceived,
       _provide = provide,
       _onGiven = onGiven {
    _server.listen(
      (request) => unawaited(_handle(request).catchError((Object _) {})),
      onError: (Object _) {},
    );
  }

  final HttpServer _server;
  final BackupTransferLink link;
  final BackupReceiveHandler? _onReceived;
  final BackupProvider? _provide;
  final void Function()? _onGiven;
  bool _done = false;

  // картинки карточек подписок едут внутри копии
  static const maxBodyBytes = 64 * 1024 * 1024;

  static Future<BackupTransferServer> start({
    required String lanAddress,
    required BackupTransferDirection direction,
    BackupReceiveHandler? onReceived,
    BackupProvider? provide,
    void Function()? onGiven,
    @visibleForTesting InternetAddress? bindAddress,
  }) async {
    assert(
      direction == BackupTransferDirection.receive
          ? onReceived != null
          : provide != null,
    );
    final server = await HttpServer.bind(
      bindAddress ?? InternetAddress.anyIPv4,
      0,
    );
    return BackupTransferServer._(
      server,
      BackupTransferLink(
        host: lanAddress,
        port: server.port,
        direction: direction,
        key: BackupTransferLink.newKey(),
      ),
      onReceived: onReceived,
      provide: provide,
      onGiven: onGiven,
    );
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    if (request.uri.path != '/backup') {
      return _reply(response, HttpStatus.notFound);
    }
    if (_done) return _reply(response, HttpStatus.gone);
    if (link.direction == BackupTransferDirection.receive) {
      if (request.method != 'POST') {
        return _reply(response, HttpStatus.methodNotAllowed);
      }
      final body = await _readBody(request);
      if (body == null) {
        return _reply(response, HttpStatus.requestEntityTooLarge);
      }
      final Uint8List plain;
      try {
        plain = await openFromTransfer(body, link.key);
      } on FormatException {
        // не тем ключом: чужое устройство или старый код
        return _reply(response, HttpStatus.forbidden);
      }
      if (_done) return _reply(response, HttpStatus.gone);
      _done = true;
      // выбор, что восстановить, ждёт пользователя, а отправитель не должен висеть до него
      final handled = _onReceived!(plain);
      await _reply(response, HttpStatus.ok);
      await handled;
      return;
    }
    if (request.method != 'GET') {
      return _reply(response, HttpStatus.methodNotAllowed);
    }
    // иначе любой в сети забрал бы зашифрованную копию первым, и код стал бы недействителен для своего устройства
    if (!_sameProof(request.headers.value(proofHeader), giveProof(link.key))) {
      return _reply(response, HttpStatus.forbidden);
    }
    _done = true;
    final sealed = await sealForTransfer(await _provide!(), link.key);
    response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.binary
      ..contentLength = sealed.length
      ..add(sealed);
    await response.close();
    _onGiven?.call();
  }

  static const proofHeader = 'x-keqdroid-proof';

  static String giveProof(List<int> key) => base64Url.encode(
    hashes.Hmac(
      hashes.sha256,
      key,
    ).convert(utf8.encode('keqdroid backup give')).bytes,
  );

  // без раннего выхода, чтобы ключ не подобрать по времени ответа
  static bool _sameProof(String? got, String want) {
    if (got == null || got.length != want.length) return false;
    var diff = 0;
    for (var i = 0; i < want.length; i++) {
      diff |= got.codeUnitAt(i) ^ want.codeUnitAt(i);
    }
    return diff == 0;
  }

  static Future<Uint8List?> _readBody(HttpRequest request) async {
    if (request.contentLength > maxBodyBytes) return null;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in request) {
      bytes.add(chunk);
      if (bytes.length > maxBodyBytes) return null;
    }
    return bytes.takeBytes();
  }

  static Future<void> _reply(HttpResponse response, int status) async {
    response.statusCode = status;
    await response.close();
  }
}

enum BackupTransferFailure { unreachable, expired, rejected }

class BackupTransferException implements Exception {
  const BackupTransferException(this.failure, [this.detail]);

  final BackupTransferFailure failure;
  final String? detail;

  @override
  String toString() => 'BackupTransferException($failure, $detail)';
}

// соседнее устройство в той же Wi-Fi, с выхода VPN его не видно, поэтому напрямую, как с телевизором
HttpClient _lanClient() => HttpClient()
  ..findProxy = ((_) => 'DIRECT')
  ..connectionTimeout = const Duration(seconds: 5);

Future<void> sendBackup(
  BackupTransferLink link,
  List<int> plain, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final sealed = await sealForTransfer(plain, link.key);
  final client = _lanClient();
  try {
    final request = await client.post(link.host, link.port, '/backup');
    request
      ..headers.contentType = ContentType.binary
      ..contentLength = sealed.length
      ..add(sealed);
    final response = await request.close().timeout(timeout);
    await response.drain<void>().timeout(timeout);
    _check(response.statusCode);
  } on BackupTransferException {
    rethrow;
  } on IOException {
    throw const BackupTransferException(BackupTransferFailure.unreachable);
  } on TimeoutException {
    throw const BackupTransferException(BackupTransferFailure.unreachable);
  } finally {
    client.close(force: true);
  }
}

Future<Uint8List> fetchBackup(
  BackupTransferLink link, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final client = _lanClient();
  try {
    final request = await client.get(link.host, link.port, '/backup');
    request.headers.set(
      BackupTransferServer.proofHeader,
      BackupTransferServer.giveProof(link.key),
    );
    final response = await request.close().timeout(timeout);
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(timeout)) {
      bytes.add(chunk);
      if (bytes.length > BackupTransferServer.maxBodyBytes) {
        throw const BackupTransferException(BackupTransferFailure.rejected);
      }
    }
    _check(response.statusCode);
    try {
      return await openFromTransfer(bytes.takeBytes(), link.key);
    } on FormatException catch (e) {
      throw BackupTransferException(BackupTransferFailure.rejected, e.message);
    }
  } on BackupTransferException {
    rethrow;
  } on IOException {
    throw const BackupTransferException(BackupTransferFailure.unreachable);
  } on TimeoutException {
    throw const BackupTransferException(BackupTransferFailure.unreachable);
  } finally {
    client.close(force: true);
  }
}

void _check(int status) {
  if (status == HttpStatus.ok) return;
  if (status == HttpStatus.gone || status == HttpStatus.forbidden) {
    throw const BackupTransferException(BackupTransferFailure.expired);
  }
  throw BackupTransferException(BackupTransferFailure.rejected, 'HTTP $status');
}
