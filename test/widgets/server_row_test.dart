import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/shared/ui/expressive_group.dart';
import 'package:keqdroid/shared/ui/server_row.dart';

// В две колонки на вертикальном телефоне строка сервера сжимала имя до
// Росс…, а пинг до 42 …. Там ряд теперь встаёт карточкой, и тест сторожит
// обе половины: что порог отличает телефон от широких окон и что карточка при
// любом масштабе шрифта умещается в шаг, который под неё считает список.

// Ширина ячейки в две колонки: поля списка по 16, поля ячейки дают полный зазор
// у края группы и половину у соседа.
double _cell(double screenWidth, double gap) =>
    (screenWidth - 32) / 2 - gap * 1.5;

final _server = ServerItem(
  id: 'nl',
  config:
      'vless://00000000-0000-0000-0000-000000000000@nl.example.com:443'
      '#Нидерланды Amsterdam Hysteria',
  type: ServerItemType.manual,
  pinnedAt: DateTime(2026),
  pingMs: 1234,
  lastTestedAt: DateTime(2026),
);

final _nameFinder = find.byWidgetPredicate(
  (w) =>
      w is Text &&
      (w.data ?? w.textSpan?.toPlainText() ?? '').contains('Amsterdam'),
);

Future<void> _pumpRow(
  WidgetTester tester, {
  required ServerRowLayout layout,
  required double width,
  double scale = 1,
}) async {
  final isCard = layout == ServerRowLayout.card;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(
        ColorScheme.fromSeed(seedColor: const Color(0xFF7B61FF)),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => SizedBox(
              width: width,
              // высота контейнера: шаг минус зазор, как в плитке списка
              height: isCard
                  ? ServerRow.cardHeight(context) - ServerRow.cardGap
                  : ServerRow.height - ExpressiveListSegment.gap,
              child: ServerRow(
                server: _server,
                pingMs: _server.pingMs,
                lastTestedAt: _server.lastTestedAt,
                emphasizeTitle: true,
                opaqueBadge: true,
                layout: layout,
                trailing: isCard ? null : const SizedBox.square(dimension: 32),
                status: isCard ? const SizedBox.square(dimension: 16) : null,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('на вертикальном телефоне строка в две колонки не помещается', () {
    for (final width in [320.0, 360.0, 412.0]) {
      expect(
        ServerRow.fitsInline(
          _cell(width, ExpressiveListSegment.gap),
          TextScaler.noScaling,
        ),
        isFalse,
        reason: 'ширина экрана $width',
      );
    }
  });

  test('телефон боком, планшет и десктоп остаются строками', () {
    for (final width in [800.0, 900.0, 915.0]) {
      expect(
        ServerRow.fitsInline(
          _cell(width, ExpressiveListSegment.gap),
          const TextScaler.linear(1.4),
        ),
        isTrue,
        reason: 'ширина экрана $width',
      );
    }
  });

  // Pixel 6a: 411 dp, на телефоне 100% интерфейса рисуются как 0.85
  double pixel6a(double uiScale) => 411.4 / (uiScale * 0.85);
  int fit(double width, int wanted, [TextScaler s = TextScaler.noScaling]) =>
      ServerRow.fittingColumns(width, s, wanted);

  test('две колонки сворачиваются в одну, когда и карточке тесно', () {
    for (final scale in [0.7, 1.0, 1.15]) {
      expect(fit(pixel6a(scale), 2), 2, reason: 'размер интерфейса $scale');
    }
    for (final scale in [1.2, 1.4]) {
      expect(fit(pixel6a(scale), 2), 1, reason: 'размер интерфейса $scale');
    }
  });

  test('три колонки на телефоне помещаются только в мелком интерфейсе', () {
    expect(fit(pixel6a(0.8), 3), 3);
    expect(fit(pixel6a(1.0), 3), 2);
    expect(fit(pixel6a(1.4), 3), 1);
  });

  test('крупный системный шрифт тоже сворачивает в одну колонку', () {
    expect(fit(484, 2), 2);
    expect(fit(484, 2, const TextScaler.linear(1.5)), 1);
  });

  test('ячейка в две колонки считается так же, как в тесте строки', () {
    for (final width in [320.0, 412.0, 800.0]) {
      expect(
        ServerRow.columnCell(width, 2),
        moreOrLessEquals(_cell(width, ExpressiveListSegment.gap)),
      );
    }
  });

  testWidgets('карточка умещается в свой шаг при любом масштабе шрифта', (
    tester,
  ) async {
    for (final scale in [0.8, 1.0, 1.4, 2.0]) {
      await _pumpRow(
        tester,
        layout: ServerRowLayout.card,
        width: _cell(320, ServerRow.cardGap),
        scale: scale,
      );
      // Переполнение Flex в тестах всплывает исключением.
      expect(tester.takeException(), isNull, reason: 'масштаб $scale');
    }
  });

  testWidgets('в карточке имени достаётся всё место справа от флага', (
    tester,
  ) async {
    final card = _cell(412, ServerRow.cardGap);
    await _pumpRow(tester, layout: ServerRowLayout.card, width: card);
    // Поля 16 по бокам, флаг 40 и 12 до текста. Длинное имя переносится, и
    // первая строка недобирает до края не больше одного знака.
    expect(
      tester.getSize(_nameFinder).width,
      greaterThan(card - 16 * 2 - 40 - 12 - 16 - 1),
    );
    // На узкой ширине пункт показывает меньше: протокол у подписок и так в
    // имени, а бейдж отнимал бы у него место.
    expect(find.text('VLESS'), findsNothing);

    final cell = _cell(412, ExpressiveListSegment.gap);
    await _pumpRow(tester, layout: ServerRowLayout.inline, width: cell);
    // Та же ячейка строкой, ровно то, на что была жалоба.
    expect(tester.getSize(_nameFinder).width, lessThan(cell / 3));
    expect(find.text('VLESS'), findsOneWidget);
  });
}
