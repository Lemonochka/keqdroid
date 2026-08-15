import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/server_flag.dart';
import 'package:keqdroid/shared/ui/server_avatar.dart';

/// Раньше кругляш умел ровно один вид флага — страновой, и только тот, что
/// знает таблица кодов пакета. Всё остальное (🇪🇺, 🏴󠁧󠁢󠁳󠁣󠁴󠁿, 🏴‍☠️) сваливалось
/// в букву протокола или в белый квадрат со знаком вопроса.
Widget _host(ServerFlag? flag) => MaterialApp(
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7B61FF)),
  ),
  home: Scaffold(
    body: Center(child: ServerAvatar(flag: flag, protocol: 'vless')),
  ),
);

void main() {
  testWidgets('страновой флаг рисуется картинкой', (tester) async {
    await tester.pumpWidget(_host(const FlagArt('ru')));
    expect(find.byKey(flagArtKey), findsOneWidget);
    // Ассет действительно грузится: иначе onError подставил бы букву протокола.
    await tester.pumpAndSettle();
    expect(find.text('V'), findsNothing);
  });

  testWidgets('флаг субъекта тоже грузится, а не падает в onError', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const FlagArt('gb-sct')));
    await tester.pumpAndSettle();
    expect(find.byKey(flagArtKey), findsOneWidget);
    expect(find.text('V'), findsNothing);
  });

  testWidgets('незнакомый флаг рисуется самим эмодзи', (tester) async {
    await tester.pumpWidget(_host(const FlagGlyph('🎌')));
    expect(find.text('🎌'), findsOneWidget);
    expect(find.byKey(flagArtKey), findsNothing);
    expect(find.byKey(flatFlagKey), findsNothing);
  });

  testWidgets('эмодзи-флаг заполняет кружок, а не сидит в его середине', (
    tester,
  ) async {
    // Страновые флаги приходят картинкой и рисуются cover — эмодзи рядом с
    // ними выглядел вдвое мельче, потому что кегль был меньше диаметра.
    await tester.pumpWidget(_host(const FlagGlyph('🎌')));
    final glyph = tester.widget<Text>(find.text('🎌'));

    expect(glyph.style!.fontSize, greaterThan(40));
    // И при этом не раздувает сам кружок — лишнее срезает ClipOval.
    expect(tester.getSize(find.byType(ServerAvatar)), const Size(40, 40));
  });

  group('плоские флаги', () {
    // Эмодзи-флаг системный шрифт рисует развевающимся на ветру: в ряду ровных
    // прямоугольников из country_flags он выглядит кривым.
    testWidgets('пиратский рисуется полотнищем, а не эмодзи', (tester) async {
      await tester.pumpWidget(_host(const FlagGlyph('🏴‍☠️')));

      expect(find.byKey(flatFlagKey), findsOneWidget);
      expect(find.text('🏴‍☠️'), findsNothing);
      // Череп остаётся эмблемой поверх полотнища — рисовать его вручную незачем.
      expect(find.text('☠️'), findsOneWidget);
    });

    testWidgets('радужный — полосы, эмодзи в кружке не остаётся', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const FlagGlyph('🏳️‍🌈')));

      expect(find.byKey(flatFlagKey), findsOneWidget);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('флаг узнаётся и без вариационного селектора', (tester) async {
      // 🏳️‍🌈 приходит и как 1F3F3 FE0F 200D 1F308, и без FE0F — это один флаг.
      await tester.pumpWidget(
        _host(const FlagGlyph('\u{1F3F3}\u{200D}\u{1F308}')),
      );

      expect(find.byKey(flatFlagKey), findsOneWidget);
    });

    testWidgets('полотнище не раздувает кружок', (tester) async {
      await tester.pumpWidget(_host(const FlagGlyph('🏁')));

      expect(find.byKey(flatFlagKey), findsOneWidget);
      expect(tester.getSize(find.byType(ServerAvatar)), const Size(40, 40));
    });
  });

  testWidgets('без флага остаётся буква протокола', (tester) async {
    await tester.pumpWidget(_host(null));
    expect(find.text('V'), findsOneWidget);
    expect(find.byKey(flagArtKey), findsNothing);
  });

  testWidgets('кругляш держит заданный размер при любом виде флага', (
    tester,
  ) async {
    for (final flag in <ServerFlag?>[
      const FlagArt('gb-sct'),
      const FlagGlyph('🏳️‍🌈'),
      null,
    ]) {
      await tester.pumpWidget(_host(flag));
      expect(tester.getSize(find.byType(ServerAvatar)), const Size(40, 40));
    }
  });

  group('цепочка', () {
    Widget hostChain({required ServerFlag? flag, required int hops}) =>
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7B61FF)),
          ),
          home: Scaffold(
            body: Center(
              child: ServerAvatar(
                flag: flag,
                protocol: 'chain',
                chainHops: hops,
              ),
            ),
          ),
        );

    testWidgets('число узлов приезжает значком поверх флага', (tester) async {
      await tester.pumpWidget(hostChain(flag: const FlagArt('jp'), hops: 3));
      await tester.pumpAndSettle();

      expect(find.byKey(flagArtKey), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('без флага вместо буквы «C» рисуются звенья', (tester) async {
      await tester.pumpWidget(hostChain(flag: null, hops: 2));

      expect(find.text('C'), findsNothing);
      expect(find.byIcon(Icons.link), findsOneWidget);
    });

    testWidgets('значок не растит кругляш', (tester) async {
      await tester.pumpWidget(hostChain(flag: null, hops: 8));

      expect(tester.getSize(find.byType(ServerAvatar)), const Size(40, 40));
    });
  });
}
