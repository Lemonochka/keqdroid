import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/traffic_split.dart';
import '../services/traffic_split_service.dart';
import '../utils/mihomo_api_session.dart';
import 'providers.dart';

/// Как часто снимаем счётчики соединений. Секунда — тот же такт, что у общей
/// скорости: разные такты давали бы разбивку, не сходящуюся с цифрой рядом.
const _pollInterval = Duration(seconds: 1);

/// Скорость с разбивкой на «в туннель» и «мимо туннеля».
///
/// `null` — разбивки нет: либо она выключена в настройках, либо ядро её не
/// отдаёт (см. [TrafficSplitSource]). Полоса показателей в этом случае
/// показывает обычные общие цифры, а не нули.
///
/// Опрос идёт СВОИМ запросом, хотя на десктопе бэкенд туннеля раз в секунду
/// дёргает тот же `/connections` ради общих сумм. Разделить их значило бы
/// протащить разбивку через состояние туннеля и написать её дважды — отдельно
/// для десктопа и для Android, где скорость приходит из системного счётчика.
/// Один лишний запрос на петлю в секунду дешевле второй копии логики, тем
/// более что он есть только пока разбивку включили и на неё смотрят.
///
/// `autoDispose`: провайдер жив, только пока на него смотрит полоса, то есть
/// при живом подключении и открытой вкладке.
final trafficSplitProvider = StreamProvider.autoDispose<TrafficSplit?>((ref) {
  final enabled = ref.watch(
    settingsNotifierProvider.select((s) => s.value?.showTrafficSplit ?? false),
  );
  // Окно в трее — на разбивку никто не смотрит. Пересоздание провайдера при
  // возврате заодно берёт новую базовую отметку: разница со снимком часовой
  // давности показала бы весь скрытый период как одну секунду.
  final visible = ref.watch(desktopUiVisibleProvider);
  if (!enabled || !visible) return Stream<TrafficSplit?>.value(null);

  final tracker = TrafficSplitTracker();
  final controller = StreamController<TrafficSplit?>();
  // Последнее удачное значение. Один не ответивший опрос (ядро занято, порт
  // моргнул) не должен схлопывать полосу в однострочный вид и обратно —
  // высота шапки прыгала бы на ровном месте.
  TrafficSplit? last;
  var inFlight = false;
  var foreground = true;

  Future<void> poll() async {
    // Прошлый запрос ещё не вернулся: очередь из запросов к подтормаживающему
    // ядру растёт быстрее, чем разбирается.
    if (inFlight || !foreground || controller.isClosed) return;
    inFlight = true;
    try {
      final api = MihomoApiSession();
      final port = api.port;
      if (port == null || !api.isActive) {
        tracker.reset();
        last = null;
        if (!controller.isClosed) controller.add(null);
        return;
      }
      final rows = await TrafficSplitSource.fetch(
        port: port,
        secret: api.secret,
      );
      if (controller.isClosed) return;
      if (rows == null) {
        controller.add(last);
        return;
      }
      last = tracker.add(rows, session: '$port');
      controller.add(last);
    } finally {
      inFlight = false;
    }
  }

  // Приложение ушло в фон (Android) или окно свернули: секундный опрос не
  // виден никому. desktopUiVisibleProvider ловит только трей на Windows.
  final lifecycle = AppLifecycleListener(
    onStateChange: (state) {
      final hidden = state == AppLifecycleState.hidden ||
          state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached;
      foreground = !hidden;
      if (hidden) tracker.reset();
    },
  );

  final timer = Timer.periodic(_pollInterval, (_) => unawaited(poll()));
  unawaited(poll());

  ref.onDispose(() {
    timer.cancel();
    lifecycle.dispose();
    unawaited(controller.close());
  });
  return controller.stream;
});
