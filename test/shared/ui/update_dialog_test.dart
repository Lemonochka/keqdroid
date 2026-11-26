import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
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

    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pumpAndSettle();
  });

  test('sanitizeReleaseNotes вырезает плитки скачивания и оставляет только текст', () {
    final notes0393 = File('release/notes-0.39.3.md').readAsStringSync();
    final cleaned = sanitizeReleaseNotes(notes0393);

    expect(cleaned, startsWith('## macOS'));
    expect(cleaned, isNot(contains('&nbsp;')));
    expect(cleaned, isNot(contains('Telegram')));
    expect(cleaned, isNot(contains('Installer')));
    expect(cleaned, isNot(contains('AppImage')));
    expect(cleaned, contains('## Settings and diagnostics'));
    expect(cleaned, contains('## Android TV'));

    final notes0390 = File('release/notes-0.39.0.md').readAsStringSync();
    final cleanedOld = sanitizeReleaseNotes(notes0390);
    expect(cleanedOld, startsWith('## Linux'));
    expect(cleanedOld, isNot(contains('shields.io')));
    expect(cleanedOld, isNot(contains('![Android]')));

    final withCodeTag = sanitizeReleaseNotes(
      '<table><tr><td><picture><img src="a.svg"></picture>&nbsp;</td></tr></table>\n'
      '[![Android](https://img.shields.io/badge/Android-APK-green)](https://example.com/a.apk)\n\n'
      '- Parses JSON wrapped in `<pre>` or between `<table>` and `</table>` (&amp;lt;ok&amp;gt;).',
    );
    expect(
      withCodeTag,
      '- Parses JSON wrapped in `<pre>` or between `<table>` and `</table>` (&lt;ok&gt;).',
    );

    final releaseDir = Directory('release');
    if (releaseDir.existsSync()) {
      for (final file in releaseDir.listSync().whereType<File>()) {
        if (!file.path.endsWith('.md')) continue;
        final text = sanitizeReleaseNotes(file.readAsStringSync());
        expect(text, isNotEmpty, reason: file.path);
        expect(text, isNot(contains('&nbsp;')), reason: file.path);
        expect(text, isNot(contains('shields.io')), reason: file.path);
        expect(text, isNot(contains('.github/badges/')), reason: file.path);
      }
    }
  });

  testWidgets('окно обновления показывает только текст без плиток и &nbsp;', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final storage = _StuckStorage(await SharedPreferences.getInstance());
    final info = UpdateInfo(
      currentVersion: '0.39.2',
      latestVersion: '0.39.3',
      downloadUrl: 'https://example.invalid/keqdroid-setup.exe',
      apkSize: 49 * 1024 * 1024,
      releaseNotes: File('release/notes-0.39.3.md').readAsStringSync(),
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

    final rendered = [
      for (final w in tester.widgetList<SelectableText>(
        find.descendant(
          of: find.byType(MarkdownBody),
          matching: find.byType(SelectableText),
        ),
      ))
        w.data ?? w.textSpan?.toPlainText() ?? '',
    ].join('\n');

    expect(rendered, isNotEmpty);
    expect(rendered, startsWith('macOS\n'));
    expect(rendered, contains('Settings and diagnostics'));
    expect(rendered, isNot(contains('&nbsp;')));
    expect(rendered, isNot(contains('Telegram')));
    expect(rendered, isNot(contains('AppImage')));

    await tester.tap(find.text('Позже'));
    await tester.pumpAndSettle();
  });
}
