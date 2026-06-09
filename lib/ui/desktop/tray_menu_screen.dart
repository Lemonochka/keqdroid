import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_settings.dart';
import '../../models/server_item.dart';
import '../../providers/providers.dart';
import '../../services/vpn_engine.dart';
import '../../services/windows_desktop_service.dart';
import 'desktop_connection_mode.dart';

/// Минималистичное меню трея (как Discord): узкая колонка, тема приложения.
class TrayMenuScreen extends ConsumerStatefulWidget {
  const TrayMenuScreen({super.key});

  static const width = 268.0;
  static const borderRadius = 10.0;
  static const itemHeight = 34.0;
  static const maxServerListHeight = 132.0;

  static double estimateHeight({
    required int serverCount,
    required bool serversExpanded,
  }) {
    const header = 42.0;
    const status = 28.0;
    const connect = itemHeight;
    const modes = itemHeight * 2;
    const footer = itemHeight * 2;
    const dividers = 3.0 * 3;
    const padding = 8.0;

    var serverBlock = itemHeight;
    if (serversExpanded && serverCount > 0) {
      serverBlock += math.min(
        serverCount * itemHeight,
        maxServerListHeight,
      );
    }

    return header +
        status +
        connect +
        modes +
        serverBlock +
        footer +
        dividers +
        padding;
  }

  @override
  ConsumerState<TrayMenuScreen> createState() => _TrayMenuScreenState();
}

class _TrayMenuScreenState extends ConsumerState<TrayMenuScreen> {
  bool _busy = false;
  bool _serversExpanded = false;

  Future<void> _closeMenu() async {
    ref.read(trayMenuVisibleProvider.notifier).set(false);
    if (Platform.isWindows) {
      await WindowsDesktopService.hideTrayMenu();
    }
  }

  Future<void> _syncPopupSize(int serverCount) async {
    if (!Platform.isWindows) return;
    await WindowsDesktopService.resizeTrayMenu(
      width: TrayMenuScreen.width,
      height: TrayMenuScreen.estimateHeight(
        serverCount: serverCount,
        serversExpanded: _serversExpanded,
      ),
    );
  }

  Future<void> _openFullApp() async {
    await _closeMenu();
    if (Platform.isWindows) {
      await WindowsDesktopService.restoreMainWindow();
    }
  }

  Future<void> _exitApp() async {
    await _closeMenu();
    if (Platform.isWindows) {
      await WindowsDesktopService.exitApp();
    }
  }

  Future<void> _toggleServersExpanded(int serverCount) async {
    setState(() => _serversExpanded = !_serversExpanded);
    await _syncPopupSize(serverCount);
  }

  Future<void> _toggleVpn(VpnStatus status) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (status == VpnStatus.connected || status == VpnStatus.connecting) {
        await ref.read(vpnStateProvider.notifier).disconnect();
      } else {
        final active = ref.read(serversProvider).activeServer;
        if (active == null) return;
        await ref.read(vpnStateProvider.notifier).connect();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectServer(ServerItem server, int serverCount) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(serversProvider.notifier).setActive(server);
      final vpnStatus = ref.read(vpnStateProvider).value?.status;
      if (vpnStatus == VpnStatus.connected ||
          vpnStatus == VpnStatus.connecting) {
        await ref.read(vpnStateProvider.notifier).reconnectToActiveServer();
      }
      if (_serversExpanded && mounted) {
        setState(() => _serversExpanded = false);
        await _syncPopupSize(serverCount);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onModeSelected(
    ConnectionMode next,
    AppSettings settings,
  ) async {
    if (next == settings.connectionModeEnum) return;

    if (next == ConnectionMode.tun) {
      final elevated = await WindowsDesktopService.isProcessElevated();
      if (!elevated) {
        await _closeMenu();
        if (Platform.isWindows) {
          await WindowsDesktopService.restoreMainWindow();
        }
        if (!mounted) return;
        final restart = await showDesktopTunAdminDialog(context);
        if (restart != true || !mounted) return;
        await ref.read(settingsNotifierProvider.notifier).save(
              settings.copyWith(connectionMode: ConnectionMode.tun.storageValue),
            );
        final ok = await WindowsDesktopService.restartAsAdministrator();
        if (!ok && mounted) {
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

    if (!mounted) return;
    await applyDesktopConnectionMode(context, ref, settings, next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();
    final mode = settings.connectionModeEnum;
    final serversState = ref.watch(serversProvider);
    final servers = serversState.servers;
    final active = serversState.activeServer;
    final vpn = ref.watch(vpnStateProvider).value;
    final status = vpn?.status ?? VpnStatus.disconnected;
    final isVpnBusy = _busy ||
        status == VpnStatus.connecting ||
        status == VpnStatus.disconnecting;

    final isConnected =
        status == VpnStatus.connected || status == VpnStatus.connecting;
    final canConnect = active != null && !isVpnBusy;

    final statusLabel = switch (status) {
      VpnStatus.connected => l10n.trayStatusConnected,
      VpnStatus.connecting => l10n.vpnConnecting,
      VpnStatus.disconnecting => l10n.vpnDisconnecting,
      VpnStatus.error => l10n.trayStatusError,
      _ => l10n.trayStatusDisconnected,
    };

    final menuBg = colorScheme.surfaceContainerHigh;
    final itemFg = colorScheme.onSurface;
    final mutedFg = colorScheme.onSurfaceVariant;

    return SizedBox.expand(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(TrayMenuScreen.borderRadius),
        child: ColoredBox(
          color: menuBg,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Text(
                l10n.trayMenuTitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: mutedFg,
                  fontSize: 13,
                ),
              ),
            ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                child: Text(
                  statusLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: mutedFg,
                    fontSize: 12,
                  ),
                ),
              ),
              const _TrayDivider(),
              _TrayItem(
                label: isConnected ? l10n.trayDisconnect : l10n.trayConnect,
                enabled: isConnected ? !isVpnBusy : canConnect,
                onTap: () => _toggleVpn(status),
                foregroundColor: itemFg,
              ),
              const _TrayDivider(),
              _TrayItem(
                label: l10n.trayModeProxy,
                enabled: !isVpnBusy,
                selected: mode == ConnectionMode.proxy,
                onTap: () => _onModeSelected(ConnectionMode.proxy, settings),
                foregroundColor: itemFg,
                accentColor: colorScheme.primary,
              ),
              _TrayItem(
                label: l10n.trayModeTun,
                enabled: !isVpnBusy,
                selected: mode == ConnectionMode.tun,
                onTap: () => _onModeSelected(ConnectionMode.tun, settings),
                foregroundColor: itemFg,
                accentColor: colorScheme.primary,
              ),
              const _TrayDivider(),
              _TrayItem(
                label: active?.displayName ?? l10n.trayPickServer,
                enabled: !isVpnBusy && servers.isNotEmpty,
                trailing: servers.length > 1
                    ? Icon(
                        _serversExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 18,
                        color: mutedFg,
                      )
                    : null,
                onTap: servers.length > 1
                    ? () => _toggleServersExpanded(servers.length)
                    : null,
                foregroundColor: itemFg,
                maxLines: 1,
              ),
              if (_serversExpanded && servers.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: TrayMenuScreen.maxServerListHeight,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: servers.length,
                    itemBuilder: (context, index) {
                      final server = servers[index];
                      final selected = server.id == active?.id;
                      return _TrayItem(
                        label: server.displayName,
                        enabled: !isVpnBusy,
                        selected: selected,
                        indent: 12,
                        onTap: () => _selectServer(server, servers.length),
                        foregroundColor: itemFg,
                        accentColor: colorScheme.primary,
                        maxLines: 1,
                      );
                    },
                  ),
                ),
              const _TrayDivider(),
              _TrayItem(
                label: l10n.trayOpenApp,
                onTap: _openFullApp,
                foregroundColor: itemFg,
              ),
              _TrayItem(
                label: l10n.trayExit,
                onTap: _exitApp,
                foregroundColor: colorScheme.error,
              ),
            const SizedBox(height: 4),
          ],
        ),
      ),
      ),
    );
  }
}

class _TrayDivider extends StatelessWidget {
  const _TrayDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.35),
    );
  }
}

class _TrayItem extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  final bool selected;
  final double indent;
  final Widget? trailing;
  final Color foregroundColor;
  final Color? accentColor;
  final int maxLines;

  const _TrayItem({
    required this.label,
    required this.foregroundColor,
    this.onTap,
    this.enabled = true,
    this.selected = false,
    this.indent = 0,
    this.trailing,
    this.accentColor,
    this.maxLines = 2,
  });

  @override
  Widget build(BuildContext context) {
    final fg = enabled ? foregroundColor : foregroundColor.withValues(alpha: 0.38);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: SizedBox(
          height: TrayMenuScreen.itemHeight,
          child: Padding(
            padding: EdgeInsets.fromLTRB(14 + indent, 0, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: fg,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (selected && accentColor != null)
                  Icon(Icons.check, size: 16, color: accentColor),
                if (trailing != null) ...[
                  const SizedBox(width: 4),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
