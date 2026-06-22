import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'socks5_credentials.dart';

/// Routes [dio] through the app's local HTTP proxy (keqrnel / xray).
///
/// Dart [HttpClient.findProxy] only understands `PROXY host:port` and `DIRECT`,
/// not `SOCKS` / `SOCKS5` — using SOCKS there throws
/// `HttpException: Invalid proxy configuration SOCKS5 …` on Windows.
void configureDioForLocalVpnHttpProxy(
  Dio dio, {
  required int httpPort,
  String? username,
  String? password,
}) {
  final user = username ?? Socks5Credentials().username;
  final pass = password ?? Socks5Credentials().password;
  final host = InternetAddress.loopbackIPv4.address;

  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      client.findProxy = (_) => 'PROXY $host:$httpPort';
      if (user.isNotEmpty && pass.isNotEmpty) {
        client.addProxyCredentials(
          host,
          httpPort,
          '',
          HttpClientBasicCredentials(user, pass),
        );
      }
      return client;
    },
  );
}

/// When the VPN is up, GitHub/update traffic must ride the tunnel on desktop.
/// On Android the app's sockets are already captured by [VpnService], so Dio
/// can stay direct.
void configureDioForActiveVpn(
  Dio dio, {
  required bool vpnConnected,
  required int httpPort,
}) {
  if (!vpnConnected) return;
  if (Platform.isAndroid) return;
  configureDioForLocalVpnHttpProxy(dio, httpPort: httpPort);
}
