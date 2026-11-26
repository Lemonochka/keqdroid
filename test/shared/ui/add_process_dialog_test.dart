import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/shared/ui/add_process_dialog.dart';

void main() {
  testWidgets('showAddProcessDialog returns edited text and disposes cleanly', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showAddProcessDialog(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '/usr/local/bin/custom-app');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(result, '/usr/local/bin/custom-app');
    expect(tester.takeException(), isNull);
  });
}
