import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/l10n/app_localizations_ru.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/providers/halloween_provider.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/servers_tab.dart';
import 'package:keqdroid/services/vpn_engine.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

class _Servers extends ServersNotifier {
  @override
  ServersState build() => ServersState(
        servers: [
          ServerItem(
            id: 'n1',
            config: 'vless://00000000-0000-0000-0000-000000000000@n1.example.com:443'
                '?security=reality&type=tcp#Node',
            type: ServerItemType.manual,
          ),
        ],
      );
}

class _NoHalloween extends HalloweenActiveNotifier {
  @override
  bool build() => false;
}

void main() {
  setUp(() => PlatformBootstrap.debugIsDesktopOverride = false);
  tearDown(() => PlatformBootstrap.debugIsDesktopOverride = null);

  // импорт из файла раскладывает что угодно (ссылки, Xray, Clash, sing-box), а подпись обещала один AmneziaWG
  testWidgets('импорт из файла не обещает только AmneziaWG', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final storage = await tester.runAsync(buildStorageService);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage!),
        serversProvider.overrideWith(_Servers.new),
        halloweenActiveProvider.overrideWith(_NoHalloween.new),
        vpnEngineProvider.overrideWithValue(
          VpnEngine.withBackend(FakeTunnelBackend()),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: ServersTab()),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(const Duration(seconds: 1));

    final l10n = AppLocalizationsRu();
    expect(find.text(l10n.serversImportFile), findsOneWidget);
    expect(find.text(l10n.serversImportFileHint), findsOneWidget);
    expect(find.textContaining('AmneziaWG'), findsNothing);
  });
}
