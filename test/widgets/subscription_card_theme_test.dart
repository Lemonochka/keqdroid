import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/models/subscription_card_theme.dart';

void main() {
  group('каталог', () {
    test('первая тема — «без темы», её и получают по умолчанию', () {
      expect(kSubscriptionCardThemes.first.isPlain, isTrue);
      expect(const Subscription(id: 'a', name: 'n', url: 'u').cardThemeId, '');
      expect(resolveCardTheme('').isPlain, isTrue);
      expect(resolveCardTheme(null).isPlain, isTrue);
    });

    test('id уникальны — иначе выбор не отличить', () {
      final ids = kSubscriptionCardThemes.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('своя картинка собирается из каталога приложения', () {
      SubscriptionCardTheme.customDirectory = '/data/app/card_themes';
      addTearDown(() => SubscriptionCardTheme.customDirectory = null);

      final theme = resolveCardTheme('file:sub-17.jpg');
      // Главная поломка: id в настройках был, а карточка оставалась пустой —
      // тему по нему никто не собирал, и выбор картинки «ничего не делал».
      expect(theme.isPlain, isFalse);
      expect(theme.asset, contains('sub-17.jpg'));
      expect(theme.id, 'file:sub-17.jpg');
    });

    test('своя картинка без известного каталога — обычная карточка', () {
      SubscriptionCardTheme.customDirectory = null;
      expect(resolveCardTheme('file:sub-17.jpg').isPlain, isTrue);
    });

    test('удалённая тема откатывается к обычной карточке, а не падает', () {
      // Так себя ведёт подписка, которой выбрали картинку, а картинку потом
      // выкинули из сборки.
      expect(resolveCardTheme('картинки-больше-нет').isPlain, isTrue);
    });

    test('каждая палитровая тема даёт три опорных цвета', () {
      const scheme = ColorScheme.dark();
      for (final palette in CardPalette.values) {
        expect(palette.colors(scheme), hasLength(3));
      }
    });
  });

  group('модель подписки', () {
    test('тема переживает сериализацию', () {
      const sub = Subscription(
        id: 'a',
        name: 'n',
        url: 'https://example/sub',
        cardThemeId: 'aurora',
      );
      expect(Subscription.fromJson(sub.toJson()).cardThemeId, 'aurora');
    });

    test('пустая тема не занимает места в хранилище', () {
      const sub = Subscription(id: 'a', name: 'n', url: 'u');
      expect(sub.toJson().containsKey('cardThemeId'), isFalse);
      expect(Subscription.fromJson(sub.toJson()).cardThemeId, '');
    });

    test('старая подписка без поля читается', () {
      final json = {'id': 'a', 'name': 'n', 'url': 'u'};
      expect(Subscription.fromJson(json).cardThemeId, '');
    });
  });

  group('подложка в списке серверов', () {
    // Смысл затеи — связь карточки с её серверами, поэтому связь включена
    // сразу, а выключают её по желанию.
    test('новая подписка показывает подложку и в группе серверов', () {
      expect(
        const Subscription(id: 'a', name: 'n', url: 'u').cardThemeInServers,
        isTrue,
      );
    });

    test('выключение переживает сериализацию', () {
      const sub = Subscription(
        id: 'a',
        name: 'n',
        url: 'u',
        cardThemeId: 'aurora',
        cardThemeInServers: false,
      );
      final restored = Subscription.fromJson(sub.toJson());
      expect(restored.cardThemeInServers, isFalse);
      // Выключили картинку в списке — сама тема карточки остаётся выбранной.
      expect(restored.cardThemeId, 'aurora');
    });

    test('включённое состояние не занимает места в хранилище', () {
      const sub = Subscription(id: 'a', name: 'n', url: 'u');
      expect(sub.toJson().containsKey('cardThemeInServers'), isFalse);
    });

    // Подписки, заведённые до появления флага, должны получить новое
    // поведение, а не остаться с невидимой настройкой «выключено».
    test('подписка без поля считается включённой', () {
      final json = {'id': 'a', 'name': 'n', 'url': 'u', 'cardThemeId': 'mint'};
      expect(Subscription.fromJson(json).cardThemeInServers, isTrue);
    });
  });

  Future<int> pumpBackground(WidgetTester tester, String id) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 120,
            child: Builder(
              builder: (context) => resolveCardTheme(id).background(context),
            ),
          ),
        ),
      ),
    );
    return tester
        .widgetList(
          find.descendant(
            of: find.byType(Scaffold),
            matching: find.byType(CustomPaint),
          ),
        )
        .length;
  }

  testWidgets('палитровая тема рисует подложку', (tester) async {
    final withTheme = await pumpBackground(tester, 'sunset');
    final plain = await pumpBackground(tester, '');
    // Scaffold сам по себе тащит служебные CustomPaint, поэтому сравниваем с
    // тем же деревом без темы, а не с нулём.
    expect(withTheme, greaterThan(plain));
  });

  testWidgets('все темы каталога строятся без исключений', (tester) async {
    for (final theme in kSubscriptionCardThemes) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 120,
              child: Builder(builder: theme.background),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'тема ${theme.id}');
    }
  });
}
