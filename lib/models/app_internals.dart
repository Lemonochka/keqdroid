import '../tunnel/connection_mode.dart';
import '../tunnel/tunnel_state.dart';

class AppInternals {
  const AppInternals({
    required this.cores,
    required this.geoBases,
    required this.session,
    required this.build,
    this.processExits = const [],
  });

  final List<CoreInfo> cores;
  final List<GeoBaseInfo> geoBases;
  final SessionInfo session;
  final BuildInfo build;

  final List<ProcessExit> processExits;
}

class ProcessExit {
  const ProcessExit({
    required this.time,
    required this.reason,
    required this.reasonName,
    this.status = 0,
    this.importance = 0,
    this.description,
    this.vpnStatus,
    this.sdkInt,
  });

  static ProcessExit? fromMap(Map<Object?, Object?> map, {int? sdkInt}) {
    final timestamp = map['timestamp'];
    if (timestamp is! int) return null;
    final reason = map['reason'] as int? ?? 0;
    final description = (map['description'] as String?)?.trim();
    return ProcessExit(
      time: DateTime.fromMillisecondsSinceEpoch(timestamp),
      reason: reason,
      reasonName: map['reasonName'] as String? ?? '$reason',
      status: map['status'] as int? ?? 0,
      importance: map['importance'] as int? ?? 0,
      description: description == null || description.isEmpty
          ? null
          : description,
      vpnStatus: map['vpnStatus'] as String?,
      sdkInt: sdkInt,
    );
  }

  final DateTime time;

  final int reason;
  final String reasonName;

  final int status;

  final int importance;

  final String? description;

  final String? vpnStatus;

  final int? sdkInt;

  bool get vpnWasOn => vpnStatus == 'connected' || vpnStatus == 'connecting';

  ProcessExitCause get cause => switch (reason) {
    1 => ProcessExitCause.self,
    3 => ProcessExitCause.memory,
    4 || 5 || 6 || 7 => ProcessExitCause.crash,
    10 when (sdkInt ?? 34) < 34 => ProcessExitCause.userOrUpdate,
    10 || 11 => ProcessExitCause.user,
    8 || 15 || 16 => ProcessExitCause.update,
    _ => ProcessExitCause.system,
  };
}

enum ProcessExitCause {
  system,

  memory,

  crash,

  user,

  userOrUpdate,

  update,

  self,
}

enum CoreRole { core, proxy, tun }

class CoreInfo {
  const CoreInfo({
    required this.name,
    required this.role,
    this.version,
    this.goVersion,
    this.path,
    this.sizeBytes,
    this.modified,
    this.engines = const {},
    this.missing = false,
  });

  const CoreInfo.missing({required this.name, required this.role})
    : version = null,
      goVersion = null,
      path = null,
      sizeBytes = null,
      modified = null,
      engines = const {},
      missing = true;

  final String name;

  final CoreRole role;

  final String? version;

  final String? goVersion;

  final String? path;
  final int? sizeBytes;
  final DateTime? modified;

  final Map<String, String> engines;

  final bool missing;
}

class GeoBaseInfo {
  const GeoBaseInfo({
    required this.name,
    required this.codeCount,
    this.sizeBytes,
    this.modified,
    this.missing = false,
  });

  final String name;

  final int codeCount;

  final int? sizeBytes;
  final DateTime? modified;
  final bool missing;
}

class SessionInfo {
  const SessionInfo({
    required this.status,
    required this.engine,
    required this.socksPort,
    required this.httpPort,
    this.mode,
    this.uptime,
    this.corePids = const {},
    this.elevated,
    this.clashApiPort,
  });

  final VpnStatus status;

  final String engine;

  final ConnectionMode? mode;

  final int socksPort;
  final int httpPort;
  final Duration? uptime;

  final Map<String, int> corePids;

  final bool? elevated;

  final int? clashApiPort;

  bool get isActive =>
      status == VpnStatus.connected || status == VpnStatus.connecting;
}

class BuildInfo {
  const BuildInfo({
    required this.appVersion,
    required this.buildNumber,
    required this.packageName,
    required this.operatingSystem,
    required this.osVersion,
    required this.abi,
    required this.dartVersion,
    required this.releaseMode,
  });

  final String appVersion;
  final String buildNumber;
  final String packageName;
  final String operatingSystem;
  final String osVersion;

  final String abi;

  final String dartVersion;

  final bool releaseMode;
}
