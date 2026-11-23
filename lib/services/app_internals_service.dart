import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../core/app_logger.dart';
import '../models/app_internals.dart';
import '../models/app_settings.dart';
import '../platform/vpn_native_bridge.dart';
import '../tunnel/linux_core_paths.dart';
import '../tunnel/linux_tunnel_backend.dart';
import '../tunnel/macos_core_paths.dart';
import '../tunnel/macos_tunnel_backend.dart';
import '../tunnel/tunnel_state.dart';
import '../tunnel/windows_core_paths.dart';
import '../tunnel/windows_tunnel_backend.dart';
import '../utils/go_build_info.dart';
import '../utils/mihomo_api_session.dart';
import 'geo_asset_service.dart';
import 'windows_desktop_service.dart';

class AppInternalsService {
  AppInternalsService._();

  static const _engineModules = <String, String>{'xtls/xray-core': 'xray-core'};

  static Future<AppInternals> collect({
    required AppSettings settings,
    required VpnState? state,
  }) async {
    final android = await VpnNativeBridge.getNativeInternals();
    return AppInternals(
      cores: await _cachedCores(android),
      geoBases: await _geoBases(),
      session: await _session(settings, state, android),
      build: await _build(android),
      processExits: await _processExits(android),
    );
  }

  static Future<List<ProcessExit>> processExits() async =>
      _processExits(await VpnNativeBridge.getNativeInternals());

  static Future<List<ProcessExit>> _processExits(
    Map<String, Object?> android,
  ) async {
    final sdkInt = android['sdkInt'] as int?;
    return [
      for (final map in await VpnNativeBridge.getProcessExits())
        ?ProcessExit.fromMap(map, sdkInt: sdkInt),
    ];
  }

  static Future<List<CoreInfo>>? _coresCache;

  static void resetCacheForTests() => _coresCache = null;

  static Future<List<CoreInfo>> _cachedCores(Map<String, Object?> android) =>
      _coresCache ??= _cores(android);

  static Future<List<CoreInfo>> _cores(Map<String, Object?> android) async {
    if (Platform.isAndroid) {
      final dir = android['nativeLibraryDir'] as String?;
      if (dir == null || dir.isEmpty) return const [];
      return [
        await _core(p.join(dir, 'libxray.so'), 'libxray.so', CoreRole.proxy),
        await _core(
          p.join(dir, 'libmihomo.so'),
          'libmihomo.so',
          CoreRole.proxy,
        ),
      ];
    }
    if (Platform.isWindows) {
      return [
        await _core(
          await WindowsCorePaths.xrayExecutable(),
          'xray.exe',
          CoreRole.core,
        ),
        await _core(
          await WindowsCorePaths.mihomoExecutable(),
          'mihomo.exe',
          CoreRole.core,
        ),
      ];
    }
    if (Platform.isLinux) {
      return [
        await _core(
          await LinuxCorePaths.xrayExecutable(),
          'xray',
          CoreRole.core,
        ),
        await _core(
          await LinuxCorePaths.mihomoExecutable(),
          'mihomo',
          CoreRole.core,
        ),
      ];
    }
    if (Platform.isMacOS) {
      return [
        await _core(
          await MacosCorePaths.xrayExecutable(),
          'xray',
          CoreRole.core,
        ),
        await _core(
          await MacosCorePaths.mihomoExecutable(),
          'mihomo',
          CoreRole.core,
        ),
      ];
    }
    return const [];
  }

  static Future<CoreInfo> _core(
    String? path,
    String name,
    CoreRole role,
  ) async {
    if (path == null) return CoreInfo.missing(name: name, role: role);
    final file = File(path);
    if (!file.existsSync()) return CoreInfo.missing(name: name, role: role);

    final stat = await file.stat();
    final info = await GoBuildInfo.fromFile(file);
    return CoreInfo(
      name: name,
      role: role,
      version: info == null ? null : formatVersion(info.moduleVersion),
      goVersion: info?.goVersion,
      path: path,
      sizeBytes: stat.size,
      modified: meaningfulDate(stat.modified),
      engines: info == null ? const {} : _engines(info),
    );
  }

  // у библиотек внутри APK дата из zip-записи, Android отдаёт 1981-01-01 для всех
  static DateTime? meaningfulDate(DateTime? date) {
    if (date == null) return null;
    return date.year < 2000 ? null : date;
  }

  static Map<String, String> _engines(GoBuildInfo info) {
    final engines = <String, String>{};
    for (final entry in _engineModules.entries) {
      if (info.isModule(entry.key)) continue;
      final version = info.depVersion(entry.key);
      if (version == null) continue;
      final formatted = formatVersion(version);
      if (formatted != null) engines[entry.value] = formatted;
    }
    return engines;
  }

  static String? formatVersion(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty || value == '(devel)') return null;
    final pseudo = _pseudoVersion.firstMatch(value);
    if (pseudo == null) return value;
    return '${pseudo.group(1)} · ${pseudo.group(3)}';
  }

  static final _pseudoVersion = RegExp(
    r'^(.*?)-(?:[\w.]+\.)?(\d{14})-([0-9a-f]{12})$',
  );

  static Future<List<GeoBaseInfo>> _geoBases() async {
    final dir = await GeoAssetService.geoDir();
    final index = await GeoAssetService.index();
    if (dir == null) {
      return const [
        GeoBaseInfo(name: 'geoip.dat', codeCount: 0, missing: true),
        GeoBaseInfo(name: 'geosite.dat', codeCount: 0, missing: true),
      ];
    }
    return [
      await _geoBase(dir, 'geoip.dat', index.geoipCodes.length),
      await _geoBase(dir, 'geosite.dat', index.geositeCodes.length),
    ];
  }

  static Future<GeoBaseInfo> _geoBase(
    String dir,
    String name,
    int codeCount,
  ) async {
    final file = File(p.join(dir, name));
    if (!file.existsSync()) {
      return GeoBaseInfo(name: name, codeCount: 0, missing: true);
    }
    final stat = await file.stat();
    return GeoBaseInfo(
      name: name,
      codeCount: codeCount,
      sizeBytes: stat.size,
      modified: meaningfulDate(stat.modified),
    );
  }

  static Future<SessionInfo> _session(
    AppSettings settings,
    VpnState? state,
    Map<String, Object?> android,
  ) async {
    return SessionInfo(
      status: state?.status ?? VpnStatus.disconnected,
      engine: Platform.isAndroid
          ? _androidCoreBinary(android)
          : _desktopEngine(),
      mode: Platform.isAndroid ? null : settings.connectionModeEnum,
      socksPort: settings.localPort,
      httpPort: settings.httpPort,
      uptime: state?.duration,
      corePids: _corePids(android),
      elevated: Platform.isWindows
          ? await WindowsDesktopService.isProcessElevated()
          : null,
      clashApiPort: Platform.isWindows
          ? WindowsTunnelBackend.activeInstance?.clashApiPort
          : Platform.isAndroid
          ? MihomoApiSession().port
          : Platform.isLinux
          ? LinuxTunnelBackend.activeInstance?.clashApiPort
          : Platform.isMacOS
          ? MacosTunnelBackend.activeInstance?.clashApiPort
          : null,
    );
  }

  static String _desktopEngine() {
    final pids = Platform.isWindows
        ? WindowsTunnelBackend.activeInstance?.activeCorePids
        : Platform.isMacOS
        ? MacosTunnelBackend.activeInstance?.activeCorePids
        : LinuxTunnelBackend.activeInstance?.activeCorePids;
    if (pids != null && pids.keys.any((k) => k.startsWith('mihomo'))) {
      return 'mihomo';
    }
    return 'xray';
  }

  static String _androidCoreBinary(Map<String, Object?> android) =>
      android['coreKind'] == 'mihomo' ? 'libmihomo' : 'libxray';

  static Map<String, int> _corePids(Map<String, Object?> android) {
    if (Platform.isAndroid) {
      final core = android['xrayPid'] as int? ?? -1;
      return {if (core > 0) _androidCoreBinary(android): core};
    }
    if (Platform.isWindows) {
      return WindowsTunnelBackend.activeInstance?.activeCorePids ?? const {};
    }
    if (Platform.isLinux) {
      return LinuxTunnelBackend.activeInstance?.activeCorePids ?? const {};
    }
    if (Platform.isMacOS) {
      return MacosTunnelBackend.activeInstance?.activeCorePids ?? const {};
    }
    return const {};
  }

  static Future<BuildInfo> _build(Map<String, Object?> android) async {
    String version = '—';
    String buildNumber = '—';
    String packageName = '—';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      buildNumber = info.buildNumber;
      packageName = info.packageName;
    } catch (e) {
      AppLogger.instance.debug('Package info unavailable', error: e);
    }
    return BuildInfo(
      appVersion: version,
      buildNumber: buildNumber,
      packageName: packageName,
      operatingSystem: Platform.operatingSystem,
      osVersion: _osVersion(android),
      abi: _abi(android),
      dartVersion: dartVersion(Platform.version),
      releaseMode: kReleaseMode,
    );
  }

  static String _osVersion(Map<String, Object?> android) {
    if (Platform.isAndroid) {
      final release = (android['release'] as String? ?? '').trim();
      final sdk = android['sdkInt'] as int?;
      if (release.isEmpty && sdk == null) {
        return Platform.operatingSystemVersion;
      }
      final manufacturer = (android['manufacturer'] as String? ?? '').trim();
      final device = manufacturer.isEmpty ? '' : ' · $manufacturer';
      return 'Android $release (API $sdk)$device';
    }
    if (Platform.isWindows) {
      return prettyWindowsVersion(Platform.operatingSystemVersion);
    }
    return Platform.operatingSystemVersion;
  }

  // реестр Windows 11 по-прежнему пишет Windows 10, отличает только сборка с 22000
  static String prettyWindowsVersion(String raw) {
    final quoted = RegExp(r'"([^"]+)"').firstMatch(raw);
    if (quoted == null) return raw;
    var name = quoted.group(1)!.trim();
    final build = int.tryParse(
      RegExp(
            r'\(Build\s+(\d+)',
            caseSensitive: false,
          ).firstMatch(raw)?.group(1) ??
          '',
    );
    if (build != null &&
        build >= 22000 &&
        !name.toLowerCase().contains('server')) {
      name = name.replaceFirst(RegExp(r'Windows\s*10'), 'Windows 11');
    }
    return build == null ? name : '$name (build $build)';
  }

  static String _abi(Map<String, Object?> android) {
    final abis = (android['abis'] as List?)?.cast<Object?>();
    if (abis != null && abis.isNotEmpty) return abis.first.toString();
    return Abi.current().toString();
  }

  static String dartVersion(String platformVersion) {
    final space = platformVersion.indexOf(' ');
    return space > 0 ? platformVersion.substring(0, space) : platformVersion;
  }

  // не локализован намеренно: отчёт читают как техданные
  static String report(AppInternals data) {
    final out = StringBuffer()
      ..writeln('# keqdroid internals')
      ..writeln('app: ${data.build.appVersion} (${data.build.buildNumber})')
      ..writeln('package: ${data.build.packageName}')
      ..writeln('os: ${data.build.osVersion}')
      ..writeln('abi: ${data.build.abi}')
      ..writeln('dart: ${data.build.dartVersion}')
      ..writeln('mode: ${data.build.releaseMode ? 'release' : 'debug'}')
      ..writeln()
      ..writeln('## cores');
    for (final core in data.cores) {
      if (core.missing) {
        out.writeln('${core.name}: missing');
        continue;
      }
      out.writeln('${core.name}: ${core.version ?? '(no own version)'}');
      for (final engine in core.engines.entries) {
        out.writeln('  ${engine.key}: ${engine.value}');
      }
      if (core.goVersion != null) out.writeln('  built with ${core.goVersion}');
      if (core.sizeBytes != null) out.writeln('  ${core.sizeBytes} bytes');
      if (core.modified != null) {
        out.writeln('  ${core.modified!.toIso8601String()}');
      }
    }

    out
      ..writeln()
      ..writeln('## geo');
    for (final base in data.geoBases) {
      out.writeln(
        base.missing
            ? '${base.name}: missing'
            : '${base.name}: ${base.codeCount} codes, ${base.sizeBytes} bytes',
      );
    }

    final session = data.session;
    out
      ..writeln()
      ..writeln('## session')
      ..writeln('status: ${session.status.name}')
      ..writeln('engine: ${session.engine}')
      ..writeln('mode: ${session.mode?.name ?? 'n/a'}')
      ..writeln('socks: ${session.socksPort}, http: ${session.httpPort}');
    if (session.clashApiPort != null) {
      out.writeln('clash api: ${session.clashApiPort}');
    }
    if (session.uptime != null) out.writeln('uptime: ${session.uptime}');
    if (session.elevated != null) out.writeln('elevated: ${session.elevated}');
    for (final pid in session.corePids.entries) {
      out.writeln('pid ${pid.key}: ${pid.value}');
    }

    if (data.processExits.isNotEmpty) {
      out
        ..writeln()
        ..writeln('## process exits')
        ..write(exitLines(data.processExits));
    }
    return out.toString();
  }

  static String exitLines(List<ProcessExit> exits) {
    final out = StringBuffer();
    for (final exit in exits) {
      out.write(
        '${_reportTime(exit.time)} ${exit.reasonName}'
        ' status=${exit.status} importance=${exit.importance}',
      );
      if (exit.vpnStatus != null) out.write(' vpn=${exit.vpnStatus}');
      if (exit.description != null) out.write(' "${exit.description}"');
      out.writeln();
    }
    return out.toString();
  }

  static String _reportTime(DateTime time) {
    final t = time.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
