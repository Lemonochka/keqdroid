import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

// единственный HTTP приложения мимо локального инбаунда: телевизор в той же Wi-Fi, с выхода VPN её не видно

class TvPairing {
  const TvPairing({
    required this.host,
    required this.port,
    required this.token,
  });

  final String host;
  final int port;
  final String token;

  static const _linkHost = 'tv-send';

  String toLink() => Uri(
        scheme: 'keqdroid',
        host: _linkHost,
        queryParameters: {'h': host, 'p': '$port', 't': token},
      ).toString();

  // только частный IPv4: подложенный QR иначе увёл бы подписку на любой сервер
  static TvPairing? parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        !const {'keqdroid', 'keqdis'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.toLowerCase() != _linkHost) {
      return null;
    }
    final q = uri.queryParameters;
    final host = q['h'] ?? '';
    final port = int.tryParse(q['p'] ?? '');
    final token = q['t'] ?? '';
    if (!isPrivateIpv4(host) ||
        port == null ||
        port < 1 ||
        port > 65535 ||
        token.length < 16) {
      return null;
    }
    return TvPairing(host: host, port: port, token: token);
  }
}

bool isPrivateIpv4(String host) {
  final addr = InternetAddress.tryParse(host);
  if (addr == null || addr.type != InternetAddressType.IPv4) return false;
  final b = addr.rawAddress;
  return b[0] == 10 ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168);
}

// у туннеля тоже частный адрес, но телефону до него не достучаться; на ПК так же с адаптерами WSL, Hyper-V, Docker и виртуалок
String? pickLanAddress(Iterable<({String name, String address})> candidates) {
  const tunnels = [
    'tun', 'ppp', 'wg', 'ipsec', 'rmnet', 'dummy', 'meta', 'wintun',
    'vethernet', 'virtualbox', 'vmware', 'docker', 'br-', 'veth', 'virbr',
    'tailscale', 'zt', 'hyper-v', 'loopback',
  ];
  final usable = [
    for (final c in candidates)
      if (isPrivateIpv4(c.address) &&
          !tunnels.any((t) => c.name.toLowerCase().startsWith(t)))
        c,
  ];
  // wlan0/eth0 у Android, Wi-Fi/Ethernet у Windows, wlp/enp/eno у Linux
  int rank(String name) {
    final n = name.toLowerCase();
    const real = ['wlan', 'wi-fi', 'wifi', 'wl', 'eth', 'en'];
    return real.any(n.startsWith) ? 0 : 1;
  }

  usable.sort((a, b) => rank(a.name).compareTo(rank(b.name)));
  return usable.isEmpty ? null : usable.first.address;
}

Future<String?> findLanAddress() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );
  return pickLanAddress([
    for (final i in interfaces)
      for (final a in i.addresses) (name: i.name, address: a.address),
  ]);
}

// идентичность не передаём: телевизор другое устройство
class TvSubscriptionOffer {
  const TvSubscriptionOffer({
    required this.url,
    this.name,
    this.nameIsAuto = true,
  });

  final String url;
  final String? name;
  final bool nameIsAuto;

  Map<String, Object?> toJson() => {
        'url': url,
        if (name != null) 'name': name,
        'auto': nameIsAuto,
      };

  static TvSubscriptionOffer? fromJson(Map<Object?, Object?> json) {
    final url = (json['url'] as String?)?.trim() ?? '';
    final uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    var name = (json['name'] as String?)?.trim();
    if (name != null && name.isEmpty) name = null;
    if (name != null && name.length > 200) name = name.substring(0, 200);
    return TvSubscriptionOffer(
      url: url,
      name: name,
      nameIsAuto: name == null || json['auto'] != false,
    );
  }
}

typedef TvOfferHandler = Future<String?> Function(TvSubscriptionOffer offer);

class TvReceiveServer {
  TvReceiveServer._(this._server, this.pairing, this._onOffer) {
    // обрыв посреди ответа иначе ушёл бы в Crashlytics как фатальный
    _server.listen(
      (request) => unawaited(_handle(request).catchError((Object _) {})),
      onError: (Object _) {},
    );
  }

  final HttpServer _server;
  final TvPairing pairing;
  final TvOfferHandler _onOffer;

  static const maxBodyBytes = 64 * 1024;

  static Future<TvReceiveServer> start({
    required String lanAddress,
    required TvOfferHandler onOffer,
  }) async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    final random = Random.secure();
    final token = base64Url
        .encode(List.generate(16, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    return TvReceiveServer._(
      server,
      TvPairing(host: lanAddress, port: server.port, token: token),
      onOffer,
    );
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    if (request.uri.path != '/add') {
      return _reply(response, HttpStatus.notFound);
    }
    if (request.method != 'POST') {
      return _reply(response, HttpStatus.methodNotAllowed);
    }
    final Object? json;
    try {
      final body = await _readBody(request);
      if (body == null) {
        return _reply(response, HttpStatus.requestEntityTooLarge);
      }
      json = jsonDecode(body);
    } catch (_) {
      return _reply(response, HttpStatus.badRequest);
    }
    if (json is! Map) return _reply(response, HttpStatus.badRequest);
    if (!_sameToken(json['t'], pairing.token)) {
      return _reply(response, HttpStatus.forbidden);
    }
    final offer = TvSubscriptionOffer.fromJson(json);
    if (offer == null) return _reply(response, HttpStatus.badRequest);
    String? error;
    try {
      error = await _onOffer(offer);
    } catch (e) {
      error = '$e';
    }
    if (error != null) {
      return _reply(response, HttpStatus.unprocessableEntity, error);
    }
    return _reply(response, HttpStatus.ok);
  }

  static Future<String?> _readBody(HttpRequest request) async {
    if (request.contentLength > maxBodyBytes) return null;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in request) {
      bytes.add(chunk);
      if (bytes.length > maxBodyBytes) return null;
    }
    return utf8.decode(bytes.takeBytes());
  }

  // без раннего выхода, чтобы ключ не подобрать по времени ответа
  static bool _sameToken(Object? got, String want) {
    if (got is! String || got.length != want.length) return false;
    var diff = 0;
    for (var i = 0; i < want.length; i++) {
      diff |= got.codeUnitAt(i) ^ want.codeUnitAt(i);
    }
    return diff == 0;
  }

  static Future<void> _reply(
    HttpResponse response,
    int status, [
    String? error,
  ]) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode({'ok': status == HttpStatus.ok, 'error': ?error}));
    await response.close();
  }
}

enum TvSendFailure {
  unreachable,

  expired,

  rejected,
}

class TvSendException implements Exception {
  const TvSendException(this.failure, [this.message]);

  final TvSendFailure failure;

  final String? message;

  @override
  String toString() => 'TvSendException($failure, $message)';
}

Future<void> sendToTv(
  TvPairing tv,
  TvSubscriptionOffer offer, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final client = HttpClient()
    ..findProxy = ((_) => 'DIRECT')
    ..connectionTimeout = const Duration(seconds: 5);
  try {
    final request = await client.post(tv.host, tv.port, '/add');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'t': tv.token, ...offer.toJson()}));
    final response = await request.close().timeout(timeout);
    final body = await utf8.decodeStream(response).timeout(timeout);
    if (response.statusCode == HttpStatus.ok) return;
    if (response.statusCode == HttpStatus.forbidden) {
      throw const TvSendException(TvSendFailure.expired);
    }
    String? message;
    try {
      message = (jsonDecode(body) as Map)['error'] as String?;
    } catch (_) {}
    throw TvSendException(
      TvSendFailure.rejected,
      message ?? 'HTTP ${response.statusCode}',
    );
  } on TvSendException {
    rethrow;
  } on IOException {
    throw const TvSendException(TvSendFailure.unreachable);
  } on TimeoutException {
    throw const TvSendException(TvSendFailure.unreachable);
  } finally {
    client.close(force: true);
  }
}
