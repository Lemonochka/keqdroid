import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/core/app_logger.dart';
import 'package:keqdroid/providers/ui_state_providers.dart';
import 'package:keqdroid/tunnel/connection_mode.dart';
import 'package:keqdroid/tunnel/desktop_traffic_stats.dart';
import 'package:keqdroid/tunnel/tunnel_state.dart';

class _ProbeTrafficStats with DesktopTrafficStats {
  @override
  ConnectionMode? get activeMode => null;

  @override
  void emit(VpnState state) {}

  @override
  Future<void> pollTrafficStats(
    ConnectionMode mode, {
    bool force = false,
  }) async {}
}

void main() {
  testWidgets(
    'сворачивание окна на панель задач выключает desktopUiVisibleProvider и возвращает при развороте',
    (tester) async {
      final binding = tester.binding;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(
        () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed),
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(desktopUiVisibleProvider), isTrue);

      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      expect(container.read(desktopUiVisibleProvider), isFalse);

      // потеря фокуса при открытом окне шлёт inactive, тикеры от этого гаснуть не должны
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(container.read(desktopUiVisibleProvider), isTrue);

      container.read(desktopWindowVisibleProvider.notifier).set(false);
      expect(container.read(desktopUiVisibleProvider), isFalse);

      container.read(desktopWindowVisibleProvider.notifier).set(true);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(container.read(desktopUiVisibleProvider), isTrue);
    },
  );

  test(
    'лог опроса трафика различает сворачивание на панель и уход в трей',
    () async {
      final dir = Directory.systemTemp.createTempSync('visibility_lifecycle');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      AppLogger.instance.enableFileLogIn(dir);
      final stats = _ProbeTrafficStats();

      stats.setTrafficStatsPollingEnabled(false, reason: 'window minimized');
      stats.setTrafficStatsPollingEnabled(true, reason: 'window shown');
      stats.setTrafficStatsPollingEnabled(false, reason: 'hidden to tray');

      final lines = (await AppLogger.instance.readFileLog()).split('\n');
      expect(
        lines,
        containsAllInOrder([
          contains('traffic polling paused: window minimized'),
          contains('traffic polling resumed: window shown'),
          contains('traffic polling paused: hidden to tray'),
        ]),
      );
    },
  );
}
