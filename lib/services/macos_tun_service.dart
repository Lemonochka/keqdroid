import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../core/app_logger.dart';
import '../tunnel/macos_core_paths.dart';
import '../tunnel/macos_elevation.dart';
import 'windows_tun_service.dart' show TunServiceState, WindowsTunService;

export 'windows_tun_service.dart' show TunServiceState;

// LaunchDaemon com.keqdroid.tun (tool/macos_tun_daemon) поднимает ядро в режиме TUN без повторного ввода пароля
class MacosTunService {
  MacosTunService._();

  static const plistPath = '/Library/LaunchDaemons/com.keqdroid.tun.plist';
  static const socketDir = '/var/run/keqdroid-tun';
  static const socketPath = '$socketDir/tun.sock';
  static const _protocolVersion = '1';
  static const _maxFrameBytes = 64 << 20;

  @visibleForTesting
  static Future<Socket> Function()? connectOverride;

  @visibleForTesting
  static Future<
    ({
      Stream<Uint8List> incoming,
      Future<void> Function(Uint8List data) send,
      Future<void> Function() close,
    })
  >
  Function()?
  transportOverride;

  @visibleForTesting
  static bool Function()? plistExistsOverride;

  @visibleForTesting
  static Future<({String xray, String mihomo})> Function()? coreHashesOverride;

  @visibleForTesting
  static Future<({int exitCode, String stderr})> Function(List<String> argv)?
  runAdminOverride;

  @visibleForTesting
  static int? uidOverride;

  static _MacosServiceCoreProcess? _current;

  static bool get isAvailable =>
      Platform.isMacOS || connectOverride != null || transportOverride != null;

  static bool isInstalledSync() =>
      plistExistsOverride?.call() ??
      (Platform.isMacOS && File(plistPath).existsSync());

  static Future<TunServiceState> state() async {
    if (!isAvailable) return TunServiceState.missing;
    if (!isInstalledSync()) return TunServiceState.missing;
    try {
      final hashes = await _bundledCoreHashes();
      if (hashes.xray.isEmpty || hashes.mihomo.isEmpty) {
        return TunServiceState.outdated;
      }
      final client = await _openFrameClient();
      try {
        await client.writeFrame('version');
        final reply = await client.readFrame().timeout(
          const Duration(seconds: 3),
        );
        final parts = reply.split('\n');
        final trusted =
            parts.length == 4 &&
            parts[0] == 'version' &&
            parts[1] == _protocolVersion &&
            parts[2] == hashes.xray &&
            parts[3] == hashes.mihomo;
        return trusted ? TunServiceState.ready : TunServiceState.outdated;
      } finally {
        await client.close();
      }
    } catch (e) {
      AppLogger.instance.debug('macOS TUN service status check failed: $e');
      return TunServiceState.outdated;
    }
  }

  static Future<({bool ok, bool cancelled})> install() async {
    final daemonBin = MacosCorePaths.daemonExecutable();
    if (daemonBin == null) {
      AppLogger.instance.warn(
        'keqdroid-tun binary is missing next to macOS cores',
      );
      return (ok: false, cancelled: false);
    }
    final uid = uidOverride ?? macosRealUid();
    if (uid <= 0) {
      AppLogger.instance.warn('macOS TUN service install: invalid uid $uid');
      return (ok: false, cancelled: false);
    }
    final binDir = p.dirname(daemonBin);
    try {
      final run = runAdminOverride ?? runMacosAdminCommand;
      final res = await run([daemonBin, 'install', '$uid', binDir]);
      if (res.exitCode == 0) return (ok: true, cancelled: false);
      final cancelled = macosAdminCancelled(res.stderr);
      if (!cancelled) {
        AppLogger.instance.warn(
          'macOS TUN service install failed (exit ${res.exitCode}): ${res.stderr}',
        );
      }
      return (ok: false, cancelled: cancelled);
    } catch (e) {
      AppLogger.instance.warn('macOS TUN service install failed', error: e);
      return (ok: false, cancelled: false);
    }
  }

  static Future<({bool ok, bool cancelled})> uninstall() async {
    final daemonBin =
        MacosCorePaths.daemonExecutable() ??
        '/Library/Application Support/keqdroid-tun/bin/keqdroid-tun';
    if (!File(daemonBin).existsSync() && runAdminOverride == null) {
      return (ok: !isInstalledSync(), cancelled: false);
    }
    try {
      final run = runAdminOverride ?? runMacosAdminCommand;
      final res = await run([daemonBin, 'uninstall']);
      if (res.exitCode == 0) return (ok: true, cancelled: false);
      final cancelled = macosAdminCancelled(res.stderr);
      if (!cancelled) {
        AppLogger.instance.warn(
          'macOS TUN service uninstall failed (exit ${res.exitCode}): ${res.stderr}',
        );
      }
      return (ok: false, cancelled: cancelled);
    } catch (e) {
      AppLogger.instance.warn('macOS TUN service uninstall failed', error: e);
      return (ok: false, cancelled: false);
    }
  }

  static String xrayForService(String xrayConfig) =>
      WindowsTunService.xrayForService(xrayConfig);

  static Future<Process> startCore({
    required String kind,
    required String config,
    String? geoDir,
  }) async {
    final _FrameSocket client;
    try {
      client = await _openFrameClient();
    } catch (e) {
      throw ProcessException('keqdroid-tun', [
        kind,
      ], 'TUN service is unreachable: $e');
    }

    final appDir = MacosCorePaths.bundleBinDir();
    final payload = 'start\n$kind\n$appDir\n${geoDir ?? ''}\n$config';
    try {
      await client.writeFrame(payload);
      final reply = await client.readFrame().timeout(
        const Duration(seconds: 10),
      );
      if (reply.startsWith('error\n')) {
        await client.close();
        throw ProcessException('keqdroid-tun', [
          kind,
        ], 'TUN service: ${reply.substring('error\n'.length)}');
      }
      if (!reply.startsWith('ok\n')) {
        await client.close();
        throw ProcessException('keqdroid-tun', [
          kind,
        ], 'TUN service returned unexpected response: $reply');
      }
      final corePid = int.tryParse(reply.substring('ok\n'.length).trim()) ?? 0;
      final process = _MacosServiceCoreProcess(corePid, client);
      _current = process;
      process._pumpFrames(() {
        if (identical(_current, process)) _current = null;
      });
      return process;
    } catch (e) {
      await client.close();
      if (e is ProcessException) rethrow;
      throw ProcessException('keqdroid-tun', [kind], 'TUN service: $e');
    }
  }

  static Future<({String xray, String mihomo})> _bundledCoreHashes() async {
    final override = coreHashesOverride;
    if (override != null) return override();
    final xrayPath = MacosCorePaths.bundledCorePath('xray');
    final mihomoPath = MacosCorePaths.bundledCorePath('mihomo');
    if (xrayPath == null || mihomoPath == null) {
      return (xray: '', mihomo: '');
    }
    final results = await Future.wait([
      MacosCorePaths.sha256Of(xrayPath),
      MacosCorePaths.sha256Of(mihomoPath),
    ]);
    return (xray: results[0], mihomo: results[1]);
  }

  static Future<_FrameSocket> _openFrameClient() async {
    final customTransport = transportOverride;
    if (customTransport != null) {
      final t = await customTransport();
      return _FrameSocket(incoming: t.incoming, send: t.send, onClose: t.close);
    }
    final override = connectOverride;
    if (override != null) {
      return _FrameSocket.fromSocket(await override());
    }
    final dirStat = FileStat.statSync(socketDir);
    if (dirStat.type != FileSystemEntityType.directory ||
        Link(socketDir).existsSync()) {
      throw const SocketException('TUN service socket directory is missing');
    }
    final sock = await Socket.connect(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
      timeout: const Duration(seconds: 2),
    );
    return _FrameSocket.fromSocket(sock);
  }
}

class _FrameSocket {
  _FrameSocket({
    required Stream<Uint8List> incoming,
    required Future<void> Function(Uint8List data) send,
    required Future<void> Function() onClose,
  }) : _send = send,
       _onClose = onClose {
    _sub = incoming.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: true,
    );
  }

  factory _FrameSocket.fromSocket(Socket socket) => _FrameSocket(
    incoming: socket,
    send: (packet) async {
      socket.add(packet);
      await socket.flush();
    },
    onClose: () async => socket.destroy(),
  );

  final Future<void> Function(Uint8List data) _send;
  final Future<void> Function() _onClose;
  late final StreamSubscription<Uint8List> _sub;
  Uint8List _buf = Uint8List(0);
  int _offset = 0;
  final List<Completer<String>> _waiters = [];
  Future<void> _writeChain = Future<void>.value();
  Object? _error;
  bool _closed = false;

  void _onData(Uint8List chunk) {
    if (chunk.isEmpty) return;
    final remaining = _buf.length - _offset;
    if (remaining == 0) {
      _buf = chunk;
      _offset = 0;
    } else {
      final combined = Uint8List(remaining + chunk.length)
        ..setRange(0, remaining, _buf, _offset)
        ..setRange(remaining, remaining + chunk.length, chunk);
      _buf = combined;
      _offset = 0;
    }
    _drainFrames();
  }

  Future<String>? _tryTakeFrame() {
    final available = _buf.length - _offset;
    if (available < 4) return null;
    final len = ByteData.sublistView(
      _buf,
      _offset,
      _offset + 4,
    ).getUint32(0, Endian.little);
    if (len > MacosTunService._maxFrameBytes) {
      const err = SocketException('TUN service frame exceeds limit');
      _failAll(err);
      return Future.error(err);
    }
    if (available < 4 + len) return null;
    final frame = const Utf8Decoder(
      allowMalformed: true,
    ).convert(Uint8List.sublistView(_buf, _offset + 4, _offset + 4 + len));
    _offset += 4 + len;
    if (_offset == _buf.length) {
      _buf = Uint8List(0);
      _offset = 0;
    }
    return Future.value(frame);
  }

  void _drainFrames() {
    while (_waiters.isNotEmpty) {
      final available = _buf.length - _offset;
      if (available < 4) return;
      final len = ByteData.sublistView(
        _buf,
        _offset,
        _offset + 4,
      ).getUint32(0, Endian.little);
      if (len > MacosTunService._maxFrameBytes) {
        _failAll(const SocketException('TUN service frame exceeds limit'));
        return;
      }
      if (available < 4 + len) return;
      final frame = const Utf8Decoder(
        allowMalformed: true,
      ).convert(Uint8List.sublistView(_buf, _offset + 4, _offset + 4 + len));
      _offset += 4 + len;
      if (_offset == _buf.length) {
        _buf = Uint8List(0);
        _offset = 0;
      }
      _waiters.removeAt(0).complete(frame);
    }
  }

  void _onError(Object error, StackTrace st) {
    _failAll(error);
  }

  void _onDone() {
    _closed = true;
    _failAll(const SocketException('TUN service closed connection'));
  }

  void _failAll(Object error) {
    _error ??= error;
    while (_waiters.isNotEmpty) {
      _waiters.removeAt(0).completeError(error);
    }
  }

  Future<String> readFrame() {
    if (_waiters.isEmpty) {
      final ready = _tryTakeFrame();
      if (ready != null) return ready;
    }
    if (_error != null) return Future.error(_error!);
    if (_closed) {
      return Future.error(
        const SocketException('TUN service closed connection'),
      );
    }
    final completer = Completer<String>();
    _waiters.add(completer);
    return completer.future;
  }

  // flush у dart:io Socket внутри зовёт addStream и падает с Bad state при параллельном вызове writeFrame
  Future<void> writeFrame(String frame) {
    final payload = utf8.encode(frame);
    final header = ByteData(4)..setUint32(0, payload.length, Endian.little);
    final packet = Uint8List(4 + payload.length)
      ..setRange(0, 4, header.buffer.asUint8List())
      ..setRange(4, 4 + payload.length, payload);
    final next = _writeChain.then((_) async {
      if (_closed) {
        throw const SocketException('TUN service client closed');
      }
      await _send(packet);
    });
    _writeChain = next.catchError((Object _) {});
    return next;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    unawaited(_sub.cancel());
    await _onClose();
    _failAll(const SocketException('TUN service client closed'));
  }
}

class _MacosServiceCoreProcess implements Process {
  _MacosServiceCoreProcess(this.pid, this._client) {
    stdin = IOSink(_MacosStdinCloser(() => _stop(graceful: true)));
  }

  @override
  final int pid;

  final _FrameSocket _client;
  final _stdout = StreamController<List<int>>();
  final _exitCode = Completer<int>();

  @override
  late final IOSink stdin;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  Future<int> get exitCode => _exitCode.future;

  void _pumpFrames(void Function() onDone) {
    unawaited(() async {
      int? code;
      try {
        while (true) {
          final frame = await _client.readFrame();
          if (frame.startsWith('out\n')) {
            final line = frame.substring('out\n'.length);
            if (!_stdout.isClosed) _stdout.add(utf8.encode('$line\n'));
          } else if (frame.startsWith('exit\n')) {
            code = int.tryParse(frame.substring('exit\n'.length).trim()) ?? -1;
            break;
          }
        }
      } catch (_) {
        code ??= -1;
      } finally {
        onDone();
        await _client.close();
        _finish(code ?? -1);
      }
    }());
  }

  void _finish(int code) {
    if (!_exitCode.isCompleted) _exitCode.complete(code);
    if (!_stdout.isClosed) unawaited(_stdout.close());
  }

  Future<void> _stop({required bool graceful}) async {
    try {
      await _client.writeFrame(graceful ? 'stop' : 'kill');
    } catch (_) {}
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    unawaited(
      _stop(
        graceful:
            signal == ProcessSignal.sigterm || signal == ProcessSignal.sigint,
      ),
    );
    return true;
  }
}

class _MacosStdinCloser implements StreamConsumer<List<int>> {
  _MacosStdinCloser(this._onClose);

  final Future<void> Function() _onClose;

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<void> close() => _onClose();
}
