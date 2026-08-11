import '../models/connection_entry.dart';

/// Держит соединения между опросами экрана и сводит одинаковые в одну строку.
///
/// Зачем: на Android список строится по access-логу ядра, а лог — это хвост
/// файла. Из этого следовали две неприятности, обе видны глазом:
///  - живое соединение исчезало из списка, как только его строка уезжала из
///    прочитанного хвоста, и появлялось снова, когда ядро что-то про него
///    напишет;
///  - к одному хосту браузер держит десяток сокетов, и каждый — своя строка;
///    экран выглядел как спам копиями одного и того же.
///
/// Поэтому: соединения запоминаются и живут в списке, пока ядро не сообщило,
/// что они закрылись (`connection ends`), а одинаковые (сеть, адрес, порт,
/// владелец, исход) показываются одной строкой со счётчиком.
///
/// Живой снимок (clash_api на десктопе) держать не нужно — там список и есть
/// текущее состояние; для него делается только свёртка.
class ConnectionsTracker {
  ConnectionsTracker({
    this.closedLinger = const Duration(seconds: 45),
    this.unreportedTtl = const Duration(seconds: 30),
    this.silentTtl = const Duration(minutes: 10),
    this.maxTracked = 600,
  });

  /// Сколько закрывшееся соединение ещё видно в списке. Ноль здесь означал бы,
  /// что соединение просто исчезает в момент закрытия — не видно, чем кончилось.
  final Duration closedLinger;

  /// Сколько держать соединение, о закрытии которого ядро сообщить не может:
  /// на уровне логов ниже `info` строк `connection ends` нет вовсе, и «живо»
  /// от «умерло» неотличимо. Держим недолго — врать про живое хуже, чем
  /// потерять строку (экран в этом случае и так предлагает включить Info).
  final Duration unreportedTtl;

  /// Предохранитель для случая, когда сообщение о закрытии мы пропустили
  /// (строка уехала из хвоста между опросами): соединение, о котором лог давно
  /// молчит, всё-таки выкидываем.
  final Duration silentTtl;

  /// Верхняя граница памяти трекера: при переполнении уходят те, о которых
  /// дольше всего не было слышно.
  final int maxTracked;

  final Map<String, _Tracked> _tracked = {};
  String? _token;

  /// В этой сессии уже был хоть один разбор лога. Отличает «догоняем историю из
  /// хвоста» от «список просто опустел, все соединения закрылись».
  bool _mergedOnce = false;

  /// Забыть всё: другая сессия ядра — другие соединения.
  void reset() {
    _tracked.clear();
    _token = null;
    _mergedOnce = false;
  }

  /// Только для тестов/диагностики: сколько соединений помнится.
  int get trackedCount => _tracked.length;

  /// Снимок для экрана: свёрнутый и, для лог-источника, дополненный тем, что
  /// ещё живо, но в прочитанный хвост лога не попало.
  ///
  /// [sessionToken] меняется вместе с сессией ядра (порт clash_api, факт
  /// переподключения) — на другом токене память сбрасывается.
  ConnectionsSnapshot merge(
    ConnectionsSnapshot fresh, {
    required String sessionToken,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();

    if (fresh.source == ConnectionsSource.unavailable) {
      // Сессии нет (или источник отвалился) — помнить её соединения незачем.
      reset();
      return fresh;
    }
    if (_token != sessionToken) {
      reset();
      _token = sessionToken;
    }

    if (fresh.source == ConnectionsSource.coreApi) {
      // clash_api отдаёт ровно то, что открыто сейчас: дополнять нечем.
      return _snapshotFrom(fresh, _group(fresh.entries));
    }

    // Первый опрос сессии: в хвосте лога лежит история, а не «то, что сейчас».
    // Закрывшееся в ней мы живым не видели, поэтому момент закрытия берём по
    // времени самого соединения — давнее отсеется сразу, свежее ещё мелькнёт.
    // Иначе экран при открытии заваливало закрытыми соединениями за всю сессию
    // (ровно то, на что это и было похоже — спам копиями из логов).
    final catchingUp = !_mergedOnce;
    _mergedOnce = true;

    for (final entry in fresh.entries) {
      final known = _tracked[entry.id];
      if (known == null) {
        _tracked[entry.id] = _Tracked(
          entry: entry,
          firstSeen: entry.startedAt ?? at,
          lastSeen: at,
          closedAt: !entry.closed
              ? null
              : catchingUp
                  ? (entry.startedAt ?? at)
                  : at,
        );
        continue;
      }
      known.absorb(entry, at);
    }

    _evict(at, closureReported: fresh.ruleInfoAvailable);

    final entries = _tracked.values.toList()
      // Живое сверху, закрытое вниз; внутри — по времени начала, свежие
      // первыми. Сортировка по «последней активности» гоняла бы строки
      // вверх-вниз на каждом опросе, а список должен стоять на месте.
      ..sort((a, b) {
        if (a.entry.closed != b.entry.closed) return a.entry.closed ? 1 : -1;
        return b.firstSeen.compareTo(a.firstSeen);
      });

    return _snapshotFrom(
      fresh,
      _group([for (final tracked in entries) tracked.entry]),
    );
  }

  void _evict(DateTime at, {required bool closureReported}) {
    _tracked.removeWhere((_, tracked) {
      final closedAt = tracked.closedAt;
      if (closedAt != null) return at.difference(closedAt) > closedLinger;
      if (!closureReported) {
        return at.difference(tracked.lastSeen) > unreportedTtl;
      }
      return at.difference(tracked.lastSeen) > silentTtl;
    });

    if (_tracked.length <= maxTracked) return;
    final byAge = _tracked.entries.toList()
      ..sort((a, b) => a.value.lastSeen.compareTo(b.value.lastSeen));
    for (final entry in byAge.take(_tracked.length - maxTracked)) {
      _tracked.remove(entry.key);
    }
  }

  static ConnectionsSnapshot _snapshotFrom(
    ConnectionsSnapshot source,
    List<ConnectionEntry> entries,
  ) =>
      ConnectionsSnapshot(
        entries: entries,
        source: source.source,
        note: source.note,
        ruleInfoAvailable: source.ruleInfoAvailable,
        appNamesAvailable: source.appNamesAvailable,
      );

  /// Сворачивает одинаковые соединения в одну строку, сохраняя порядок первого
  /// вхождения.
  static List<ConnectionEntry> _group(List<ConnectionEntry> entries) {
    final groups = <String, List<ConnectionEntry>>{};
    for (final entry in entries) {
      groups.putIfAbsent(entry.groupKey, () => []).add(entry);
    }
    return [
      for (final members in groups.values) _mergeGroup(members),
    ];
  }

  static ConnectionEntry _mergeGroup(List<ConnectionEntry> members) {
    if (members.length == 1) return members.first;

    var upload = 0;
    var download = 0;
    var hasBytes = false;
    DateTime? startedAt;
    var rule = '';
    var inbound = '';
    var closed = true;
    for (final member in members) {
      if (member.upload != null || member.download != null) {
        hasBytes = true;
        upload += member.upload ?? 0;
        download += member.download ?? 0;
      }
      final start = member.startedAt;
      if (start != null && (startedAt == null || start.isBefore(startedAt))) {
        startedAt = start;
      }
      if (rule.isEmpty) rule = member.rule;
      if (inbound.isEmpty) inbound = member.inbound;
      // Строка считается закрытой, только когда закрылись все её соединения:
      // одно живое — соединение к этому адресу есть.
      if (!member.closed) closed = false;
    }

    final first = members.first;
    return first.copyWith(
      // Ключ группы стабилен между опросами, в отличие от id отдельного сокета.
      id: 'group:${first.groupKey}',
      // Источник — конкретный локальный сокет, у группы он не один: показывать
      // чей-то один значит врать. Их количество и так видно по счётчику.
      source: '',
      rule: rule,
      inbound: inbound,
      startedAt: startedAt,
      upload: hasBytes ? upload : null,
      download: hasBytes ? download : null,
      closed: closed,
      count: members.length,
    );
  }
}

/// Одно запомненное соединение: сама запись и то, когда его видели.
class _Tracked {
  _Tracked({
    required this.entry,
    required this.firstSeen,
    required this.lastSeen,
    this.closedAt,
  });

  ConnectionEntry entry;

  /// Когда соединение впервые попало в список — по нему стоит порядок строк.
  final DateTime firstSeen;

  /// Последний опрос, в котором лог о нём что-то сказал.
  DateTime lastSeen;

  /// Когда стало известно о закрытии. null — ядро о закрытии не сообщало.
  DateTime? closedAt;

  /// Вливает свежую запись о том же соединении.
  void absorb(ConnectionEntry fresh, DateTime at) {
    lastSeen = at;
    if (fresh.closed) closedAt ??= at;
    entry = fresh.copyWith(
      // Домен ядро узнаёт сниффингом позже адреса, а имя приложения приходит
      // от системы и только для живых сокетов — однажды выясненное не теряем.
      host: fresh.host.isEmpty ? entry.host : fresh.host,
      destIp: fresh.destIp.isEmpty ? entry.destIp : fresh.destIp,
      process: fresh.process.isEmpty ? entry.process : fresh.process,
      rule: fresh.rule.isEmpty ? entry.rule : fresh.rule,
      outbound: fresh.outbound.isEmpty ? entry.outbound : fresh.outbound,
      startedAt: entry.startedAt ?? fresh.startedAt,
      // Закрытие необратимо: строка о нём тоже уезжает из хвоста лога.
      closed: entry.closed || fresh.closed,
    );
  }
}
