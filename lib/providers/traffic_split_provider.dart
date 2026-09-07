import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/traffic_split.dart';
import '../services/traffic_split_service.dart';
import '../services/traffic_split_store.dart';
import '../tunnel/tunnel_state.dart';
import '../utils/mihomo_api_session.dart';
import 'providers.dart';

/// Как часто снимаем счётчики соединений. Секунда — тот же такт, что у общей
/// скорости: разные такты давали бы разбивку, не сходящуюся с цифрой рядом.
const _pollInterval = Duration(seconds: 1);

/// Как часто счёт уходит на диск.
///
/// Не каждый такт: писать файл раз в секунду всю сессию незачем, а потерять
/// при внезапной смерти процесса можно лишь то, что закрылось за последние
/// несколько секунд. Соединения, пережившие закрытие, при восстановлении
/// отдадут всё, что унесли, — им запись не нужна.
const _saveInterval = Duration(seconds: 5);

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
/// Одну паузу закрыть всё-таки удаётся — закрытое приложение. На Android ядро
/// живёт своим процессом, туннель от закрытия не падает, а Dart вместе с
/// накопленным объёмом умирает; счёт при этом начинался с нуля рядом с общим
/// чипом, честно показывающим объём за весь час. Поэтому счёт кладётся на диск
/// ([TrafficSplitStore]) и при следующем запуске подхватывается — вместе со
/// счётчиками соединений, переживших закрытие: у них ядро всё это время
/// считало, и унесённое за час попадает в объём целиком.
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
  // Счёт прошлого запуска спрашиваем ровно один раз: дальше он живёт в
  // трекере, и повторное чтение файла откатило бы его назад.
  var restoreTried = false;
  DateTime? savedAt;
  ConnectionsSnapshot? lastSnapshot;
  // Считать с прошлой записи было что. Заодно отсекает запись до первого
  // подсчёта: уход в фон в ту секунду, пока читается прошлый счёт, положил бы
  // поверх него пустой.
  var counted = false;

  void save({required bool now}) {
    final snapshot = lastSnapshot;
    if (snapshot == null || !counted) return;
    final at = DateTime.now();
    if (!now && savedAt != null && at.difference(savedAt!) < _saveInterval) {
      return;
    }
    final state = tracker.stateFor(
      coreDownload: snapshot.coreDownload,
      coreUpload: snapshot.coreUpload,
    );
    if (state == null) return;
    savedAt = at;
    counted = false;
    unawaited(TrafficSplitStore.save(state));
  }

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
      final snapshot = await TrafficSplitSource.fetch(
        port: port,
        secret: api.secret,
      );
      if (controller.isClosed) return;
      if (snapshot == null) {
        controller.add(last);
        return;
      }
      final session = TrafficSplitStore.sessionKey(
        port: port,
        secret: api.secret,
      );
      if (!restoreTried) {
        restoreTried = true;
        // Читаем только теперь, а не при создании провайдера: подходит запись
        // или нет, видно лишь по ответу ядра — по его общим суммам.
        final stored = await TrafficSplitStore.load();
        if (controller.isClosed) return;
        if (stored != null &&
            stored.belongsTo(
              session: session,
              coreDownload: snapshot.coreDownload,
              coreUpload: snapshot.coreUpload,
            )) {
          tracker.restore(stored);
        }
      }
      lastSnapshot = snapshot;
      last = tracker.add(snapshot.connections, session: session);
      counted = true;
      controller.add(last);
      save(now: false);
    } finally {
      inFlight = false;
    }
  }

  final timer = Timer.periodic(_pollInterval, (_) => unawaited(poll()));
  unawaited(poll());

  // Уход в фон — последний момент, когда мы ещё можем что-то записать: на
  // Android движок уничтожают сразу после него, и всё, что накопилось с
  // прошлой записи, иначе осталось бы только в памяти умершего изолята.
  final lifecycle = AppLifecycleListener(
    onStateChange: (state) {
      if (state == AppLifecycleState.hidden ||
          state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached) {
        save(now: true);
      }
    },
  );

  ref.onDispose(() {
    timer.cancel();
    lifecycle.dispose();
    unawaited(controller.close());
  });
  return controller.stream;
});
