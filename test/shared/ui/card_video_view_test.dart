import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/shared/ui/card_video_view.dart';
import 'package:video_player/video_player.dart';

class _FakeController extends VideoPlayerController {
  _FakeController() : super.file(File('cover.mp4'));

  var plays = 0;
  var pauses = 0;
  var disposed = false;

  @override
  Future<void> initialize() async {
    value = value.copyWith(
      isInitialized: true,
      duration: const Duration(seconds: 3),
      size: const Size(16, 9),
    );
  }

  @override
  Future<void> setLooping(bool looping) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> play() async => plays++;

  @override
  Future<void> pause() async => pauses++;

  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }
}

void main() {
  late List<_FakeController> created;
  final ticking = ValueNotifier(true);

  setUp(() {
    created = [];
    ticking.value = true;
    CardVideoView.debugCreateController = (_) {
      final c = _FakeController();
      created.add(c);
      return c;
    };
  });

  tearDown(() {
    CardVideoView.debugCreateController = null;
  });

  Future<void> host(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: ticking,
          builder: (_, on, child) => TickerMode(enabled: on, child: child!),
          child: const SizedBox(
            width: 320,
            height: 120,
            child: CardVideoView(path: 'cover.mp4', poster: 'cover.jpg'),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> goTo(WidgetTester tester, List<AppLifecycleState> states) async {
    for (final s in states) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump();
  }

  const toBackground = [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ];
  const toForeground = [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ];

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    expect(CardVideoView.debugRecheckTimers, 0);
  }

  testWidgets('видимая шапка открывает плеер и играет', (tester) async {
    await host(tester);

    expect(created, hasLength(1));
    expect(created.single.plays, greaterThan(0));
    expect(CardVideoView.debugRecheckTimers, 1);
    await unmount(tester);
  });

  testWidgets('на чужой вкладке плеер встаёт и через 2 с закрывается, без таймера', (
    tester,
  ) async {
    await host(tester);
    final player = created.single;

    ticking.value = false;
    await tester.pump();
    expect(player.pauses, greaterThan(0));
    expect(player.disposed, isFalse);
    expect(CardVideoView.debugRecheckTimers, 0);

    await tester.pump(const Duration(milliseconds: 2100));
    expect(player.disposed, isTrue);

    await tester.pump(const Duration(minutes: 1));
    expect(created, hasLength(1));
    await unmount(tester);
  });

  testWidgets('вернулись на вкладку быстрее 2 с: тот же плеер играет дальше', (
    tester,
  ) async {
    await host(tester);
    final player = created.single;
    final playsBefore = player.plays;

    ticking.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    ticking.value = true;
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(created, hasLength(1));
    expect(player.disposed, isFalse);
    expect(player.plays, greaterThan(playsBefore));
    await unmount(tester);
  });

  testWidgets('в свёрнутом приложении плеер закрывается и таймер не тикает', (
    tester,
  ) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await host(tester);
    final player = created.single;

    await goTo(tester, toBackground);
    expect(player.pauses, greaterThan(0));
    expect(CardVideoView.debugRecheckTimers, 0);

    await tester.pump(const Duration(milliseconds: 2100));
    expect(player.disposed, isTrue);

    await tester.pump(const Duration(minutes: 10));
    expect(created, hasLength(1));
    expect(CardVideoView.debugRecheckTimers, 0);

    await goTo(tester, toForeground);
    await tester.pump();
    expect(created, hasLength(2));
    expect(created.last.plays, greaterThan(0));
    expect(CardVideoView.debugRecheckTimers, 1);
    await unmount(tester);
  });

  testWidgets('свернули и сразу вернулись: плеер тот же', (tester) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await host(tester);
    final player = created.single;

    await goTo(tester, toBackground);
    await tester.pump(const Duration(seconds: 1));
    await goTo(tester, toForeground);
    await tester.pump(const Duration(seconds: 3));

    expect(created, hasLength(1));
    expect(player.disposed, isFalse);
    await unmount(tester);
  });

  testWidgets('шторка поверх приложения плеер не трогает', (tester) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await host(tester);
    final player = created.single;

    await goTo(tester, [AppLifecycleState.inactive]);
    await tester.pump(const Duration(seconds: 5));

    expect(player.disposed, isFalse);
    expect(player.pauses, 0);
    expect(CardVideoView.debugRecheckTimers, 1);
    await unmount(tester);
  });
}
