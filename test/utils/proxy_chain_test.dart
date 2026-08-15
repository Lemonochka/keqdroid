import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/utils/proxy_chain.dart';

const _de = 'vless://uuid-de@de.example.com:443?security=tls&type=tcp#%F0%9F%87%A9%F0%9F%87%AA%20DE-1';
const _nl = 'trojan://pass@nl.example.com:8443?sni=nl.example.com#NL-2';
const _jp = 'ss://YWVzLTI1Ni1nY206cGFzcw@jp.example.com:8388#JP-3';

ProxyChainConfig _chain({String name = 'DE → JP'}) => ProxyChainConfig(
      name: name,
      hops: const [
        ProxyChainHop(serverId: 'id-de', name: 'DE-1', config: _de),
        ProxyChainHop(serverId: 'id-nl', name: 'NL-2', config: _nl),
        ProxyChainHop(serverId: 'id-jp', name: 'JP-3', config: _jp),
      ],
    );

void main() {
  group('ProxyChainConfig', () {
    test('encode/parse round-trip keeps order, ids and names', () {
      final parsed = ProxyChainConfig.tryParse(_chain().encode());

      expect(parsed, isNotNull);
      expect(parsed!.name, 'DE → JP');
      expect(parsed.hops.map((h) => h.serverId), ['id-de', 'id-nl', 'id-jp']);
      expect(parsed.hops.map((h) => h.name), ['DE-1', 'NL-2', 'JP-3']);
      expect(parsed.entry.config, _de);
      expect(parsed.exit.config, _jp);
    });

    test('encoded link carries no padding and is recognised by scheme', () {
      final encoded = _chain().encode();

      expect(encoded.startsWith('keqchain://'), isTrue);
      expect(encoded.contains('='), isFalse);
      expect(ProxyChainConfig.looksLikeChain(encoded), isTrue);
      expect(ProxyChainConfig.looksLikeChain(_de), isFalse);
    });

    test('rejects damaged payload instead of throwing', () {
      expect(ProxyChainConfig.tryParse('keqchain://not-base64!!!'), isNull);
      expect(ProxyChainConfig.tryParse('keqchain://'), isNull);
      expect(ProxyChainConfig.tryParse(_de), isNull);
    });

    test('describeProblem flags single-node and oversized chains', () {
      expect(ProxyChainConfig.describeProblem(_chain().encode()), isNull);

      final single = ProxyChainConfig(
        name: 'solo',
        hops: const [ProxyChainHop(config: _de)],
      );
      expect(ProxyChainConfig.describeProblem(single.encode()), isNotNull);

      final huge = ProxyChainConfig(
        name: 'huge',
        hops: List.generate(
          ProxyChainConfig.maxHops + 1,
          (i) => const ProxyChainHop(config: _de),
        ),
      );
      expect(ProxyChainConfig.describeProblem(huge.encode()), isNotNull);
    });

    test('canBeHop accepts link protocols and refuses awg/custom/chain', () {
      expect(ProxyChainConfig.canBeHop('vless'), isTrue);
      expect(ProxyChainConfig.canBeHop('hy2'), isTrue);
      expect(ProxyChainConfig.canBeHop('awg'), isFalse);
      expect(ProxyChainConfig.canBeHop('custom'), isFalse);
      expect(ProxyChainConfig.canBeHop('chain'), isFalse);
    });

    test('refreshed pulls the current link of a node that is still around', () {
      const rotated = 'vless://uuid-de@de.example.com:2053?security=tls#DE-1';
      final updated = _chain().refreshed({
        'id-de': (config: rotated, name: 'DE-1 (new)'),
      });

      expect(updated.entry.config, rotated);
      expect(updated.entry.name, 'DE-1 (new)');
      // Узлы, которых нет в списке, остаются на снимке.
      expect(updated.hops[1].config, _nl);
    });

    test('refreshed returns the same object when nothing moved', () {
      final chain = _chain();
      final same = chain.refreshed({
        'id-de': (config: _de, name: 'DE-1'),
      });

      expect(identical(same, chain), isTrue,
          reason: 'иначе загрузка списка писала бы в хранилище на пустом месте');
    });
  });

  group('ServerItem as a chain', () {
    ServerItem itemOf(ProxyChainConfig chain) => ServerItem(
          id: 'chain-1',
          config: chain.encode(),
          type: ServerItemType.manual,
        );

    test('protocol, name and endpoint come from the chain', () {
      final item = itemOf(_chain());

      expect(item.protocol, 'chain');
      expect(item.displayName, 'DE → JP');
      // Адрес — ВХОДНОЙ узел: только к нему подключается устройство.
      expect(item.address, 'de.example.com');
      expect(item.port, 443);
      expect(item.chainHopItems.length, 3);
    });

    test('unnamed chain falls back to the route', () {
      final item = itemOf(_chain(name: ''));

      expect(item.displayName, 'DE-1 → NL-2 → JP-3');
    });

    test('damaged chain link stays unknown instead of crashing the list', () {
      final item = ServerItem(
        id: 'broken',
        config: 'keqchain://%%%',
        type: ServerItemType.manual,
      );

      // Не 'chain': иначе тайл разыменовал бы chainConfig! и уронил список.
      expect(item.protocol, 'unknown');
      expect(item.chainConfig, isNull);
      expect(item.chainHopItems, isEmpty);
      expect(item.flag, isNull);
      expect(() => item.address, returnsNormally);
    });
  });
}
