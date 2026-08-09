import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/connection_entry.dart';
import 'package:keqdroid/screens/settings/connection_tile.dart';

/// Экран «Соединения» дважды показывал пустоту при непустом счётчике: оба раза
/// плитка падала внутри списка (сначала в paint на разноцветной рамке со
/// скруглением, потом в layout на Row со stretch при неограниченной высоте), а
/// исключение молча гасилось на уровне render object'а. Поэтому проверяем
/// плитку именно так, как она живёт в приложении — пачкой внутри ListView.
Widget _screen(List<ConnectionEntry> entries, {bool showProcess = false}) =>
    MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7B61FF),
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(
        body: Column(
          children: [
            const Padding(padding: EdgeInsets.all(12), child: Text('фильтр')),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                itemCount: entries.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => ConnectionTile(
                  entry: entries[i],
                  showProcess: showProcess,
                  ruleInfoAvailable: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );

ConnectionEntry _entry({
  required String host,
  String network = 'tcp',
  int port = 443,
  String outbound = 'proxy',
  String rule = 'proxy-geosite',
  String inbound = 'socks-in',
  String source = '127.0.0.1:53182',
  String process = '',
  String destIp = '',
  bool rejected = false,
  bool decidedByCore = false,
}) =>
    ConnectionEntry(
      id: '$source>$network:$host:$port',
      network: network,
      host: host,
      destPort: port,
      destIp: destIp,
      source: source,
      process: process,
      inbound: inbound,
      outbound: outbound,
      rule: rule,
      startedAt: DateTime(2026, 8, 9, 9, 58, 12),
      rejected: rejected,
      decidedByCore: decidedByCore,
    );

/// Ровно тот набор, что бывает на живом экране: все вердикты, оба состояния
/// правила, длинные значения и запись без части полей.
List<ConnectionEntry> _sevenConnections() => [
      _entry(host: 'www.google.com'),
      _entry(host: 'ya.ru', outbound: 'direct', rule: 'direct-ru'),
      _entry(
        host: 'ads.doubleclick.net',
        outbound: 'block',
        rule: 'block-ads',
        rejected: true,
      ),
      _entry(host: '104.244.42.129', outbound: 'proxy', decidedByCore: true),
      _entry(host: 'dns.google', network: 'udp', port: 53, rule: ''),
      _entry(
        host: 'very-long-subdomain.example-of-a-really-long-hostname.co.uk',
        process: 'C:\\Program Files\\Mozilla Firefox\\firefox.exe',
        destIp: '2606:4700:4700::1111',
      ),
      _entry(host: 'telegram.org', inbound: '', source: '', rule: '*'),
    ];

void main() {
  group('ConnectionTile in a list', () {
    testWidgets('renders every connection without throwing', (tester) async {
      final entries = _sevenConnections();
      await tester.pumpWidget(_screen(entries));

      expect(tester.takeException(), isNull);
      expect(find.byType(ConnectionTile), findsNWidgets(entries.length));
      expect(find.text('www.google.com:443'), findsOneWidget);
      expect(find.text('ads.doubleclick.net:443'), findsOneWidget);
      // Вердикты подписаны, а не только раскрашены.
      expect(find.text('БЛОК'), findsOneWidget);
      expect(find.text('НАПРЯМУЮ'), findsOneWidget);
      expect(find.text('ЯДРО'), findsOneWidget);
    });

    testWidgets('every tile gets a finite, content-sized height',
        (tester) async {
      await tester.pumpWidget(_screen(_sevenConnections()));

      final sizes = tester
          .widgetList(find.byType(ConnectionTile))
          .map((w) => tester.getSize(find.byWidget(w)))
          .toList();

      expect(sizes, isNotEmpty);
      for (final size in sizes) {
        expect(size.height.isFinite, isTrue);
        // Плитка не схлопнута и не растянута по высоте вьюпорта.
        expect(size.height, greaterThan(40));
        expect(size.height, lessThan(200));
      }
    });

    testWidgets('process name is shown only where the source knows it',
        (tester) async {
      await tester.pumpWidget(_screen(_sevenConnections(), showProcess: true));
      expect(find.text('firefox.exe'), findsOneWidget);

      await tester.pumpWidget(_screen(_sevenConnections()));
      expect(find.text('firefox.exe'), findsNothing);
    });
  });
}
