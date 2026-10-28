import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../platform/platform_bootstrap.dart';
import '../models/ping_test_config.dart';
import '../models/server_item.dart';
import '../services/vpn_engine.dart';
import '../services/windows_desktop_service.dart';
import '../tunnel/vpn_backend.dart';
import '../tunnel/windows_tunnel_backend.dart';
import '../utils/config_gen.dart';
import '../utils/desktop_tun.dart';
import '../utils/hysteria_uri.dart';
import '../utils/mihomo_config_gen.dart';
import '../utils/multi_ping_config.dart';
import '../utils/pooled.dart';
import '../utils/vpn_core_support.dart';

enum PingType { tcp, url, speed, icmp }

enum PingLatencyQuality { good, fair, poor }

const String kDefaultPingTestUrl =
    'https://connectivitycheck.gstatic.com/generate_204';

class PingResult {
  final String serverId;
  final String serverName;
  final int? latencyMs;
  final bool success;
  final String error;
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
  static Future<PingResult> pingTcp(
    ServerItem server, {
    int timeoutSeconds = 5,
  }) async {
    final protocol = server.protocol;
    // AmneziaWG не отвечает ни на tcp-коннект, ни на случайный udp, остаётся ICMP
    if (protocol == 'awg') {
      return _pingIcmp(server, timeoutSeconds: timeoutSeconds);
    }
    if (protocol == 'hysteria' ||
        protocol == 'hysteria2' ||
        protocol == 'hy2' ||
        protocol == 'tuic') {
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

  static Future<PingResult> _pingIcmp(
    ServerItem server, {
    required int timeoutSeconds,
  }) async {
    final host = server.address;
    // host с минусом ping принял бы за флаг
    if (host.isEmpty || host.startsWith('-')) {
      return PingResult(
        serverId: server.id,
        serverName: server.displayName,
        success: false,
        error: 'Invalid server address',
        pingType: PingType.icmp,
      );
    }
    try {
      final timeoutMs = timeoutSeconds * 1000;
      final safeHost = RegExp(r'^[A-Za-z0-9._:\-]+$').hasMatch(host);
      final sw = Stopwatch()..start();
      final ProcessResult result;
      if (Platform.isWindows && safeHost) {
        // chcp 65001: иначе на русской Windows вывод в OEM-кодировке, и мс не парсится
        result = await Process.run(
          'cmd',
          ['/c', 'chcp 65001>nul & ping -n 1 -w $timeoutMs $host'],
          stdoutEncoding: utf8,
        ).timeout(Duration(seconds: timeoutSeconds + 3));
      } else {
        final args = Platform.isWindows
            ? ['-n', '1', '-w', '$timeoutMs', host]
            : ['-c', '1', '-W', '$timeoutSeconds', host];
        result = await Process.run('ping', args)
            .timeout(Duration(seconds: timeoutSeconds + 3));
      }
      sw.stop();
      final out = '${result.stdout}\n${result.stderr}';

      // вывод ping локализован: time=23ms, время=23мс, time=23.4 ms
      final timeMatch = RegExp(
        r'[=<]\s*([\d]+(?:[.,]\d+)?)\s*(?:ms|мс)',
        caseSensitive: false,
      ).firstMatch(out);
      final hasTtl = RegExp(r'ttl[=:]\s*\d+', caseSensitive: false).hasMatch(out);

      if (timeMatch != null || hasTtl) {
        final int ms;
        if (timeMatch != null) {
          ms = double.parse(timeMatch.group(1)!.replaceAll(',', '.')).round();
        } else {
          ms = sw.elapsedMilliseconds;
        }
        return PingResult(
          serverId: server.id,
          serverName: server.displayName,
          latencyMs: ms,
          success: true,
          pingType: PingType.icmp,
        );
      }
      return PingResult(
        serverId: server.id,
        serverName: server.displayName,
        success: false,
        error: 'ICMP: no reply (server may block ping)',
        pingType: PingType.icmp,
      );
    } catch (e) {
      return PingResult(
        serverId: server.id,
        serverName: server.displayName,
        success: false,
        error: e.toString(),
      );
    }
  }

  static Future<PingResult> _pingHysteria(
    ServerItem server, {
    required int timeoutSeconds,
  }) async {
    final params = HysteriaLinkParams.fromConfig(server.config);
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

      socket = await RawDatagramSocket.bind(
        target.type == InternetAddressType.IPv6
            ? InternetAddress.anyIPv6
            : InternetAddress.anyIPv4,
        0,
      );

      final sw = Stopwatch()..start();

      Uint8List payload;
      if (server.protocol == 'hysteria2' ||
          server.protocol == 'hy2' ||
          server.protocol == 'tuic') {
        // QUIC initial с выдуманной версией: сервер ответит version negotiation
        payload = Uint8List.fromList([
          0xc0, // long header
          0x12, 0x34, 0x56, 0x78, // dummy version
          0x08, // dcid len
          0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // dcid
          0x00, // scid len
        ]);
      } else if (server.protocol == 'awg') {
        payload = Uint8List(148);
        payload[0] = 1; // type: initiation
      } else {
        payload = Uint8List(32);
      }

      socket.send(payload, target, port);

      final completer = Completer<int?>();
      late final StreamSubscription<RawSocketEvent> sub;
      sub = socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket?.receive();
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

  // каждый замер это процесс с Go-рантаймом: 28 МБ у keqrnel, 19 у mihomo.
  // на телефоне больше шести держать негде
  static int get urlPingConcurrency => PlatformBootstrap.isDesktop ? 16 : 6;

  static Future<List<PingResult>> pingUrlBatch(
    List<ServerItem> servers,
    AppSettings settings, {
    String testUrl = kDefaultPingTestUrl,
    int timeoutSeconds = 15,
    Map<String, String>? resolvedIps,
    void Function(PingResult)? onResult,
    int? concurrency,
  }) async {
    if (servers.isEmpty) return [];
    final workers = concurrency ?? urlPingConcurrency;

    final ips = resolvedIps ?? await _resolveServerIps(servers);
    final takenPorts = <int>{};
    final outboundInterface = await _tunBypassInterface(settings);

    if (multiPingSupported) {
      final byCore = <VpnBackend, List<ServerItem>>{};
      final singles = <ServerItem>[];
      for (final server in servers) {
        if (mergeableForMultiPing(server.config)) {
          byCore.putIfAbsent(pingCoreFor(server.config, settings), () => []).add(server);
        } else {
          singles.add(server);
        }
      }
      if (byCore.values.any((group) => group.length > 1)) {
        final results = <String, PingResult>{};
        final batches = <({VpnBackend core, List<ServerItem> chunk})>[];
        for (final entry in byCore.entries) {
          final group = entry.value;
          if (group.length == 1) {
            singles.addAll(group);
            continue;
          }
          for (final chunk in _chunked(group, multiPingChunk)) {
            batches.add((core: entry.key, chunk: chunk));
          }
        }
        final measured = await mapPooled(
          batches,
          multiPingBatches,
          (batch) => _pingUrlMulti(
            batch.chunk,
            settings,
            core: batch.core,
            testUrl: testUrl,
            timeoutMs: timeoutSeconds * 1000,
            ips: ips,
            takenPorts: takenPorts,
            outboundInterface: outboundInterface,
            onResult: onResult,
          ),
        );
        for (final list in measured) {
          for (final result in list) {
            results[result.serverId] = result;
          }
        }
        final rest = await mapPooled(singles, workers, (server) async {
          final result = await _pingUrlSingle(
            server,
            settings,
            testUrl: testUrl,
            timeoutMs: timeoutSeconds * 1000,
            resolvedIp: ips[server.id],
            takenPorts: takenPorts,
            outboundInterface: outboundInterface,
          );
          onResult?.call(result);
          return result;
        });
        for (final result in rest) {
          results[result.serverId] = result;
        }
        return [
          for (final server in servers)
            results[server.id] ??
                PingResult(
                  serverId: server.id,
                  serverName: server.displayName,
                  success: false,
                  error: 'no result',
                  pingType: PingType.url,
                ),
        ];
      }
    }

    return mapPooled(servers, workers, (server) async {
      final result = await _pingUrlSingle(
        server,
        settings,
        testUrl: testUrl,
        timeoutMs: timeoutSeconds * 1000,
        resolvedIp: ips[server.id],
        takenPorts: takenPorts,
        outboundInterface: outboundInterface,
      );
      onResult?.call(result);
      return result;
    });
  }

  @visibleForTesting
  static bool? debugMultiPingSupported;

  @visibleForTesting
  static VpnEngine? debugEngine;

  static VpnEngine get _engine => debugEngine ?? VpnEngine();

  static bool get multiPingSupported =>
      debugMultiPingSupported ?? Platform.isAndroid;

  static const multiPingChunk = 10;

  static const multiPingBatches = 3;

  static bool mergeableForMultiPing(String serverConfig) =>
      detectServerFormat(serverConfig) == ServerFormat.link;

  static Iterable<List<T>> _chunked<T>(List<T> items, int size) sync* {
    for (var i = 0; i < items.length; i += size) {
      yield items.sublist(i, (i + size).clamp(0, items.length));
    }
  }

  // ядро не говорит, какой аутбаунд ему не понравился, поэтому делим пополам
  static Future<List<PingResult>> _pingUrlMulti(
    List<ServerItem> servers,
    AppSettings settings, {
    required VpnBackend core,
    required String testUrl,
    required int timeoutMs,
    required Map<String, String> ips,
    required Set<int> takenPorts,
    required String? outboundInterface,
    void Function(PingResult)? onResult,
  }) async {
    if (servers.isEmpty) return [];
    if (servers.length == 1) {
      final result = await _pingUrlSingle(
        servers.first,
        settings,
        testUrl: testUrl,
        timeoutMs: timeoutMs,
        resolvedIp: ips[servers.first.id],
        takenPorts: takenPorts,
        outboundInterface: outboundInterface,
      );
      onResult?.call(result);
      return [result];
    }

    final probes = <PingProbe>[];
    final measured = <ServerItem>[];
    final failed = <PingResult>[];
    for (final server in servers) {
      final port = await _freePort(avoid: takenPorts);
      takenPorts.add(port);
      try {
        probes.add((
          id: server.id,
          configJson: _pingConfigFor(
            core,
            server.config,
            settings,
            socksPort: port,
            resolvedServerIp: ips[server.id],
            outboundInterface: outboundInterface,
          ),
          port: port,
        ));
        measured.add(server);
      } catch (e) {
        final result = PingResult(
          serverId: server.id,
          serverName: server.displayName,
          success: false,
          error: e.toString(),
          pingType: PingType.url,
        );
        onResult?.call(result);
        failed.add(result);
      }
    }
    if (probes.isEmpty) return failed;

    final byId = {for (final server in measured) server.id: server};
    PingResult toResult(ServerItem server, bool success, int? latencyMs, String error) =>
        PingResult(
          serverId: server.id,
          serverName: server.displayName,
          latencyMs: latencyMs,
          success: success,
          error: error,
          pingType: PingType.url,
        );
    final reported = <String>{};

    List<({String id, bool success, int? latencyMs, String error, int? httpStatus})>?
        raw;
    try {
      raw = await _engine.xrayUrlTestMulti(
        config: core == VpnBackend.mihomo
            ? MultiPingConfig.mergeMihomo(probes, httpListeners: !Platform.isAndroid)
            : MultiPingConfig.mergeXray(probes),
        probes: [for (final probe in probes) (probe.id, probe.port)],
        core: core,
        testUrl: testUrl,
        timeoutMs: timeoutMs,
        keepAlive: settings.pingKeepAlive,
        onEach: onResult == null
            ? null
            : (item) {
                final server = byId[item.id];
                if (server == null || !reported.add(item.id)) return;
                onResult(toResult(server, item.success, item.latencyMs, item.error));
              },
      );
    } catch (_) {
      raw = null;
    }

    if (raw == null || raw.length != probes.length) {
      final half = measured.length ~/ 2;
      final left = await _pingUrlMulti(
        measured.sublist(0, half),
        settings,
        core: core,
        testUrl: testUrl,
        timeoutMs: timeoutMs,
        ips: ips,
        takenPorts: takenPorts,
        outboundInterface: outboundInterface,
        onResult: onResult,
      );
      final right = await _pingUrlMulti(
        measured.sublist(half),
        settings,
        core: core,
        testUrl: testUrl,
        timeoutMs: timeoutMs,
        ips: ips,
        takenPorts: takenPorts,
        outboundInterface: outboundInterface,
        onResult: onResult,
      );
      return [...failed, ...left, ...right];
    }

    final results = <PingResult>[];
    for (final item in raw) {
      final server = byId[item.id];
      if (server == null) continue;
      final result = toResult(server, item.success, item.latencyMs, item.error);
      if (!reported.contains(item.id)) onResult?.call(result);
      results.add(result);
    }
    return [...failed, ...results];
  }

  static VpnBackend pingCoreFor(String serverConfig, AppSettings settings) {
    final choice = resolveVpnBackend(
      config: serverConfig,
      preference: settings.vpnCore,
      mihomoAvailable: mihomoShipsHere,
    );
    return choice.backend == VpnBackend.mihomo
        ? VpnBackend.mihomo
        : VpnBackend.xray;
  }

  static String _pingConfigFor(
    VpnBackend core,
    String serverConfig,
    AppSettings settings, {
    required int socksPort,
    String? resolvedServerIp,
    required String? outboundInterface,
  }) =>
      core == VpnBackend.mihomo
          ? MihomoConfigGen.generatePingConfig(
              serverConfig,
              settings,
              socksPort: socksPort,
              httpInbound: !Platform.isAndroid,
              outboundInterface: outboundInterface,
            )
          : ConfigGeneratorV2.generatePingConfig(
              serverConfig,
              settings,
              socksPort: socksPort,
              resolvedServerIp: resolvedServerIp,
              httpInbound: !Platform.isAndroid,
              outboundInterface: outboundInterface,
            );

  // в TUN туннель нюхает SNI раньше правила своих процессов и подменяет адрес REALITY на маску:
  // замер сервера с маской store.teamfortress.com уходил к Valve. выходим той сетью, что ядро туннеля
  static Future<String?> _tunBypassInterface(AppSettings settings) async {
    if (!Platform.isWindows || !settings.tun.autoRoute) return null;
    final backend = WindowsTunnelBackend.activeInstance;
    if (backend == null || backend.activeMode != ConnectionMode.tun) return null;
    final cores = backend.activeCorePids;
    if (cores.isEmpty) return null;
    int? tunIndex;
    try {
      for (final iface in await NetworkInterface.list()) {
        if (iface.name == kTunInterfaceName ||
            iface.addresses.any((a) => a.address == kTunInterfaceAddress)) {
          tunIndex = iface.index;
          break;
        }
      }
    } catch (_) {}
    if (tunIndex == null) return null;
    return WindowsDesktopService.tunBypassInterface(
      tunIndex: tunIndex,
      mihomoRule: cores.containsKey('mihomo'),
    );
  }

  static Future<PingResult> _pingUrlSingle(
    ServerItem server,
    AppSettings settings, {
    required String testUrl,
    required int timeoutMs,
    String? resolvedIp,
    Set<int>? takenPorts,
    required String? outboundInterface,
  }) async {
    // порт на каждый замер: с общим проба уходила в чужое ядро и мерила не тот сервер
    final socksPort = await _freePort(avoid: takenPorts);
    // внутри try: исключение генератора иначе роняло бы весь батч
    try {
      final core = pingCoreFor(server.config, settings);
      final config = _pingConfigFor(
        core,
        server.config,
        settings,
        socksPort: socksPort,
        resolvedServerIp: resolvedIp,
        outboundInterface: outboundInterface,
      );
      final raw = await _engine.xrayUrlTest(
        xrayConfig: config,
        socksPort: socksPort,
        core: core,
        testUrl: testUrl,
        timeoutMs: timeoutMs,
        keepAlive: settings.pingKeepAlive,
      );
      return PingResult(
        serverId: server.id,
        serverName: server.displayName,
        latencyMs: raw.latencyMs,
        success: raw.success,
        error: raw.error,
        pingType: PingType.url,
      );
    } catch (e) {
      return PingResult(
        serverId: server.id,
        serverName: server.displayName,
        success: false,
        error: e.toString(),
        pingType: PingType.url,
      );
    }
  }

  static Future<List<PingResult>> pingSpeedBatch(
    List<ServerItem> servers,
    AppSettings settings, {
    int timeoutSeconds = 20,
    Map<String, String>? resolvedIps,
    void Function(PingResult)? onResult,
  }) async {
    if (servers.isEmpty) return [];

    final ips = resolvedIps ?? await _resolveServerIps(servers);
    final timeoutMs = timeoutSeconds * 1000;
    final results = <PingResult>[];
    final outboundInterface = await _tunBypassInterface(settings);

    for (final s in servers) {
      final socksPort = await _freePort();
      PingResult result;
      try {
        final core = pingCoreFor(s.config, settings);
        final config = _pingConfigFor(
          core,
          s.config,
          settings,
          socksPort: socksPort,
          resolvedServerIp: ips[s.id],
          outboundInterface: outboundInterface,
        );
        final raw = await _engine.xraySpeedTest(
          xrayConfig: config,
          socksPort: socksPort,
          core: core,
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

  static Future<int> _freePort({Set<int>? avoid}) async {
    var port = 0;
    for (var attempt = 0; attempt < 8; attempt++) {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      port = socket.port;
      await socket.close();
      if (avoid == null || avoid.add(port)) return port;
    }
    return port;
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

  static PingType pingTypeFromSettings(AppSettings settings) {
    switch (settings.pingType) {
      case 'url':
        return PingType.url;
      case 'speed':
        return PingType.speed;
      case 'icmp':
        return PingType.icmp;
      default:
        return PingType.tcp;
    }
  }

  static String testUrlFromSettings(AppSettings settings) =>
      PingTestConfig.resolveTestUrl(settings);

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
    // у цепочки tcp/icmp померил бы только входной узел
    if (server.protocol == 'chain') return PingType.url;
    return shouldUseUrlPingForServer(server, type) ? PingType.url : type;
  }

  // при поднятом TUN сырой tcp-коннект закрывает локальный стек, и у всех серверов одинаковые 2-4 мс
  static PingType pingTypeForConnectionState(
    PingType base, {
    required bool vpnConnected,
    required bool tunMode,
    bool? platformAlwaysTun,
  }) {
    // на Android активный режим в состояние не доезжает, а туннель там всегда TUN
    final throughTun = tunMode || (platformAlwaysTun ?? Platform.isAndroid);
    if (vpnConnected &&
        throughTun &&
        (base == PingType.tcp || base == PingType.icmp)) {
      return PingType.url;
    }
    return base;
  }

  static String pingTypeToStored(PingType type) => type.name;

  static PingType? pingTypeFromStored(String? raw) {
    switch (raw) {
      case 'url':
        return PingType.url;
      case 'speed':
        return PingType.speed;
      case 'icmp':
        return PingType.icmp;
      case 'tcp':
        return PingType.tcp;
      default:
        return null;
    }
  }

  static PingType pingColorTypeForServer(
    ServerItem server,
    AppSettings settings,
  ) {
    final stored = pingTypeFromStored(server.lastPingType);
    if (stored != null) return stored;
    return effectivePingType(server, pingTypeFromSettings(settings));
  }

  static const tcpPingGoodMs = 80;
  static const tcpPingFairMs = 150;
  static const urlPingGoodMs = 600;
  static const urlPingFairMs = 1200;
  static const speedGoodKbps = 25000;
  static const speedFairKbps = 8000;

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

  static String formatPingValue(int value, PingType type) {
    if (type == PingType.speed) {
      final mbps = value / 1000.0;
      return mbps >= 100
          ? '${mbps.toStringAsFixed(0)} Mbps'
          : '${mbps.toStringAsFixed(1)} Mbps';
    }
    return '$value ms';
  }

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
    if (effectiveType == PingType.icmp) {
      return _pingIcmp(server, timeoutSeconds: timeoutSeconds);
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
    // всегда временное ядро: у инбаунда VPN пароль, а HttpClient не умеет SOCKS с кредами
    return pingUrl(
      server,
      settings,
      testUrl: url,
      timeoutSeconds: timeoutSeconds,
      resolvedServerIp: resolvedServerIp,
    );
  }

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
    final icmpServers = servers
        .where((s) => effectivePingType(s, type) == PingType.icmp)
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

    for (var i = 0; i < icmpServers.length; i += batchSize) {
      final batch = icmpServers.skip(i).take(batchSize).toList();
      final batchResults = await Future.wait(
        batch.map((s) => _pingIcmp(s, timeoutSeconds: timeoutSeconds)),
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
