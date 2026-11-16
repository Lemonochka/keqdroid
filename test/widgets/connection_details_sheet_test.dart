import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/connection_entry.dart';
import 'package:keqdroid/screens/settings/connection_details_sheet.dart';
import 'package:keqdroid/screens/settings/connection_tile.dart';
import 'package:keqdroid/utils/connection_route.dart';

final _t0 = DateTime(2026, 11, 16, 13, 20, 12);

ConnectionEntry _one(
  String source,
  DateTime at, {
  bool closed = false,
  int? download,
  int? upload,
}) =>
    ConnectionEntry(
      id: source,
      network: 'tcp',
      host: 'drinkit-mobile-api.drinkit.dodois.io',
      destPort: 443,
      destIp: '51.250.39.172',
      source: source,
      process: 'Drinkit',
      inbound: 'tun-in',
      outbound: 'direct',
      rule: 'keq-route-3-domains',
      startedAt: at,
      closed: closed,
      download: download,
      upload: upload,
    );

ConnectionEntry _group(int n, {bool live = false}) {
  final members = [
    for (var i = n - 1; i >= 0; i--)
      _one(
        '172.19.0.1:${43600 + i}',
        _t0.add(Duration(seconds: i)),
        closed: i.isEven,
        download: live ? 1024 * (i + 1) : null,
        upload: live ? 100 : null,
      ),
  ];
  return members.first.copyWith(
    id: 'group:x',
    source: '',
    startedAt: _t0,
    count: n,
    members: members,
    closed: false,
  );
}

const _lists = [
  ConnectionListLine('Российские сайты', ListMatch.hit, note: 'маршрут включён'),
  ConnectionListLine('Белые списки мобильной связи', ListMatch.hit),
  ConnectionListLine('Реклама и трекеры', ListMatch.miss),
  ConnectionListLine('Иранские сайты', ListMatch.unknown, note: 'нет в базе'),
];

Widget _app(Widget sheet) => MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE76FAD),
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(body: sheet),
    );

ConnectionDetailsSheet _sheet(
  ValueListenable<ConnectionEntry> entry, {
  bool live = false,
  bool livenessKnown = true,
  Future<ConnectionInsightView>? insight,
}) =>
    ConnectionDetailsSheet(
      entry: entry,
      live: live,
      livenessKnown: livenessKnown,
      insight: insight ??
          Future.value(
            const ConnectionInsightView(
              rule: ConnectionField(
                'keq-route-3-domains',
                mono: true,
                note: 'маршрут «Российские сайты»',
              ),
              lists: _lists,
            ),
          ),
      app: const ConnectionField('Drinkit'),
      rule: const ConnectionField('keq-route-3-domains', mono: true),
      exit: const ConnectionField('direct', mono: true, note: 'мимо VPN'),
      now: () => _t0.add(const Duration(minutes: 2, seconds: 14)),
    );

void main() {
  testWidgets('a single connection: every field, its own source, no member list',
      (tester) async {
    final entry = ValueNotifier(_one('172.19.0.1:43612', _t0));
    await tester.pumpWidget(_app(_sheet(entry)));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('drinkit-mobile-api.drinkit.dodois.io:443'), findsOneWidget);
    expect(find.text('НАПРЯМУЮ'), findsOneWidget);
    expect(find.text('51.250.39.172'), findsOneWidget);
    expect(find.text('Drinkit'), findsOneWidget);
    expect(find.text('маршрут «Российские сайты»'), findsOneWidget);
    expect(find.text('мимо VPN'), findsOneWidget);
    expect(find.text('172.19.0.1:43612'), findsOneWidget);
    expect(find.text('начало'), findsOneWidget);
    expect(find.text('13:20:12'), findsOneWidget);
    // по логу не видно, сколько оно живёт
    expect(find.textContaining('открыто'), findsNothing);
    expect(find.textContaining('Соединения:'), findsNothing);
  });

  testWidgets('ready lists: a check, a dash and an honest unknown',
      (tester) async {
    final entry = ValueNotifier(_one('a:1', _t0));
    await tester.pumpWidget(_app(_sheet(entry)));
    await tester.pump();

    expect(find.text('Во встроенных списках'), findsOneWidget);
    expect(
      find.textContaining('Российские сайты  маршрут включён'),
      findsOneWidget,
    );
    expect(find.textContaining('Иранские сайты  нет в базе'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
    expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);
  });

  testWidgets('while the base is read the lists wait, the rest is already there',
      (tester) async {
    final entry = ValueNotifier(_one('a:1', _t0));
    final pending = Completer<ConnectionInsightView>();
    await tester.pumpWidget(_app(_sheet(entry, insight: pending.future)));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('keq-route-3-domains'), findsOneWidget);
    expect(find.text('маршрут «Российские сайты»'), findsNothing);

    pending.complete(const ConnectionInsightView(lists: _lists));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a group lists its connections, four first, the rest on tap',
      (tester) async {
    final entry = ValueNotifier(_group(6));
    await tester.pumpWidget(_app(_sheet(entry)));
    await tester.pump();

    expect(find.text('Соединения: 6'), findsOneWidget);
    expect(find.text('первое'), findsOneWidget);
    // у группы нет одного источника
    expect(find.text('источник'), findsNothing);
    expect(find.text('172.19.0.1:43605'), findsOneWidget);
    expect(find.text('172.19.0.1:43600'), findsNothing);
    expect(find.text('открыто'), findsWidgets);
    expect(find.text('закрыто'), findsWidgets);

    // шторка не выше 85% экрана, кнопка уезжает в прокрутку
    await tester.ensureVisible(find.text('ещё 2'));
    await tester.tap(find.text('ещё 2'));
    await tester.pump();
    expect(find.text('172.19.0.1:43600'), findsOneWidget);
    expect(find.text('ещё 2'), findsNothing);
  });

  testWidgets('without Info logs nobody is called open or closed',
      (tester) async {
    final entry = ValueNotifier(_group(3));
    await tester.pumpWidget(_app(_sheet(entry, livenessKnown: false)));
    await tester.pump();

    expect(find.text('открыто'), findsNothing);
    expect(find.text('закрыто'), findsNothing);
  });

  testWidgets('live snapshot: how long it is open and bytes per connection',
      (tester) async {
    final entry = ValueNotifier(_group(2, live: true).copyWith(
      download: 3072,
      upload: 200,
    ));
    await tester.pumpWidget(_app(_sheet(entry, live: true)));
    await tester.pump();

    expect(find.text('открыто 02:14'), findsOneWidget);
    expect(find.text('↓ 3.0 KB  ↑ 200 B'), findsOneWidget);
    expect(find.text('↓ 2.0 KB  ↑ 100 B'), findsOneWidget);

    entry.value = entry.value.copyWith(download: 4096);
    await tester.pump();
    expect(find.text('↓ 4.0 KB  ↑ 200 B'), findsOneWidget);
  });

  testWidgets('copy puts every field into the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final entry = ValueNotifier(_one('172.19.0.1:43612', _t0));
    await tester.pumpWidget(_app(_sheet(entry)));
    await tester.pump();
    await tester.tap(find.text('Скопировать'));
    await tester.pump();

    expect(copied, contains('drinkit-mobile-api.drinkit.dodois.io:443 TCP'));
    expect(copied, contains('правило: keq-route-3-domains (маршрут «Российские сайты»)'));
    expect(copied, contains('выход: direct (мимо VPN)'));
    expect(copied, contains('источник: 172.19.0.1:43612'));
  });

  testWidgets('the list card opens details on tap, the host text too',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(ListView(
      children: [
        ConnectionTile(
          entry: _one('a:1', _t0),
          showProcess: true,
          ruleInfoAvailable: true,
          onTap: () => taps++,
        ),
      ],
    )));
    await tester.tap(find.text('direct'));
    await tester.tap(find.text('drinkit-mobile-api.drinkit.dodois.io:443'));
    expect(taps, 2);
  });
}
