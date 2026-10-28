import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/tunnel/tunnel_state.dart';
import 'package:keqdroid/ui/desktop/desktop_rail.dart';

import '../helpers/test_storage.dart';

/// Боковая панель ПК по спеке M3E: разделы как кнопки-переключатели, кнопка меню
/// сворачивает панель, в узком окне она свёрнута сама.
class _NoSubs extends SubscriptionsNotifier {
  @override
  Future<List<Subscription>> build() async => const [];
}

class _NoServers extends ServersNotifier {
  @override
  ServersState build() => ServersState(servers: const []);
}

// настоящий заводит таймеры сторожа автовыбора
class _IdleVpn extends VpnStateNotifier {
  @override
  Future<VpnState> build() async => const VpnState(status: VpnStatus.disconnected);
}

Future<(List<int>, ProviderContainer)> _pumpRail(
  WidgetTester tester, {
  int index = 0,
  Size window = const Size(1200, 760),
  AppSettings settings = const AppSettings(),
  Locale locale = const Locale('en'),
}) async {
  final tapped = <int>[];
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final storage = await tester.runAsync(() => buildStorageService(
        initialValues: {'keqdis_settings': settings.toJsonString()},
      ));
  final container = ProviderContainer(
    overrides: [
      storageProvider.overrideWithValue(storage!),
      subscriptionsProvider.overrideWith(_NoSubs.new),
      serversProvider.overrideWith(_NoServers.new),
      vpnStateProvider.overrideWith(_IdleVpn.new),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StatefulBuilder(
                builder: (context, setState) => DesktopRail(
                  index: index,
                  onSelect: (i) {
                    tapped.add(i);
                    setState(() => index = i);
                  },
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
  return (tapped, container);
}

void main() {
  testWidgets('клик выбирает раздел, у выбранного значок залит, у остальных контурный', (
    tester,
  ) async {
    final (tapped, _) = await _pumpRail(tester);
    expect(find.byIcon(Icons.dns_rounded), findsOneWidget);
    expect(find.byIcon(Icons.subscriptions_outlined), findsOneWidget);
    await tester.tap(find.text('Subscriptions'));
    await tester.pumpAndSettle();
    expect(tapped, [1]);
    expect(find.byIcon(Icons.subscriptions_rounded), findsOneWidget);
    expect(find.byIcon(Icons.dns_outlined), findsOneWidget);
  });

  testWidgets('нажатый раздел растёт, соседи на миг уступают, после отпускания всё как было', (
    tester,
  ) async {
    await _pumpRail(tester);
    double heightOf(String label) => tester
        .getSize(find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first)
        .height;
    final rest = heightOf('Subscriptions');
    final gesture = await tester.startGesture(tester.getCenter(find.text('Subscriptions')));
    // первый кадр только запускает пружину
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(heightOf('Subscriptions'), greaterThan(rest + 6));
    expect(heightOf('Servers'), lessThan(rest - 3));
    expect(heightOf('Settings'), lessThan(rest - 3));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(heightOf('Subscriptions'), closeTo(rest, 0.5));
    expect(heightOf('Servers'), closeTo(rest, 0.5));
  });

  testWidgets('кнопка меню сворачивает панель, и выбор запоминается', (tester) async {
    final (_, container) = await _pumpRail(tester);
    expect(tester.getSize(find.byType(DesktopRail)).width, DesktopRail.expandedWidth);
    await tester.tap(find.byTooltip('Collapse panel'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DesktopRail)).width, DesktopRail.collapsedWidth);
    expect(container.read(settingsNotifierProvider).value?.desktopRailExpanded, isFalse);
    // подпись в свёрнутой панели под значком, а не справа от него
    final icon = tester.getRect(find.byIcon(Icons.subscriptions_outlined));
    final label = tester.getRect(find.text('Subscriptions'));
    expect(label.top, greaterThan(icon.bottom - 1));
    await tester.tap(find.byTooltip('Expand panel'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DesktopRail)).width, DesktopRail.expandedWidth);
  });

  testWidgets('свёрнутая панель остаётся свёрнутой после перезапуска', (tester) async {
    await _pumpRail(
      tester,
      settings: const AppSettings().copyWith(desktopRailExpanded: false),
    );
    expect(tester.getSize(find.byType(DesktopRail)).width, DesktopRail.collapsedWidth);
  });

  testWidgets('в узком окне панель свёрнута сама, кнопки меню нет', (tester) async {
    await _pumpRail(tester, window: const Size(820, 600));
    expect(tester.getSize(find.byType(DesktopRail)).width, DesktopRail.collapsedWidth);
    expect(find.byTooltip('Expand panel'), findsNothing);
  });

  testWidgets('в узком окне место кнопки меню не пустует, в широком она возвращается', (
    tester,
  ) async {
    await _pumpRail(
      tester,
      window: const Size(820, 600),
      settings: const AppSettings().copyWith(desktopRailExpanded: false),
    );
    final narrow = tester.getRect(find.text('Servers')).top;
    tester.view.physicalSize = const Size(1200, 760);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Expand panel'), findsOneWidget);
    // кнопка 48 и зазор до кнопки режима, если она есть
    expect(tester.getRect(find.text('Servers')).top - narrow, inInclusiveRange(47.5, 60.5));
  });

  // перелёт пружины сужал список на 1 dp, и на пограничной ширине окна плитки мигали компактными
  testWidgets('панель не перелетает за свою ширину ни при сворачивании, ни при разворачивании', (
    tester,
  ) async {
    await _pumpRail(tester);
    final widths = <double>[];
    Future<void> watch(String tooltip) async {
      await tester.tap(find.byTooltip(tooltip));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        widths.add(tester.getSize(find.byType(DesktopRail)).width);
      }
    }

    await watch('Collapse panel');
    expect(widths.reduce(math.min), greaterThanOrEqualTo(DesktopRail.collapsedWidth));
    widths.clear();
    await watch('Expand panel');
    expect(widths.reduce(math.max), lessThanOrEqualTo(DesktopRail.expandedWidth));
  });

  testWidgets('в свёрнутой панели между разделами 4 dp, как в M3E', (tester) async {
    await _pumpRail(tester, settings: const AppSettings().copyWith(desktopRailExpanded: false));
    final servers = tester.getRect(find.text('Servers')).top;
    final subscriptions = tester.getRect(find.text('Subscriptions')).top;
    // высота раздела 64 и зазор 4
    expect(subscriptions - servers, moreOrLessEquals(68, epsilon: 0.5));
  });
}
