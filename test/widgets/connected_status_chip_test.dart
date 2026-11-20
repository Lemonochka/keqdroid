import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/services/exit_ip_service.dart';
import 'package:keqdroid/shared/ui/connected_status_chip.dart';
import 'package:keqdroid/shared/ui/server_avatar.dart';

// Чип Подключено к …: флаг выхода той же формы, что флаги серверов, а
// адрес показывается только по нажатию на флаг и ненадолго, вместо подписи.
void main() {
  const label = 'Подключено к Node One';
  const ip = '45.131.212.234';
  const exit = ExitIp(ip: ip, countryCode: 'NL');

  late int jumps;
  late List<String> clipboard;

  setUp(() {
    jumps = 0;
    clipboard = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });

  Future<void> pump(WidgetTester tester, ExitIp? exit) => tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildAppTheme(
        ColorScheme.fromSeed(seedColor: const Color(0xFF4A6DB0)),
      ),
      home: Scaffold(
        body: Center(
          child: ConnectedStatusChip(
            label: label,
            exit: exit,
            onJumpToActive: () => jumps++,
            textStyle: const TextStyle(fontSize: 14),
            verticalPadding: 8,
          ),
        ),
      ),
    ),
  );

  testWidgets('без выхода — прежний чип: подпись и переход к серверу', (
    tester,
  ) async {
    await pump(tester, null);
    expect(find.text(label), findsOneWidget);
    expect(find.byType(ServerAvatar), findsNothing);

    await tester.tap(find.text(label));
    expect(jumps, 1);
  });

  testWidgets('флаг на месте, адреса не видно, пока не нажали', (tester) async {
    await pump(tester, exit);
    await tester.pumpAndSettle();
    expect(find.byType(ServerAvatar), findsOneWidget);
    expect(find.text(label), findsOneWidget);
    expect(find.text(ip), findsNothing);
  });

  testWidgets(
    'нажатие на флаг подменяет подпись адресом, потом она возвращается',
    (tester) async {
      await pump(tester, exit);
      await tester.tap(find.byType(ServerAvatar));
      await tester.pumpAndSettle();
      expect(find.text(ip), findsOneWidget);
      expect(find.text(label), findsNothing);

      await tester.pump(ConnectedStatusChip.revealFor);
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
      expect(find.text(ip), findsNothing);
    },
  );

  testWidgets(
    'нажатие на показанный адрес копирует его, а не уводит к серверу',
    (tester) async {
      await pump(tester, exit);
      await tester.tap(find.byType(ServerAvatar));
      await tester.pumpAndSettle();

      await tester.tap(find.text(ip));
      await tester.pumpAndSettle();

      expect(clipboard, [ip]);
      expect(jumps, 0);
      expect(find.text('IP скопирован'), findsOneWidget);
      expect(find.text(label), findsOneWidget);
    },
  );

  testWidgets('сменился выход — показанный адрес прячется', (tester) async {
    await pump(tester, exit);
    await tester.tap(find.byType(ServerAvatar));
    await tester.pumpAndSettle();
    expect(find.text(ip), findsOneWidget);

    await pump(tester, const ExitIp(ip: '5.6.7.8', countryCode: 'DE'));
    await tester.pumpAndSettle();
    expect(find.text(label), findsOneWidget);
    expect(find.text('5.6.7.8'), findsNothing);
  });
}
