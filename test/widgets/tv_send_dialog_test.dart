import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/screens/tv_send_dialog.dart';
import 'package:keqdroid/services/tv_handoff.dart';

// Телефон после скана кода телевизора: выбор подписки и отправка. Отправка
// идёт настоящим сокетом на сервер приёма на 127.0.0.1.
void main() {
  // flutter_test подменяет HttpClient заглушкой, которая на всё отвечает 400,
  // а здесь проверяется настоящий обмен.
  setUp(() {
    final mock = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = mock);
  });

  final home = Subscription.create(
    name: 'Kequinq VPN',
    url: 'https://sub.example/home',
  );
  final spare = Subscription.create(
    name: 'Запасная',
    url: 'https://sub.example/spare',
    nameIsAuto: true,
  );

  Future<ValueNotifier<bool?>> openDialog(
    WidgetTester tester,
    TvPairing tv,
  ) async {
    final result = ValueNotifier<bool?>(null);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result.value = await showDialog<bool>(
                context: context,
                builder: (_) =>
                    TvSendDialog(tv: tv, subscriptions: [home, spare]),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  // Ждёт настоящий сетевой обмен: в тестах виджетов время ненастоящее.
  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 50 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  testWidgets('выбранная подписка уходит на телевизор', (tester) async {
    final received = <TvSubscriptionOffer>[];
    final server = (await tester.runAsync(
      () => TvReceiveServer.start(
        lanAddress: '127.0.0.1',
        onOffer: (offer) async {
          received.add(offer);
          return null;
        },
      ),
    ))!;
    addTearDown(() => tester.runAsync(server.close));

    final result = await openDialog(tester, server.pairing);
    expect(find.text('Отправить на телевизор'), findsOneWidget);
    expect(find.text('Какую подписку отправить?'), findsOneWidget);
    expect(find.text('Kequinq VPN'), findsOneWidget);

    await tester.tap(find.text('Запасная'));
    await tester.pump();
    await tester.tap(find.text('Отправить'));
    await waitFor(tester, () => result.value != null);
    await tester.pumpAndSettle();

    expect(result.value, isTrue);
    expect(received.single.url, spare.url);
    expect(received.single.name, 'Запасная');
    expect(received.single.nameIsAuto, isTrue);
  });

  testWidgets('телевизор не ответил — диалог остаётся с объяснением', (
    tester,
  ) async {
    // Порт, на котором никто не слушает: сервер подняли и сразу закрыли.
    final pairing = (await tester.runAsync(() async {
      final server = await TvReceiveServer.start(
        lanAddress: '127.0.0.1',
        onOffer: (_) async => null,
      );
      await server.close();
      return server.pairing;
    }))!;

    final result = await openDialog(tester, pairing);
    await tester.tap(find.text('Отправить'));
    await waitFor(
      tester,
      () => find.textContaining('Телевизор не отвечает').evaluate().isNotEmpty,
    );

    expect(find.textContaining('Телевизор не отвечает'), findsOneWidget);
    expect(find.text('Отправить на телевизор'), findsOneWidget);
    expect(result.value, isNull);
  });
}
