import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_internals.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/settings_tab.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/shared/ui/expressive_group.dart';
import 'package:keqdroid/utils/external_link.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

const _internals = AppInternals(
  cores: [],
  geoBases: [],
  session: SessionInfo(
    status: VpnStatus.disconnected,
    engine: 'xray',
    socksPort: 10808,
    httpPort: 10809,
  ),
  build: BuildInfo(
    appVersion: '0.39.0',
    buildNumber: '390',
    packageName: 'com.keqdroid.keqdroid',
    operatingSystem: 'android',
    osVersion: 'Android 16',
    abi: 'arm64-v8a',
    dartVersion: '3.11.3',
    releaseMode: true,
  ),
);

void main() {
  testWidgets('наверху О приложении автор и ссылки одной группой', (
    tester,
  ) async {
    final StorageService storage = (await tester.runAsync(
      buildStorageService,
    ))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage),
          vpnEngineProvider.overrideWithValue(
            VpnEngine.withBackend(FakeTunnelBackend()),
          ),
          appInternalsProviderForTest.overrideWith((ref) async => _internals),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: appInternalsScreenForTest(),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    final author = tester.widget<ExpressiveGroupSegment>(
      find.ancestor(
        of: find.text('Alice'),
        matching: find.byType(ExpressiveGroupSegment),
      ),
    );
    expect(author.index, 0);
    expect(author.count, 4);
    expect(find.text('Lemonochka'), findsOneWidget);
    expect(find.text('Telegram chat'), findsOneWidget);
    expect(find.text('Documentation'), findsOneWidget);
    expect(find.text('GNU AGPL 3.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('аватарка лежит в сборке, из сети её не грузим', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final bytes = await rootBundle.load('assets/author.jpg');
    expect(bytes.lengthInBytes, greaterThan(1000));
  });

  test('все ссылки блока открываются как внешние https', () {
    for (final url in authorLinksForTest) {
      final uri = Uri.parse(url);
      expect(uri.scheme, 'https', reason: url);
      expect(isSafeExternalLink(uri), isTrue, reason: url);
    }
  });
}
