import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/app_logger.dart';

enum TunServiceState { missing, outdated, ready }

// служба KeqdroidTun (windows/tun_service) поднимает ядро в TUN, когда у приложения нет прав администратора
class WindowsTunService {
  WindowsTunService._();

  // windows/runner/windows_tun_service_client.cpp
  static const _channel = MethodChannel('keqdroid/tun_service');

  static _ServiceCoreProcess? _current;
  static bool _handlerSet = false;

  static Future<TunServiceState> state() async {
    if (!Platform.isWindows) return TunServiceState.missing;
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('status');
      if (map?['installed'] != true) return TunServiceState.missing;
      final error = map?['error'];
      if (error is String && error.isNotEmpty) {
        AppLogger.instance.warn('TUN service: $error');
      }
      return map?['trusted'] == true
          ? TunServiceState.ready
          : TunServiceState.outdated;
    } on MissingPluginException {
      return TunServiceState.missing;
    } on PlatformException catch (e) {
      AppLogger.instance.warn('TUN service status failed', error: e);
      return TunServiceState.missing;
    }
  }

  // окно UAC появляется один раз, и при обновлении приложения ещё раз: в службе суммы прежних ядер
  static Future<({bool ok, bool cancelled})> install() async {
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('install');
      final ok = map?['ok'] == true;
      if (!ok && map?['cancelled'] != true) {
        AppLogger.instance.warn(
          'TUN service install failed: code ${map?['code']}',
        );
      }
      return (ok: ok, cancelled: map?['cancelled'] == true);
    } on PlatformException catch (e) {
      AppLogger.instance.warn('TUN service install failed', error: e);
      return (ok: false, cancelled: false);
    } on MissingPluginException {
      return (ok: false, cancelled: false);
    }
  }

  static Future<Process> startCore({
    required String kind,
    required String config,
    String? geoDir,
    List<String> adapterIds = const [],
  }) async {
    _ensureHandler();
    final Map<String, Object?>? map;
    try {
      map = await _channel.invokeMapMethod<String, Object?>('startCore', {
        'kind': kind,
        'config': config,
        'geoDir': ?geoDir,
        'adapterIds': adapterIds,
      });
    } on PlatformException catch (e) {
      throw ProcessException('keqdroid-tun', [
        kind,
      ], 'TUN service: ${e.message ?? e.code}');
    }
    final removed =
        (map?['removedAdapters'] as List?)?.cast<String>() ?? const [];
    if (removed.isNotEmpty) {
      AppLogger.instance.info(
        'Removed stale TUN adapters: ${removed.join(', ')}',
      );
    }
    final process = _ServiceCoreProcess((map?['pid'] as int?) ?? 0);
    _current = process;
    return process;
  }

  // те же списки, что у службы в windows/tun_service/config_check.cpp: она отклонит конфиг целиком, здесь лишнее вырезаем
  static const _xraySections = {
    'log',
    'inbounds',
    'outbounds',
    'routing',
    'dns',
    'policy',
    'stats',
    'metrics',
    'fakedns',
    'observatory',
    'burstobservatory',
    'version',
  };
  static const _xrayDenied = {
    'script',
    'webhook',
    'certificatefile',
    'keyfile',
  };

  // xray от имени SYSTEM исполнил бы и запись лога в любой файл, и скачивание geodata, и чтение ключей с диска
  static String xrayForService(String xrayConfig) {
    final Object? json;
    try {
      json = jsonDecode(xrayConfig);
    } on FormatException {
      return xrayConfig;
    }
    if (json is! Map<String, dynamic>) return xrayConfig;
    var changed = false;
    json.removeWhere((key, _) {
      final drop = !_xraySections.contains(key.toLowerCase());
      changed |= drop;
      return drop;
    });
    void strip(Object? node) {
      if (node is Map) {
        node.removeWhere((key, _) {
          final drop = _xrayDenied.contains('$key'.toLowerCase());
          changed |= drop;
          return drop;
        });
        node.values.forEach(strip);
      } else if (node is List) {
        node.forEach(strip);
      }
    }

    strip(json);
    for (final entry in json.entries) {
      final log = entry.value;
      if (entry.key.toLowerCase() != 'log' || log is! Map) continue;
      for (final key in log.keys.toList()) {
        final name = '$key'.toLowerCase();
        if (name != 'access' && name != 'error') continue;
        final value = log[key];
        if (value == null || value == '' || '$value'.toLowerCase() == 'none') {
          continue;
        }
        log[key] = '';
        changed = true;
      }
    }
    return changed ? jsonEncode(json) : xrayConfig;
  }

  static Future<void> _stop({required bool graceful}) async {
    try {
      await _channel.invokeMethod<void>('stopCore', {'graceful': graceful});
    } on PlatformException catch (e) {
      AppLogger.instance.warn('TUN service stop failed', error: e);
    }
  }

  static void _ensureHandler() {
    if (_handlerSet) return;
    _handlerSet = true;
    _channel.setMethodCallHandler((call) async {
      final process = _current;
      final args = call.arguments;
      if (process == null || args is! Map) return;
      switch (call.method) {
        case 'onOutput':
          process._line(args['line'] as String? ?? '');
        case 'onExit':
          process._exit(args['code'] as int? ?? -1);
          if (identical(_current, process)) _current = null;
      }
    });
  }
}

// ядро службы под видом Process: бэкенд читает его вывод, ждёт выхода и гасит так же, как своё
class _ServiceCoreProcess implements Process {
  _ServiceCoreProcess(this.pid) {
    stdin = IOSink(_StdinCloser());
  }

  @override
  final int pid;

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

  void _line(String line) {
    if (!_stdout.isClosed) _stdout.add(utf8.encode('$line\n'));
  }

  void _exit(int code) {
    if (!_exitCode.isCompleted) _exitCode.complete(code);
    if (!_stdout.isClosed) unawaited(_stdout.close());
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    unawaited(WindowsTunService._stop(graceful: false));
    return true;
  }
}

// закрытый stdin у xray значит «выйди сам», служба закрывает настоящий stdin ядра
class _StdinCloser implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<void> close() => WindowsTunService._stop(graceful: true);
}
