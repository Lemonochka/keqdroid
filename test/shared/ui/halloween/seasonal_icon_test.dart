import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/providers/halloween_provider.dart';
import 'package:keqdroid/shared/ui/halloween/halloween_icons.dart';

class _Fixed extends HalloweenActiveNotifier {
  _Fixed(this.value);
  final bool value;

  @override
  bool build() => value;
}

Future<void> _pump(
  WidgetTester tester, {
  required bool active,
  required bool scoped,
  IconData icon = Icons.refresh_rounded,
}) {
  final child = SeasonalIcon(icon);
  return tester.pumpWidget(
    ProviderScope(
      overrides: [halloweenActiveProvider.overrideWith(() => _Fixed(active))],
      child: MaterialApp(
        home: Center(child: scoped ? HalloweenIconScope(child: child) : child),
      ),
    ),
  );
}

bool _isPlainIcon(WidgetTester tester) => find
    .descendant(of: find.byType(SeasonalIcon), matching: find.byType(Icon))
    .evaluate()
    .isNotEmpty;

// ячейка задаёт значку жёсткий размер, как узкая боковая панель на ПК
Future<Size> _glyphInCell(
  WidgetTester tester,
  Size cell, {
  double? size,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [halloweenActiveProvider.overrideWith(() => _Fixed(true))],
      child: MaterialApp(
        home: Center(
          child: SizedBox.fromSize(
            size: cell,
            child: HalloweenIconScope(
              child: SeasonalIcon(Icons.dns_rounded, size: size),
            ),
          ),
        ),
      ),
    ),
  );
  return tester.getSize(
    find
        .descendant(
          of: find.byType(SeasonalIcon),
          matching: find.byType(CustomPaint),
        )
        .first,
  );
}

void main() {
  testWidgets('в праздник на главном экране значок заменён', (tester) async {
    await _pump(tester, active: true, scoped: true);
    expect(_isPlainIcon(tester), isFalse);
  });

  testWidgets('вне главного экрана значок свой даже в праздник', (
    tester,
  ) async {
    // иначе сеть в настройках LAN тоже стала бы амулетом
    await _pump(tester, active: true, scoped: false);
    expect(_isPlainIcon(tester), isTrue);
  });

  testWidgets('вне праздника значок свой', (tester) async {
    await _pump(tester, active: false, scoped: true);
    expect(_isPlainIcon(tester), isTrue);
  });

  testWidgets(
    'в узкой боковой панели знак своего размера, а не во всю ячейку',
    (tester) async {
      expect(
        await _glyphInCell(tester, const Size(60, 48)),
        const Size(24, 24),
      );
      expect(
        await _glyphInCell(tester, const Size(60, 40), size: 20),
        const Size(20, 20),
      );
    },
  );

  testWidgets('шестерёнка и пуск с паузой остаются своими и в праздник', (
    tester,
  ) async {
    for (final icon in [
      Icons.settings_rounded,
      Icons.play_arrow_outlined,
      Icons.pause_rounded,
    ]) {
      await _pump(tester, active: true, scoped: true, icon: icon);
      expect(_isPlainIcon(tester), isTrue, reason: '$icon');
    }
  });
}
