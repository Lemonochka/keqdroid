import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/app_logger.dart';
import '../core/exceptions.dart';
import '../models/probe_results.dart';
import '../services/core_dial_failures.dart';
import '../services/ephemeral_xray_ping.dart';
import '../services/xray_connection_lines.dart';
import '../services/xray_route_decisions.dart';
import '../utils/xray_session_log.dart';
import 'local_port_plan.dart';
import 'tunnel_backend.dart';
import 'tunnel_session_request.dart';
import 'tunnel_state.dart';
import 'vpn_backend.dart';

final _xrayStartedLine = RegExp(r'\bXray \S+ started\b');

// без подчёркиваний, как у DesktopTrafficStats: приватное у mixin видно только в своей библиотеке
mixin DesktopCoreSession {
  @protected
  final connectionLines = XrayConnectionLines();

  // до фильтра уровня: при loglevel error строка Warning в буфер не попадает
  @protected
  bool xrayStarted = false;

  @protected
  int xrayLogThreshold = 0;

  // пока идёт штатный стоп, сторож не должен принять наш kill за смерть ядра
  @protected
  bool stoppingSession = false;

  @protected
  Iterable<Process?> get sessionCores;

  @protected
  void emit(VpnState state);

  @protected
  Future<void> stopSessionInner({bool emitStates = true});

  @protected
  String? coreExitHint(String coreOutput) => null;

  @protected
  String coreExitDetails() => '';

  String exportConnectionLines() => connectionLines.text;

  Future<void> stopSession() async {
    stoppingSession = true;
    try {
      await stopSessionInner();
    } finally {
      stoppingSession = false;
    }
  }

  // без эмитов: disconnected из стрима проходит в UI и при connect-in-flight, кнопка проваливалась в серое
  @protected
  Future<void> cleanupForRestart() async {
    stoppingSession = true;
    try {
      await stopSessionInner(emitStates: false);
    } finally {
      stoppingSession = false;
    }
  }

  // без сторожа смерть ядра оставляла интерфейс в Connected, а системный прокси на мёртвом порту
  @protected
  void watchCoreExit(Process? process, String label) {
    if (process == null) return;
    unawaited(
      process.exitCode.then((code) async {
        if (stoppingSession) return;
        if (!sessionCores.any((core) => identical(core, process))) return;
        // хвост до teardown: голый exit code ничего не говорит, а после остановки логов уже нет
        final details = coreExitDetails();
        AppLogger.instance.error(
          '$label exited unexpectedly with code $code; tearing the session down'
          '$details',
        );
        try {
          await stopSession();
        } catch (e) {
          AppLogger.instance.warn('Teardown after core exit failed', error: e);
        }
        emit(
          VpnState(
            status: VpnStatus.error,
            errorMessage:
                '$label stopped unexpectedly (exit code $code). Disconnected.'
                '$details',
          ),
        );
      }),
    );
  }

  // только буфер: лог на каждую строку ядра подтормаживал UI при подключении
  @protected
  void appendCoreLine(StringBuffer buffer, String line) {
    if (!xrayStarted && _xrayStartedLine.hasMatch(line)) xrayStarted = true;
    CoreDialFailures.observe(line);
    XrayRouteDecisions.observe(line);
    connectionLines.add(line);
    if (!XraySessionLog.keep(line, xrayLogThreshold)) return;
    buffer.writeln(line);
    if (buffer.length > 64 * 1024) {
      final trimmed = coreLogTail(buffer, maxLines: 200);
      buffer
        ..clear()
        ..writeln(trimmed);
    }
  }

  @protected
  List<StreamSubscription<String>> listenCoreOutput(
    Process process,
    StringBuffer buffer,
  ) {
    // allowMalformed: строка ядра не в UTF-8 (ANSI у русской Windows) иначе роняет весь поток лога
    const decoder = Utf8Decoder(allowMalformed: true);
    // строки режем по всему потоку: кусок из трубы обрывается где попало
    StreamSubscription<String> listen(Stream<List<int>> stream) => stream
        .transform(decoder)
        .transform(const LineSplitter())
        .listen((line) => appendCoreLine(buffer, line));
    return [listen(process.stderr), listen(process.stdout)];
  }

  @protected
  Future<bool> waitForLocalPort(
    int port, {
    Process? process,
    StringBuffer? log,
    String processLabel = 'Process',
  }) async {
    var waited = 0;
    while (waited < 20000) {
      if (process != null) {
        final code = await exitCodeOrNull(process);
        if (code != null) {
          if (code != 0) {
            final buffer = log ?? StringBuffer();
            final hint = coreExitHint(buffer.toString());
            throw VpnStartException(
              '$processLabel exited with code $code.'
              '${hint == null ? '' : '\n$hint'}'
              '\n${coreLogTail(buffer)}',
            );
          }
          return false;
        }
      }
      try {
        final s = await Socket.connect(
          '127.0.0.1',
          port,
          timeout: const Duration(milliseconds: 400),
        );
        await s.close();
        return true;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        waited += 300;
      }
    }
    return false;
  }

  Future<int?> getPing(String address, int port) async {
    final sw = Stopwatch()..start();
    try {
      final s = await Socket.connect(
        address,
        port,
        timeout: const Duration(seconds: 5),
      );
      sw.stop();
      await s.close();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  Future<List<ServerUrlTestResult>?> xrayUrlTestMulti({
    required String config,
    required List<(String id, int port)> probes,
    VpnBackend core = VpnBackend.xray,
    String testUrl = 'https://connectivitycheck.gstatic.com/generate_204',
    int timeoutMs = 15000,
    bool keepAlive = true,
    int concurrency = 16,
    UrlTestProgress? onEach,
  }) => EphemeralXrayPing.urlTestMulti(
    configJson: config,
    probes: probes,
    core: core,
    testUrl: testUrl,
    timeoutMs: timeoutMs,
    keepAlive: keepAlive,
    concurrency: concurrency,
    onEach: onEach,
  );

  Future<List<ServerUrlTestResult>> xrayUrlTestBatch({
    required List<(String id, String xrayConfig)> items,
    required int socksPort,
    VpnBackend core = VpnBackend.xray,
    String testUrl = 'https://connectivitycheck.gstatic.com/generate_204',
    int timeoutMs = 15000,
    bool keepAlive = true,
  }) async {
    if (items.isEmpty) return [];
    final raw = await EphemeralXrayPing.urlTestBatch(
      items: items.map((e) => (id: e.$1, xrayConfigJson: e.$2)).toList(),
      socksPort: socksPort,
      core: core,
      testUrl: testUrl,
      timeoutMs: timeoutMs,
      keepAlive: keepAlive,
    );
    return raw
        .map(
          (r) => (
            id: r.id,
            success: r.success,
            latencyMs: r.latencyMs,
            error: r.error,
            httpStatus: r.httpStatus,
          ),
        )
        .toList();
  }

  Future<List<ServerSpeedTestResult>> xraySpeedTestBatch({
    required List<(String id, String xrayConfig)> items,
    required int socksPort,
    VpnBackend core = VpnBackend.xray,
    String downloadUrl = kDefaultSpeedTestUrl,
    int timeoutMs = 20000,
  }) async {
    if (items.isEmpty) return [];
    return EphemeralXrayPing.speedTestBatch(
      items: items.map((e) => (id: e.$1, xrayConfigJson: e.$2)).toList(),
      socksPort: socksPort,
      core: core,
      downloadUrl: downloadUrl,
      timeoutMs: timeoutMs,
    );
  }
}

String coreLogTail(StringBuffer buffer, {int maxLines = 12}) {
  final lines = buffer.toString().split('\n').where((l) => l.trim().isNotEmpty);
  final tail = lines.length > maxLines
      ? lines.skip(lines.length - maxLines)
      : lines;
  final text = tail.join('\n');
  return text.isEmpty ? '(no process output)' : text;
}

// убитый сигналом процесс на Linux даёт отрицательный код, поэтому выход проверяем по null
Future<int?> exitCodeOrNull(Process process) => process.exitCode
    .then<int?>((c) => c)
    .timeout(const Duration(milliseconds: 1), onTimeout: () => null);

Future<void> stopCoreProcess(Process? process, {bool graceful = false}) async {
  if (process == null) return;
  try {
    if (graceful) {
      // kill на Windows делает жёсткий TerminateProcess, и ядро не вернуло бы адаптер и маршруты;
      // xray мягко выходит по EOF на stdin, tool/patches/xray-desktop-stdin-stop.patch
      try {
        await process.stdin.close();
      } catch (_) {}
      final code = await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -2,
      );
      if (code != -2) return;
    }
    process.kill(ProcessSignal.sigterm);
    await process.exitCode.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  } catch (_) {}
}

Future<void> deleteSessionDir(Directory? dir) async {
  if (dir == null || !dir.existsSync()) return;
  try {
    await dir.delete(recursive: true);
  } catch (e) {
    AppLogger.instance.debug('Session dir not deleted', error: e);
  }
}

Future<int> freeLoopbackPort() async {
  final s = await ServerSocket.bind('127.0.0.1', 0);
  final port = s.port;
  await s.close();
  return port;
}

// HTTP-инбаунд ядро поднимает всегда (через него ходит апдейтер), и занятый порт роняет его целиком
Future<void> ensureLocalPortsFree(TunnelSessionRequest request) async {
  final socksIssue = await LocalPortResolver.probe(
    '127.0.0.1',
    request.socksPort,
  );
  if (socksIssue != null) {
    throw VpnStartException(
      localPortBlockedMessage(
        label: 'SOCKS',
        port: request.socksPort,
        issue: socksIssue,
      ),
    );
  }
  final httpIssue = await LocalPortResolver.probe(
    '127.0.0.1',
    request.httpPort,
  );
  if (httpIssue != null) {
    throw VpnStartException(
      localPortBlockedMessage(
        label: 'HTTP',
        port: request.httpPort,
        issue: httpIssue,
      ),
    );
  }
}
