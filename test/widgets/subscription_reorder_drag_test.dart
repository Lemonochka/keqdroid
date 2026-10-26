import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/subscriptions_tab.dart';
import 'package:keqdroid/services/vpn_engine.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

/// Перенос карточки подписки под масштабом интерфейса: поднятая карточка едет
/// за пальцем и не уезжает вбок.

class _FakeSubs extends SubscriptionsNotifier {
  @override
  Future<List<Subscription>> build() async => const [
        Subscription(id: 'a', name: 'Gaming VPN', url: 'https://a.example'),
        Subscription(id: 'b', name: 'Work VPN', url: 'https://b.example'),
      ];
}

class _FakeSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

class _FakeVpn extends VpnStateNotifier {
  @override
  Future<VpnState> build() async =>
      const VpnState(status: VpnStatus.disconnected);
}

// как _UiZoom в app.dart: всё приложение рисуется крупнее и сжимается
Widget _zoom(BuildContext context, Widget? child, double scale) =>
    LayoutBuilder(
      builder: (context, constraints) => FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(
          size: constraints.biggest / scale,
          child: child,
        ),
      ),
    );

void main() {
  testWidgets('под масштабом поднятая карточка не съезжает вбок', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final storage = await buildStorageService();
    final shot = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: shot,
        child: ProviderScope(
          overrides: [
            storageProvider.overrideWithValue(storage),
            subscriptionsProvider.overrideWith(_FakeSubs.new),
            settingsNotifierProvider.overrideWith(_FakeSettings.new),
            vpnStateProvider.overrideWith(_FakeVpn.new),
            vpnEngineProvider.overrideWithValue(
              VpnEngine.withBackend(FakeTunnelBackend()),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('ru'),
            builder: (context, child) => _zoom(context, child, 0.85),
            home: const Scaffold(body: SubscriptionsTab()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final title = find.text('Gaming VPN');
    final rest = tester.getRect(title);
    final gesture = await tester.startGesture(tester.getCenter(title));
    await tester.pump(const Duration(milliseconds: 700));
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 50));
    }
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final boundary =
        shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final (bytes, width) = (await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final w = image.width;
      image.dispose();
      return (data!, w);
    }))!;
    int luma(Offset p) {
      final i = (p.dy.round() * width + p.dx.round()) * 4;
      return (bytes.getUint8(i) + bytes.getUint8(i + 1) + bytes.getUint8(i + 2)) ~/ 3;
    }

    // карточка ушла за пальцем на 40 вниз: начало заголовка там, левее него фон карточки
    final y = rest.center.dy + 40;
    final text = luma(Offset(rest.left + 3, y));
    final before = luma(Offset(rest.left - 8, y));
    expect((text - before).abs(), greaterThan(40));

    await gesture.moveBy(const Offset(0, -40));
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
