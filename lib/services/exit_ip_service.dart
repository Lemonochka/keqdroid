import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/server_flag.dart';
import '../utils/exit_ip_probe.dart';
import '../utils/local_vpn_proxy.dart';

class ExitIp {
  const ExitIp({required this.ip, this.countryCode});

  final String ip;

  final String? countryCode;

  FlagArt? get flag {
    final code = countryCode?.toLowerCase();
    return code != null && flagArtCodes.contains(code) ? FlagArt(code) : null;
  }
}

// Трассировка Cloudflare отдаёт и ip=, и loc=, а Cloudflare приложению уже знаком по пингу. Ходим через
// локальный HTTP-инбаунд: пакет приложения исключён из туннеля, и прямой запрос показал бы адрес без VPN
abstract final class ExitIpService {
  static Future<ExitIp?> lookup({
    required int proxyPort,
    Duration timeout = const Duration(seconds: 8),
    @visibleForTesting Uri? traceUrl,
  }) async {
    final url = traceUrl ?? Uri.parse(kExitIpProbeUrl);
    final client = HttpClient()..connectionTimeout = timeout;
    configureHttpClientForLocalVpnProxy(client, () => proxyPort);
    try {
      final request = await client.getUrl(url).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      return parseTrace(await utf8.decodeStream(response).timeout(timeout));
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  @visibleForTesting
  static ExitIp? parseTrace(String body) {
    String? ip;
    String? loc;
    for (final line in const LineSplitter().convert(body)) {
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final value = line.substring(eq + 1).trim();
      switch (line.substring(0, eq)) {
        case 'ip':
          ip = value;
        case 'loc':
          loc = value.toUpperCase();
      }
    }
    if (ip == null || InternetAddress.tryParse(ip) == null) return null;
    final known = loc != null && RegExp(r'^[A-Z]{2}$').hasMatch(loc) && loc != 'XX';
    return ExitIp(ip: ip, countryCode: known ? loc : null);
  }
}
