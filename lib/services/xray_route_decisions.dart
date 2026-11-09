import 'xray_access_log_parser.dart';

// решения роутинга встроенного xray за всю сессию: экран Соединения открывают позже, чем браузер открыл соединения,
// а хвост лога держит пару сотен строк, на debug и того меньше
abstract final class XrayRouteDecisions {
  static final _byTarget = <String, XrayRouteDecision>{};
  static const _limit = 4000;

  static void observe(String line) {
    if (!line.contains('detour') && !line.contains('default route')) return;
    final parsed = XrayAccessLogParser.parseRouteDecisions(line);
    for (final MapEntry(:key, :value) in parsed.entries) {
      final previous = _byTarget.remove(key);
      _byTarget[key] = value.outbound.isEmpty && previous != null
          ? XrayRouteDecision(rule: value.rule, outbound: previous.outbound)
          : value;
    }
    while (_byTarget.length > _limit) {
      _byTarget.remove(_byTarget.keys.first);
    }
  }

  static XrayRouteDecision? forTarget(String key) => _byTarget[key];

  static bool get isEmpty => _byTarget.isEmpty;

  static void reset() => _byTarget.clear();
}
