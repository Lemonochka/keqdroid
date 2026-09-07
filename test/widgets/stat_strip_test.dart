import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/shared/ui/stat_strip.dart';

StatMetric _rate(String value) => StatMetric(
      icon: Icons.arrow_downward_rounded,
      label: 'Скорость приёма',
      value: value,
      template: '999.9 MB/s',
    );

final _four = <StatMetric>[
  _rate('37.7 KB/s'),
  StatMetric(
    icon: Icons.arrow_upward_rounded,
    label: 'Скорость отдачи',
    value: '121.2 KB/s',
    template: '999.9 MB/s',
  ),
  StatMetric(
    icon: Icons.data_usage_rounded,
    label: 'Вх',
    value: '2.4 MB',
    template: '999.99 GB',
  ),
  StatMetric(
    icon: Icons.schedule_rounded,
    label: 'Время',
    value: '44s',
    template: '59m 59s',
  ),
];

/// Ячейки «в туннель / мимо туннеля»: приём и отдача, каждая двумя строками.
List<StatMetric> _splitOf(String vpn, String direct) => [
      StatMetric.split(
        icon: Icons.arrow_downward_rounded,
        label: 'Скорость приёма',
        lines: [
          StatValue(tag: 'VPN', value: vpn, template: '999.9 MB/s'),
          StatValue(tag: 'мимо', value: direct, template: '999.9 MB/s'),
        ],
      ),
      const StatMetric.split(
        icon: Icons.arrow_upward_rounded,
        label: 'Скорость отдачи',
        lines: [
          StatValue(tag: 'VPN', value: '22.0 KB/s', template: '999.9 MB/s'),
          StatValue(tag: 'мимо', value: '3.0 KB/s', template: '999.9 MB/s'),
        ],
      ),
    ];

final _split = _splitOf('1.1 MB/s', '0.1 MB/s');

Future<Size> _pumpStrip(
  WidgetTester tester,
  List<StatMetric> metrics, {
  double width = 1000,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            // Через `Align`, а не `Row`: `Row` отдаёт ребёнку НЕограниченную
            // ширину по главной оси, и полоса не узнала бы про тесноту окна.
            child: Align(child: StatStrip(metrics: metrics)),
          ),
        ),
      ),
    ),
  );
  return tester.getSize(find.byType(StatStrip));
}

void main() {
  testWidgets('значения не меняют ширину полосы', (tester) async {
    // Показатели обновляются раз в секунду: полоса, дышащая на каждом
    // обновлении, тянула бы за собой весь экран под кнопкой.
    final a = await _pumpStrip(tester, [_rate('0 B/s')]);
    final b = await _pumpStrip(tester, [_rate('137.7 KB/s')]);
    final c = await _pumpStrip(tester, [_rate('9.9 MB/s')]);

    expect(b.width, a.width);
    expect(c.width, a.width);
  });

  testWidgets('на широком экране всё в одну строку', (tester) async {
    final size = await _pumpStrip(tester, _four);

    // Одна строка — значит высота порядка одной ячейки, а не двух.
    expect(size.height, lessThan(60));
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('в узком окне полоса делится пополам, а не 3 + 1', (
    tester,
  ) async {
    final wide = await _pumpStrip(tester, _four);
    final narrow = await _pumpStrip(tester, _four, width: wide.width - 40);

    // Ровно два ряда: между ними один горизонтальный разделитель.
    expect(find.byType(Divider), findsOneWidget);
    expect(narrow.height, greaterThan(wide.height));
    // И половина прежней ширины — колонки не разъезжаются.
    expect(narrow.width, lessThan(wide.width));
    expect(tester.takeException(), isNull);
  });

  testWidgets('полоса не вылезает за края узкого окна', (tester) async {
    tester.view.physicalSize = const Size(288, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: StatStrip(metrics: _four)),
        ),
      ),
    );

    final box = tester.renderObject<RenderBox>(find.byType(StatStrip));
    final left = box.localToGlobal(Offset.zero).dx;
    expect(left, greaterThanOrEqualTo(0));
    expect(left + box.size.width, lessThanOrEqualTo(288));
    expect(tester.takeException(), isNull);
  });

  testWidgets('у каждой ячейки есть подпись для доступности', (tester) async {
    // На экране показатель несёт значок; слово остаётся только в семантике.
    final handle = tester.ensureSemantics();
    await _pumpStrip(tester, _four);

    expect(find.bySemanticsLabel('Скорость приёма'), findsOneWidget);
    expect(find.bySemanticsLabel('Время'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('разбивка живёт двумя строками в одной ячейке', (tester) async {
    // Не вторым рядом ячеек: ряд под кнопкой стоит целой высоты ячейки, а
    // здесь хватает одной высоты текста.
    final size = await _pumpStrip(tester, _split);

    expect(find.text('VPN'), findsNWidgets(2));
    expect(find.text('мимо'), findsNWidgets(2));
    expect(find.textContaining('1.1 MB/s'), findsOneWidget);
    expect(find.textContaining('0.1 MB/s'), findsOneWidget);
    // Один ряд: горизонтального разделителя между рядами нет.
    expect(find.byType(Divider), findsNothing);

    final plain = await _pumpStrip(tester, [_rate('1.1 MB/s'), _rate('0.1 MB/s')]);
    expect(size.height, greaterThan(plain.height));
  });

  testWidgets('значения разбивки не меняют ширину полосы', (tester) async {
    final a = await _pumpStrip(tester, _split);
    final b = await _pumpStrip(tester, _splitOf('0 B/s', '0 B/s'));
    expect(b.width, a.width);
  });

  testWidgets('обе строки ячейки уходят в семантику', (tester) async {
    // На экране их различает только подпись: незрячему пользователю без неё
    // приезжают два числа подряд без единого намёка, где какое.
    final handle = tester.ensureSemantics();
    await _pumpStrip(tester, _split);

    final node = tester.getSemantics(
      find.bySemanticsLabel('Скорость приёма').first,
    );
    expect(node.value, contains('VPN'));
    expect(node.value, contains('мимо'));
    expect(node.value, contains('1.1 MB/s'));
    expect(node.value, contains('0.1 MB/s'));
    handle.dispose();
  });
}
