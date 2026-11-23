import 'dart:io';

import '../models/app_settings.dart';

enum LocalPortIssue {
  occupied,

  // netstat пуст, а бинд запрещён: список виден только в netsh interface ipv4 show excludedportrange protocol=tcp
  reserved,

  privileged,

  unknown,
}

class LocalPortAssignment {
  final String label;
  final String host;
  final int requested;
  final int effective;

  final LocalPortIssue? issue;

  const LocalPortAssignment({
    required this.label,
    required this.host,
    required this.requested,
    required this.effective,
    this.issue,
  });

  bool get changed => requested != effective;

  String describe() {
    final reason = switch (issue) {
      LocalPortIssue.occupied =>
        'another program is listening on it (another VPN client, a leftover '
            'core from a previous run, a local server)',
      LocalPortIssue.reserved =>
        'the system forbids binding it (WSAEACCES 10013): a range reserved for '
            'Hyper-V/WSL/containers, a program holding it exclusively, or a '
            'security product. Check '
            '`netsh interface ipv4 show excludedportrange protocol=tcp`',
      LocalPortIssue.privileged => 'ports below 1024 need root on Linux',
      LocalPortIssue.unknown => 'the socket could not be bound',
      null => '',
    };
    if (!changed) return '$label $host:$effective';
    return '$label port $requested is not usable ($reason) — '
        'using $effective for this session';
  }
}

String localPortBlockedMessage({
  required String label,
  required int port,
  required LocalPortIssue issue,
}) => switch (issue) {
  LocalPortIssue.occupied =>
    '$label port $port is already in use by another program (another VPN '
        'client, a leftover core from a previous run, a local server). '
        'Close it, or change the local port in the app settings.',
  LocalPortIssue.reserved =>
    '$label port $port cannot be opened: the system forbids binding it '
        '(WSAEACCES). Three things look like this on Windows — a range '
        'reserved for Hyper-V / WSL2 / Docker (nothing is listening, so '
        'the port looks free: check '
        '`netsh interface ipv4 show excludedportrange protocol=tcp`), '
        'another program holding the port exclusively, and a security '
        'product blocking local listeners. Pick a different local port in '
        'the app settings.',
  LocalPortIssue.privileged =>
    '$label port $port is privileged: ports below 1024 need root on Linux. '
        'Pick a port above 1024 in the app settings.',
  LocalPortIssue.unknown =>
    '$label port $port could not be opened. Change the local port in the '
        'app settings, or check local firewall / security software.',
};

class LocalPortPlan {
  final int socksPort;
  final int httpPort;
  final int lanSocksPort;
  final int lanHttpPort;

  final List<LocalPortAssignment> assignments;

  const LocalPortPlan({
    required this.socksPort,
    required this.httpPort,
    required this.lanSocksPort,
    required this.lanHttpPort,
    this.assignments = const [],
  });

  List<LocalPortAssignment> get changes =>
      assignments.where((a) => a.changed).toList();

  AppSettings applyTo(AppSettings settings) => settings.copyWith(
    localPort: socksPort,
    httpPort: httpPort,
    lanSocksPort: lanSocksPort,
    lanHttpPort: lanHttpPort,
  );
}

class LocalPortResolver {
  static const loopbackHost = '127.0.0.1';

  // порт бывает свободен на петле и занят на 0.0.0.0
  static const anyHost = '0.0.0.0';

  // изъятые диапазоны идут блоками по сотне, +1 их не перепрыгнет, а эфемерный порт система даёт мимо них
  static const _ladderSteps = 24;

  static Future<LocalPortPlan> resolve(
    AppSettings settings, {
    bool? includeLan,
  }) async {
    final lan = includeLan ?? settings.lanSharing;
    final taken = <int>{};
    final assignments = <LocalPortAssignment>[];

    Future<int> pick(String label, String host, int requested) async {
      final a = await _pick(
        label: label,
        host: host,
        requested: requested,
        taken: taken,
      );
      assignments.add(a);
      taken.add(a.effective);
      return a.effective;
    }

    final socks = await pick('SOCKS', loopbackHost, settings.localPort);
    final http = await pick('HTTP', loopbackHost, settings.httpPort);
    final lanSocks = lan
        ? await pick('LAN SOCKS', anyHost, settings.lanSocksPort)
        : settings.lanSocksPort;
    final lanHttp = lan
        ? await pick('LAN HTTP', anyHost, settings.lanHttpPort)
        : settings.lanHttpPort;

    return LocalPortPlan(
      socksPort: socks,
      httpPort: http,
      lanSocksPort: lanSocks,
      lanHttpPort: lanHttp,
      assignments: assignments,
    );
  }

  static Future<LocalPortAssignment> _pick({
    required String label,
    required String host,
    required int requested,
    required Set<int> taken,
  }) async {
    // порт другого инбаунда этой сессии для системы свободен, но ядро упадёт на втором
    if (!taken.contains(requested)) {
      final issue = await probe(host, requested);
      if (issue == null) {
        return LocalPortAssignment(
          label: label,
          host: host,
          requested: requested,
          effective: requested,
        );
      }
      final replacement = await _findFree(host, requested, taken);
      return LocalPortAssignment(
        label: label,
        host: host,
        requested: requested,
        effective: replacement,
        issue: issue,
      );
    }
    final replacement = await _findFree(host, requested, taken);
    return LocalPortAssignment(
      label: label,
      host: host,
      requested: requested,
      effective: replacement,
      issue: LocalPortIssue.occupied,
    );
  }

  static Future<int> _findFree(String host, int from, Set<int> taken) async {
    for (var i = 1; i <= _ladderSteps; i++) {
      final candidate = from + i;
      if (candidate > 65535) break;
      if (taken.contains(candidate)) continue;
      if (await probe(host, candidate) == null) return candidate;
    }
    for (var attempt = 0; attempt < 8; attempt++) {
      final ephemeral = await _ephemeral(host);
      if (ephemeral != null && !taken.contains(ephemeral)) return ephemeral;
    }
    return from;
  }

  static Future<LocalPortIssue?> probe(String host, int port) async {
    if (port <= 0 || port > 65535) return LocalPortIssue.unknown;
    ServerSocket? socket;
    try {
      socket = await ServerSocket.bind(host, port);
      return null;
    } on SocketException catch (e) {
      return classify(e);
    } catch (_) {
      return LocalPortIssue.unknown;
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }

  static LocalPortIssue classify(SocketException e) {
    final code = e.osError?.errorCode;
    // повторный бинд в нашем процессе dart:io ловит сам и отдаёт -1 с текстом про shared
    final message = (e.osError?.message ?? '').toLowerCase();
    if (message.contains('shared flag')) return LocalPortIssue.occupied;
    if (Platform.isWindows) {
      return switch (code) {
        10048 => LocalPortIssue.occupied, // WSAEADDRINUSE
        // WSAEACCES: изъятый диапазон, SO_EXCLUSIVEADDRUSE у чужого сокета или запрет защиты, различить нечем
        10013 => LocalPortIssue.reserved,
        _ => LocalPortIssue.unknown,
      };
    }
    return switch (code) {
      48 || 98 => LocalPortIssue.occupied, // EADDRINUSE (Darwin 48, Linux 98)
      13 => port1024(e) ? LocalPortIssue.privileged : LocalPortIssue.reserved,
      _ => LocalPortIssue.unknown,
    };
  }

  static bool port1024(SocketException e) => (e.port ?? 0) < 1024;

  static Future<int?> _ephemeral(String host) async {
    try {
      final s = await ServerSocket.bind(host, 0);
      final port = s.port;
      await s.close();
      return port;
    } catch (_) {
      return null;
    }
  }
}

class ActiveLocalPorts {
  static final ActiveLocalPorts _instance = ActiveLocalPorts._();

  factory ActiveLocalPorts() => _instance;

  ActiveLocalPorts._();

  int? _socksPort;
  int? _httpPort;

  void set({required int socksPort, required int httpPort}) {
    _socksPort = socksPort;
    _httpPort = httpPort;
  }

  void clear() {
    _socksPort = null;
    _httpPort = null;
  }

  int? get socksPort => _socksPort;
  int? get httpPort => _httpPort;

  int httpPortOr(int fallback) => _httpPort ?? fallback;

  int socksPortOr(int fallback) => _socksPort ?? fallback;
}
