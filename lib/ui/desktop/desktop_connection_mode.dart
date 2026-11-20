import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_settings.dart';
import '../../providers/providers.dart';
import '../../services/vpn_engine.dart';
import '../../services/windows_desktop_service.dart';
import '../../services/windows_tun_service.dart';
import '../../shared/ui/app_theme.dart';
import '../../shared/ui/liquid_toast.dart';
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

  // на Linux права даёт pkexec при подключении, на Windows без прав TUN поднимает служба keqdroid
  if (next == ConnectionMode.tun && !await ensureWindowsTunService(context)) {
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
        AppSnack.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e, context))),
        );
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
        AppSnack.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e, context))),
        );
      }
    }
  }
}

// true: можно подключаться в TUN. без прав и без службы спрашивает и ставит её, Windows покажет окно UAC
Future<bool> ensureWindowsTunService(BuildContext context) async {
  if (!Platform.isWindows) return true;
  if (await WindowsDesktopService.isProcessElevated()) return true;
  final state = await WindowsTunService.state();
  if (state == TunServiceState.ready) return true;
  if (!context.mounted) return false;
  final install = await showDesktopTunServiceDialog(
    context,
    update: state == TunServiceState.outdated,
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

// автозапуск с правами оставляет выбранным TUN, а запуск руками идёт без них: перед подключением ставим службу
Future<bool> ensureTunReadyToConnect(
  BuildContext context,
  AppSettings? settings,
) async {
  if (!Platform.isWindows ||
      settings?.connectionModeEnum != ConnectionMode.tun) {
    return true;
  }
  return ensureWindowsTunService(context);
}

Future<bool?> showDesktopTunServiceDialog(
  BuildContext context, {
  required bool update,
}) {
  final l10n = AppLocalizations.of(context)!;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.card(ctx),
      title: Text(
        l10n.desktopTunServiceTitle,
        style: TextStyle(color: AppTheme.text(ctx)),
      ),
      content: Text(
        update
            ? l10n.desktopTunServiceUpdateMessage
            : l10n.desktopTunServiceMessage,
        style: TextStyle(
          color: AppTheme.textLight(ctx),
          height: 1.4,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.desktopTunServiceCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            update ? l10n.desktopTunServiceUpdate : l10n.desktopTunServiceInstall,
          ),
        ),
      ],
    ),
  );
}
