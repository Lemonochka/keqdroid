import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/providers/halloween_provider.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/servers/server_config_editor.dart';
import 'package:keqdroid/screens/servers_tab.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/shared/ui/smooth_scroll.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

// колесо мыши на ПК: без SmoothScroll список прыгает шагами, как жаловались на меню сервера и редактор

final _server = ServerItem(
  id: 'n1',
  config:
      'vless://00000000-0000-0000-0000-000000000000@n1.example.com:443'
      '?security=reality&type=tcp#Node%201',
  type: ServerItemType.manual,
);

class _Servers extends ServersNotifier {
  @override
  ServersState build() => ServersState(servers: [_server]);
}

class _Settings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

class _NoHalloween extends HalloweenActiveNotifier {
  @override
  bool build() => false;
}

ScrollController? _outerController(WidgetTester tester, Finder scope) => tester
    .widget<SingleChildScrollView>(
      find
          .descendant(of: scope, matching: find.byType(SingleChildScrollView))
          .first,
    )
    .controller;

void main() {
  testWidgets(
    'редактор конфига сервера листается колесом плавно',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serversProvider.overrideWith(_Servers.new),
            settingsNotifierProvider.overrideWith(_Settings.new),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ServerConfigEditorScreen(serverId: _server.id),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        _outerController(tester, find.byType(ServerConfigEditorScreen)),
        isA<SmoothScrollController>(),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'меню по зажатию сервера листается колесом плавно',
    (tester) async {
      tester.view.physicalSize = const Size(700, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final storage = (await tester.runAsync(buildStorageService))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageProvider.overrideWithValue(storage),
            serversProvider.overrideWith(_Servers.new),
            settingsNotifierProvider.overrideWith(_Settings.new),
            halloweenActiveProvider.overrideWith(_NoHalloween.new),
            vpnEngineProvider.overrideWithValue(
              VpnEngine.withBackend(FakeTunnelBackend()),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: const Scaffold(body: ServersTab()),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      await tester.longPress(find.text('Node 1').first);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(
        _outerController(tester, find.byType(BottomSheet)),
        isA<SmoothScrollController>(),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
