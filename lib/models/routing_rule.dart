import 'package:uuid/uuid.dart';

enum RuleAction { proxy, direct, block }

extension RuleActionX on RuleAction {
  String get value => switch (this) {
    RuleAction.proxy => 'proxy',
    RuleAction.direct => 'direct',
    RuleAction.block => 'block',
  };

  static RuleAction fromString(String s) => switch (s.toLowerCase()) {
    'proxy' => RuleAction.proxy,
    'direct' => RuleAction.direct,
    'block' => RuleAction.block,
    _ => RuleAction.proxy,
  };
}

enum RuleType { domain, ipCidr, geoip, geosite, processName }

extension RuleTypeX on RuleType {
  String get value => switch (this) {
    RuleType.domain => 'domain',
    RuleType.ipCidr => 'ipCidr',
    RuleType.geoip => 'geoip',
    RuleType.geosite => 'geosite',
    RuleType.processName => 'processName',
  };

  static RuleType fromString(String s) => switch (s.toLowerCase()) {
    'domain' => RuleType.domain,
    'ipcidr' || 'ip_cidr' => RuleType.ipCidr,
    'geoip' => RuleType.geoip,
    'geosite' => RuleType.geosite,
    'processname' || 'process_name' => RuleType.processName,
    _ => RuleType.domain,
  };
}

// своё правило прежних версий, живёт только до переноса в маршруты (routesFromLegacy)
class RoutingRule {
  final String id;
  final String name;
  final RuleType type;
  final List<String> values;
  final RuleAction action;
  final bool enabled;
  final int priority;

  const RoutingRule({
    required this.id,
    required this.name,
    required this.type,
    required this.values,
    required this.action,
    this.enabled = true,
    this.priority = 50,
  });

  factory RoutingRule.create({
    required String name,
    required RuleType type,
    required List<String> values,
    required RuleAction action,
    int priority = 50,
  }) => RoutingRule(
    id: const Uuid().v4(),
    name: name,
    type: type,
    values: values,
    action: action,
    priority: priority,
  );

  factory RoutingRule.fromJson(Map<String, dynamic> json) => RoutingRule(
    id: json['id'] as String,
    name: json['name'] as String,
    type: RuleTypeX.fromString(json['type'] as String),
    values: List<String>.from(json['values'] as List),
    action: RuleActionX.fromString(json['action'] as String),
    enabled: json['enabled'] as bool? ?? true,
    priority: json['priority'] as int? ?? 50,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.value,
    'values': values,
    'action': action.value,
    'enabled': enabled,
    'priority': priority,
  };

  RoutingRule copyWith({
    String? id,
    String? name,
    RuleType? type,
    List<String>? values,
    RuleAction? action,
    bool? enabled,
    int? priority,
  }) => RoutingRule(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    values: values ?? this.values,
    action: action ?? this.action,
    enabled: enabled ?? this.enabled,
    priority: priority ?? this.priority,
  );
}
