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

/// When the VPN is up, GitHub/update traffic must ride the tunnel through the
/// local HTTP inbound. That applies on Android too: the VpnService excludes the
/// app's own package from the TUN (иначе in-process xray зациклился бы), так
/// что «сокеты и так в туннеле» — неправда, прямой Dio ходит мимо VPN и
/// упирается в блокировку release-assets.githubusercontent.com.
///
/// Единственный случай без локального прокси — Android + AmneziaWG (чистый
/// amneziawg-go, xray не запущен): там собственный пакет включён в TUN и
/// прямой Dio едет через туннель сам. Вызывающий код обязан передать
/// useLocalProxy=false в этом случае — см. [tunnelHasLocalHttpProxy].
void configureDioForActiveVpn(
  Dio dio, {
  required bool useLocalProxy,
  required int httpPort,
}) {
  if (!useLocalProxy) return;
  configureDioForLocalVpnHttpProxy(dio, httpPort: httpPort);
}

/// Есть ли у активного туннеля локальный HTTP-инбаунд на 127.0.0.1:httpPort,
/// через который Dio может выйти в сеть по туннелю:
///  - desktop: есть всегда (xray/keqrnel http-in; wireproxy [http] в awg);
///  - Android xray: есть (http-in из config_gen работает и в chain-режиме);
///  - Android awg: нет — но пакет приложения включён в TUN, прокси не нужен.
bool tunnelHasLocalHttpProxy({
  required bool vpnConnected,
  required bool awgBackend,
}) =>
    vpnConnected && !(Platform.isAndroid && awgBackend);
