import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import '../core/app_logger.dart';
import '../utils/local_vpn_proxy.dart';
import '../utils/socks5_credentials.dart';
import 'expiry_reminder.dart';
import 'notification_service.dart';
import 'storage_service.dart';
import 'subscription_service.dart';

const _kTaskName       = 'subscription_update';
const _kTaskUniqueName = 'keqdis_sub_update_periodic';

const _kNotifChannelId   = 'keqdis_subscription';
const _kNotifChannelName = 'Subscription Updates';
const _kNotifId          = 42;

// без pragma tree-shaker выкинет функцию из релиза
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != _kTaskName) return true;

    try {
      // в фоновом изоляте без этого StorageService.init() падает с MissingPluginException
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();
      await AppLogger.instance.enableFileLog();

      final storage = await StorageService.init();

      // туннеля в этом изоляте нет: порт сессии читаем с диска, reload потому что писал другой изолят
      await storage.reloadFromDisk();
      final proxyPort = await resolveLocalProxyForBackground(
        storage.getActiveLocalHttpPort(),
      );
      // без пароля инбаунда каждое фоновое обновление при включённом VPN упиралось в 407
      final creds = storage.getActiveLocalHttpCredentials();
      Socks5Credentials().init(creds.username, creds.password);
      final service = SubscriptionService(storage, localProxyPort: proxyPort);

      final due = await service.getDueForUpdate(
        defaultInterval: const Duration(hours: 1),
      );
      if (due.isNotEmpty) {
        final results = await Future.wait(
          due.map(service.updateSubscription),
          eagerError: false,
        );

        final ok      = results.where((r) => r.success).length;
        final failed  = results.length - ok;
        final total   = results.fold(0, (sum, r) => sum + r.serverCount);

        final settings = await storage.getSettings();
        if (settings.notifySubscriptionUpdates) {
          await _showUpdateNotification(
            ok: ok,
            failed: failed,
            totalServers: total,
          );
        }
      }

      await remindExpiringSubscriptions(
        storage,
        await storage.getSubscriptions(),
        now: DateTime.now(),
        show: (sub, title, body) =>
            NotificationService.showSubscriptionNoticeInBackground(
          subscriptionId: sub.id,
          title: title,
          body: body,
        ),
      );

      return true;
    } catch (e, st) {
      AppLogger.instance.error(
        'Background subscription update task failed',
        error: e,
        stackTrace: st,
      );
      // false: workmanager повторит с нарастающей паузой
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

  const androidInit =
      AndroidInitializationSettings('@drawable/ic_notification');
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
        importance: Importance.low,
        priority: Priority.low,
        icon: '@drawable/ic_notification',
        playSound: false,
        enableVibration: false,
      ),
    ),
  );
}

class BackgroundService {

  static Future<void> init() async {
    await Workmanager().initialize(
      callbackDispatcher,
    );

    final plugin = FlutterLocalNotificationsPlugin();
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
  }

  // update: пересоздаём на каждом старте, чтобы вытащить задачу из подвисшего состояния
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

  static Future<void> runOnce() async {
    await Workmanager().registerOneOffTask(
      '${_kTaskUniqueName}_manual',
      _kTaskName,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  static Future<void> cancel() async {
    await Workmanager().cancelByUniqueName(_kTaskUniqueName);
  }
}