import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/models/server_group.dart';
import 'package:keqdroid/shared/ui/server_group_anchors.dart';
import 'package:keqdroid/ui/desktop/sidebar_group_nav.dart';

/// Быстрый переход в боковой панели десктопа: под тремя разделами оставалось
/// полэкрана пустоты, а список серверов у человека с несколькими подписками
/// листается долго.
class _FakeServers extends ServersNotifier {
  _FakeServers(this._state);

  final ServersState _state;

  @override
  ServersState build() => _state;
}

class _FakeSubs extends SubscriptionsNotifier {
  _FakeSubs(this._subs);

  final List<Subscription> _subs;

  @override
  Future<List<Subscription>> build() async => _subs;
}

class _FakeSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

ServerItem _server(String id, {String? subscriptionId}) => ServerItem(
      id: id,
      config: 'vless://uuid@$id.example:443?type=tcp&security=none',
      type: subscriptionId == null
          ? ServerItemType.manual
          : ServerItemType.subscription,
      subscriptionId: subscriptionId,
    );

Subscription _sub(String id, String name) =>
    Subscription(id: id, name: name, url: 'https://example.com/$id');

Future<int> _pumpNav(
  WidgetTester tester, {
  required List<ServerItem> servers,
  required List<Subscription> subs,
  String? activeServerId,
  bool compact = false,
}) async {
  var opened = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        serversProvider.overrideWith(
          () => _FakeServers(
            ServersState(servers: servers, activeServerId: activeServerId),
          ),
        ),
        subscriptionsProvider.overrideWith(() => _FakeSubs(subs)),
        settingsNotifierProvider.overrideWith(_FakeSettings.new),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 220,
                child: Column(
                  children: [
                    SidebarGroupNav(
                      compact: compact,
                      onOpenServers: () => opened++,
                    ),
                  ],
                ),
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return opened;
}

FontWeight? _weightOf(WidgetTester tester, String title) =>
    tester.widget<Text>(find.text(title)).style?.fontWeight;

void main() {
  setUp(() => ServerGroupAnchors.instance.currentGroup.value = null);

  testWidgets('подсветка идёт за положением списка, а не за активным сервером', (
    tester,
  ) async {
    // Ровно та жалоба: активный сервер лежит в первой группе, поэтому метка
    // навсегда оставалась на ней — сколько бы групп ни пролистали.
    await _pumpNav(
      tester,
      servers: [_server('a1', subscriptionId: 'sub-a'), _server('m1')],
      subs: [_sub('sub-a', 'Alpha')],
      activeServerId: 'a1',
    );

    ServerGroupAnchors.instance.currentGroup.value = kManualServerGroupKey;
    await tester.pumpAndSettle();

    // Вес берём из шкалы (emphasized), поэтому сверяем не константу, а то,
    // что подсвеченный пункт тяжелее соседа.
    final selectedWeight = _weightOf(tester, 'Manual servers');
    final otherWeight = _weightOf(tester, 'Alpha') ?? FontWeight.w400;
    expect(selectedWeight, isNotNull);
    expect(selectedWeight!.value, greaterThan(otherWeight.value));
  });

  testWidgets('показывает все группы списка и переводит на серверы', (
    tester,
  ) async {
    await _pumpNav(
      tester,
      servers: [
        _server('a1', subscriptionId: 'sub-a'),
        _server('b1', subscriptionId: 'sub-b'),
        _server('m1'),
      ],
      subs: [_sub('sub-a', 'Alpha'), _sub('sub-b', 'Bravo')],
    );

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Bravo'), findsOneWidget);
    // Ручная группа берёт своё название из локализации, а не из подписки.
    expect(find.text('Manual servers'), findsOneWidget);
    // Счётчик серверов у каждой группы.
    expect(find.text('1'), findsNWidgets(3));
  });

  testWidgets('клик по группе открывает вкладку серверов', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serversProvider.overrideWith(
            () => _FakeServers(
              ServersState(
                servers: [
                  _server('a1', subscriptionId: 'sub-a'),
                  _server('m1'),
                ],
              ),
            ),
          ),
          subscriptionsProvider.overrideWith(
            () => _FakeSubs([_sub('sub-a', 'Alpha')]),
          ),
          settingsNotifierProvider.overrideWith(_FakeSettings.new),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 220,
              child: Column(
                children: [
                  SidebarGroupNav(
                    compact: false,
                    onOpenServers: () => opened++,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    expect(opened, 1);
    // Списка серверов в этом дереве нет — прыжок обязан промолчать, а не упасть.
    expect(tester.takeException(), isNull);
  });

  testWidgets('прижат к низу колонки, а не к верху свободного места', (
    tester,
  ) async {
    // Разделы вверху, переход внизу: иначе это одна разъехавшаяся группа
    // кнопок с провалом посередине.
    await _pumpNav(
      tester,
      servers: [
        _server('a1', subscriptionId: 'sub-a'),
        _server('b1', subscriptionId: 'sub-b'),
        _server('m1'),
      ],
      subs: [_sub('sub-a', 'Alpha'), _sub('sub-b', 'Bravo')],
    );

    final area = tester.getRect(find.byType(SidebarGroupNav));
    final lastTile = tester.getRect(find.text('Manual servers'));
    final firstTile = tester.getRect(find.text('Alpha'));

    expect(area.bottom - lastTile.bottom, lessThan(40));
    expect(
      firstTile.top - area.top,
      greaterThan(100),
      reason: 'свободное место обязано остаться СВЕРХУ, а не под кнопками',
    );
  });

  testWidgets('одна группа — переходить некуда, панель пуста', (tester) async {
    await _pumpNav(
      tester,
      servers: [_server('m1'), _server('m2')],
      subs: const [],
    );

    expect(find.byType(InkWell), findsNothing);
    expect(find.text('Manual servers'), findsNothing);
  });

  testWidgets('узкая панель показывает только значки', (tester) async {
    await _pumpNav(
      tester,
      servers: [_server('a1', subscriptionId: 'sub-a'), _server('m1')],
      subs: [_sub('sub-a', 'Alpha')],
      compact: true,
    );

    expect(find.text('Alpha'), findsNothing);
    expect(find.byType(Tooltip), findsNWidgets(2));
  });
}
