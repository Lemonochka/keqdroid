import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/server_group.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/utils/proxy_chain.dart';

/// Разбиение на группы — общее у списка серверов и у бокового навигатора.
/// Кнопка «перейти к группе», которой в списке нет (или которая там не на своём
/// месте), — это не мелочь оформления, а сломанная навигация, поэтому порядок и
/// состав закреплены тестом.
ServerItem _server(String id, {String? subscriptionId}) => ServerItem(
      id: id,
      config: 'vless://uuid@$id.example:443?type=tcp&security=none',
      type: subscriptionId == null
          ? ServerItemType.manual
          : ServerItemType.subscription,
      subscriptionId: subscriptionId,
    );

ServerItem _chain() => ServerItem(
      id: 'chain-1',
      config: ProxyChainConfig(
        name: 'DE → NL',
        hops: const [
          ProxyChainHop(
            serverId: 'a',
            name: 'DE',
            config: 'vless://uuid@de.example:443?type=tcp&security=none',
          ),
          ProxyChainHop(
            serverId: 'b',
            name: 'NL',
            config: 'vless://uuid@nl.example:443?type=tcp&security=none',
          ),
        ],
      ).encode(),
      type: ServerItemType.manual,
    );

Subscription _sub(String id, String name) => Subscription(
      id: id,
      name: name,
      url: 'https://example.com/$id',
    );

void main() {
  test('порядок: цепочки → подписки → ручные', () {
    final groups = buildServerGroups(
      servers: [
        _server('m1'),
        _server('s1', subscriptionId: 'sub-a'),
        _chain(),
        _server('s2', subscriptionId: 'sub-b'),
      ],
      subscriptions: [_sub('sub-a', 'A'), _sub('sub-b', 'B')],
    );

    expect(
      groups.map((g) => g.kind).toList(),
      [
        ServerGroupKind.chains,
        ServerGroupKind.subscription,
        ServerGroupKind.subscription,
        ServerGroupKind.manual,
      ],
    );
    expect(groups.map((g) => g.key).toList(), [
      kChainsServerGroupKey,
      'sub-a',
      'sub-b',
      kManualServerGroupKey,
    ]);
  });

  test('подписки идут в своём порядке, а не в порядке серверов', () {
    final groups = buildServerGroups(
      servers: [
        _server('s-b', subscriptionId: 'sub-b'),
        _server('s-a', subscriptionId: 'sub-a'),
      ],
      subscriptions: [_sub('sub-a', 'A'), _sub('sub-b', 'B')],
    );

    expect(groups.map((g) => g.subscriptionName).toList(), ['A', 'B']);
  });

  test('пустая подписка группой не становится', () {
    final groups = buildServerGroups(
      servers: [_server('s1', subscriptionId: 'sub-a')],
      subscriptions: [_sub('sub-a', 'A'), _sub('sub-empty', 'Empty')],
    );

    expect(groups, hasLength(1));
    expect(groups.single.key, 'sub-a');
  });

  test('цепочка не попадает в ручные, а её серверы — в подписочные', () {
    final groups = buildServerGroups(
      servers: [_chain(), _server('m1')],
      subscriptions: const [],
    );

    expect(groups.map((g) => g.kind).toList(), [
      ServerGroupKind.chains,
      ServerGroupKind.manual,
    ]);
    expect(groups.first.servers.single.id, 'chain-1');
    expect(groups.last.servers.single.id, 'm1');
  });

  test('пусто, когда серверов нет вовсе', () {
    expect(
      buildServerGroups(servers: const [], subscriptions: [_sub('a', 'A')]),
      isEmpty,
    );
  });
}
