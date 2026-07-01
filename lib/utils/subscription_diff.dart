import '../models/subscription.dart';

/// true, если списки подписок отличаются по составу или по любому отображаемому
/// в UI полю. Сравнение по id (порядок не важен), затем по полям. Нужно, чтобы
/// фоновая синхронизация дёргала state только при реальном изменении.
bool subscriptionsDiffer(List<Subscription> a, List<Subscription> b) {
  if (identical(a, b)) return false;
  if (a.length != b.length) return true;
  final byIdA = {for (final s in a) s.id: s};
  final byIdB = {for (final s in b) s.id: s};
  if (byIdA.length != byIdB.length) return true;
  for (final entry in byIdA.entries) {
    final x = entry.value;
    final y = byIdB[entry.key];
    if (y == null) return true;
    if (x.name != y.name ||
        x.url != y.url ||
        x.lastUpdatedAt != y.lastUpdatedAt ||
        x.usedBytes != y.usedBytes ||
        x.totalBytes != y.totalBytes ||
        x.expiresAt != y.expiresAt ||
        x.autoUpdate != y.autoUpdate ||
        x.serverCount != y.serverCount ||
        x.updateIntervalHours != y.updateIntervalHours) {
      return true;
    }
  }
  return false;
}
