import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/platform/vpn_native_bridge.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:keqdroid/services/update_download_notice.dart';
import 'package:keqdroid/services/update_service.dart';
import 'package:keqdroid/shared/ui/update_dialog.dart';
import 'package:keqdroid/tunnel/tunnel_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StuckStorage extends StorageService {
  _StuckStorage(super.prefs);

  @override
  Future<AppSettings> getSettings() => Completer<AppSettings>().future;
}

class _FakeVpn extends VpnStateNotifier {
  @override
  Future<VpnState> build() async =>
      const VpnState(status: VpnStatus.disconnected);
}

void main() {
  testWidgets('на Android «Обновить» сразу ставит уведомление с загрузкой',
      (tester) async {
    UpdateDownloadNotice.debugSupported = true;
    addTearDown(() => UpdateDownloadNotice.debugSupported = null);
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      VpnNativeBridge.channel,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(VpnNativeBridge.channel, null));
    SharedPreferences.setMockInitialValues({});
    final storage = _StuckStorage(await SharedPreferences.getInstance());
    final info = UpdateInfo(
      currentVersion: '0.37.1',
      latestVersion: '0.38.0',
      downloadUrl: 'https://example.invalid/keqdroid.apk',
      apkSize: 8 * 1024 * 1024,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage),
          vpnStateProvider.overrideWith(_FakeVpn.new),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('ru'),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showUpdateDialog(context, info),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Обновить'));
    await tester.pump();

    expect([for (final c in calls) c.method], ['startUpdateDownload']);
    expect(calls.single.arguments, {
      'channel': 'Загрузка обновления',
      'title': 'Скачивается обновление 0.38.0',
    });
  });
}
