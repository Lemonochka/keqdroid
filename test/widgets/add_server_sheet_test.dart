import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final added = <String>[];

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

  @override
  Future<void> addManual(String rawConfig) async => added.add(rawConfig);
}

class _NoHalloween extends HalloweenActiveNotifier {
  @override
  bool build() => false;
}

final _l10n = AppLocalizationsRu();

// в шторке и на экране вода крутится без конца, pumpAndSettle не дождался бы
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<_Servers> _openAddSheet(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  final servers = _Servers();
  final storage = await tester.runAsync(buildStorageService);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      storageProvider.overrideWithValue(storage!),
      serversProvider.overrideWith(() => servers),
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
  await _frames(tester);
  await tester.tap(find.byType(FloatingActionButton));
  await _frames(tester);
  return servers;
}

void _clipboard(WidgetTester tester, String? text) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => call.method == 'Clipboard.getData'
        ? (text == null ? null : <String, dynamic>{'text': text})
        : null,
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
}

void main() {
  setUp(() => PlatformBootstrap.debugIsDesktopOverride = false);
  tearDown(() => PlatformBootstrap.debugIsDesktopOverride = null);

  // импорт из файла раскладывает что угодно (ссылки, Xray, Clash, sing-box), а подпись обещала один AmneziaWG
  testWidgets('импорт из файла не обещает только AmneziaWG', (tester) async {
    await _openAddSheet(tester);

    expect(find.text(_l10n.serversImportFile), findsOneWidget);
    expect(find.text(_l10n.serversImportFileHint), findsOneWidget);
    expect(find.textContaining('AmneziaWG'), findsNothing);
  });

  group('вставить ссылку(и)', () {
    testWidgets('берёт ссылки прямо из буфера, без окна ввода', (tester) async {
      const vless = 'vless://uuid@de.example.com:443?security=tls&type=tcp#DE';
      _clipboard(tester, '  $vless\n');
      final servers = await _openAddSheet(tester);

      await tester.tap(find.text(_l10n.serversPasteLinks));
      await _frames(tester);

      expect(servers.added, [vless]);
      expect(find.byType(TextField), findsNothing);
      expect(find.text(_l10n.serversAddServer), findsNothing, reason: 'шторка закрыта');
      expect(find.text(_l10n.serversImportedSummary(1, 1)), findsOneWidget);
    });

    // на телевизоре буфер пуст, и набрать ссылку можно только в поле
    for (final (name, clip) in [('пустой', ''), ('без текста', null)]) {
      testWidgets('$name буфер открывает поле ввода, как раньше', (tester) async {
        _clipboard(tester, clip);
        final servers = await _openAddSheet(tester);

        await tester.tap(find.text(_l10n.serversPasteLinks));
        await _frames(tester);

        expect(servers.added, isEmpty);
        expect(find.byType(TextField), findsOneWidget);
        expect(find.text(_l10n.serversPasteHint), findsOneWidget);
      });
    }
  });
}
