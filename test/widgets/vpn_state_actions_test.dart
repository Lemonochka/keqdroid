import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/shared/ui/bottom_nav.dart';

void main() {
  testWidgets('bottom nav shows connected badge for servers tab', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          bottomNavigationBar: const AppBottomNav(
            index: 0,
            showConnectedBadge: true,
            onTap: _noop,
          ),
        ),
      ),
    );

    final serversLabel = find.text('Servers');
    expect(serversLabel, findsOneWidget);
    expect(find.byType(Stack), findsWidgets);
  });
}

void _noop(int _) {}

