import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/servers/chain_editor.dart';
import 'package:keqdroid/utils/proxy_chain.dart';
import 'package:keqdroid/utils/server_sort.dart';

const _de = 'vless://uuid-de@de.example.com:443?security=tls&type=tcp#DE-1';
const _nl = 'trojan://pass@nl.example.com:8443?sni=nl.example.com#NL-2';

/// Список серверов без хранилища: экран читает только его, а `_load()` из
/// настоящего нотифаера полез бы в SharedPreferences.
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

/// Настоящий нотифаер режимов сортировки читает их из хранилища, которого в
/// тесте нет (storageProvider намеренно бросает без override).
class _FakeSortModes extends ServerSortModesNotifier {
  _FakeSortModes(this._modes);

  final Map<String, String> _modes;

  @override
  Map<String, String> build() => _modes;
}

Subscription _sub(String id, String name) =>
    Subscription(id: id, name: name, url: 'https://$id.example.com/sub');

ServerItem _server(String id, String name, {String? subscriptionId}) =>
    ServerItem(
      id: id,
      config: 'vless://uuid-$id@$id.example.com:443?security=tls&type=tcp#$name',
      type: subscriptionId == null
          ? ServerItemType.manual
          : ServerItemType.subscription,
      subscriptionId: subscriptionId,
    );

ServerItem _chainItem() {
  final chain = ProxyChainConfig(
    name: 'DE → NL',
    hops: const [
      ProxyChainHop(serverId: 'id-de', name: 'DE-1', config: _de),
      ProxyChainHop(serverId: 'id-nl', name: 'NL-2', config: _nl),
    ],
  );
  return ServerItem(
    id: 'chain-1',
    config: chain.encode(),
    type: ServerItemType.manual,
  );
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  String? serverId,
  double textScale = 1.0,
  List<ServerItem> servers = const [],
  List<Subscription> subscriptions = const [],
  Map<String, String> sortModes = const {},
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        serversProvider.overrideWith(
          () => _FakeServers(ServersState(servers: servers)),
        ),
        subscriptionsProvider.overrideWith(() => _FakeSubs(subscriptions)),
        settingsNotifierProvider.overrideWith(_FakeSettings.new),
        serverSortModesProvider.overrideWith(() => _FakeSortModes(sortModes)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: ChainEditorScreen(serverId: serverId),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('маршрут существующей цепочки раскладывается без overflow', (
    tester,
  ) async {
    final chain = _chainItem();
    await _pumpEditor(tester, serverId: chain.id, servers: [chain]);

    expect(find.text('DE-1'), findsOneWidget);
    expect(find.text('NL-2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('крупный системный шрифт не рвёт строку узла', (tester) async {
    // Ровно этот случай и рвался: у строки была фиксированная высота, и две
    // строки текста при увеличенном шрифте в неё переставали влезать.
    final chain = _chainItem();
    await _pumpEditor(
      tester,
      serverId: chain.id,
      servers: [chain],
      textScale: 1.8,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('кружок на рельсе непрозрачен, иначе линия перечёркивает его', (
    tester,
  ) async {
    // Узлы стоят ПОВЕРХ линии маршрута: у полупрозрачной подложки она
    // просвечивала насквозь, и кнопка добавления выглядела перечёркнутой.
    await _pumpEditor(tester);

    final node = tester.widget<Container>(
      find
          .ancestor(of: find.byIcon(Icons.add_rounded), matching: find.byType(Container))
          .first,
    );
    expect((node.decoration as BoxDecoration).color!.a, 1.0);
  });

  testWidgets('узлы в выборе разложены по подпискам', (tester) async {
    // Без заголовков одинаковые имена из разных подписок не различить —
    // выбор входа и выхода превращался в угадайку.
    await _pumpEditor(
      tester,
      subscriptions: [_sub('s1', 'Alpha Sub'), _sub('s2', 'Beta Sub')],
      servers: [
        _server('a1', 'NL-1', subscriptionId: 's1'),
        _server('b1', 'NL-1', subscriptionId: 's2'),
        _server('m1', 'My own'),
      ],
    );

    await tester.tap(find.text('Add node'));
    await tester.pumpAndSettle();

    expect(find.text('Alpha Sub'), findsOneWidget);
    expect(find.text('Beta Sub'), findsOneWidget);
    expect(find.text('Manual servers'), findsOneWidget);
    // Тёзки из разных подписок остаются оба — группа объясняет, кто есть кто.
    expect(find.text('NL-1'), findsNWidgets(2));
  });

  testWidgets('внутри группы работает её же сортировка с главного экрана', (
    tester,
  ) async {
    // Иначе один и тот же набор серверов выглядит в приложении двумя разными
    // списками: на главной по алфавиту, в выборе узла — как пришло.
    await _pumpEditor(
      tester,
      subscriptions: [_sub('s1', 'Alpha Sub')],
      sortModes: {'s1': ServerSortMode.name.name},
      servers: [
        _server('a1', 'Zurich', subscriptionId: 's1'),
        _server('a2', 'Amsterdam', subscriptionId: 's1'),
      ],
    );

    await tester.tap(find.text('Add node'));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Amsterdam')).dy,
      lessThan(tester.getTopLeft(find.text('Zurich')).dy),
    );
  });

  testWidgets('подписка без подходящих серверов не даёт пустой заголовок', (
    tester,
  ) async {
    await _pumpEditor(
      tester,
      subscriptions: [_sub('s1', 'Alpha Sub'), _sub('s2', 'Beta Sub')],
      servers: [_server('a1', 'NL-1', subscriptionId: 's1')],
    );

    await tester.tap(find.text('Add node'));
    await tester.pumpAndSettle();

    expect(find.text('Alpha Sub'), findsOneWidget);
    expect(find.text('Beta Sub'), findsNothing);
    expect(find.text('Manual servers'), findsNothing);
  });

  testWidgets('пустая цепочка не даёт сохранить и объясняет почему', (
    tester,
  ) async {
    await _pumpEditor(tester);

    final save = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(save.onPressed, isNull);
    expect(find.text('A chain needs at least two nodes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
