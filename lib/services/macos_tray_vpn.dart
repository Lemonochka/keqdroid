import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app.dart';
import '../providers/providers.dart';
import '../ui/desktop/desktop_connection_mode.dart';
import 'macos_background_service.dart';
import 'vpn_engine.dart';

class MacosTrayVpn {
  MacosTrayVpn(this._ref, this._tray);

  final Ref _ref;
  final MacosBackgroundService _tray;

  void init() {
    _tray.onToggleVpn = _toggle;
    _ref.listen(
      vpnStateProvider.select((a) => a.value?.status),
      (_, _) => _sync(),
    );
    _ref.listen(
      serversProvider.select((s) => s.activeServer != null),
      (_, _) => _sync(),
      fireImmediately: true,
    );
  }

  void dispose() => _tray.onToggleVpn = null;

  void _sync() => unawaited(
    _tray.setTrayVpn(
      status:
          _ref.read(vpnStateProvider).value?.status ?? VpnStatus.disconnected,
      hasServer: _ref.read(serversProvider).activeServer != null,
    ),
  );

  Future<void> _toggle() async {
    final status =
        _ref.read(vpnStateProvider).value?.status ?? VpnStatus.disconnected;
    final notifier = _ref.read(vpnStateProvider.notifier);
    switch (status) {
      case VpnStatus.connected:
        await notifier.disconnect();
      case VpnStatus.connecting:
        await notifier.cancelConnect();
      case VpnStatus.disconnecting:
        return;
      case VpnStatus.disconnected || VpnStatus.error:
        if (_ref.read(serversProvider).activeServer == null) return;
        final context = rootNavigatorKey.currentContext;
        if (context != null &&
            context.mounted &&
            !await ensureTunReadyToConnect(
              context,
              _ref.read(settingsNotifierProvider).value,
              showWindow: true,
            )) {
          return;
        }
        await notifier.connect();
    }
  }
}

final macosTrayVpnProvider = Provider<MacosTrayVpn?>((ref) {
  if (!Platform.isMacOS) return null;
  final vpn = MacosTrayVpn(ref, MacosBackgroundService.instance);
  ref.onDispose(vpn.dispose);
  vpn.init();
  return vpn;
});
