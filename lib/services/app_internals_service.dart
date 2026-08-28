import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../models/app_internals.dart';
import '../models/app_settings.dart';
import '../platform/vpn_native_bridge.dart';
import '../tunnel/linux_core_paths.dart';
import '../tunnel/linux_tunnel_backend.dart';
import '../tunnel/tunnel_state.dart';
import '../tunnel/windows_core_paths.dart';
import '../tunnel/windows_tunnel_backend.dart';
import '../utils/go_build_info.dart';
import '../utils/mihomo_api_session.dart';
import 'geo_asset_service.dart';
import 'windows_desktop_service.dart';

/// Собирает данные для панели «Внутренности».
///
/// Версии ядер берутся из самих бинарей ([GoBuildInfo]), а не из зашитых в код
/// констант: константы врут ровно в тот момент, когда ядро обновили, а строчку
/// поправить забыли, — а именно в этот момент версия и нужна.
class AppInternalsService {
  AppInternalsService._();

  /// Как называются движки внутри ядра — в порядке показа.
  static const _engineModules = <String, String>{
    'xtls/xray-core': 'xray-core',
    'sagernet/sing-box': 'sing-box',
    'amnezia-vpn/amneziawg-go': 'amneziawg-go',
    'xjasonlyu/tun2socks/v2': 'tun2socks',
  };

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
    );
  }

  // ── Ядра ────────────────────────────────────────────────────────────────

  static Future<List<CoreInfo>>? _coresCache;

  /// Только для тестов: сбросить кэш.
  static void resetCacheForTests() => _coresCache = null;

  /// Разбор ядра — это поиск метки в бинаре на десятки мегабайт (у libxray она
  /// лежит под самый конец 39 МБ). Файлы едут в сборке и в рантайме не
  /// меняются, поэтому читаем их один раз на процесс — как [GeoAssetService]
  /// делает с geo-базами. Пересборка панели (подключились/отключились) после
  /// этого бесплатна.
  static Future<List<CoreInfo>> _cachedCores(Map<String, Object?> android) =>
      _coresCache ??= _cores(android);

  static Future<List<CoreInfo>> _cores(Map<String, Object?> android) async {
    if (Platform.isAndroid) {
      final dir = android['nativeLibraryDir'] as String?;
      if (dir == null || dir.isEmpty) return const [];
      return [
        // На Android движок всегда chain: ядро владеет протоколами,
        // tun2socks — TUN-устройством. keqrnel сюда не поставляется.
        //
        // Прокси-ядер два, и они взаимозаменяемы: какое из них исполняет
        // сервер, выбирает пользователь прямо на этом экране
        // (AppSettings.vpnCore).
        await _core(p.join(dir, 'libxray.so'), 'libxray.so', CoreRole.proxy),
        await _core(p.join(dir, 'libmihomo.so'), 'libmihomo.so', CoreRole.proxy),
        await _core(
            p.join(dir, 'libtun2socks.so'), 'libtun2socks.so', CoreRole.tun),
        await _core(
            p.join(dir, 'libwg-go.so'), 'libwg-go.so', CoreRole.amneziawg),
      ];
    }
    if (Platform.isWindows) {
      return [
        await _core(await WindowsCorePaths.keqrnelExecutable(), 'keqrnel.exe',
            CoreRole.core),
        // mihomo — второе ядро, а не довесок: в TUN-режиме оно владеет
        // адаптером само, и keqrnel в такой сессии не участвует вовсе.
        await _core(await WindowsCorePaths.mihomoExecutable(), 'mihomo.exe',
            CoreRole.core),
        await _core(await WindowsCorePaths.wireproxyExecutable(),
            'wireproxy.exe', CoreRole.amneziawg),
      ];
    }
    if (Platform.isLinux) {
      return [
        await _core(
            await LinuxCorePaths.keqrnelExecutable(), 'keqrnel', CoreRole.core),
        await _core(
            await LinuxCorePaths.mihomoExecutable(), 'mihomo', CoreRole.core),
        await _core(await LinuxCorePaths.wireproxyExecutable(), 'wireproxy',
            CoreRole.amneziawg),
      ];
    }
    return const [];
  }

  static Future<CoreInfo> _core(String? path, String name, CoreRole role) async {
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

  /// Дата правки файла, если она вообще что-то значит.
  ///
  /// У библиотек внутри APK её нет: zip-записи несут эпоху формата, и Android
  /// отдаёт `1981-01-01` для всех ядер разом. Показывать такое — врать с
  /// точностью до дня; лучше не показывать ничего.
  static DateTime? meaningfulDate(DateTime? date) {
    if (date == null) return null;
    return date.year < 2000 ? null : date;
  }

  /// Движки внутри ядра. Себя ядро в список не включает: у libxray модуль и
  /// есть xray-core, и строка «xray-core внутри xray-core» пользы не несёт.
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

  /// Версия модуля в человеческом виде.
  ///
  /// `(devel)` — бинарь собран из рабочего дерева, версии у него нет вовсе
  /// (так собирается keqrnel), возвращаем null. Псевдоверсию Go
  /// (`v1.260327.1-0.20260728075948-5ca6f4b7d4dc`) ужимаем до версии и
  /// короткого коммита: полная строка занимает две трети экрана телефона.
  static String? formatVersion(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty || value == '(devel)') return null;
    final pseudo = _pseudoVersion.firstMatch(value);
    if (pseudo == null) return value;
    return '${pseudo.group(1)} · ${pseudo.group(3)}';
  }

  static final _pseudoVersion =
      RegExp(r'^(.*?)-(?:[\w.]+\.)?(\d{14})-([0-9a-f]{12})$');

  // ── Geo-базы ────────────────────────────────────────────────────────────

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

  // ── Сессия ──────────────────────────────────────────────────────────────

  static Future<SessionInfo> _session(
    AppSettings settings,
    VpnState? state,
    Map<String, Object?> android,
  ) async {
    return SessionInfo(
      status: state?.status ?? VpnStatus.disconnected,
      // Движок берём у сессии, а не из настройки: ядро выбирают на ходу, и
      // после переключения панель показывала бы новый выбор поверх туннеля,
      // который всё ещё исполняет старое ядро.
      engine: Platform.isAndroid
          ? _androidCoreBinary(android)
          : _desktopEngine(settings),
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
          // На Android API поднимает mihomo — у xray его нет вовсе, и там
          // строка честно отсутствует, а не показывает чужой порт.
          : Platform.isAndroid
              ? MihomoApiSession().port
              : Platform.isLinux
                  ? LinuxTunnelBackend.activeInstance?.clashApiPort
                  : null,
    );
  }

  /// Чем идёт текущая десктопная сессия.
  ///
  /// `settings.coreEngine` описывает только связку вокруг xray и про mihomo не
  /// знает: при живой mihomo-сессии панель показывала бы `keqrnel`, которого в
  /// ней нет. Спрашиваем поэтому у самой сессии — как и на Android.
  static String _desktopEngine(AppSettings settings) {
    final pids = Platform.isWindows
        ? WindowsTunnelBackend.activeInstance?.activeCorePids
        : LinuxTunnelBackend.activeInstance?.activeCorePids;
    if (pids != null && pids.keys.any((k) => k.startsWith('mihomo'))) {
      return 'mihomo';
    }
    return settings.coreEngine;
  }

  /// Имя бинаря, которым идёт текущая android-сессия.
  ///
  /// Оба прокси-ядра запускаются одним и тем же путём и держат один и тот же
  /// pid-слот в сервисе, поэтому отличить их можно только по тому, что сервис
  /// сам записал при старте. Пусто (сессии не было) — libxray: это ядро по
  /// умолчанию.
  static String _androidCoreBinary(Map<String, Object?> android) =>
      android['coreKind'] == 'mihomo' ? 'libmihomo' : 'libxray';

  static Map<String, int> _corePids(Map<String, Object?> android) {
    if (Platform.isAndroid) {
      final core = android['xrayPid'] as int? ?? -1;
      final tun2socks = android['tun2socksPid'] as int? ?? -1;
      return {
        if (core > 0) _androidCoreBinary(android): core,
        if (tun2socks > 0) 'tun2socks': tun2socks,
      };
    }
    if (Platform.isWindows) {
      return WindowsTunnelBackend.activeInstance?.activeCorePids ?? const {};
    }
    if (Platform.isLinux) {
      return LinuxTunnelBackend.activeInstance?.activeCorePids ?? const {};
    }
    return const {};
  }

  // ── Приложение и устройство ─────────────────────────────────────────────

  static Future<BuildInfo> _build(Map<String, Object?> android) async {
    String version = '—';
    String buildNumber = '—';
    String packageName = '—';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      buildNumber = info.buildNumber;
      packageName = info.packageName;
    } catch (_) {
      // На тестовом биндинге плагина нет — панель обойдётся прочерками.
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
      if (release.isEmpty && sdk == null) return Platform.operatingSystemVersion;
      final manufacturer = (android['manufacturer'] as String? ?? '').trim();
      final device = manufacturer.isEmpty ? '' : ' · $manufacturer';
      return 'Android $release (API $sdk)$device';
    }
    return Platform.operatingSystemVersion;
  }

  static String _abi(Map<String, Object?> android) {
    // На Android берём первую поддерживаемую ABI устройства: она точнее, чем
    // Abi.current() — показывает, в каком варианте установлен сам APK.
    final abis = (android['abis'] as List?)?.cast<Object?>();
    if (abis != null && abis.isNotEmpty) return abis.first.toString();
    return Abi.current().toString();
  }

  /// Только номер версии Dart: `Platform.version` — это ещё и дата сборки SDK
  /// с хешем, целиком в строку панели оно не влезает.
  static String dartVersion(String platformVersion) {
    final space = platformVersion.indexOf(' ');
    return space > 0 ? platformVersion.substring(0, space) : platformVersion;
  }

  /// Отчёт для буфера обмена — то, что уходит в чат поддержки.
  ///
  /// Намеренно не локализован: адресат такого текста читает его как техданные,
  /// и «Версия приложения» на фарси помогает ему меньше, чем `app`.
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
      out.writeln(base.missing
          ? '${base.name}: missing'
          : '${base.name}: ${base.codeCount} codes, ${base.sizeBytes} bytes');
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
    return out.toString();
  }
}
