import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../models/server_item.dart';
import '../providers/providers.dart';
import '../services/ping_service.dart';
import 'vpn_native_bridge.dart';

// виджет рабочего стола рисует лаунчер без Flutter: тему и сервер он знает только из того, что прислали отсюда
Map<String, int> homeWidgetColors(ColorScheme s) => {
      'surfaceContainer': s.surfaceContainer.toARGB32(),
      'surfaceContainerHighest': s.surfaceContainerHighest.toARGB32(),
      'onSurface': s.onSurface.toARGB32(),
      'onSurfaceVariant': s.onSurfaceVariant.toARGB32(),
      'primary': s.primary.toARGB32(),
      'onPrimary': s.onPrimary.toARGB32(),
      'primaryContainer': s.primaryContainer.toARGB32(),
      'onPrimaryContainer': s.onPrimaryContainer.toARGB32(),
      'secondaryContainer': s.secondaryContainer.toARGB32(),
      'onSecondaryContainer': s.onSecondaryContainer.toARGB32(),
      'error': s.error.toARGB32(),
      'errorContainer': s.errorContainer.toARGB32(),
      'onErrorContainer': s.onErrorContainer.toARGB32(),
    };

// key это сырое имя: по нему натив узнаёт, тот ли это сервер, что в последней сессии
typedef HomeWidgetServer = ({
  String key,
  String name,
  String? countryCode,
  String? ping,
});

HomeWidgetServer? homeWidgetServer(ServerItem? server, AppSettings settings) {
  if (server == null) return null;
  final type = PingService.pingColorTypeForServer(server, settings);
  final ping = server.pingMs;
  return (
    key: server.displayName,
    name: server.cleanName,
    countryCode: server.countryCode,
    // у замера скорости в pingMs килобиты, это не пинг
    ping: ping != null && type != PingType.speed
        ? PingService.formatPingValue(ping, type)
        : null,
  );
}

final homeWidgetServerProvider = Provider<HomeWidgetServer?>((ref) {
  final server = ref.watch(serversProvider.select((s) => s.activeServer));
  final settings =
      ref.watch(settingsNotifierProvider).value ?? const AppSettings();
  return homeWidgetServer(server, settings);
});

final homeWidgetSyncProvider = Provider<void>((ref) {
  if (!Platform.isAndroid) return;
  ref.listen(homeWidgetServerProvider, (_, next) {
    if (next == null) return;
    unawaited(VpnNativeBridge.updateHomeWidget(server: {
      'key': next.key,
      'name': next.name,
      'flag': next.countryCode,
      'ping': next.ping,
    }));
  }, fireImmediately: true);
});
