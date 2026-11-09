import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/providers/providers.dart';

import '../helpers/test_storage.dart';

const _box = Key('box');

class _Probe extends StatelessWidget {
  const _Probe({this.onCornerTap});
  final VoidCallback? onCornerTap;

  static MediaQueryData? seen;

  @override
  Widget build(BuildContext context) {
    seen = MediaQuery.of(context);
    return Stack(
      children: [
        const Positioned(
          left: 0,
          top: 0,
          child: SizedBox(key: _box, width: 100, height: 100),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: GestureDetector(
            onTap: onCornerTap,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox(width: 20, height: 20),
          ),
        ),
      ],
    );
  }
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required double uiScale,
  Widget home = const _Probe(),
}) async {
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = const Size(720, 1600);
  tester.view.padding = const FakeViewPadding(top: 48, bottom: 32);
  addTearDown(tester.view.reset);
  final settings = const AppSettings().copyWith(uiScale: uiScale);
  final storage = await tester.runAsync(() => buildStorageService(
        initialValues: {'keqdis_settings': settings.toJsonString()},
      ));
  await tester.pumpWidget(ProviderScope(
    overrides: [storageProvider.overrideWithValue(storage!)],
    child: KeqdroidApp(home: home),
  ));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => PlatformBootstrap.debugIsDesktopOverride = null);

  group('размер интерфейса масштабирует всё, а не только текст', () {
    testWidgets('на ПК 100% рисуется один в один', (tester) async {
      PlatformBootstrap.debugIsDesktopOverride = true;
      await _pumpApp(tester, uiScale: 1.0);

      expect(tester.getRect(find.byKey(_box)).width, 100);
      expect(_Probe.seen!.size, const Size(360, 800));
      expect(_Probe.seen!.textScaler.scale(16), 16);
    });

    testWidgets('70% сжимают коробку, а экран внутри становится шире',
        (tester) async {
      PlatformBootstrap.debugIsDesktopOverride = true;
      await _pumpApp(tester, uiScale: 0.7);

      expect(tester.getRect(find.byKey(_box)).width, moreOrLessEquals(70));
      final mq = _Probe.seen!;
      expect(mq.size.width, moreOrLessEquals(360 / 0.7));
      expect(mq.size.height, moreOrLessEquals(800 / 0.7));
      expect(mq.padding.top, moreOrLessEquals(24 / 0.7));
      expect(mq.devicePixelRatio, moreOrLessEquals(2.0 * 0.7));
      // текст масштабирует сама обёртка, второй раз через textScaler его сжимать нельзя
      expect(mq.textScaler.scale(16), 16);
    });

    testWidgets('на телефоне 100% это 85% размеров', (tester) async {
      PlatformBootstrap.debugIsDesktopOverride = false;
      await _pumpApp(tester, uiScale: 1.0);

      expect(tester.getRect(find.byKey(_box)).width, moreOrLessEquals(85));
      expect(_Probe.seen!.size.width, moreOrLessEquals(360 / 0.85));
    });

    testWidgets('нажатие у самого края экрана доходит при уменьшении',
        (tester) async {
      PlatformBootstrap.debugIsDesktopOverride = true;
      var taps = 0;
      await _pumpApp(tester, uiScale: 0.7, home: _Probe(onCornerTap: () => taps++));

      await tester.tapAt(const Offset(360 - 3, 800 - 3));
      expect(taps, 1);
    });

    testWidgets('смена масштаба через 100% не закрывает открытые экраны',
        (tester) async {
      PlatformBootstrap.debugIsDesktopOverride = true;
      await _pumpApp(tester, uiScale: 0.9);

      unawaited(rootNavigatorKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('second')),
      )));
      await tester.pumpAndSettle();
      expect(find.text('second'), findsOneWidget);

      final container =
          ProviderScope.containerOf(tester.element(find.text('second')));
      final notifier = container.read(settingsNotifierProvider.notifier);
      for (final scale in [1.0, 0.75]) {
        // запись хранилища из runAsync в фейковом времени не завершится, состояние меняется сразу
        notifier.save(const AppSettings().copyWith(uiScale: scale)).ignore();
        await tester.pumpAndSettle();
        expect(find.text('second'), findsOneWidget);
      }
    });
  });
}
