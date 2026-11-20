import '../models/server_item.dart';

// hy2:// и hysteria2:// один протокол, в шторке одна строка
String protocolFilterKey(String protocol) =>
    protocol == 'hy2' ? 'hysteria2' : protocol;

String protocolFilterKeyOf(String config) => protocolFilterKey(
  ServerItem(
    id: '',
    config: config,
    type: ServerItemType.subscription,
  ).protocol,
);

({List<String> kept, Map<String, int> counts}) siftProtocols(
  List<String> configs,
  Set<String> excluded,
) {
  final counts = <String, int>{};
  final kept = <String>[];
  for (final config in configs) {
    final key = protocolFilterKeyOf(config);
    counts[key] = (counts[key] ?? 0) + 1;
    if (!excluded.contains(key)) kept.add(config);
  }
  // провайдер прислал одни выключенные: пустая подписка хуже, чем лишние серверы
  return (kept: kept.isEmpty ? configs : kept, counts: counts);
}
