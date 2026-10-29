import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/ui/desktop/desktop_home_screen.dart';

import 'fake_tunnel_backend.dart';
import 'test_storage.dart';

// карточка с расходом, сроком и временем обновления: без неё вкладка подписок пустая, и её строки не проверяются
class _OneSub extends SubscriptionsNotifier {
  @override
  Future<List<Subscription>> build() async => [
        Subscription(
          id: 's1',
          name: 'Provider with a rather long name',
          url: 'https://sub.example/abc',
          usedBytes: 667684659200,
          totalBytes: 107374182400,
          expiresAt: DateTime.now().add(const Duration(days: 12)),
          lastUpdatedAt: DateTime.now().subtract(const Duration(minutes: 12)),
          serverCount: 12,
          supportUrl: 'https://t.me/support',
          webPageUrl: 'https://sub.example',
        ),
      ];
}

class _IdleVpn extends VpnStateNotifier {
  @override
  Future<VpnState> build() async => const VpnState(status: VpnStatus.disconnected);
}

Future<void> _frames(WidgetTester tester, [int n = 4]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Set<String> _texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((s) => s.trim().isNotEmpty && s.length < 60)
    .toSet();

// каждый случай в своём файле: в одном процессе состояние прошлого прогона прятало переполнение у следующего.
// обходит вкладки и все разделы настроек с их пунктами и собирает ошибки отрисовки.
// переполнение в релизе не падает, а молча обрезает текст и кнопки
Future<Map<String, Set<String>>> sweepDesktopScreens(
  WidgetTester tester, {
  required String locale,
  required Size window,
  required double textScale,
}) async {
  final found = <String, Set<String>>{};
  var where = 'запуск';
  final prev = FlutterError.onError;
  FlutterError.onError = (d) =>
      (found[d.exceptionAsString().split('\n').first] ??= {}).add(where);
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  try {
    final settings = AppSettings(appLanguageCode: locale);
    final storage = await tester.runAsync(() => buildStorageService(
          initialValues: {'keqdis_settings': settings.toJsonString()},
        ));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage!),
        subscriptionsProvider.overrideWith(_OneSub.new),
        vpnStateProvider.overrideWith(_IdleVpn.new),
        vpnEngineProvider.overrideWithValue(
          VpnEngine.withBackend(FakeTunnelBackend()),
        ),
      ],
      child: const KeqdisApp(home: DesktopHomeScreen()),
    ));
    await _frames(tester, 20);

    for (final (outlined, rounded, name) in const [
      (Icons.subscriptions_outlined, Icons.subscriptions_rounded, 'Подписки'),
      (Icons.dns_outlined, Icons.dns_rounded, 'Серверы'),
      (Icons.settings_outlined, Icons.settings_rounded, 'Настройки'),
    ]) {
      where = 'вкладка $name';
      final tab = find.byIcon(outlined).evaluate().isNotEmpty
          ? find.byIcon(outlined)
          : find.byIcon(rounded);
      if (tab.evaluate().isEmpty) continue;
      await tester.tap(tab.first, warnIfMissed: false);
      await _frames(tester);
    }

    // текст может уйти с экрана между прокруткой и нажатием: анимации живые
    Future<bool> tapText(String text) async {
      if (find.text(text).evaluate().isEmpty) return false;
      await tester.ensureVisible(find.text(text).first);
      await tester.pump();
      if (find.text(text).evaluate().isEmpty) return false;
      await tester.tap(find.text(text).first, warnIfMissed: false);
      await _frames(tester);
      return true;
    }

    final root = _texts(tester);
    for (final label in root) {
      where = 'Настройки → $label';
      if (!await tapText(label)) continue;
      for (final sub in _texts(tester).difference(root).take(30)) {
        where = 'Настройки → $label → $sub';
        if (!await tapText(sub)) continue;
        for (var i = 0; i < 3 && find.text(label).evaluate().isEmpty; i++) {
          await tester.binding.handlePopRoute();
          await _frames(tester);
        }
        if (find.byType(BottomSheet).evaluate().isNotEmpty ||
            find.byType(Dialog).evaluate().isNotEmpty) {
          await tester.binding.handlePopRoute();
          await _frames(tester);
        }
      }
    }
  } finally {
    FlutterError.onError = prev;
  }
  return found;
}
