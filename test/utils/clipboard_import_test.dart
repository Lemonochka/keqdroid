import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/shared/ui/liquid_toast.dart';
import 'package:keqdroid/shared/ui/shape_loading_indicator.dart';
import 'package:keqdroid/utils/clipboard_import.dart';

/// Подписки без сети: настоящий `add` сразу качал бы её содержимое.
class _FakeSubs extends SubscriptionsNotifier {
  final added = <Subscription>[];

  // настоящий add возвращается только после скачивания подписки
  Completer<void>? download;

  @override
  Future<List<Subscription>> build() async => const [];

  @override
  Future<void> add(Subscription sub) async {
    added.add(sub);
    await download?.future;
  }
}

/// Серверы без хранилища: `_load()` настоящего полез бы в SharedPreferences.
class _FakeServers extends ServersNotifier {
  final added = <String>[];

  @override
  ServersState build() => ServersState();

  @override
  Future<void> addManual(String rawConfig) async => added.add(rawConfig);
}

typedef _Paste = Future<Object?> Function(BuildContext context, WidgetRef ref);

/// Кнопка «Вставить ссылку(и)» с пустого экрана серверов, без самого экрана.
Future<(_FakeSubs, _FakeServers)> _mount(
  WidgetTester tester,
  String clipboard, {
  _Paste paste = pasteLinksFromClipboard,
  Completer<void>? download,
  bool drop = false,
}) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => call.method == 'Clipboard.getData'
        ? <String, dynamic>{'text': clipboard}
        : null,
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));

  final subs = _FakeSubs()..download = download;
  final servers = _FakeServers();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        subscriptionsProvider.overrideWith(() => subs),
        serversProvider.overrideWith(() => servers),
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // капля Модерна и ПК: её хост стоит над всем приложением
        builder: drop ? (context, child) => LiquidToastHost(child: child!) : null,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => paste(context, ref),
              child: const Text('paste'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('paste'));
  return (subs, servers);
}

Future<(_FakeSubs, _FakeServers)> _pasteFromClipboard(
  WidgetTester tester,
  String clipboard,
) async {
  final mounted = await _mount(tester, clipboard);
  await tester.pumpAndSettle();
  return mounted;
}

final _loading = find.byType(ShapeLoadingIndicator);

void main() {
  testWidgets('ссылка подписки из буфера становится подпиской', (tester) async {
    final (subs, servers) =
        await _pasteFromClipboard(tester, 'https://sub.example/api/token');

    expect(subs.added.single.url, 'https://sub.example/api/token');
    expect(subs.added.single.name, 'sub.example');
    expect(subs.added.single.nameIsAuto, isTrue);
    expect(servers.added, isEmpty);
    expect(find.text('Подписка добавлена: sub.example'), findsOneWidget);
  });

  testWidgets('ссылка сервера из буфера становится сервером', (tester) async {
    const vless = 'vless://uuid@de.example.com:443?security=tls&type=tcp#DE';
    final (subs, servers) = await _pasteFromClipboard(tester, vless);

    expect(subs.added, isEmpty);
    expect(servers.added, [vless]);
    expect(find.text('Добавлено серверов: 1 из 1'), findsOneWidget);
  });

  group('загрузка, пока подписка скачивается', () {
    for (final (name, paste) in <(String, _Paste)>[
      ('ссылки', pasteLinksFromClipboard),
      ('подписка', pasteSubscriptionFromClipboard),
    ]) {
      testWidgets('$name: видна до итога, итог её сменяет', (tester) async {
        final download = Completer<void>();
        await _mount(
          tester,
          'https://sub.example/api/token',
          paste: paste,
          download: download,
        );
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(_loading, findsOneWidget);
        expect(find.text('Добавляю…'), findsOneWidget);

        download.complete();
        await tester.pumpAndSettle();
        expect(_loading, findsNothing);
        expect(find.text('Добавляю…'), findsNothing);
        expect(find.text('Подписка добавлена: sub.example'), findsOneWidget);
      });
    }

    // сервер добавляется сразу: мелькнувшая на кадр загрузка выглядела бы сбоем
    testWidgets('быстрая вставка обходится без неё', (tester) async {
      await _mount(
        tester,
        'vless://uuid@de.example.com:443?security=tls&type=tcp#DE',
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(_loading, findsNothing);
      }
      expect(find.text('Добавлено серверов: 1 из 1'), findsOneWidget);
    });

    testWidgets('ошибка скачивания тоже убирает загрузку', (tester) async {
      final download = Completer<void>();
      await _mount(tester, 'https://sub.example/api/token', download: download);
      await tester.pump(const Duration(seconds: 1));
      expect(_loading, findsOneWidget);

      download.completeError(Exception('HTTP 404'));
      await tester.pumpAndSettle();
      expect(_loading, findsNothing);
      // на месте загрузки сообщение об ошибке, а не пустота
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Добавляю…'), findsNothing);
      expect(find.textContaining('Подписка добавлена'), findsNothing);
    });
  });

  // в Модерне и на ПК вместо SnackBar капля LiquidToastHost
  group('капля', () {
    setUp(() => LiquidToast.enabled = true);
    tearDown(() {
      LiquidToast.enabled = false;
      LiquidToast.current.value = null;
    });

    Future<void> frames(WidgetTester tester, int count) async {
      for (var i = 0; i < count; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    // уход загрузки в край и выход итога заново оставляли почти секунду пустого экрана
    testWidgets('итог сменяет загрузку в той же капле, без пустой паузы', (tester) async {
      final download = Completer<void>();
      await _mount(
        tester,
        'https://sub.example/api/token',
        download: download,
        drop: true,
      );
      await frames(tester, 20);
      expect(find.text('Добавляю…'), findsOneWidget);

      download.complete();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final loading = find.text('Добавляю…').evaluate().isNotEmpty;
        final done = find.text('Подписка добавлена: sub.example').evaluate().isNotEmpty;
        expect(loading || done, isTrue, reason: 'кадр ${i + 1} пустой');
      }
      expect(find.text('Добавляю…'), findsNothing);
      expect(find.text('Подписка добавлена: sub.example'), findsOneWidget);

      // итог уходит сам, как любое уведомление
      await frames(tester, 120);
      expect(find.text('Подписка добавлена: sub.example'), findsNothing);
    });

    testWidgets('ошибка тоже сменяет загрузку на месте', (tester) async {
      final download = Completer<void>();
      await _mount(
        tester,
        'https://sub.example/api/token',
        download: download,
        drop: true,
      );
      await frames(tester, 20);
      download.completeError(Exception('HTTP 404'));
      await frames(tester, 10);
      expect(find.text('Добавляю…'), findsNothing);
      expect(find.byType(ShapeLoadingIndicator), findsNothing);
      expect(LiquidToast.current.value, isNotNull);
      await frames(tester, 120);
    });

    testWidgets('быстрая вставка показывает только итог', (tester) async {
      await _mount(
        tester,
        'vless://uuid@de.example.com:443?security=tls&type=tcp#DE',
        drop: true,
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('Добавляю…'), findsNothing);
      }
      expect(find.text('Добавлено серверов: 1 из 1'), findsOneWidget);
      await frames(tester, 120);
    });
  });
}
