import 'dart:io';

import '../models/app_settings.dart';

/// Почему локальный порт не удалось занять.
enum LocalPortIssue {
  /// Порт держит другой процесс (`EADDRINUSE` / `WSAEADDRINUSE`). Классика —
  /// второй VPN-клиент на тех же 2080/1080 или наше же осиротевшее ядро.
  occupied,

  /// Windows отдал диапазон под Hyper-V / WSL2 / контейнеры (или бинд запретила
  /// защита) — `WSAEACCES` 10013. Слушателя при этом НЕТ вовсе: `netstat` пуст,
  /// а бинд всё равно запрещён, и список видно только через
  /// `netsh interface ipv4 show excludedportrange protocol=tcp`.
  reserved,

  /// Порт < 1024 под обычным пользователем на Linux (`EACCES`).
  privileged,

  /// Всё остальное: адрес не поднят, экзотика стека.
  unknown,
}

/// Один разрешённый порт: что просили, что получилось и почему.
class LocalPortAssignment {
  final String label;
  final String host;
  final int requested;
  final int effective;

  /// Причина замены; null — порт достался как есть.
  final LocalPortIssue? issue;

  const LocalPortAssignment({
    required this.label,
    required this.host,
    required this.requested,
    required this.effective,
    this.issue,
  });

  bool get changed => requested != effective;

  /// Строка для лога/сообщения об ошибке — с причиной, а не «занят кем-то».
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

/// Текст отказа, когда подменить порт уже нельзя (он вшит в готовый конфиг).
///
/// Один и тот же «порт занят» имеет три разных причины и три разных действия
/// пользователя, поэтому сообщение обязано называть ту, что случилась.
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

/// Порты, на которых сессия РЕАЛЬНО поднимется.
///
/// Настройка — это пожелание: порт из неё может быть занят соседом или изъят
/// системой, и до сих пор это означало отказ подключаться («SOCKS port 2080 is
/// already in use»). Для пользователя это выглядит как «TUN/прокси не
/// работает», причём чинить надо руками и в другом месте. План выбирает
/// работающий порт сам, а несовпадение с настройкой честно пишет в лог.
class LocalPortPlan {
  final int socksPort;
  final int httpPort;
  final int lanSocksPort;
  final int lanHttpPort;

  /// Все разобранные порты в порядке разрешения.
  final List<LocalPortAssignment> assignments;

  const LocalPortPlan({
    required this.socksPort,
    required this.httpPort,
    required this.lanSocksPort,
    required this.lanHttpPort,
    this.assignments = const [],
  });

  /// Только те, где пришлось отступить от настройки.
  List<LocalPortAssignment> get changes =>
      assignments.where((a) => a.changed).toList();

  /// Настройки сессии с фактическими портами. Генераторы конфигов читают порты
  /// из `AppSettings` (в том числе LAN-инбаунды — прямо из полей), поэтому
  /// подмена делается один раз и здесь, а не в каждом из них.
  AppSettings applyTo(AppSettings settings) => settings.copyWith(
    localPort: socksPort,
    httpPort: httpPort,
    lanSocksPort: lanSocksPort,
    lanHttpPort: lanHttpPort,
  );
}

/// Подбор локальных портов перед стартом ядра.
class LocalPortResolver {
  /// Инбаунды под петлёй (socks/http) — их слушает ядро на 127.0.0.1.
  static const loopbackHost = '127.0.0.1';

  /// LAN-раздача слушает все интерфейсы, и проверять её надо там же: порт бывает
  /// свободен на петле и занят на 0.0.0.0 (типовой 8080 у любого dev-сервера).
  static const anyHost = '0.0.0.0';

  /// Сколько соседних портов пробуем, прежде чем уйти в эфемерный.
  ///
  /// Изъятые Windows диапазоны идут блоками по несколько сотен портов, так что
  /// «+1» их не перепрыгивает; зато эфемерный бинд (`port: 0`) система выдаёт
  /// заведомо мимо своих же резерваций.
  static const _ladderSteps = 24;

  /// Разрешает порты сессии. [includeLan] — проверять ли порты раздачи
  /// (только когда она включена: иначе ядро их не слушает вовсе).
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
    // Порт, уже отданный другому инбаунду этой же сессии, свободен для системы,
    // но занят для нас: ядро поднимает их одновременно и упадёт на втором.
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
    // Последний рубеж: пусть порт назовёт сама система. Он заведомо не попадёт
    // ни в чужой слушатель, ни в изъятый Windows диапазон.
    for (var attempt = 0; attempt < 8; attempt++) {
      final ephemeral = await _ephemeral(host);
      if (ephemeral != null && !taken.contains(ephemeral)) return ephemeral;
    }
    // Не выйти совсем: возвращаем исходный — пусть ядро скажет своё, а мы
    // покажем его сообщение. Молча «подключаться» на невозможном порту нельзя.
    return from;
  }

  /// Пробный бинд. `null` — порт можно занять; иначе причина отказа.
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

  /// Разбор ошибки бинда. Коды ОС различают «кто-то слушает» и «система не
  /// дала» — и это два разных совета пользователю, поэтому одного «занят» мало.
  static LocalPortIssue classify(SocketException e) {
    final code = e.osError?.errorCode;
    // Повторный бинд ВНУТРИ нашего же процесса до ОС не доходит: dart:io ловит
    // его сам и подставляет собственный код -1 с текстом про `shared`.
    final message = (e.osError?.message ?? '').toLowerCase();
    if (message.contains('shared flag')) return LocalPortIssue.occupied;
    if (Platform.isWindows) {
      return switch (code) {
        10048 => LocalPortIssue.occupied, // WSAEADDRINUSE
        // WSAEACCES. Три разных случая с одним кодом: изъятый системой
        // диапазон (Hyper-V/WSL/контейнеры), порт, занятый чужим сокетом с
        // SO_EXCLUSIVEADDRUSE, и запрет от защитного ПО. Различать их изнутри
        // нечем, поэтому [localPortBlockedMessage] называет все три.
        10013 => LocalPortIssue.reserved,
        _ => LocalPortIssue.unknown,
      };
    }
    return switch (code) {
      98 => LocalPortIssue.occupied, // EADDRINUSE
      13 => port1024(e) ? LocalPortIssue.privileged : LocalPortIssue.reserved,
      _ => LocalPortIssue.unknown,
    };
  }

  /// EACCES на Linux почти всегда означает привилегированный порт; отличаем по
  /// самому порту, чтобы не советовать root там, где дело в другом.
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

/// Порты ЖИВОЙ сессии — для кода, который ходит в локальный HTTP-инбаунд
/// (апдейтер), но не участвует в подключении и потому знает только настройку.
///
/// Настройка и факт разъезжаются ровно тогда, когда порт пришлось подменить
/// ([LocalPortPlan]); без этой пары апдейтер стучался бы в порт, которого нет.
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

  /// Порт активной сессии, а при её отсутствии — из настроек.
  int httpPortOr(int fallback) => _httpPort ?? fallback;

  int socksPortOr(int fallback) => _socksPort ?? fallback;
}
