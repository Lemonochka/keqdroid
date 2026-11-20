import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/ui/halloween/halloween_season.dart';
import 'providers.dart';

// пересчёт на границе окна по таймеру и при возврате на экран: во сне телефон откладывает таймеры
final halloweenActiveProvider = NotifierProvider<HalloweenActiveNotifier, bool>(
  HalloweenActiveNotifier.new,
);

class HalloweenActiveNotifier extends Notifier<bool> {
  @override
  bool build() {
    final enabled = ref.watch(
      settingsNotifierProvider.select((s) => s.value?.seasonalDecor ?? true),
    );

    final wait = HalloweenSeason.untilNextBoundary(HalloweenSeason.current);
    // секунда запаса: сработав на миг раньше полуночи, таймер увидел бы прежнее окно
    // и уснул до следующей границы
    final timer = wait == null
        ? null
        : Timer(wait + const Duration(seconds: 1), ref.invalidateSelf);
    final lifecycle = AppLifecycleListener(onResume: ref.invalidateSelf);
    ref.onDispose(() {
      timer?.cancel();
      lifecycle.dispose();
    });

    return enabled && HalloweenSeason.isNow;
  }
}
