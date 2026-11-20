import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:keqdroid/services/update_service.dart';
import 'package:keqdroid/shared/ui/update_dialog.dart';
import 'package:keqdroid/tunnel/tunnel_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Настройки не приходят никогда: загрузка стоит на старте и в сеть не идёт.
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
  testWidgets('кнопки диалога не двигаются, когда пошла загрузка', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final storage = _StuckStorage(await SharedPreferences.getInstance());
    final info = UpdateInfo(
      currentVersion: '0.26.0',
      latestVersion: '0.27.0',
      downloadUrl: 'https://example.invalid/keqdroid.apk',
      apkSize: 40 * 1024 * 1024,
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

    final buttons = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    expect(buttons, findsNWidgets(3));
    // диалог по центру и вырастает на полосу прогресса, поэтому сверяем кнопки
    // относительно первой: ширина, отступ слева и раскладка ряд/столбик
    List<(double, double, double)> layout() {
      final rects = [for (var i = 0; i < 3; i++) tester.getRect(buttons.at(i))];
      return [
        for (final r in rects) (r.left, r.width, r.top - rects.first.top),
      ];
    }

    final before = layout();
    await tester.tap(find.text('Обновить'));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Обновить'), findsOneWidget);
    expect(layout(), before);
  });
}
