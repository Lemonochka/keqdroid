import 'server_item.dart';
import 'subscription.dart';

/// Ключ скоупа группы цепочек — общий для пинга, сворачивания и сортировки.
const String kChainsServerGroupKey = '__chains__';

/// То же для серверов, добавленных руками (без подписки).
const String kManualServerGroupKey = '__manual__';

/// Откуда взялась группа. Заголовок и действия у трёх видов разные, а порядок
/// и состав — общие, поэтому вид едет полем, а не тремя списками.
enum ServerGroupKind { chains, subscription, manual }

/// Группа серверов в том виде, в каком её показывает список.
///
/// Отдельный тип нужен ровно затем, чтобы список и боковой навигатор строили
/// ОДИН И ТОТ ЖЕ набор групп в одном и том же порядке: кнопка «перейти к
/// группе», которой в списке нет (или которая там третья, а не первая), — это
/// не мелочь оформления, а сломанная навигация.
class ServerGroupRef {
  final ServerGroupKind kind;

  /// Ключ группы: `sub.id` у подписки, иначе служебная константа.
  final String key;

  /// Подписка группы; null у цепочек и ручных серверов.
  final Subscription? subscription;

  final List<ServerItem> servers;

  const ServerGroupRef({
    required this.kind,
    required this.key,
    required this.subscription,
    required this.servers,
  });

  /// Имя подписки; у служебных групп пусто — заголовок им даёт локализация.
  String get subscriptionName => subscription?.name.trim() ?? '';
}

/// Группы списка серверов: цепочки → подписки (в порядке самих подписок) →
/// добавленные руками. Пустые группы выпадают — карточки без единого сервера
/// в списке нет, значит и кнопки к ней быть не должно.
List<ServerGroupRef> buildServerGroups({
  required List<ServerItem> servers,
  required List<Subscription> subscriptions,
}) {
  final chains = servers.where((s) => s.protocol == 'chain').toList();
  final manual = servers
      .where((s) => s.subscriptionId == null && s.protocol != 'chain')
      .toList();
  final bySubId = <String, List<ServerItem>>{};
  for (final s in servers.where((s) => s.subscriptionId != null)) {
    bySubId.putIfAbsent(s.subscriptionId!, () => []).add(s);
  }

  return [
    if (chains.isNotEmpty)
      ServerGroupRef(
        kind: ServerGroupKind.chains,
        key: kChainsServerGroupKey,
        subscription: null,
        servers: chains,
      ),
    for (final sub in subscriptions)
      if ((bySubId[sub.id] ?? const []).isNotEmpty)
        ServerGroupRef(
          kind: ServerGroupKind.subscription,
          key: sub.id,
          subscription: sub,
          servers: bySubId[sub.id]!,
        ),
    if (manual.isNotEmpty)
      ServerGroupRef(
        kind: ServerGroupKind.manual,
        key: kManualServerGroupKey,
        subscription: null,
        servers: manual,
      ),
  ];
}
