import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/connections_service.dart';

/// Ответ `GET /connections` у sing-box и mihomo одинаков по форме, но
/// «правило» они пишут по-разному, и экран должен читать оба.
void main() {
  Map<String, dynamic> conn({
    required String rule,
    String rulePayload = '',
    String host = 'example.com',
  }) =>
      {
        'id': 'abc',
        'rule': rule,
        if (rulePayload.isNotEmpty) 'rulePayload': rulePayload,
        'chains': ['proxy'],
        'start': '2026-08-22T10:00:00Z',
        'upload': 10,
        'download': 20,
        'metadata': {
          'network': 'tcp',
          'host': host,
          'destinationIP': '203.0.113.5',
          'destinationPort': '443',
          'sourceIP': '10.0.0.2',
          'sourcePort': '51000',
          'type': 'Socks5',
        },
      };

  test('mihomo: тип правила склеивается со значением', () {
    final entry = ConnectionsService.entryFromClashJson(
      conn(rule: 'GeoSite', rulePayload: 'category-ru'),
    );
    expect(entry!.rule, 'GeoSite(category-ru)');
  });

  // Catch-all не несёт информации: под него попадает всё, что не поймали
  // остальные правила. У sing-box он зовётся final, у mihomo — Match.
  test('финальное правило прячут оба ядра', () {
    expect(
      ConnectionsService.entryFromClashJson(conn(rule: 'Match'))!.rule,
      isEmpty,
    );
    expect(
      ConnectionsService.entryFromClashJson(conn(rule: 'final'))!.rule,
      isEmpty,
    );
  });

  test('sing-box: готовая строка правила остаётся как есть', () {
    final entry = ConnectionsService.entryFromClashJson(
      conn(rule: 'domain_suffix => proxy'),
    );
    expect(entry!.rule, 'domain_suffix => proxy');
  });

  test('соединение без хоста и адреса назначения отбрасывается', () {
    expect(
      ConnectionsService.entryFromClashJson({
        'id': 'x',
        'metadata': {'network': 'tcp'},
      }),
      isNull,
    );
  });

  // у xray звенья цепочки в журнал не попадают, у mihomo это его Inner-соединение к следующему узлу
  test('соединение звена цепочки не показывается', () {
    final hop = {
      ...conn(rule: ''),
      'chains': ['keq-chain-0'],
    };
    expect(ConnectionsService.entryFromClashJson(hop), isNull);
    expect(ConnectionsService.entryFromClashJson(conn(rule: '')), isNotNull);
  });

  // у Clash-узла с dialer-proxy звено зовётся по-авторски, префикса нет
  test('соединение звена из Clash-конфига не показывается', () {
    final base = conn(rule: '');
    final hop = {
      ...base,
      'chains': ['🇷🇺 Вход'],
      'metadata': {...base['metadata'] as Map, 'type': 'Inner'},
    };
    expect(ConnectionsService.entryFromClashJson(hop), isNull);
  });
}
