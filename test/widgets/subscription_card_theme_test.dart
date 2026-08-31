import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/models/subscription_card_layout.dart';
import 'package:keqdroid/models/subscription_card_theme.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/subscriptions_tab.dart';
import 'package:keqdroid/shared/ui/expressive_button_group.dart';

import '../helpers/test_storage.dart';

class _FakeSubs extends SubscriptionsNotifier {
  _FakeSubs(this._subs);

  final List<Subscription> _subs;

  @override
  Future<List<Subscription>> build() async => _subs;
}

class _FakeSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

Future<void> _pumpTab(WidgetTester tester, Subscription sub) async {
  final storage = await buildStorageService();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
        subscriptionsProvider.overrideWith(() => _FakeSubs([sub])),
        settingsNotifierProvider.overrideWith(_FakeSettings.new),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SubscriptionsTab(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Subscription _sub({
  String cardThemeId = '',
  Set<SubscriptionCardElement> hidden = const {},
  CardVeil veil = CardVeil.medium,
  String? announce,
}) => Subscription(
  id: 'a',
  name: 'Sub',
  url: 'https://example/sub',
  cardThemeId: cardThemeId,
  hiddenCardElements: hidden,
  cardVeil: veil,
  announce: announce,
);

/// Доводит до открытого редактора оформления карточки.
///
/// Через меню карточки, а не напрямую: половина смысла редактора в том, что до
/// него можно дойти, не открывая форму с адресом подписки.
Future<void> _openCardLookSheet(
  WidgetTester tester, {
  required String cardThemeId,
  Set<SubscriptionCardElement> hidden = const {},
  CardVeil veil = CardVeil.medium,
  String? announce,
}) async {
  await _pumpTab(
    tester,
    _sub(
      cardThemeId: cardThemeId,
      hidden: hidden,
      veil: veil,
      announce: announce,
    ),
  );

  await tester.tap(find.byIcon(Icons.more_vert_rounded));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Card look'));
  await tester.pumpAndSettle();
}

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

    test('картинки нет на диске — тема обычная, а не «с картинкой»', () {
      // Так приезжает подписка из бэкапа, в который сама картинка не попала:
      // `cardThemeId` есть, файла нет. Считать такую тему картинкой нельзя —
      // шапка группы вырастала на полосу растворения, а показывать было нечего.
      SubscriptionCardTheme.customDirectory = '/data/app/card_themes';
      SubscriptionCardTheme.customFiles = {'sub-17.jpg'};
      addTearDown(() {
        SubscriptionCardTheme.customDirectory = null;
        SubscriptionCardTheme.customFiles = null;
      });

      expect(resolveCardTheme('file:sub-17.jpg').hasImage, isTrue);

      final missing = resolveCardTheme('file:sub-99.jpg');
      expect(missing.isPlain, isTrue);
      expect(missing.hasImage, isFalse);
    });

    test('каталог ещё не читали — картинка считается живой', () {
      // null у customFiles значит «не знаем», и это НЕ повод прятать оформление:
      // список каталога мог не удаться, а карточка обязана остаться прежней.
      SubscriptionCardTheme.customDirectory = '/data/app/card_themes';
      SubscriptionCardTheme.customFiles = null;
      addTearDown(() => SubscriptionCardTheme.customDirectory = null);

      expect(resolveCardTheme('file:sub-17.jpg').hasImage, isTrue);
    });

    test('удалённая тема откатывается к обычной карточке, а не падает', () {
      // Так себя ведёт подписка, которой выбрали картинку, а картинку потом
      // выкинули из сборки.
      expect(resolveCardTheme('картинки-больше-нет').isPlain, isTrue);
    });

    test('картинка есть только у картиночных тем', () {
      SubscriptionCardTheme.customDirectory = '/data/app/card_themes';
      addTearDown(() => SubscriptionCardTheme.customDirectory = null);

      // Палитра — не пустая тема, но и не картинка: её рисуют цветами схемы на
      // месте. Пока эти два вопроса отвечались одним `isPlain`, шапка группы
      // серверов вырастала на полосу под картинку, которой нет.
      for (final theme in kSubscriptionCardThemes.where((t) => !t.isPlain)) {
        expect(theme.hasImage, theme.asset != null, reason: 'тема ${theme.id}');
      }
      expect(resolveCardTheme('aurora').isPlain, isFalse);
      expect(resolveCardTheme('aurora').hasImage, isFalse);
      expect(resolveCardTheme('').hasImage, isFalse);
      expect(resolveCardTheme('file:sub-17.jpg').hasImage, isTrue);
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

    // Тумблер обещает картинку («Картинка заполнит и шапку группы»), поэтому
    // предлагать его там, где картинки нет, — обещание, которое некому
    // выполнить: включённым он растил шапку группы на пустую полосу.
    testWidgets('у палитровой темы тумблера нет', (tester) async {
      await _openCardLookSheet(tester, cardThemeId: 'aurora');

      expect(find.text('Backdrop'), findsOneWidget);
      expect(find.text('Show in server list'), findsNothing);
    });

    testWidgets('у своей картинки тумблер на месте', (tester) async {
      SubscriptionCardTheme.customDirectory = '/data/app/card_themes';
      addTearDown(() => SubscriptionCardTheme.customDirectory = null);

      await _openCardLookSheet(tester, cardThemeId: 'file:sub-a.jpg');

      expect(find.text('Show in server list'), findsOneWidget);
    });

    testWidgets('без темы тумблера тоже нет', (tester) async {
      await _openCardLookSheet(tester, cardThemeId: '');

      expect(find.text('Show in server list'), findsNothing);
    });
  });

  Future<int> pumpBackground(
    WidgetTester tester,
    String id, {
    CardVeil veil = CardVeil.medium,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 120,
            child: Builder(
              builder: (context) =>
                  resolveCardTheme(id).background(context, veil: veil),
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
              child: Builder(
                builder: (context) =>
                    theme.background(context, veil: CardVeil.medium),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'тема ${theme.id}');
    }
  });

  /// Состав карточки и затемнение картинки — редактор оформления.
  ///
  /// С этого началась жалоба: объявление провайдера в чужой карточке читается
  /// как реклама в приложении, а убрать его было нечем.
  group('состав карточки', () {
    test('новая подписка показывает всё', () {
      const sub = Subscription(id: 'a', name: 'n', url: 'u');
      expect(sub.hiddenCardElements, isEmpty);
      expect(sub.cardPreset, SubscriptionCardPreset.full);
      for (final element in SubscriptionCardElement.values) {
        expect(sub.showsCard(element), isTrue, reason: element.name);
      }
    });

    test('состав и затемнение переживают сериализацию', () {
      final sub = _sub(
        hidden: {SubscriptionCardElement.announce},
        veil: CardVeil.none,
      );
      final restored = Subscription.fromJson(sub.toJson());
      expect(restored.hiddenCardElements, {SubscriptionCardElement.announce});
      expect(restored.cardVeil, CardVeil.none);
      expect(restored.showsCard(SubscriptionCardElement.announce), isFalse);
      expect(restored.showsCard(SubscriptionCardElement.usage), isTrue);
    });

    test('умолчания не занимают места в хранилище', () {
      const sub = Subscription(id: 'a', name: 'n', url: 'u');
      expect(sub.toJson().containsKey('cardHidden'), isFalse);
      expect(sub.toJson().containsKey('cardVeil'), isFalse);
    });

    test('настройка из версии новее не ломает разбор', () {
      // Ключ, которого в этой сборке нет, отбрасывается: уронить на нём весь
      // список подписок — потерять их все ради одного поля оформления.
      final json = {
        'id': 'a',
        'name': 'n',
        'url': 'u',
        'cardHidden': ['announce', 'нового-такого-нет', 42],
        'cardVeil': 'ультра',
      };
      final sub = Subscription.fromJson(json);
      expect(sub.hiddenCardElements, {SubscriptionCardElement.announce});
      expect(sub.cardVeil, CardVeil.medium);
    });

    test('пресет вычисляется из состава, а не хранится рядом', () {
      expect(
        SubscriptionCardPreset.of(const {}),
        SubscriptionCardPreset.full,
      );
      expect(
        SubscriptionCardPreset.of(
          SubscriptionCardPreset.compact.hidden!,
        ),
        SubscriptionCardPreset.compact,
      );
      expect(
        SubscriptionCardPreset.of(SubscriptionCardPreset.minimal.hidden!),
        SubscriptionCardPreset.minimal,
      );
      // Собранное вручную не совпадает ни с одним набором.
      expect(
        SubscriptionCardPreset.of(const {SubscriptionCardElement.usage}),
        SubscriptionCardPreset.custom,
      );
      // Выбрать «свою» нельзя — в неё попадают.
      expect(
        SubscriptionCardPreset.selectable,
        isNot(contains(SubscriptionCardPreset.custom)),
      );
    });

    testWidgets('объявление провайдера показывается, пока не убрано', (
      tester,
    ) async {
      await _pumpTab(tester, _sub(announce: 'Реклама бота'));

      expect(find.text('Реклама бота'), findsOneWidget);
    });

    testWidgets('скрытое объявление не рисуется на карточке', (tester) async {
      await _pumpTab(
        tester,
        _sub(
          announce: 'Реклама бота',
          hidden: {SubscriptionCardElement.announce},
        ),
      );

      expect(find.text('Реклама бота'), findsNothing);
    });

    testWidgets('у палитры затемнять нечего', (tester) async {
      await _openCardLookSheet(tester, cardThemeId: 'aurora');

      expect(find.text('Image dimming'), findsNothing);
    });

    testWidgets('у картинки затемнение выбирается шагами', (tester) async {
      SubscriptionCardTheme.customDirectory = '/data/app/card_themes';
      addTearDown(() => SubscriptionCardTheme.customDirectory = null);

      await _openCardLookSheet(tester, cardThemeId: 'file:sub-a.jpg');

      expect(find.text('Image dimming'), findsOneWidget);
      // «Нет» — тоже шаг: именно его и просили.
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('Heavy'), findsOneWidget);
    });

    // Образец наверху шторки — настоящая карточка, а не картинка с двумя
    // строчками: на вопрос «а что изменится, если убрать трафик» нарисованный
    // отдельно образец не отвечал никак.
    testWidgets('образец в шторке — та же карточка со всем содержимым', (
      tester,
    ) async {
      await _openCardLookSheet(
        tester,
        cardThemeId: '',
        announce: 'Реклама бота',
      );

      // Две: одна в списке под шторкой, вторая — образец.
      expect(find.text('Реклама бота'), findsNWidgets(2));
    });

    testWidgets('переключатель убирает часть и из образца тоже', (
      tester,
    ) async {
      await _openCardLookSheet(
        tester,
        cardThemeId: '',
        announce: 'Реклама бота',
      );

      final tile = find.ancestor(
        of: find.text('Provider announcement'),
        matching: find.byType(SwitchListTile),
      );
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();

      // Ни в образце, ни на самой карточке: правка применяется сразу.
      expect(find.text('Реклама бота'), findsNothing);
    });

    testWidgets('свёрнутая карточка в образце всё равно раскрыта', (
      tester,
    ) async {
      // Сворачиваемая часть живёт в AnimatedCrossFade, а он держит в дереве
      // ОБА состояния — по тексту свёрнутость не проверить, только по нему
      // самому.
      int expandedCards() => tester
          .widgetList<AnimatedCrossFade>(find.byType(AnimatedCrossFade))
          .where((w) => w.crossFadeState == CrossFadeState.showFirst)
          .length;

      await _pumpTab(tester, _sub());
      await tester.tap(find.byIcon(Icons.expand_more_rounded));
      await tester.pumpAndSettle();
      expect(expandedCards(), 0, reason: 'карточку в списке свернули');

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Card look'));
      await tester.pumpAndSettle();

      // Свёрнутый образец прятал бы ровно то, что в этой шторке переключают,
      // поэтому у него своя ProviderScope.
      expect(expandedCards(), 1, reason: 'образец развёрнут');
    });

    testWidgets('редактор показывает состав и текущий пресет', (tester) async {
      await _openCardLookSheet(
        tester,
        cardThemeId: '',
        hidden: SubscriptionCardPreset.compact.hidden!,
      );

      expect(find.text('What to show'), findsOneWidget);
      expect(find.text('Provider announcement'), findsOneWidget);

      final announce = tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text('Provider announcement'),
          matching: find.byType(SwitchListTile),
        ),
      );
      final usage = tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text('Traffic'),
          matching: find.byType(SwitchListTile),
        ),
      );
      expect(announce.value, isFalse, reason: 'компактная прячет объявление');
      expect(usage.value, isTrue, reason: 'трафик компактная оставляет');

      // Пресет выбирается связанной группой кнопок, а не чипами: у чипа в M3
      // роль фильтра (выбранных может быть несколько), а пресет — набор целиком.
      final presets = tester
          .widget<ExpressiveConnectedButtons<SubscriptionCardPreset>>(
        find.byType(ExpressiveConnectedButtons<SubscriptionCardPreset>),
      );
      expect(presets.selected, SubscriptionCardPreset.compact);
    });
  });
}
