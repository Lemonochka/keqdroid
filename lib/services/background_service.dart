// фоновое обновление подписок через workmanager + локальные нотификации

import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import '../core/app_logger.dart';
import 'storage_service.dart';
import 'subscription_service.dart';

const _kTaskName       = 'subscription_update';
const _kTaskUniqueName = 'keqdis_sub_update_periodic';

const _kNotifChannelId   = 'keqdis_subscription';
const _kNotifChannelName = 'Subscription Updates';
const _kNotifId          = 42;

// @pragma обязателен — иначе tree-shaker выкинет функцию в release
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != _kTaskName) return true;

    try {
      // в фоновом изоляте нужно поднять биндинги и плагины,
      // иначе StorageService.init() падает с MissingPluginException
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();

      final storage = await StorageService.init();

      // vpn в фоне может быть выключен — прокси не форсим, retry разрулит сеть
      final service = SubscriptionService(storage);

      // обновляем только то, у чего вышел интервал.
      // defaultInterval = 1 ч — фоллбэк, если updateIntervalHours не задан
      final due = await service.getDueForUpdate(
        defaultInterval: const Duration(hours: 1),
      );
      if (due.isEmpty) {
        return true;
      }

      final results = await Future.wait(
        due.map(service.updateSubscription),
        eagerError: false,
      );

      final ok      = results.where((r) => r.success).length;
      final failed  = results.length - ok;
      final total   = results.fold(0, (sum, r) => sum + r.serverCount);

      await _showUpdateNotification(
        ok: ok,
        failed: failed,
        totalServers: total,
      );

      return true;
    } catch (e, st) {
      AppLogger.instance.error(
        'Background subscription update task failed',
        error: e,
        stackTrace: st,
      );
      // false → workmanager сделает retry с exponential backoff
      return false;
    }
  });
}

Future<void> _showUpdateNotification({
  required int ok,
  required int failed,
  required int totalServers,
}) async {
  final plugin = FlutterLocalNotificationsPlugin();

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(settings: const InitializationSettings(android: androidInit));

  String title;
  String body;

  if (ok > 0 && failed == 0) {
    title = 'Subscriptions updated';
    body  = '$ok subscription${ok > 1 ? 's' : ''} refreshed'
        '${totalServers > 0 ? ' · $totalServers servers' : ''}';
  } else if (ok > 0 && failed > 0) {
    title = 'Subscriptions partially updated';
    body  = '$ok updated, $failed failed';
  } else {
    // всё упало — нотификацию не шлём, чтобы не спамить
    return;
  }

  await plugin.show(
    id: _kNotifId,
    title: title,
    body: body,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        _kNotifChannelId,
        _kNotifChannelName,
        channelDescription: 'Background subscription refresh results',
        importance: Importance.low,      // тихо, без звука
        priority: Priority.low,
        icon: '@mipmap/ic_launcher',
        playSound: false,
        enableVibration: false,
      ),
    ),
  );
}

class BackgroundService {

  /// вызвать один раз в main() до runApp()
  static Future<void> init() async {
    await Workmanager().initialize(
      callbackDispatcher,
    );

    // разрешение на нотификации (android 13+)
    final plugin = FlutterLocalNotificationsPlugin();
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
  }

  /// периодическая задача. android даёт минимум 15 мин между запусками,
  /// реальный интервал — в Subscription.updateIntervalHours (фильтр getDueForUpdate).
  /// policy=update: пересоздаём на каждом старте, чтобы подхватить параметры
  /// и вытащить задачу из подвисшего состояния.
  static Future<void> registerPeriodicTask() async {
    await Workmanager().registerPeriodicTask(
      _kTaskUniqueName,
      _kTaskName,
      frequency: const Duration(hours: 1),
      initialDelay: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      backoffPolicy: BackoffPolicy.exponential,
    );
  }

  /// разовое обновление прямо сейчас (например по кнопке)
  static Future<void> runOnce() async {
    await Workmanager().registerOneOffTask(
      '${_kTaskUniqueName}_manual',
      _kTaskName,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  /// отменить фоновую задачу (например когда выключили autoUpdate)
  static Future<void> cancel() async {
    await Workmanager().cancelByUniqueName(_kTaskUniqueName);
  }
}