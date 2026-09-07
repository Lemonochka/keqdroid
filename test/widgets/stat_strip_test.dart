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

/// Две ячейки-канала: слева всё про туннель, справа всё про обход.
List<StatMetric> _channelsOf(String vpnDown, String directDown) => [
      StatMetric.channel(
        tag: 'VPN',
        label: 'Через VPN',
        lines: [
          StatLine(
            icon: Icons.arrow_downward_rounded,
            label: 'Приём',
            value: vpnDown,
            template: '999.9 MB/s',
          ),
          const StatLine(
            icon: Icons.arrow_upward_rounded,
            label: 'Отдача',
            value: '22.0 KB/s',
            template: '999.9 MB/s',
          ),
          const StatLine(
            icon: Icons.data_usage_rounded,
            label: 'Принято',
            value: '239.5 KB',
            template: '999.99 GB',
          ),
        ],
      ),
      StatMetric.channel(
        tag: 'обход',
        label: 'Мимо VPN',
        lines: [
          StatLine(
            icon: Icons.arrow_downward_rounded,
            label: 'Приём',
            value: directDown,
            template: '999.9 MB/s',
          ),
          const StatLine(
            icon: Icons.arrow_upward_rounded,
            label: 'Отдача',
            value: '3.0 KB/s',
            template: '999.9 MB/s',
          ),
          const StatLine(
            icon: Icons.data_usage_rounded,
            label: 'Принято',
            value: '12.0 KB',
            template: '999.99 GB',
          ),
        ],
      ),
    ];

final _channels = _channelsOf('1.1 MB/s', '0.1 MB/s');

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

  testWidgets('канал занимает одну ячейку, а не колонку из них', (tester) async {
    // Все числа туннеля стоят вместе, все числа обхода — вместе: иначе ответ
    // на «а сюда что-нибудь идёт» приходится собирать из соседних ячеек.
    await _pumpStrip(tester, _channels);

    // Подпись канала одна на ячейку, а не по одной на строку.
    expect(find.text('VPN'), findsOneWidget);
    expect(find.text('обход'), findsOneWidget);
    expect(find.textContaining('1.1 MB/s'), findsOneWidget);
    expect(find.textContaining('0.1 MB/s'), findsOneWidget);
    expect(find.textContaining('239.5 KB'), findsOneWidget);
    expect(find.textContaining('12.0 KB'), findsOneWidget);
    // Один ряд: горизонтального разделителя между рядами нет.
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('значения канала не меняют ширину полосы', (tester) async {
    final a = await _pumpStrip(tester, _channels);
    final b = await _pumpStrip(tester, _channelsOf('0 B/s', '0 B/s'));
    expect(b.width, a.width);
  });

  testWidgets('все строки ячейки уходят в семантику', (tester) async {
    // На экране их различают значки; незрячему пользователю без имён приезжают
    // три числа подряд без единого намёка, где какое.
    final handle = tester.ensureSemantics();
    await _pumpStrip(tester, _channels);

    final node = tester.getSemantics(find.bySemanticsLabel('Через VPN'));
    expect(node.value, contains('Приём 1.1 MB/s'));
    expect(node.value, contains('Отдача 22.0 KB/s'));
    expect(node.value, contains('Принято 239.5 KB'));
    handle.dispose();
  });
}
