import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_settings.dart';
import '../../providers/providers.dart';
import '../../services/vpn_engine.dart';
import '../../services/windows_desktop_service.dart';
import '../../shared/ui/app_theme.dart';

/// Переключение Proxy/TUN на desktop (sidebar и tray).
Future<void> applyDesktopConnectionMode(
  BuildContext context,
  WidgetRef ref,
  AppSettings settings,
  ConnectionMode next,
) async {
  if (next == settings.connectionModeEnum) return;

  final vpn = ref.read(vpnStateProvider).value;
  if (vpn?.status == VpnStatus.connected ||
      vpn?.status == VpnStatus.connecting) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.desktopDisconnectBeforeModeChange,
          ),
        ),
      );
    }
    return;
  }

  if (next == ConnectionMode.tun) {
    final elevated = await WindowsDesktopService.isProcessElevated();
    if (!elevated) {
      if (!context.mounted) return;
      final restart = await showDesktopTunAdminDialog(context);
      if (restart != true) return;

      await ref.read(settingsNotifierProvider.notifier).save(
            settings.copyWith(connectionMode: ConnectionMode.tun.storageValue),
          );
      final ok = await WindowsDesktopService.restartAsAdministrator();
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.desktopTunAdminRestartFailed,
            ),
          ),
        );
      }
      return;
    }
  }

  await ref.read(settingsNotifierProvider.notifier).save(
        settings.copyWith(connectionMode: next.storageValue),
      );
}

Future<bool?> showDesktopTunAdminDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.card(ctx),
      title: Text(
        l10n.desktopTunAdminTitle,
        style: TextStyle(color: AppTheme.text(ctx)),
      ),
      content: Text(
        l10n.desktopTunAdminMessage,
        style: TextStyle(
          color: AppTheme.textLight(ctx),
          height: 1.4,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.desktopTunAdminCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.desktopTunAdminRestart),
        ),
      ],
    ),
  );
}
