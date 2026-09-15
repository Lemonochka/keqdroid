import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/shared/ui/nav_rail.dart';

/// Рейка вместо нижней панели на телефоне боком.
///
/// Спека запрещает резать подпись пункта навигации многоточием, а в рейке на
/// подпись всего 88dp — длинные «Subscriptions» и «Abonnements» туда влезают
/// только переносом. Проверяем на всех языках приложения.
Future<void> _pumpRail(
  WidgetTester tester, {
  required Locale locale,
  int index = 0,
  bool badge = false,
  void Function(int)? onTap,
}) async {
  tester.view.physicalSize = const Size(915, 412);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Row(
          children: [
            AppNavRail(
              index: index,
              showConnectedBadge: badge,
              onTap: onTap ?? (_) {},
            ),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ширина рейки — 96dp по токенам свёрнутой рейки M3E', (
    tester,
  ) async {
    await _pumpRail(tester, locale: const Locale('en'));
    expect(tester.getSize(find.byType(AppNavRail)).width, AppNavRail.width);
  });

  testWidgets('подписи пунктов не режутся ни на одном языке', (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      await _pumpRail(tester, locale: locale);
      // Через Text, а не RichText: значок Icon рисуется тем же RichText.
      final labels = find.descendant(
        of: find.byType(AppNavRail),
        matching: find.byType(Text),
      );
      expect(labels, findsNWidgets(3), reason: '$locale');
      final paragraphs = [
        for (var i = 0; i < 3; i++)
          tester.renderObject<RenderParagraph>(
            find.descendant(
              of: labels.at(i),
              matching: find.byType(RichText),
            ),
          ),
      ];
      for (final p in paragraphs) {
        expect(
          p.didExceedMaxLines,
          isFalse,
          reason: '$locale: «${p.text.toPlainText()}»',
        );
      }
      expect(tester.takeException(), isNull, reason: '$locale');
    }
  });

  testWidgets('нажатие по полю рядом с индикатором тоже переключает', (
    tester,
  ) async {
    var selected = 0;
    await _pumpRail(
      tester,
      locale: const Locale('en'),
      onTap: (i) => selected = i,
    );

    // Цель нажатия по спеке — вся ширина рейки, а не только индикатор 56dp.
    final settings = tester.getCenter(find.byIcon(Icons.settings_rounded));
    await tester.tapAt(Offset(4, settings.dy));
    expect(selected, 2);

    await tester.tap(find.byIcon(Icons.language_rounded));
    expect(selected, 1);
  });

  testWidgets('точка «подключено» стоит на пункте серверов', (tester) async {
    await _pumpRail(tester, locale: const Locale('en'), badge: true);
    final dots = find.descendant(
      of: find.byType(AppNavRail),
      matching: find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints?.maxWidth == 8 &&
            w.constraints?.maxHeight == 8,
      ),
    );
    expect(dots, findsOneWidget);
  });
}
