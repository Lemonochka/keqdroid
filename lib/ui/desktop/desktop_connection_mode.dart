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

/// То немногое из провайдеров, что нужно переключателю режима.
///
/// Раньше сюда передавался `WidgetRef`. Но зовёт эту функцию не только экран:
/// меню трея на Windows живёт в провайдере, и у него есть только `Ref`. Общего
/// предка у `Ref` и `WidgetRef` нет, а принять сам `ref.read` мешает то, что
/// `ProviderListenable` из flutter_riverpod наружу не экспортируется. Поэтому
/// зависимости передаются явно — заодно видно, что функция вообще трогает.
class DesktopModeDeps {
  const DesktopModeDeps({
    required this.vpn,
    required this.settings,
    required this.status,
  });

  final VpnStateNotifier vpn;
  final SettingsNotifier settings;

  /// Функцией, а не значением: статус перечитывается после await'ов.
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

/// Переключение Proxy/TUN на desktop (sidebar, tray, хоткей).
/// При активном туннеле режим меняется с автоматическим переподключением
/// (disconnect → save → connect) — как это всегда делал хоткей, вместо
/// отказа «сначала отключитесь».
Future<void> applyDesktopConnectionMode(
  BuildContext context,
  DesktopModeDeps deps,
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
        notifier: deps.vpn,
        status: deps.status(),
      );
      await deps.settings.save(
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

  final status = deps.status();
  final wasActive =
      status == VpnStatus.connected || status == VpnStatus.connecting;
  if (wasActive) {
    try {
      await deps.vpn.disconnect();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
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
