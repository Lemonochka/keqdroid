// vpn-уведомление в шторке с кнопками connect/disconnect.
// init() в main() после BackgroundService.init(), дальше updateStatus() по смене состояния.

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/app_logger.dart';
import 'vpn_engine.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;

  static const _channelId   = 'keqdis_vpn_control';
  static const _channelName = 'VPN Control';
  static const _notifId     = 1338;

  FlutterLocalNotificationsPlugin? _plugin;
  bool _initialized = false;
  VpnState? _lastState;

  /// init, один раз после BackgroundService.init()
  static Future<void> init() async {
    final ns = instance;
    if (ns._initialized) return;

    final plugin = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await plugin.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    ns._plugin = plugin;
    ns._initialized = true;

    // разрешение на Android 13+
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
  }

  /// шторка со статусом vpn
  static Future<void> showNotification({
    required VpnState state,
    String? serverName,
  }) async {
    final ns = instance;
    if (!ns._initialized || ns._plugin == null) {
      AppLogger.instance.warn('NotificationService not initialized');
      return;
    }

    final plugin = ns._plugin!;
    ns._lastState = state;

    final (title, body, isConnected) = _buildContent(state, serverName);

    // берём стандартную mipmap иконку
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'VPN connection control and status',
      importance: Importance.low,
      priority: Priority.low,
      icon: '@mipmap/ic_launcher',
      ongoing: isConnected,
      autoCancel: !isConnected,
      // нужно для кнопок-действий
      playSound: false,
      enableVibration: false,
      showWhen: false,
      category: AndroidNotificationCategory.service,
      visibility: NotificationVisibility.public,
      actions: _buildActions(state),
      styleInformation: BigTextStyleInformation(body),
    );

    await plugin.show(
      _notifId,
      title,
      body,
      NotificationDetails(android: androidDetails),
    );
  }

  /// то же showNotification, для удобства
  static Future<void> updateStatus(VpnState state, {String? serverName}) async {
    await showNotification(state: state, serverName: serverName);
  }

  /// убрать из шторки
  static Future<void> hideNotification() async {
    final ns = instance;
    if (!ns._initialized || ns._plugin == null) return;
    await ns._plugin!.cancel(_notifId);
  }

  /// Отменяет уведомление и освобождает ресурсы.
  static Future<void> dispose() async {
    final ns = instance;
    if (!ns._initialized || ns._plugin == null) return;
    await ns._plugin!.cancelAll();
    ns._initialized = false;
    ns._plugin = null;
  }

  // private

  static (String title, String body, bool isConnected) _buildContent(
    VpnState state,
    String? serverName,
  ) {
    final server = serverName != null ? ' · $serverName' : '';
    final status = state.status;

    return switch (status) {
      VpnStatus.connected => (
        'VPN Connected$server',
        _formatConnectedBody(state),
        true,
      ),
      VpnStatus.connecting => (
        'Connecting…',
        serverName ?? 'Establishing connection',
        false,
      ),
      VpnStatus.disconnecting => (
        'Disconnecting…',
        serverName ?? 'Stopping VPN',
        false,
      ),
      VpnStatus.error => (
        'VPN Error',
        state.errorMessage ?? 'Connection failed',
        false,
      ),
      VpnStatus.disconnected => (
        'VPN Disconnected',
        'Tap to connect',
        false,
      ),
    };
  }

  static String _formatConnectedBody(VpnState state) {
    final parts = <String>[];

    if (state.duration != null) {
      parts.add(_formatDuration(state.duration!));
    }

    if (state.downloadSpeed != null && state.downloadSpeed! > 0) {
      parts.add('↓ ${_formatSpeed(state.downloadSpeed!)}');
    }
    if (state.uploadSpeed != null && state.uploadSpeed! > 0) {
      parts.add('↑ ${_formatSpeed(state.uploadSpeed!)}');
    }

    return parts.isEmpty ? 'Connected' : parts.join('  ·  ');
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  static String _formatSpeed(int bytesPerSec) {
    if (bytesPerSec < 1024) return '$bytesPerSec B/s';
    if (bytesPerSec < 1024 * 1024) return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  static List<AndroidNotificationAction> _buildActions(VpnState state) {
    final isConnected = state.status == VpnStatus.connected;
    final isConnecting = state.status == VpnStatus.connecting ||
                         state.status == VpnStatus.disconnecting;

    if (isConnecting) {
      return []; // во время переключения кнопки не показываем
    }

    if (isConnected) {
      return [
        const AndroidNotificationAction(
          'action_disconnect',
          'Disconnect',
          showsUserInterface: true,
        ),
      ];
    } else {
      return [
        const AndroidNotificationAction(
          'action_connect',
          'Connect',
          showsUserInterface: true,
        ),
      ];
    }
  }

  static void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    final actionId = response.actionId;

    AppLogger.instance.debug(
      'Notification tap: action=$actionId payload=$payload',
    );

    // обработка кнопок из уведомления
    if (actionId == 'action_connect') {
      _handleConnect();
    } else if (actionId == 'action_disconnect') {
      _handleDisconnect();
    }
    // тап по самому уведомлению открывает приложение (contentIntent на android)
  }

  static Future<void> _handleConnect() async {
    try {
      // само подключение идёт через провайдер VPN, тут только сигнал
      const channel = MethodChannel('keqdis_vpn_channel');
      AppLogger.instance.debug('VPN connect action from notification');
    } catch (e, st) {
      AppLogger.instance.error('Failed to handle connect action', error: e, stackTrace: st);
    }
  }

  static Future<void> _handleDisconnect() async {
    try {
      const channel = MethodChannel('keqdis_vpn_channel');
      await channel.invokeMethod('stopVpn');
      AppLogger.instance.debug('VPN disconnect action from notification');
    } catch (e, st) {
      AppLogger.instance.error('Failed to handle disconnect action', error: e, stackTrace: st);
    }
  }
}