import '../models/app_settings.dart';
import '../models/routing_rule.dart';

/// Складывает включённые структурированные правила [rules] в текстовые списки
/// настроек (directRules/proxyRules/blockedRules), которые читают оба генератора
/// конфига (xray и sing-box TUN). Так модель [RoutingRule] реально влияет на
/// роутинг, не трогая сами генераторы — они по-прежнему работают со строками.
///
/// processName-правила пропускаются: пер-аппный роутинг делается отдельно через
/// split tunneling, а не через доменно-адресные списки.
AppSettings applyRoutingRules(AppSettings settings, List<RoutingRule> rules) {
  if (rules.isEmpty) return settings;

  final direct = <String>[];
  final proxy = <String>[];
  final blocked = <String>[];

  for (final rule in rules) {
    if (!rule.enabled) continue;
    final tokens = _ruleTokens(rule);
    if (tokens.isEmpty) continue;
    switch (rule.action) {
      case RuleAction.direct:
        direct.addAll(tokens);
      case RuleAction.proxy:
        proxy.addAll(tokens);
      case RuleAction.block:
        blocked.addAll(tokens);
    }
  }

  if (direct.isEmpty && proxy.isEmpty && blocked.isEmpty) return settings;

  return settings.copyWith(
    directRules: _append(settings.directRules, direct),
    proxyRules: _append(settings.proxyRules, proxy),
    blockedRules: _append(settings.blockedRules, blocked),
  );
}

/// Значения правила в токенах, понятных генераторам. geoip/geosite получают свой
/// префикс, если пользователь ввёл голый код (RU вместо geoip:RU).
List<String> _ruleTokens(RoutingRule rule) {
  final values =
      rule.values.map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
  if (values.isEmpty) return const [];
  switch (rule.type) {
    case RuleType.domain:
    case RuleType.ipCidr:
      return values;
    case RuleType.geoip:
      return values
          .map((v) => v.toLowerCase().startsWith('geoip:') ? v : 'geoip:$v')
          .toList();
    case RuleType.geosite:
      return values
          .map((v) => v.toLowerCase().startsWith('geosite:') ? v : 'geosite:$v')
          .toList();
    case RuleType.processName:
      return const [];
  }
}

String _append(String existing, List<String> tokens) {
  if (tokens.isEmpty) return existing;
  final base = existing.trimRight();
  final joined = tokens.join(', ');
  return base.isEmpty ? joined : '$base\n$joined';
}
