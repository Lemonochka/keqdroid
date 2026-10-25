import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/providers/halloween_provider.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/servers_tab.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/shared/ui/smooth_fade.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

/// Края списка серверов: карточки уходят в прозрачность, сверху только при
/// прокрутке, снизу всегда.

class _FakeServers extends ServersNotifier {
  @override
  ServersState build() => ServersState(
    servers: [
      for (var i = 0; i < 30; i++)
        ServerItem(
          id: 's$i',
          config:
              'vless://00000000-0000-0000-0000-000000000000@s$i.example'
              '.com:443#Server$i',
          type: ServerItemType.manual,
          pingMs: 40 + i,
          lastTestedAt: DateTime(2026),
        ),
    ],
    activeServerId: 's0',
  );
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

class _NoHalloween extends HalloweenActiveNotifier {
  @override
  bool build() => false;
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(412, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final storage = await tester.runAsync(buildStorageService);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage!),
        serversProvider.overrideWith(_FakeServers.new),
        settingsNotifierProvider.overrideWith(_FakeSettings.new),
        vpnStateProvider.overrideWith(_FakeVpn.new),
        halloweenActiveProvider.overrideWith(_NoHalloween.new),
        exitIpProvider.overrideWith((ref) async => null),
        vpnEngineProvider.overrideWithValue(
          VpnEngine.withBackend(FakeTunnelBackend()),
        ),
      ],
      child: RepaintBoundary(
        key: _shotKey,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: ServersTab()),
        ),
      ),
    ),
  );
  // волна в шапке анимируется вечно, pumpAndSettle повис бы
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder get _listScrollable => find
    .descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<ui.Image> _shot(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_shotKey),
  );
  return (await tester.runAsync(() => boundary.toImage()))!;
}

final _shotKey = GlobalKey();

// средняя яркость строки пикселей поперёк списка
Future<double> _row(WidgetTester tester, ui.Image image, double y) async {
  final data = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  var sum = 0.0;
  var n = 0;
  final row = y.round();
  for (var x = 24; x < image.width - 24; x++) {
    final i = (row * image.width + x) * 4;
    sum += (data.getUint8(i) + data.getUint8(i + 1) + data.getUint8(i + 2)) / 3;
    n++;
  }
  return sum / n;
}

void main() {
  testWidgets(
    'верх тает только при прокрутке, низ всегда, позиция не сбрасывается',
    (tester) async {
      await tester.runAsync(SmoothFade.load);
      await _pump(tester);
      final list = tester.getRect(_listScrollable);
      final surface = Theme.of(
        tester.element(_listScrollable),
      ).colorScheme.surface;
      final bg = (surface.r + surface.g + surface.b) / 3 * 255;

      var image = await _shot(tester);
      // в отступе над первой карточкой в покое пусто, туда свисает только хвост воды шапки
      final restTop = await _row(tester, image, list.top + 1);
      // без затухания снизу тут были бы строки серверов
      expect(await _row(tester, image, list.bottom - 4), closeTo(bg, 2));
      expect(
        (await _row(tester, image, list.bottom - 80) - bg).abs(),
        greaterThan(4),
      );

      await tester.drag(_listScrollable, const Offset(0, -240));
      await _settle(tester);
      final position = tester.state<ScrollableState>(_listScrollable).position;
      expect(position.pixels, greaterThan(100));

      image = await _shot(tester);
      expect(await _row(tester, image, list.top + 1), closeTo(restTop, 2));
      expect(
        (await _row(tester, image, list.top + 70) - restTop).abs(),
        greaterThan(4),
      );
    },
  );
}
