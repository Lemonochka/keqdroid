import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/settings_tab.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:keqdroid/shared/ui/expressive_group.dart';

import '../helpers/test_storage.dart';

// Блок режима подключения в О приложении (только Android). Строка пароля
// появляется лишь в режиме прокси, и тогда же она последняя в группе: раньше
// в режиме VPN она оставалась пустой последней строкой и срезала углы у Прокси.
const _proxy = 'Proxy';
const _authTitle = 'Proxy password';
const _authOff = 'Any app on the device can use the proxy';

Future<void> _pump(WidgetTester tester, AppSettings settings) async {
  final StorageService storage = (await tester.runAsync(
    () => buildStorageService(
      initialValues: {'keqdis_settings': settings.toJsonString()},
    ),
  ))!;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [storageProvider.overrideWithValue(storage)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(body: ListView(children: [tunnelModeGroupForTest()])),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ExpressiveGroupSegment _segmentOf(WidgetTester tester, String text) =>
    tester.widget<ExpressiveGroupSegment>(
      find.ancestor(
        of: find.text(text),
        matching: find.byType(ExpressiveGroupSegment),
      ),
    );

void main() {
  testWidgets('в режиме VPN группа из двух строк и Прокси закрывает её', (
    tester,
  ) async {
    await _pump(tester, const AppSettings());

    expect(find.text(_authTitle), findsNothing);
    final proxy = _segmentOf(tester, _proxy);
    expect(proxy.count, 2);
    expect(proxy.index, 1);
  });

  testWidgets('режим прокси добавляет строку пароля последней', (
    tester,
  ) async {
    await _pump(
      tester,
      const AppSettings(
        connectionMode: 'proxy',
        connectionModeChosen: true,
        proxyModeUser: 'keq',
        proxyModePass: 'secret',
      ),
    );

    final auth = _segmentOf(tester, _authTitle);
    expect(auth.count, 3);
    expect(auth.index, 2);
    expect(find.text('keq'), findsOneWidget);
    expect(find.text('secret'), findsOneWidget);
    expect(find.text(_authOff), findsNothing);
  });

  testWidgets('без пароля подпись говорит, что прокси открыт всем', (
    tester,
  ) async {
    await _pump(
      tester,
      const AppSettings(
        connectionMode: 'proxy',
        connectionModeChosen: true,
        proxyModeAuth: false,
        proxyModeUser: 'keq',
        proxyModePass: 'secret',
      ),
    );

    expect(find.text(_authOff), findsOneWidget);
    expect(find.text('secret'), findsNothing);
  });

  testWidgets('нажатие на Прокси выбирает режим и показывает пароль', (
    tester,
  ) async {
    await _pump(tester, const AppSettings());

    await tester.tap(find.text(_proxy));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    final saved = container.read(settingsNotifierProvider).value!;
    expect(saved.connectionModeChosen, isTrue);
    expect(saved.connectionMode, 'proxy');
    expect(_segmentOf(tester, _authTitle).index, 2);
  });
}
