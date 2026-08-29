import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_settings.dart';
import '../../providers/providers.dart';
import '../../services/vpn_engine.dart';
import '../../services/windows_desktop_service.dart';
import '../../shared/ui/app_theme.dart';
import '../../utils/error_messages.dart';

/// Переключение Proxy/TUN на desktop (sidebar, tray, хоткей).
/// При активном туннеле режим меняется с автоматическим переподключением
/// (disconnect → save → connect) — как это всегда делал хоткей, вместо
/// отказа «сначала отключитесь».
Future<void> applyDesktopConnectionMode(
  BuildContext context,
  WidgetRef ref,
  AppSettings settings,
  ConnectionMode next,
) async {
  if (next == settings.connectionModeEnum) return;

  // Linux elevates per-connect via pkexec (sing-box), so only Windows needs
  // the relaunch-as-admin flow before switching to TUN.
  if (next == ConnectionMode.tun && Platform.isWindows) {
    final elevated = await WindowsDesktopService.isProcessElevated();
    if (!elevated) {
      if (!context.mounted) return;
      final restart = await showDesktopTunAdminDialog(context);
      if (restart != true) return;

      await stopSessionBeforeElevation(
        notifier: ref.read(vpnStateProvider.notifier),
        status: ref.read(vpnStateProvider).value?.status,
      );
      await ref.read(settingsNotifierProvider.notifier).save(
            settings.copyWith(
              connectionMode: ConnectionMode.tun.storageValue,
              connectionModeChosen: true,
            ),
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

  final status = ref.read(vpnStateProvider).value?.status;
  final wasActive =
      status == VpnStatus.connected || status == VpnStatus.connecting;
  if (wasActive) {
    try {
      await ref.read(vpnStateProvider.notifier).disconnect();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e, context))),
        );
      }
      return;
    }
  }
  await ref.read(settingsNotifierProvider.notifier).save(
        settings.copyWith(
          connectionMode: next.storageValue,
          connectionModeChosen: true,
        ),
      );
  if (wasActive) {
    try {
      await ref.read(vpnStateProvider.notifier).connect();
    } catch (e) {
      // Ошибка уже лежит в state (её покажет круг подключения); снекбар —
      // немедленная подсказка, если пользователь смотрит на sidebar/трей.
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e, context))),
        );
      }
    }
  }
}

/// Рвёт активный туннель перед перезапуском с правами администратора.
///
/// `restartAsAdministrator` просто вызывает PostQuitMessage и процесс умирает,
/// ничего не остановив: без этого keqrnel proxy-сессии оставался жить (новый
/// elevated-экземпляр поднимался раньше, чем умирал старый, и держал job object
/// открытым), а системный прокси Windows продолжал указывать на порт, который
/// вот-вот исчезнет. Нотифаер и статус передаются значениями: в трее вызов идёт
/// уже после демонтажа меню, когда `ref` мёртв. Ошибку глотаем — перезапуск
/// важнее, остатки подберёт стартовая зачистка (initCoreProcessGuard).
Future<void> stopSessionBeforeElevation({
  required VpnStateNotifier notifier,
  required VpnStatus? status,
}) async {
  if (status != VpnStatus.connected && status != VpnStatus.connecting) return;
  try {
    await notifier.disconnect();
  } catch (_) {}
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
