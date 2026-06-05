import 'connection_mode.dart';

enum VpnStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error;

  static VpnStatus fromString(String s) => switch (s.toLowerCase()) {
        'disconnected' || 'stopped' => VpnStatus.disconnected,
        'connecting' || 'starting' => VpnStatus.connecting,
        'connected' || 'running' => VpnStatus.connected,
        'disconnecting' || 'stopping' => VpnStatus.disconnecting,
        'error' || 'failed' => VpnStatus.error,
        _ => VpnStatus.disconnected,
      };
}

class VpnState {
  final VpnStatus status;
  final String? errorMessage;
  final int? uploadSpeed;
  final int? downloadSpeed;
  final int? totalUpload;
  final int? totalDownload;
  final Duration? duration;
  final ConnectionMode? activeMode;

  const VpnState({
    required this.status,
    this.errorMessage,
    this.uploadSpeed,
    this.downloadSpeed,
    this.totalUpload,
    this.totalDownload,
    this.duration,
    this.activeMode,
  });

  static const disconnected = VpnState(status: VpnStatus.disconnected);
  static const connecting = VpnState(status: VpnStatus.connecting);
  static const connected = VpnState(status: VpnStatus.connected);

  factory VpnState.fromMap(Map<Object?, Object?> map) => VpnState(
        status: VpnStatus.fromString(map['status'] as String? ?? 'disconnected'),
        errorMessage: map['error'] as String?,
        uploadSpeed: map['uploadSpeed'] as int?,
        downloadSpeed: map['downloadSpeed'] as int?,
        totalUpload: map['totalUpload'] as int?,
        totalDownload: map['totalDownload'] as int?,
        duration: map['durationSeconds'] != null
            ? Duration(seconds: map['durationSeconds'] as int)
            : null,
        activeMode: map['connectionMode'] != null
            ? ConnectionMode.fromStorage(map['connectionMode'] as String?)
            : null,
      );

  bool telemetryEquals(VpnState other) =>
      status == other.status &&
      errorMessage == other.errorMessage &&
      uploadSpeed == other.uploadSpeed &&
      downloadSpeed == other.downloadSpeed &&
      totalUpload == other.totalUpload &&
      totalDownload == other.totalDownload &&
      duration?.inSeconds == other.duration?.inSeconds &&
      activeMode == other.activeMode;
}
