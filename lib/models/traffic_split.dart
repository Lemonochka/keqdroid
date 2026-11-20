class ChannelTraffic {
  final int downloadSpeed;
  final int uploadSpeed;

  final int totalDownload;
  final int totalUpload;

  int get total => totalDownload + totalUpload;

  const ChannelTraffic({
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.totalDownload,
    required this.totalUpload,
  });

  static const zero = ChannelTraffic(
    downloadSpeed: 0,
    uploadSpeed: 0,
    totalDownload: 0,
    totalUpload: 0,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChannelTraffic &&
          downloadSpeed == other.downloadSpeed &&
          uploadSpeed == other.uploadSpeed &&
          totalDownload == other.totalDownload &&
          totalUpload == other.totalUpload;

  @override
  int get hashCode =>
      Object.hash(downloadSpeed, uploadSpeed, totalDownload, totalUpload);

  @override
  String toString() =>
      'ChannelTraffic(${downloadSpeed}B/s down, ${uploadSpeed}B/s up, '
      '$total B total)';
}

class TrafficSplit {
  final ChannelTraffic vpn;

  final ChannelTraffic direct;

  const TrafficSplit({required this.vpn, required this.direct});

  static const zero = TrafficSplit(
    vpn: ChannelTraffic.zero,
    direct: ChannelTraffic.zero,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrafficSplit && vpn == other.vpn && direct == other.direct;

  @override
  int get hashCode => Object.hash(vpn, direct);

  @override
  String toString() => 'TrafficSplit(vpn: $vpn, direct: $direct)';
}

class TrafficSplitState {
  final String session;

  // метка сессии после реконнекта из плитки та же,
  // перезапуск ядра видно только по тому, что эти суммы стали меньше
  final int coreDownload;
  final int coreUpload;

  final int vpnDownload;
  final int vpnUpload;
  final int directDownload;
  final int directUpload;

  final Map<String, (int, int)> connections;

  const TrafficSplitState({
    required this.session,
    required this.coreDownload,
    required this.coreUpload,
    required this.vpnDownload,
    required this.vpnUpload,
    required this.directDownload,
    required this.directUpload,
    required this.connections,
  });

  bool belongsTo({
    required String session,
    required int coreDownload,
    required int coreUpload,
  }) =>
      this.session == session &&
      coreDownload >= this.coreDownload &&
      coreUpload >= this.coreUpload;

  Map<String, Object?> toJson() => {
    'v': 1,
    'session': session,
    'core': [coreDownload, coreUpload],
    'vpn': [vpnDownload, vpnUpload],
    'direct': [directDownload, directUpload],
    'conns': {
      for (final e in connections.entries) e.key: [e.value.$1, e.value.$2],
    },
  };

  static TrafficSplitState? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json['v'] != 1) return null;
    final session = json['session'];
    if (session is! String || session.isEmpty) return null;

    (int, int)? pair(Object? raw) {
      if (raw is! List || raw.length != 2) return null;
      final a = raw[0], b = raw[1];
      if (a is! num || b is! num) return null;
      return (a.toInt(), b.toInt());
    }

    final core = pair(json['core']);
    final vpn = pair(json['vpn']);
    final direct = pair(json['direct']);
    if (core == null || vpn == null || direct == null) return null;

    final rawConns = json['conns'];
    if (rawConns is! Map) return null;
    final conns = <String, (int, int)>{};
    for (final e in rawConns.entries) {
      final counters = pair(e.value);
      if (counters == null) return null;
      conns[e.key.toString()] = counters;
    }

    return TrafficSplitState(
      session: session,
      coreDownload: core.$1,
      coreUpload: core.$2,
      vpnDownload: vpn.$1,
      vpnUpload: vpn.$2,
      directDownload: direct.$1,
      directUpload: direct.$2,
      connections: conns,
    );
  }
}
