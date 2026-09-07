import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/traffic_split.dart';
import '../services/traffic_split_service.dart';
import '../tunnel/tunnel_state.dart';
import '../utils/mihomo_api_session.dart';
import 'providers.dart';

/// Как часто снимаем счётчики соединений. Секунда — тот же такт, что у общей
/// скорости: разные такты давали бы разбивку, не сходящуюся с цифрой рядом.
const _pollInterval = Duration(seconds: 1);

/// Трафик с разбивкой на «в туннель» и «мимо туннеля».
///
/// `null` — разбивки нет: либо она выключена в настройках, либо нет
/// подключения, либо ядро её не отдаёт (см. [TrafficSplitSource]). Полоса
/// показателей в этом случае показывает обычные общие цифры, а не нули.
///
/// Живёт всю сессию туннеля, а не пока на неё смотрят, и опрос не глохнет ни в
/// фоне, ни в трее. Это не расточительность, а единственный способ получить
/// верное число: ядро отдаёт накопительные счётчики ЖИВЫХ соединений, и всё,
/// что успело пройти и закрыться, пока мы не смотрели, узнать уже неоткуда.
/// Первая версия считала только при открытой вкладке — и на прогоне спидтеста
/// в браузере (то есть в другом приложении) насчитывала десятки байт вместо
/// десятков мегабайт.
///
/// Общий счётчик рядом такой ошибки не знает: он кумулятивный в самом ядре, и
/// пауза опроса ему ничего не стоит. Здесь же пауза — это потерянные данные.
///
/// Опрос идёт СВОИМ запросом, хотя на десктопе бэкенд туннеля раз в секунду
/// дёргает тот же `/connections` ради общих сумм. Разделить их значило бы
/// протащить разбивку через состояние туннеля и написать её дважды — отдельно
/// для десктопа и для Android, где скорость приходит из системного счётчика.
final trafficSplitProvider = StreamProvider<TrafficSplit?>((ref) {
  final enabled = ref.watch(
    settingsNotifierProvider.select((s) => s.value?.showTrafficSplit ?? false),
  );
  final connected = ref.watch(
    vpnStateProvider.select((a) => a.value?.status == VpnStatus.connected),
  );
  if (!enabled || !connected) return Stream<TrafficSplit?>.value(null);

  final tracker = TrafficSplitTracker();
  final controller = StreamController<TrafficSplit?>();
  // Последнее удачное значение. Один не ответивший опрос (ядро занято, порт
  // моргнул) не должен схлопывать полосу в общие цифры и обратно — высота
  // шапки прыгала бы на ровном месте.
  TrafficSplit? last;
  var inFlight = false;

  Future<void> poll() async {
    // Прошлый запрос ещё не вернулся: очередь из запросов к подтормаживающему
    // ядру растёт быстрее, чем разбирается.
    if (inFlight || controller.isClosed) return;
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

  final timer = Timer.periodic(_pollInterval, (_) => unawaited(poll()));
  unawaited(poll());

  ref.onDispose(() {
    timer.cancel();
    unawaited(controller.close());
  });
  return controller.stream;
});
