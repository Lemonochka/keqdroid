import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../models/app_settings.dart';
import '../models/ping_test_config.dart';
import '../models/server_item.dart';
import '../services/vpn_engine.dart';
import '../utils/config_gen.dart';
import '../utils/hysteria_uri.dart';

/// tcp = raw connect latency, url = GET via ephemeral xray,
/// speed = download throughput in kbps (not ms).
enum PingType { tcp, url, speed }

/// latency bands for ui coloring
enum PingLatencyQuality { good, fair, poor }

const String kDefaultPingTestUrl =
    'https://connectivitycheck.gstatic.com/generate_204';

class PingResult {
  final String serverId;
  final String serverName;
  final int? latencyMs;
  final bool success;
  final String error;
  /// метод, которым получили результат (нужен для порогов цвета)
  final PingType pingType;

  const PingResult({
    required this.serverId,
    required this.serverName,
    this.latencyMs,
    required this.success,
    this.error = '',
    this.pingType = PingType.tcp,
  });

  @override
  String toString() => success
      ? 'PingResult($serverName: ${latencyMs}ms)'
      : 'PingResult($serverName: FAIL - $error)';
}

class PingService {
  /// tcp-пинг: меряем время коннекта, работает без vpn
  static Future<PingResult> pingTcp(
    ServerItem server, {
    int timeoutSeconds = 5,
  }) async {
    final protocol = server.protocol;
    // udp-протоколы пингуем через udp сокет
    if (protocol == 'awg' ||
        protocol == 'hysteria' ||
        protocol == 'hysteria2' ||
        protocol == 'hy2') {
      return _pingHysteria(server, timeoutSeconds: timeoutSeconds);
    }

    final address = server.address;
    final port = server.port;

    if (address.isEmpty || port == 0) {
      return PingResult(
        serverId: server.id,
        serverName: server.displayName,
        success: false,
        error: 'Invalid server address or port',
      );
    }

    Socket? socket;
    try {
      final sw = Stopwatch()..start();
      socket = await Socket.connect(
        address,
        port,
        timeout: Duration(seconds: timeoutSeconds),
      );
      sw.stop();

      return PingResult(
        serverId: server.id,
        serverName: server.displayName,
        latencyMs: sw.elapsedMilliseconds,
        success: true,
      );
    } on SocketException catch (e) {
      return PingResult(
        serverId: server.id,
        serverName: server.displayName,
        success: false,
        error: 'Connection failed: ${e.message}',
      );
    } on TimeoutException {
      return PingResult(
        serverId: server.id,
        serverName: server.displayName,
        success: false,
        error: 'Timeout (${timeoutSeconds}s)',
      );
    } catch (e) {
      return PingResult(
        serverId: server.id,
        serverName: server.displayName,
        success: false,
        error: e.toString(),
      );
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }

  /// hysteria/hy2: пробуем udp quic, при obfs или таймауте — фоллбэк на tcp
  static Future<PingResult> _pingHysteria(
    ServerItem server, {
    required int timeoutSeconds,
  }) async {
    final params = HysteriaLinkParams.fromConfig(server.config);
    // с salamander obfs обычные udp/tcp пробы не доходят до hy2
    if (params.hasSalamanderObfs) {
      return PingResult(
        serverId: server.id,
        serverName: server.displayName,
        success: false,
        error: 'Hysteria2+obfs: use HTTP via proxy ping in Advanced settings',
      );
    }

    final udp = await _pingUdp(server, timeoutSeconds: timeoutSeconds);
    if (udp.success) return udp;

    final tcp = await _pingTcpReachability(server, timeoutSeconds: timeoutSeconds);
    if (tcp.success) {
      return PingResult(
        serverId: server.id,
        serverName: server.displayName,
        latencyMs: tcp.latencyMs,
        success: true,
      );
    }

    return PingResult(
      serverId: server.id,
      serverName: server.displayName,
      success: false,
      error: udp.error.isNotEmpty ? udp.error : tcp.error,
    );
  }

  /// просто проверка доступности по tcp, без хендшейка hysteria
  static Future<PingResult> _pingTcpReachability(
    ServerItem server, {
    required int timeoutSeconds,
  }) async {
    final address = server.address;
    final port = server.port;
    if (address.isEmpty || port == 0) {
      return PingResult(
        serverId: server.id,
        serverName: server.displayName,
        success: false,
        error: 'Invalid server address or port',
      );
    }

    Socket? socket;
    try {
      final sw = Stopwatch()..start();
      socket = await Socket.connect(
        address,
        port,
        timeout: Duration(seconds: timeoutSeconds),
      );
      sw.stop();
      return PingResult(
        serverId: server.id,
        serverName: server.displayName,
        latencyMs: sw.elapsedMilliseconds,
        success: true,
      );
    } on SocketException catch (e) {
      return PingResult(
        serverId: server.id,
        serverName: server.displayName,
        success: false,
        error: 'TCP: ${e.message}',
      );
    } on TimeoutException {
      return PingResult(
        serverId: server.id,
        serverName: server.displayName,
        success: false,
        error: 'TCP timeout (${timeoutSeconds}s)',
      );
    } catch (e) {
      return PingResult(
        serverId: server.id,
        serverName: server.displayName,
        success: false,
        error: e.toString(),
      );
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }

  /// udp-пинг для wireguard и hysteria (quic)
  static Future<PingResult> _pingUdp(
    ServerItem server, {
    required int timeoutSeconds,
  }) async {
    final address = server.address;
    final port = server.port;
    if (address.isEmpty || port == 0) {
      return PingResult(
        serverId: server.id,
        serverName: server.displayName,
        success: false,
        error: 'Invalid Endpoint',
      );
    }

    RawDatagramSocket? socket;
    try {
      final targets = await InternetAddress.lookup(address)
          .timeout(Duration(seconds: timeoutSeconds));
      if (targets.isEmpty) {
        return PingResult(
          serverId: server.id,
          serverName: server.displayName,
          success: false,
          error: 'DNS lookup failed',
        );
      }
      final target = targets.first;

      // биндимся на любой порт, учитывая ipv4/ipv6
      socket = await RawDatagramSocket.bind(
        target.type == InternetAddressType.IPv6
            ? InternetAddress.anyIPv6
            : InternetAddress.anyIPv4,
        0,
      );

      final sw = Stopwatch()..start();

      // пейлоад зависит от протокола
      Uint8List payload;
      if (server.protocol == 'hysteria2' || server.protocol == 'hy2') {
        // quic initial с фейковой версией, чтобы спровоцировать version negotiation
        payload = Uint8List.fromList([
          0xc0, // long header
          0x12, 0x34, 0x56, 0x78, // dummy version
          0x08, // dcid len
          0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // dcid
          0x00, // scid len
        ]);
      } else if (server.protocol == 'awg') {
        // wireguard handshake initiation, упрощённый заголовок
        payload = Uint8List(148);
        payload[0] = 1; // type: initiation
      } else {
        // hysteria 1 или общий udp
        payload = Uint8List(32);
      }

      socket.send(payload, target, port);

      final completer = Completer<int?>();
      late final StreamSubscription<RawSocketEvent> sub;
      sub = socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket?.receive();
          // любой ответ — значит сервер живой
          if (dg != null && !completer.isCompleted) {
            sw.stop();
            completer.complete(sw.elapsedMilliseconds);
          }
        }
      });

      final ms = await completer.future.timeout(
        Duration(seconds: timeoutSeconds),
        onTimeout: () => null,
      );

      await sub.cancel();

      if (ms != null) {
        return PingResult(
          serverId: server.id,
          serverName: server.displayName,
          latencyMs: ms,
          success: true,
        );
      }
      return PingResult(
        serverId: server.id,
        serverName: server.displayName,
        success: false,
        error: 'No UDP reply',
      );
    } catch (e) {
      return PingResult(
        serverId: server.id,
        serverName: server.displayName,
        success: false,
        error: e.toString(),
      );
    } finally {
      socket?.close();
    }
  }

  /// http get через локальный socks5. не работает: vpn socks требует auth,
  /// а HttpClient не умеет слать креды. используй pingUrl.
  @Deprecated('Use pingUrl; VPN SOCKS requires auth that HttpClient cannot provide')
  static Future<PingResult> pingViaLocalProxy(
    ServerItem server,
    int proxyPort, {
    String testUrl = kDefaultPingTestUrl,
    int timeoutSeconds = 15,
  }) =>
      _httpGetViaSocks(
        server: server,
        socksPort: proxyPort,
        testUrl: testUrl,
        timeoutSeconds: timeoutSeconds,
      );

  /// реальный пинг: поднимает временный xray на outbound сервера и делает get
  static Future<PingResult> pingUrl(
    ServerItem server,
    AppSettings settings, {
    String testUrl = kDefaultPingTestUrl,
    int timeoutSeconds = 15,
    String? resolvedServerIp,
  }) async {
    final results = await pingUrlBatch(
      [server],
      settings,
      testUrl: testUrl,
      timeoutSeconds: timeoutSeconds,
      resolvedIps: resolvedServerIp != null
          ? {server.id: resolvedServerIp}
          : null,
    );
    return results.first;
  }

  /// батч url-пинга: dns параллельно, onResult дёргается после каждого сервера для ui
  static Future<List<PingResult>> pingUrlBatch(
    List<ServerItem> servers,
    AppSettings settings, {
    String testUrl = kDefaultPingTestUrl,
    int timeoutSeconds = 15,
    Map<String, String>? resolvedIps,
    void Function(PingResult)? onResult,
  }) async {
    if (servers.isEmpty) return [];

    final socksPort = ConfigGeneratorV2.ephemeralPingPort;
    final ips = resolvedIps ?? await _resolveServerIps(servers);
    final timeoutMs = timeoutSeconds * 1000;
    final results = <PingResult>[];

    for (final s in servers) {
      final config = ConfigGeneratorV2.generatePingConfig(
        s.config,
        settings,
        socksPort: socksPort,
        resolvedServerIp: ips[s.id],
      );
      PingResult result;
      try {
        final raw = await VpnEngine().xrayUrlTest(
          xrayConfig: config,
          socksPort: socksPort,
          testUrl: testUrl,
          timeoutMs: timeoutMs,
        );
        result = PingResult(
          serverId: s.id,
          serverName: s.displayName,
          latencyMs: raw.latencyMs,
          success: raw.success,
          error: raw.error,
          pingType: PingType.url,
        );
      } catch (e) {
        result = PingResult(
          serverId: s.id,
          serverName: s.displayName,
          success: false,
          error: e.toString(),
          pingType: PingType.url,
        );
      }
      results.add(result);
      onResult?.call(result);
    }

    return results;
  }

  /// батч спидтеста: на каждый сервер поднимаем временный xray и меряем
  /// скорость скачивания (kbps), кладём её в PingResult.latencyMs
  static Future<List<PingResult>> pingSpeedBatch(
    List<ServerItem> servers,
    AppSettings settings, {
    int timeoutSeconds = 20,
    Map<String, String>? resolvedIps,
    void Function(PingResult)? onResult,
  }) async {
    if (servers.isEmpty) return [];

    final socksPort = ConfigGeneratorV2.ephemeralPingPort;
    final ips = resolvedIps ?? await _resolveServerIps(servers);
    final timeoutMs = timeoutSeconds * 1000;
    final results = <PingResult>[];

    for (final s in servers) {
      final config = ConfigGeneratorV2.generatePingConfig(
        s.config,
        settings,
        socksPort: socksPort,
        resolvedServerIp: ips[s.id],
      );
      PingResult result;
      try {
        final raw = await VpnEngine().xraySpeedTest(
          xrayConfig: config,
          socksPort: socksPort,
          timeoutMs: timeoutMs,
        );
        result = PingResult(
          serverId: s.id,
          serverName: s.displayName,
          latencyMs: raw.kbps,
          success: raw.success,
          error: raw.error,
          pingType: PingType.speed,
        );
      } catch (e) {
        result = PingResult(
          serverId: s.id,
          serverName: s.displayName,
          success: false,
          error: e.toString(),
          pingType: PingType.speed,
        );
      }
      results.add(result);
      onResult?.call(result);
    }

    return results;
  }

  static Future<Map<String, String>> _resolveServerIps(
    List<ServerItem> servers,
  ) async {
    final out = <String, String>{};
    await Future.wait(
      servers.map((s) async {
        try {
          final addresses = await InternetAddress.lookup(s.address)
              .timeout(const Duration(seconds: 3));
          if (addresses.isNotEmpty) out[s.id] = addresses.first.address;
        } catch (_) {}
      }),
    );
    return out;
  }

  static Future<PingResult> _httpGetViaSocks({
    required ServerItem server,
    required int socksPort,
    required String testUrl,
    required int timeoutSeconds,
  }) async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.findProxy = (_) => 'SOCKS5 127.0.0.1:$socksPort';
      client.connectionTimeout = Duration(seconds: timeoutSeconds);
      client.badCertificateCallback = (_, __, ___) => true;

      final sw = Stopwatch()..start();
      final req = await client.getUrl(Uri.parse(testUrl));
      req.headers.set('User-Agent', 'KEQDIS/3.1');
      req.headers.set('Connection', 'close');
      final res = await req.close();
      await res.drain<void>();
      sw.stop();

      final ok = res.statusCode == 204 ||
          res.statusCode == 200 ||
          (res.statusCode >= 200 && res.statusCode < 400);
      return PingResult(
        serverId: server.id,
        serverName: server.displayName,
        latencyMs: sw.elapsedMilliseconds,
        success: ok,
        error: ok ? '' : 'HTTP ${res.statusCode}',
      );
    } on SocketException catch (e) {
      return PingResult(
        serverId: server.id,
        serverName: server.displayName,
        success: false,
        error: 'Socket: ${e.message}',
      );
    } on TimeoutException {
      return PingResult(
        serverId: server.id,
        serverName: server.displayName,
        success: false,
        error: 'Timeout',
      );
    } on HandshakeException catch (e) {
      return PingResult(
        serverId: server.id,
        serverName: server.displayName,
        success: false,
        error: 'TLS: ${e.message}',
      );
    } catch (e) {
      return PingResult(
        serverId: server.id,
        serverName: server.displayName,
        success: false,
        error: e.toString(),
      );
    } finally {
      try {
        client?.close(force: true);
      } catch (_) {}
    }
  }

  static PingType pingTypeFromSettings(AppSettings settings) {
    switch (settings.pingType) {
      case 'url':
        return PingType.url;
      case 'speed':
        return PingType.speed;
      default:
        return PingType.tcp;
    }
  }

  static String testUrlFromSettings(AppSettings settings) =>
      PingTestConfig.resolveTestUrl(settings);

  /// hy2/udp+obfs нельзя померить tcp/udp пробами, нужен реальный http-пинг
  static bool shouldUseUrlPingForServer(ServerItem server, PingType type) {
    if (type == PingType.url) return true;
    final protocol = server.protocol;
    if (protocol != 'hysteria' &&
        protocol != 'hysteria2' &&
        protocol != 'hy2') {
      return false;
    }
    return HysteriaLinkParams.fromConfig(server.config).hasSalamanderObfs;
  }

  static PingType effectivePingType(ServerItem server, PingType type) {
    if (type == PingType.speed) return PingType.speed;
    return shouldUseUrlPingForServer(server, type) ? PingType.url : type;
  }

  /// при активном tun raw tcp-коннект закрывает локальный tun-стек ещё до того,
  /// как syn дойдёт до сервера, поэтому все сервера показывают одинаковую низкую
  /// задержку. в этом случае осмысленен только url-пинг через временный core,
  /// который делает реальный round-trip в обход туннеля.
  static PingType pingTypeForConnectionState(
    PingType base, {
    required bool vpnConnected,
    required bool tunMode,
  }) {
    // через tun неизмерим только raw tcp; url и speed идут через временный core
    if (vpnConnected && tunMode && base == PingType.tcp) return PingType.url;
    return base;
  }

  static String pingTypeToStored(PingType type) => type.name;

  static PingType? pingTypeFromStored(String? raw) {
    switch (raw) {
      case 'url':
        return PingType.url;
      case 'speed':
        return PingType.speed;
      case 'tcp':
        return PingType.tcp;
      default:
        return null;
    }
  }

  /// тип для порогов цвета: берём сохранённый last ping type, иначе из настроек
  static PingType pingColorTypeForServer(
    ServerItem server,
    AppSettings settings,
  ) {
    final stored = pingTypeFromStored(server.lastPingType);
    if (stored != null) return stored;
    return effectivePingType(server, pingTypeFromSettings(settings));
  }

  // tcp — прямой коннект, мало ms. url — xray + socks + http, базовая планка выше
  static const tcpPingGoodMs = 80;
  static const tcpPingFairMs = 150;
  static const urlPingGoodMs = 600;
  static const urlPingFairMs = 1200;
  // для speed это kbps, больше — лучше (шкала перевёрнута)
  static const speedGoodKbps = 25000;
  static const speedFairKbps = 8000;

  /// для speed value — это kbps (больше лучше), иначе задержка в ms (меньше лучше)
  static PingLatencyQuality pingLatencyQuality(int value, PingType type) {
    if (type == PingType.speed) {
      if (value >= speedGoodKbps) return PingLatencyQuality.good;
      if (value >= speedFairKbps) return PingLatencyQuality.fair;
      return PingLatencyQuality.poor;
    }
    final (good, fair) = type == PingType.url
        ? (urlPingGoodMs, urlPingFairMs)
        : (tcpPingGoodMs, tcpPingFairMs);
    if (value < good) return PingLatencyQuality.good;
    if (value < fair) return PingLatencyQuality.fair;
    return PingLatencyQuality.poor;
  }

  /// формат значения для ui: mbps для спидтеста, иначе ms
  static String formatPingValue(int value, PingType type) {
    if (type == PingType.speed) {
      final mbps = value / 1000.0;
      return mbps >= 100
          ? '${mbps.toStringAsFixed(0)} Mbps'
          : '${mbps.toStringAsFixed(1)} Mbps';
    }
    return '$value ms';
  }

  /// универсальный пинг: tcp или http через xray
  static Future<PingResult> ping(
    ServerItem server,
    PingType type, {
    AppSettings settings = const AppSettings(),
    int proxyPort = 2080,
    int timeoutSeconds = 5,
    String? testUrl,
    String? resolvedServerIp,
    bool vpnConnected = false,
  }) async {
    final url = testUrl ?? testUrlFromSettings(settings);
    final effectiveType = effectivePingType(server, type);
    if (effectiveType == PingType.tcp) {
      return pingTcp(server, timeoutSeconds: timeoutSeconds);
    }
    if (effectiveType == PingType.speed) {
      final results = await pingSpeedBatch(
        [server],
        settings,
        timeoutSeconds: timeoutSeconds,
        resolvedIps: resolvedServerIp != null
            ? {server.id: resolvedServerIp}
            : null,
      );
      return results.first;
    }
    // всегда временный xray: vpn socks inbound с паролем, а HttpClient
    // не умеет слать socks5 креды (в логах: invalid username or password)
    return pingUrl(
      server,
      settings,
      testUrl: url,
      timeoutSeconds: timeoutSeconds,
      resolvedServerIp: resolvedServerIp,
    );
  }

  /// параллельный пинг нескольких серверов батчами по batchSize.
  /// url-пинг идёт одним батчем (xray последовательно, без channel на каждый)
  static Future<List<PingResult>> pingBatch(
    List<ServerItem> servers,
    PingType type, {
    AppSettings settings = const AppSettings(),
    int proxyPort = 2080,
    int timeoutSeconds = 5,
    int batchSize = 5,
    String? testUrl,
    bool vpnConnected = false,
    Future<String?> Function(ServerItem server)? resolveServerIp,
    void Function(PingResult)? onResult,
  }) async {
    final url = testUrl ?? testUrlFromSettings(settings);
    final resultById = <String, PingResult>{};

    final urlServers = servers
        .where((s) => effectivePingType(s, type) == PingType.url)
        .toList();
    final speedServers = servers
        .where((s) => effectivePingType(s, type) == PingType.speed)
        .toList();
    final tcpServers = servers
        .where((s) => effectivePingType(s, type) == PingType.tcp)
        .toList();

    if (speedServers.isNotEmpty) {
      Map<String, String>? ips;
      if (resolveServerIp != null) {
        ips = {};
        await Future.wait(
          speedServers.map((s) async {
            final ip = await resolveServerIp(s);
            if (ip != null) ips![s.id] = ip;
          }),
        );
      }
      final speedResults = await pingSpeedBatch(
        speedServers,
        settings,
        timeoutSeconds: timeoutSeconds,
        resolvedIps: ips,
        onResult: onResult,
      );
      for (final r in speedResults) {
        resultById[r.serverId] = r;
      }
    }

    if (urlServers.isNotEmpty) {
      Map<String, String>? ips;
      if (resolveServerIp != null) {
        ips = {};
        await Future.wait(
          urlServers.map((s) async {
            final ip = await resolveServerIp(s);
            if (ip != null) ips![s.id] = ip;
          }),
        );
      }
      final urlResults = await pingUrlBatch(
        urlServers,
        settings,
        testUrl: url,
        timeoutSeconds: timeoutSeconds,
        resolvedIps: ips,
        onResult: onResult,
      );
      for (final r in urlResults) {
        resultById[r.serverId] = r;
      }
    }

    for (var i = 0; i < tcpServers.length; i += batchSize) {
      final batch = tcpServers.skip(i).take(batchSize).toList();
      final batchResults = await Future.wait(
        batch.map((s) => pingTcp(s, timeoutSeconds: timeoutSeconds)),
      );
      for (final r in batchResults) {
        resultById[r.serverId] = r;
        onResult?.call(r);
      }
    }

    return servers
        .map(
          (s) =>
              resultById[s.id] ??
              PingResult(
                serverId: s.id,
                serverName: s.displayName,
                success: false,
                error: 'Ping skipped',
                pingType: effectivePingType(s, type),
              ),
        )
        .toList();
  }
}
