import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_group.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/models/subscription_card_theme.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/shared/ui/server_group_anchors.dart';
import 'package:keqdroid/tunnel/tunnel_state.dart';
import 'package:keqdroid/ui/desktop/sidebar_group_nav.dart';

/// Быстрый переход в боковой панели ПК: карусель обложек групп. Большая обложка у группы,
/// на которой стоит список, клик по обложке ведёт к группе.
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

class _FakeVpn extends VpnStateNotifier {
  _FakeVpn(this._status);

  final VpnStatus _status;

  @override
  Future<VpnState> build() async => VpnState(status: _status);
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

final _threeGroups = [
  _server('a1', subscriptionId: 'sub-a'),
  _server('b1', subscriptionId: 'sub-b'),
  _server('b2', subscriptionId: 'sub-b'),
  _server('m1'),
];
final _subs = [_sub('sub-a', 'Alpha'), _sub('sub-b', 'Bravo')];

Future<List<int>> _pumpNav(
  WidgetTester tester, {
  List<ServerItem>? servers,
  List<Subscription>? subs,
  String? activeServerId,
  double labels = 1,
  VpnStatus status = VpnStatus.disconnected,
  bool withList = false,
}) async {
  final opened = <int>[];
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        serversProvider.overrideWith(
          () => _FakeServers(
            ServersState(servers: servers ?? _threeGroups, activeServerId: activeServerId),
          ),
        ),
        subscriptionsProvider.overrideWith(() => _FakeSubs(subs ?? _subs)),
        settingsNotifierProvider.overrideWith(_FakeSettings.new),
        vpnStateProvider.overrideWith(() => _FakeVpn(status)),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 248,
                height: 500,
                child: SidebarGroupNav(
                  labels: labels,
                  onOpenServers: () => opened.add(1),
                ),
              ),
              Expanded(
                child: withList
                    ? ServerGroupAnchorScope(
                        leadingInset: 0,
                        child: CustomScrollView(
                          key: const Key('list'),
                          slivers: [
                            for (final key in ['sub-a', 'sub-b', kManualServerGroupKey])
                              SliverToBoxAdapter(
                                child: ServerGroupAnchor(
                                  groupKey: key,
                                  child: const SizedBox(height: 600),
                                ),
                              ),
                          ],
                        ),
                      )
                    : const SizedBox(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return opened;
}

ScrollPosition _carouselPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(of: find.byType(CarouselView), matching: find.byType(Scrollable)),
    )
    .position;

final _covers = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_GroupCover');

Finder _cover(String groupKey) => find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_GroupCover' && (w as dynamic).group.key == groupKey,
    );

double _coverTop(WidgetTester tester, String groupKey) => tester.getRect(_cover(groupKey)).top;

// по подписи большую обложку не узнать: названия на всех
String _big(WidgetTester tester) {
  final tallest = _covers
      .evaluate()
      .reduce((a, b) => a.size!.height >= b.size!.height ? a : b);
  return (tallest.widget as dynamic).group.key as String;
}

// панель пересобирается на каждом кадре, как от анимации вкладок
Future<void> _expectNoRollback(WidgetTester tester, ScrollPosition position) async {
  var peak = position.pixels;
  for (var i = 0; i < 90; i++) {
    tester.element(find.byType(SidebarGroupNav)).markNeedsBuild();
    await tester.pump(const Duration(milliseconds: 16));
    expect(position.pixels, greaterThanOrEqualTo(peak - 0.5), reason: 'кадр ${i * 16} мс');
    peak = math.max(peak, position.pixels);
  }
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => ServerGroupAnchors.instance.currentGroup.value = null);

  testWidgets('большая обложка у группы, на которой стоит список, и едет за ним', (
    tester,
  ) async {
    await _pumpNav(tester);
    expect(_big(tester), 'sub-a');

    ServerGroupAnchors.instance.currentGroup.value = 'sub-b';
    await tester.pumpAndSettle();
    expect(_big(tester), 'sub-b');
    // число серверов группы рядом с названием
    expect(find.text('2'), findsOneWidget);

    ServerGroupAnchors.instance.currentGroup.value = kManualServerGroupKey;
    await tester.pumpAndSettle();
    expect(_big(tester), kManualServerGroupKey);
    // ручная группа берёт название из локализации
    expect(find.text('Manual servers'), findsOneWidget);
  });

  testWidgets('названия и на маленьких обложках: там посередине, на большой у нижнего края', (
    tester,
  ) async {
    await _pumpNav(tester);
    final small = tester.getRect(_cover('sub-b'));
    final smallTitle = tester.getRect(find.text('Bravo'));
    expect((smallTitle.center.dy - small.center.dy).abs(), lessThan(3));
    final big = tester.getRect(_cover('sub-a'));
    final bigTitle = tester.getRect(find.text('Alpha'));
    expect(big.bottom - bigTitle.bottom, moreOrLessEquals(14, epsilon: 0.5));
  });

  // картинка, затемнение и фон сглаживались по краю каждое само, и по краю светилась полоска
  testWidgets('обложка скругляется одним слоем, а её фон шире её на 1 dp', (tester) async {
    await _pumpNav(tester);
    expect(
      tester.widget<CarouselView>(find.byType(CarouselView)).itemClipBehavior,
      Clip.antiAliasWithSaveLayer,
    );
    final background = find.descendant(
      of: _cover('sub-a'),
      matching: find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter.runtimeType.toString() == '_DefaultCoverPainter',
      ),
    );
    expect(
      tester.getRect(background),
      rectMoreOrLessEquals(tester.getRect(_cover('sub-a')).inflate(1)),
    );
  });

  testWidgets('надпись над первой обложкой с запуска и после пересборки панели', (tester) async {
    await _pumpNav(tester);
    double gap() => _coverTop(tester, 'sub-a') - tester.getRect(find.text('Jump to')).bottom;
    final atStart = gap();
    expect(atStart, inInclusiveRange(0, 40), reason: 'надпись висит над пустым местом');
    // так панель пересобирается от каждой анимации вкладок
    tester.element(find.byType(SidebarGroupNav)).markNeedsBuild();
    await tester.pump();
    expect(gap(), moreOrLessEquals(atStart, epsilon: 0.5), reason: 'обложка заехала на надпись');
  });

  testWidgets('к верхней группе карусель едет назад, а не крутит круг вперёд', (tester) async {
    await _pumpNav(tester);
    ServerGroupAnchors.instance.currentGroup.value = kManualServerGroupKey;
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: find.byType(CarouselView), matching: find.byType(Scrollable)),
        )
        .position;
    var last = position.pixels;
    ServerGroupAnchors.instance.currentGroup.value = 'sub-a';
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(position.pixels, lessThanOrEqualTo(last + 0.5), reason: 'кадр ${i * 16} мс');
      last = position.pixels;
    }
    await tester.pumpAndSettle();
    expect(_big(tester), 'sub-a');
  });

  testWidgets('каждый щелчок колеса сразу шаг, список догоняет один раз, когда колесо встало', (
    tester,
  ) async {
    final opened = await _pumpNav(tester);
    final center = tester.getCenter(find.byType(CarouselView));
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(center));
    Future<void> notch(double dy) => tester.sendEventToBinding(mouse.scroll(Offset(0, dy)));

    await notch(100);
    await tester.pump(const Duration(milliseconds: 60));
    // второй щелчок посреди анимации первого: не ждёт её, а добавляет шаг
    await notch(100);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(_big(tester), kManualServerGroupKey);
    expect(opened, [1]);

    await notch(-100);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(_big(tester), 'sub-b');
    expect(opened, [1, 1]);
  });

  // список едет к группе анимацией через промежуточные группы, и карусель шла за ним назад:
  // пролистанная обложка вспухала и сжималась
  testWidgets('колесом через группу: пока список догоняет, карусель не откатывается', (
    tester,
  ) async {
    await _pumpNav(tester, withList: true);
    final position = _carouselPosition(tester);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(tester.getCenter(find.byType(CarouselView))));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
    await _expectNoRollback(tester, position);
    expect(_big(tester), kManualServerGroupKey);
    expect(ServerGroupAnchors.instance.currentGroup.value, kManualServerGroupKey);
  });

  testWidgets('мышкой через группу: пока список догоняет, карусель не откатывается', (
    tester,
  ) async {
    await _pumpNav(tester, withList: true);
    final position = _carouselPosition(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CarouselView)),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 0; i < 13; i++) {
      await gesture.moveBy(const Offset(0, -50));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 300));
    tester.element(find.byType(SidebarGroupNav)).markNeedsBuild();
    await gesture.up();
    await _expectNoRollback(tester, position);
    expect(_big(tester), kManualServerGroupKey);
    expect(ServerGroupAnchors.instance.currentGroup.value, kManualServerGroupKey);
  });

  testWidgets('прыжок списка перебили прокруткой: карусель встаёт туда, где список остановился', (
    tester,
  ) async {
    await _pumpNav(tester, withList: true);
    final list = tester
        .state<ScrollableState>(
          find.descendant(of: find.byKey(const Key('list')), matching: find.byType(Scrollable)),
        )
        .position;
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(tester.getCenter(find.byType(CarouselView))));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
    for (var i = 0; i < 60 && list.pixels <= 600; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(ServerGroupAnchors.instance.currentGroup.value, 'sub-b');
    list.jumpTo(600);
    await tester.pumpAndSettle();
    expect(_big(tester), 'sub-b');
  });

  testWidgets('на ПК у карусели нет полосы прокрутки сбоку', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await _pumpNav(tester);
    expect(
      find.descendant(of: find.byType(SidebarGroupNav), matching: find.byType(Scrollbar)),
      findsNothing,
    );
    expect(
      find.descendant(of: find.byType(SidebarGroupNav), matching: find.byType(RawScrollbar)),
      findsNothing,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('граница обложек идёт за мышью один к одному', (tester) async {
    await _pumpNav(tester);
    double bravoTop() => _coverTop(tester, 'sub-b');
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CarouselView)),
      kind: PointerDeviceKind.mouse,
    );
    // первый сдвиг съедает порог начала тяги
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump(const Duration(milliseconds: 50));
    final before = bravoTop();
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(before - bravoTop(), moreOrLessEquals(100, epsilon: 2));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('бросок мышью ведёт к соседней обложке и не проскакивает её', (tester) async {
    for (final step in [25.0, 50.0]) {
      await _pumpNav(tester);
      final position = _carouselPosition(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(CarouselView)),
        kind: PointerDeviceKind.mouse,
      );
      // 1500 и 3000 пикселей в секунду
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(Offset(0, -step), timeStamp: Duration(milliseconds: 16 * (i + 1)));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up(timeStamp: const Duration(milliseconds: 100));
      var peak = position.pixels;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        peak = math.max(peak, position.pixels);
      }
      await tester.pumpAndSettle();
      expect(_big(tester), 'sub-b', reason: 'шаг $step');
      // пиксель-другой перелетает сама пружина доводки Flutter, и без мыши тоже
      expect(peak, lessThanOrEqualTo(position.pixels + 3), reason: 'шаг $step');
      await tester.pumpWidget(const SizedBox());
      ServerGroupAnchors.instance.currentGroup.value = null;
    }
  });

  testWidgets('тяга мышкой не в шесть раз резвее: 60 пикселей мало, 300 хватает', (tester) async {
    Future<void> slowDrag(double dy) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(CarouselView)),
        kind: PointerDeviceKind.mouse,
      );
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(Offset(0, dy / 10));
        await tester.pump(const Duration(milliseconds: 50));
      }
      // замираем перед отпусканием: без скорости броска решает только пройденное
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pumpAndSettle();
    }

    final opened = await _pumpNav(tester);
    await slowDrag(-60);
    expect(_big(tester), 'sub-a');
    expect(opened, isEmpty);
    await slowDrag(-300);
    expect(_big(tester), 'sub-b');
    expect(opened, [1]);
  });

  testWidgets('карусель тянется мышкой, и список идёт туда, где она осела', (tester) async {
    final opened = await _pumpNav(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CarouselView)),
      kind: PointerDeviceKind.mouse,
    );
    // мышь не бросает: решает пройденное, больше половины обложки
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_big(tester), 'sub-b');
    expect(opened, [1]);
  });

  testWidgets('с последней группы к первой назад по одной, через край не перескакивает', (
    tester,
  ) async {
    await _pumpNav(tester);
    ServerGroupAnchors.instance.currentGroup.value = kManualServerGroupKey;
    await tester.pumpAndSettle();
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(tester.getCenter(find.byType(CarouselView))));
    Future<void> wheel(double dy, int ms) async {
      await tester.sendEventToBinding(
        mouse.scroll(Offset(0, dy), timeStamp: Duration(milliseconds: ms)),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    // у последней группы вниз листать некуда: первая под ней не выглядывает
    await wheel(100, 1000);
    expect(_big(tester), kManualServerGroupKey);
    await wheel(-100, 2000);
    expect(_big(tester), 'sub-b');
    await wheel(-100, 3000);
    expect(_big(tester), 'sub-a');
    await wheel(-100, 4000);
    expect(_big(tester), 'sub-a');
  });

  testWidgets('клик по краю следующей обложки открывает вкладку серверов', (tester) async {
    final opened = await _pumpNav(tester);
    final nav = tester.getRect(find.byType(SidebarGroupNav));
    await tester.tapAt(Offset(nav.center.dx, nav.bottom - 20));
    await tester.pumpAndSettle();
    expect(opened, [1]);
    // списка серверов в этом дереве нет: прыжок обязан промолчать, а не упасть
    expect(tester.takeException(), isNull);
  });

  testWidgets('у групп без картинки обложка из форм, а не значок на пустой плашке', (
    tester,
  ) async {
    await _pumpNav(tester);
    expect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter.runtimeType.toString() == '_DefaultCoverPainter',
      ),
      findsWidgets,
    );
    expect(find.byIcon(Icons.edit_rounded), findsNothing);
    expect(find.byIcon(Icons.cloud_rounded), findsNothing);
  });

  testWidgets('большая обложка с картинкой выше 320 dp раскладывается без ошибок', (tester) async {
    SubscriptionCardTheme.customDirectory = '/data/app/card_themes';
    addTearDown(() => SubscriptionCardTheme.customDirectory = null);
    await _pumpNav(
      tester,
      subs: [
        Subscription(
          id: 'sub-a',
          name: 'Alpha',
          url: 'https://example.com/sub-a',
          cardThemeId: '${SubscriptionCardTheme.filePrefix}pic.png',
        ),
        _sub('sub-b', 'Bravo'),
      ],
    );
    expect(tester.getSize(_cover('sub-a')).height, greaterThan(320));
    expect(tester.takeException(), isNull);
    final picture = find.descendant(of: _cover('sub-a'), matching: find.byType(OverflowBox));
    expect(tester.getSize(picture).width, tester.getSize(_cover('sub-a')).width + 2);
  });

  testWidgets('одна группа: переходить некуда, карусели нет', (tester) async {
    await _pumpNav(
      tester,
      servers: [_server('a1', subscriptionId: 'sub-a')],
      subs: [_sub('sub-a', 'Alpha')],
    );
    expect(find.byType(CarouselView), findsNothing);
  });

  testWidgets('в свёрнутой панели обложки без подписей', (tester) async {
    await _pumpNav(tester, labels: 0);
    expect(find.byType(CarouselView), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);
    expect(find.text('Jump to'), findsNothing);
  });

  testWidgets('без подключения точки нет', (tester) async {
    await _pumpNav(tester, activeServerId: 'a1');
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).shape == BoxShape.circle,
      ),
      findsNothing,
    );
  });

  testWidgets('у группы, через которую подключено, точка у названия', (tester) async {
    Finder dot() => find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).shape == BoxShape.circle,
        );
    await _pumpNav(tester, activeServerId: 'a1', status: VpnStatus.connected);
    expect(dot(), findsOneWidget);
  });
}
