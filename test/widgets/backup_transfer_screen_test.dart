import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/backup_transfer_flow.dart';
import 'package:keqdroid/screens/backup_transfer_screen.dart';
import 'package:keqdroid/screens/settings_tab.dart';
import 'package:keqdroid/services/backup_transfer.dart';
import 'package:keqdroid/services/settings_backup_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

final _en = lookupAppLocalizations(const Locale('en'));

const _sub = Subscription(
  id: 's1',
  name: 'Ranteis VPN',
  url: 'https://sub.example/secret',
);

BackupTransferLink _shownLink(WidgetTester tester) {
  final qr = tester.widget<QrImageView>(find.byType(QrImageView));
  final link = BackupTransferLink.parse((qr.key! as ValueKey<String>).value)!;
  return BackupTransferLink(
    host: '127.0.0.1',
    port: link.port,
    direction: link.direction,
    key: link.key,
  );
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(1080, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final storage = (await tester.runAsync(buildStorageService))!;
  await tester.runAsync(() => storage.saveSubscriptions([_sub]));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
        vpnEngineProvider.overrideWithValue(
          VpnEngine.withBackend(FakeTunnelBackend()),
        ),
        updateInfoProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: home,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

// сервер экрана заведён в поддельном времени теста: клиент там же, а сокету даём настоящие паузы
Future<T> _exchange<T>(WidgetTester tester, Future<T> Function() run) async {
  T? value;
  Object? error;
  var done = false;
  unawaited(
    run()
        .then((v) => value = v, onError: (Object e) => error = e)
        .whenComplete(() => done = true),
  );
  for (var i = 0; i < 200 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  if (error != null) throw error!;
  expect(done, isTrue, reason: 'the exchange did not finish');
  return value as T;
}

class _Opener extends StatefulWidget {
  const _Opener(this.direction);

  final BackupTransferDirection direction;

  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  KeqdroidBackup? result;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: TextButton(
      onPressed: () async {
        final got = await BackupTransferScreen.open(context, widget.direction);
        setState(() => result = got);
      },
      child: const Text('open'),
    ),
  );
}

void main() {
  // flutter_test подменяет HttpClient заглушкой с ответом 400, а здесь обмен по настоящему сокету
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
  });
  setUp(() => BackupTransferScreen.lanAddress = () async => '192.168.1.47');
  tearDown(() {
    PlatformBootstrap.debugIsDesktopOverride = null;
    PlatformBootstrap.debugIsTelevisionOverride = null;
  });

  group('backup screen', () {
    Future<void> openBackup(WidgetTester tester) async {
      await _pump(tester, const SettingsTab());
      await tester.tap(find.text(_en.settingsBackupRestore));
      await tester.pumpAndSettle();
    }

    Future<void> openTransferSheet(WidgetTester tester) async {
      await openBackup(tester);
      // на экране одна строка без подписи, всё остальное в шторке
      expect(find.text(_en.backupTransferOpen), findsOneWidget);
      expect(find.text(_en.backupTransferReceive), findsNothing);
      await tester.tap(find.text(_en.backupTransferOpen));
      await tester.pumpAndSettle();
      expect(find.text(_en.backupTransferTitle), findsOneWidget);
    }

    testWidgets('a phone can receive, give and scan', (tester) async {
      PlatformBootstrap.debugIsDesktopOverride = false;
      PlatformBootstrap.debugIsTelevisionOverride = false;
      await openTransferSheet(tester);
      expect(find.text(_en.backupTransferReceive), findsOneWidget);
      expect(find.text(_en.backupTransferGive), findsOneWidget);
      expect(find.text(_en.backupTransferScan), findsOneWidget);
    });

    testWidgets('a computer only shows the code, it has no camera', (
      tester,
    ) async {
      PlatformBootstrap.debugIsDesktopOverride = true;
      await openTransferSheet(tester);
      expect(find.text(_en.backupTransferReceive), findsOneWidget);
      expect(find.text(_en.backupTransferGive), findsOneWidget);
      expect(find.text(_en.backupTransferScan), findsNothing);
    });

    testWidgets('a tile in the sheet closes it and opens the code', (
      tester,
    ) async {
      PlatformBootstrap.debugIsDesktopOverride = true;
      await openTransferSheet(tester);
      await tester.tap(find.text(_en.backupTransferReceive));
      await _settle(tester);
      expect(find.text(_en.backupTransferTitle), findsNothing);
      expect(find.byType(BackupTransferScreen), findsOneWidget);
      expect(find.text(_en.backupTransferWaitingReceive), findsOneWidget);
    });
  });

  testWidgets('a backup sent to the receive screen comes back for restoring', (
    tester,
  ) async {
    await _pump(tester, const _Opener(BackupTransferDirection.receive));
    await tester.tap(find.text('open'));
    await _settle(tester);
    expect(find.text(_en.backupTransferWaitingReceive), findsOneWidget);

    final link = _shownLink(tester);
    final payload = KeqdroidBackup(
      version: 1,
      exportedAt: DateTime.utc(2026, 11, 18),
      data: {
        'subscriptions': [_sub.toJson()],
      },
    );
    await _exchange(
      tester,
      () => sendBackup(link, utf8.encode(payload.toJsonString())),
    );
    await _settle(tester);

    final opener = tester.state<_OpenerState>(find.byType(_Opener));
    expect(opener.result?.data['subscriptions'], payload.data['subscriptions']);
    expect(find.byType(BackupTransferScreen), findsNothing);
  });

  testWidgets('the give screen hands over this device and says it was taken', (
    tester,
  ) async {
    await _pump(tester, const _Opener(BackupTransferDirection.give));
    await tester.tap(find.text('open'));
    await _settle(tester);
    expect(find.text(_en.backupTransferWaitingGive), findsOneWidget);

    final link = _shownLink(tester);
    final plain = await _exchange(tester, () => fetchBackup(link));
    await _settle(tester);

    final backup = KeqdroidBackup.parse(plain);
    final subs = backup.data['subscriptions'] as List;
    expect(subs.single['url'], _sub.url);
    expect(find.text(_en.backupTransferGiven), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing, reason: 'the code is spent');
  });

  testWidgets('a scanned receive code asks before this device sends', (
    tester,
  ) async {
    final received = Completer<Uint8List>();
    final server = (await tester.runAsync(
      () => BackupTransferServer.start(
        lanAddress: '192.168.1.47',
        direction: BackupTransferDirection.receive,
        onReceived: (plain) async => received.complete(plain),
        bindAddress: InternetAddress.loopbackIPv4,
      ),
    ))!;
    addTearDown(() => tester.runAsync(server.close));
    final link = BackupTransferLink(
      host: '127.0.0.1',
      port: server.link.port,
      direction: BackupTransferDirection.receive,
      key: server.link.key,
    );

    await _pump(
      tester,
      Consumer(
        builder: (context, ref, _) => Scaffold(
          body: TextButton(
            onPressed: () => runBackupTransferLink(context, ref, link),
            child: const Text('scan'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('scan'));
    await tester.pumpAndSettle();
    expect(
      find.text(_en.backupTransferSendMessage('127.0.0.1')),
      findsOneWidget,
    );
    expect(received.isCompleted, isFalse, reason: 'nothing leaves before Send');

    await tester.tap(find.text(_en.backupTransferSendAction));
    await _settle(tester);
    final plain = (await tester.runAsync(() => received.future))!;
    expect(utf8.decode(plain), contains(_sub.url));
    expect(find.text(_en.backupTransferSent), findsOneWidget);
  });
}
