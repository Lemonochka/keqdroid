import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/main.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/providers/halloween_provider.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/shared/ui/server_row.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

class _NoHalloween extends HalloweenActiveNotifier {
  @override
  bool build() => false;
}

class _Servers extends ServersNotifier {
  void put(ServersState next) => state = next;
}

// пинг всех серверов сливает ответы в список раз в 200 мс, и каждый слив перестраивает группы
void main() {
  testWidgets('пакет пинга собирает заново только плитки серверов, которым пришёл ответ',
      (tester) async {
    PlatformBootstrap.debugIsDesktopOverride = false;
    addTearDown(() => PlatformBootstrap.debugIsDesktopOverride = null);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    final subs = [
      for (var s = 0; s < 2; s++)
        Subscription(
          id: 'sub$s',
          name: 'Provider $s',
          url: 'https://example.com/$s',
          autoUpdate: false,
        ),
    ];
    final servers = [
      for (var s = 0; s < 2; s++)
        for (var i = 0; i < 6; i++)
          ServerItem(
            id: 's$s-$i',
            config: 'vless://00000000-0000-4000-8000-000000000000@198.51.100.$i:443'
                '?type=tcp&security=reality&pbk=k&sni=example.com#Server%20$s-$i',
            type: ServerItemType.subscription,
            subscriptionId: 'sub$s',
            subscriptionName: 'Provider $s',
            addedAt: DateTime(2026, 11, 1),
          ),
    ];
    final storage = await tester.runAsync(() => buildStorageService(initialValues: {
          'keqdis_servers_v2': jsonEncode([for (final s in servers) s.toJson()]),
          'keqdis_subscriptions': jsonEncode([for (final s in subs) s.toJson()]),
        }));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage!),
          halloweenActiveProvider.overrideWith(_NoHalloween.new),
          exitIpProvider.overrideWith((ref) async => null),
          updateInfoProvider.overrideWith((ref) async => null),
          vpnEngineProvider.overrideWithValue(
            VpnEngine.withBackend(FakeTunnelBackend()),
          ),
          serversProvider.overrideWith(_Servers.new),
        ],
        child: const KeqdroidApp(home: VpnHomeScreen()),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(ServerRow), findsAtLeastNWidgets(8));

    final container =
        ProviderScope.containerOf(tester.element(find.byType(VpnHomeScreen)));
    final notifier = container.read(serversProvider.notifier) as _Servers;
    final rebuilt = <String>[];
    var headers = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      final widget = element.widget;
      if (widget is ServerRow) rebuilt.add(widget.server.id);
      if (widget.runtimeType.toString() == '_ServerGroupHeader') headers++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    final state = container.read(serversProvider);
    final pinged = {'s0-1': 77, 's1-2': 140};
    notifier.put(state.copyWith(servers: [
      for (final s in state.servers)
        pinged.containsKey(s.id)
            ? s.copyWith(pingMs: pinged[s.id], lastTestedAt: DateTime(2026, 11, 13))
            : s,
    ]));
    await tester.pump(const Duration(milliseconds: 16));
    debugOnRebuildDirtyWidget = null;

    expect(rebuilt.toSet(), pinged.keys.toSet());
    expect(headers, 0);
    final rows = tester.widgetList<ServerRow>(find.byType(ServerRow));
    for (final MapEntry(key: id, value: ms) in pinged.entries) {
      expect(rows.singleWhere((r) => r.server.id == id).pingMs, ms);
    }

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });
}
