import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/ui/responsive/desktop_page_layout.dart';
import 'package:keqdroid/ui/responsive/window_breakpoints.dart';

/// Раскладка выбирается по ширине окна, а не по платформе. До этого телефон
/// боком получал ту же вертикальную раскладку, и шапка экрана серверов съедала
/// всю высоту — списку не оставалось места.
Future<({bool expanded, double contentWidth})> _probe(
  WidgetTester tester,
  Size screen,
) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  late bool expanded;
  const key = Key('content');
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          expanded = WindowBreakpoints.isExpandedMobile(context);
          return const DesktopPageLayout(
            maxWidth: 720,
            child: SizedBox.expand(key: key),
          );
        },
      ),
    ),
  );
  return (expanded: expanded, contentWidth: tester.getSize(find.byKey(key)).width);
}

void main() {
  tearDown(() => PlatformBootstrap.debugIsDesktopOverride = null);

  group('телефон', () {
    setUp(() => PlatformBootstrap.debugIsDesktopOverride = false);

    testWidgets('вертикально — прежняя раскладка во всю ширину', (
      tester,
    ) async {
      final r = await _probe(tester, const Size(412, 915));
      expect(r.expanded, isFalse);
      expect(r.contentWidth, 412);
    });

    testWidgets('боком — expanded, вкладка не шире своего предела', (
      tester,
    ) async {
      final r = await _probe(tester, const Size(915, 412));
      expect(r.expanded, isTrue);
      // Боковые поля на телефоне даёт сама вкладка: без второго набора.
      expect(r.contentWidth, 720);
    });

    testWidgets('планшет вертикально (medium) остаётся с нижней панелью', (
      tester,
    ) async {
      final r = await _probe(tester, const Size(800, 1280));
      expect(r.expanded, isFalse);
    });
  });

  testWidgets('десктоп в expanded не попадает — у него своя оболочка', (
    tester,
  ) async {
    PlatformBootstrap.debugIsDesktopOverride = true;
    final r = await _probe(tester, const Size(1280, 800));
    expect(r.expanded, isFalse);
    // Десктоп сохраняет свои поля по 24.
    expect(r.contentWidth, 720 - 48);
  });
}
