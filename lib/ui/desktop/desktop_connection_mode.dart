import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_settings.dart';
import '../../providers/providers.dart';
import '../../services/macos_background_service.dart';
import '../../services/macos_tun_service.dart';
import '../../services/vpn_engine.dart';
import '../../services/windows_desktop_service.dart';
import '../../services/windows_tun_service.dart';
import '../../shared/ui/app_theme.dart';
import '../../shared/ui/liquid_toast.dart';
import '../../tunnel/macos_elevation.dart';
import '../../utils/error_messages.dart';

// у Ref и WidgetRef нет общего предка, а меню трея знает только Ref, поэтому зависимости явно
class DesktopModeDeps {
  const DesktopModeDeps({
    required this.vpn,
    required this.settings,
    required this.status,
  });

  final VpnStateNotifier vpn;
  final SettingsNotifier settings;

  // функцией: статус перечитывается после await
  final VpnStatus? Function() status;

  factory DesktopModeDeps.of(WidgetRef ref) => DesktopModeDeps(
    vpn: ref.read(vpnStateProvider.notifier),
    settings: ref.read(settingsNotifierProvider.notifier),
    status: () => ref.read(vpnStateProvider).value?.status,
  );

  factory DesktopModeDeps.ofRef(Ref ref) => DesktopModeDeps(
    vpn: ref.read(vpnStateProvider.notifier),
    settings: ref.read(settingsNotifierProvider.notifier),
    status: () => ref.read(vpnStateProvider).value?.status,
  );
}

Future<void> applyDesktopConnectionMode(
  BuildContext context,
  DesktopModeDeps deps,
  AppSettings settings,
  ConnectionMode next,
) async {
  if (next == settings.connectionModeEnum) return;

  // на Linux права даёт pkexec при подключении, на Windows и macOS без прав TUN поднимает служба keqdroid
  if (next == ConnectionMode.tun && !await ensureDesktopTunService(context)) {
    return;
  }
  if (!context.mounted) return;

  final status = deps.status();
  final wasActive =
      status == VpnStatus.connected || status == VpnStatus.connecting;
  if (wasActive) {
    try {
      await deps.vpn.disconnect();
    } catch (e) {
      if (context.mounted) {
        AppSnack.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
      }
      return;
    }
  }
  await deps.settings.save(
    settings.copyWith(
      connectionMode: next.storageValue,
      connectionModeChosen: true,
    ),
  );
  if (wasActive) {
    try {
      await deps.vpn.connect();
    } catch (e) {
      if (context.mounted) {
        AppSnack.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
      }
    }
  }
}

Future<bool> ensureDesktopTunService(
  BuildContext context, {
  bool showWindow = false,
}) async {
  if (Platform.isWindows) {
    return ensureWindowsTunService(context, showWindow: showWindow);
  }
  if (Platform.isMacOS) {
    return ensureMacosTunService(context, showWindow: showWindow);
  }
  return true;
}

// true: можно подключаться в TUN. без прав и без службы спрашивает и ставит её, Windows покажет окно UAC.
// showWindow: окно может лежать в трее, и вопрос в нём никто бы не увидел
Future<bool> ensureWindowsTunService(
  BuildContext context, {
  bool showWindow = false,
}) async {
  if (!Platform.isWindows) return true;
  if (await WindowsDesktopService.isProcessElevated()) return true;
  final state = await WindowsTunService.state();
  if (state == TunServiceState.ready) return true;
  if (showWindow) await WindowsDesktopService.restoreMainWindow();
  if (!context.mounted) return false;
  final install = await showDesktopTunServiceDialog(
    context,
    update: state == TunServiceState.outdated,
    macos: false,
  );
  if (install != true) return false;
  final result = await WindowsTunService.install();
  if (result.ok && await WindowsTunService.state() == TunServiceState.ready) {
    return true;
  }
  if (!result.cancelled && context.mounted) {
    AppSnack.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.desktopTunServiceFailed),
      ),
    );
  }
  return false;
}

Future<bool> ensureMacosTunService(
  BuildContext context, {
  bool showWindow = false,
  Future<void> Function()? restoreWindow,
}) async {
  if (!MacosTunService.isAvailable) return true;
  if (macosRunningAsRoot()) return true;
  final state = await MacosTunService.state();
  if (state == TunServiceState.ready) return true;
  if (showWindow) {
    await (restoreWindow ??
        MacosBackgroundService.instance.restoreMainWindow)();
  }
  if (!context.mounted) return false;
  final install = await showDesktopTunServiceDialog(
    context,
    update: state == TunServiceState.outdated,
    macos: true,
  );
  if (install != true) return false;
  final result = await MacosTunService.install();
  if (result.ok && await _waitForMacosTunReady()) {
    return true;
  }
  if (!result.cancelled && context.mounted) {
    AppSnack.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.desktopTunServiceFailed),
      ),
    );
  }
  return false;
}

Future<bool> _waitForMacosTunReady() async {
  for (var attempt = 0; attempt < 5; attempt++) {
    if (await MacosTunService.state() == TunServiceState.ready) return true;
    if (attempt < 4) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }
  return false;
}

// автозапуск с правами оставляет выбранным TUN, а запуск руками идёт без них: перед подключением ставим службу
Future<bool> ensureTunReadyToConnect(
  BuildContext context,
  AppSettings? settings, {
  bool showWindow = false,
}) async {
  if (settings?.connectionModeEnum != ConnectionMode.tun) {
    return true;
  }
  return ensureDesktopTunService(context, showWindow: showWindow);
}

// без службы connect на старте молча уходил в Proxy и запоминал его, а про службу так и не спрашивал.
// отказ в окне ведёт туда же, в Proxy
Future<void> connectOnStartup(
  BuildContext context, {
  required AppSettings? settings,
  required VpnStateNotifier vpn,
  required VpnStatus? Function() status,
}) async {
  await ensureTunReadyToConnect(context, settings, showWindow: true);
  if (!context.mounted) return;
  final now = status();
  if (now == VpnStatus.connected || now == VpnStatus.connecting) return;
  await vpn.connect(autostartTunFallback: true);
}

Future<bool?> showDesktopTunServiceDialog(
  BuildContext context, {
  required bool update,
  bool? macos,
}) {
  final l10n = AppLocalizations.of(context)!;
  final isMacos = macos ?? Platform.isMacOS;
  final body = switch ((isMacos, update)) {
    (true, true) => l10n.desktopTunServiceUpdateMessageMacos,
    (true, false) => l10n.desktopTunServiceMessageMacos,
    (false, true) => l10n.desktopTunServiceUpdateMessage,
    (false, false) => l10n.desktopTunServiceMessage,
  };
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.card(ctx),
      title: Text(
        l10n.desktopTunServiceTitle,
        style: TextStyle(color: AppTheme.text(ctx)),
      ),
      content: Text(
        body,
        style: TextStyle(color: AppTheme.textLight(ctx), height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.desktopTunServiceCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            update
                ? l10n.desktopTunServiceUpdate
                : l10n.desktopTunServiceInstall,
          ),
        ),
      ],
    ),
  );
}
