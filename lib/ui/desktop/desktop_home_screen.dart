import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/desktop_background_service.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_settings.dart';
import '../../providers/providers.dart';
import '../../screens/servers_tab.dart';
import '../../screens/settings_tab.dart';
import '../../screens/subscriptions_tab.dart';
import '../../services/update_service.dart';
import '../../services/vpn_engine.dart';
import '../../services/windows_desktop_service.dart';
import '../../shared/ui/app_theme.dart';
import '../../shared/ui/update_dialog.dart';

/// desktop shell: фиксированный sidebar + вкладки (без NavigationRail — на windows ломается layout)
class DesktopHomeScreen extends ConsumerStatefulWidget {
  const DesktopHomeScreen({super.key});

  @override
  ConsumerState<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends ConsumerState<DesktopHomeScreen>
    with WidgetsBindingObserver {
  int _index = 0;
  bool _updatePromptShown = false;
  bool _startupTasksDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(homeTabIndexProvider.notifier).state = _index;
      ref.read(homeTabPageProvider.notifier).state = _index.toDouble();
      ref.read(updateInfoProvider);
      unawaited(_runWindowsStartupTasks());
    });
  }

  Future<void> _runWindowsStartupTasks() async {
    if (!Platform.isWindows || _startupTasksDone) return;
    _startupTasksDone = true;

    final storage = ref.read(storageProvider);
    final settings = await storage.getSettings();
    await WindowsDesktopService.applySettings(settings);

    if (!WindowsDesktopService.isAutostartLaunch) return;
    if (!settings.launchAtStartup || !settings.autoConnectLastServer) return;

    await ref.read(serversProvider.notifier).reloadPreservingActive();
    if (!mounted) return;

    final active = ref.read(serversProvider).activeServer;
    if (active == null) return;

    final vpn = ref.read(vpnStateProvider).valueOrNull;
    if (vpn?.status == VpnStatus.connected ||
        vpn?.status == VpnStatus.connecting) {
      return;
    }

    await ref.read(vpnStateProvider.notifier).connect(autostartTunFallback: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(DesktopBackgroundService.onAppResumed());
    }
  }

  void _selectTab(int index) {
    if (_index == index) return;
    setState(() => _index = index);
    ref.read(homeTabIndexProvider.notifier).state = index;
    ref.read(homeTabPageProvider.notifier).state = index.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    ref.listen<AsyncValue<UpdateInfo?>>(updateInfoProvider, (prev, next) {
      if (_updatePromptShown) return;
      final info = next.valueOrNull;
      if (info == null) return;
      _updatePromptShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showUpdateDialog(context, info);
      });
    });

    final destinations = [
      (icon: Icons.dns_outlined, label: l10n.navServers),
      (icon: Icons.subscriptions_outlined, label: l10n.navSubscriptions),
      (icon: Icons.settings_outlined, label: l10n.navSettings),
    ];

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: SizedBox(
              width: MediaQuery.sizeOf(context).width >= 900 ? 220.0 : 76.0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  if (Platform.isWindows) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: MediaQuery.sizeOf(context).width >= 900
                          ? const _ConnectionModeChip()
                          : const Center(child: _ConnectionModeMenuButton()),
                    ),
                    const SizedBox(height: 12),
                    Divider(height: 1, color: AppTheme.divider(context)),
                    const SizedBox(height: 8),
                  ],
                  for (var i = 0; i < destinations.length; i++)
                    _SidebarTile(
                      icon: destinations[i].icon,
                      label: destinations[i].label,
                      selected: _index == i,
                      compact: MediaQuery.sizeOf(context).width < 900,
                      onTap: () => _selectTab(i),
                    ),
                  const Spacer(),
                ],
              ),
            ),
          ),
          VerticalDivider(width: 1, color: AppTheme.divider(context)),
          Expanded(
            child: IndexedStack(
              index: _index,
              sizing: StackFit.expand,
              children: const [
                _DesktopTabHost(child: ServersTab()),
                _DesktopTabHost(child: SubscriptionsTab()),
                _DesktopTabHost(child: SettingsTab()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// bounded constraints для корней вкладок (нужно в IndexedStack)
class _DesktopTabHost extends StatelessWidget {
  final Widget child;
  const _DesktopTabHost({required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppTheme.bg(context),
      child: SizedBox.expand(child: child),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fg = selected ? colorScheme.onSecondaryContainer : colorScheme.onSurfaceVariant;
    final bg = selected ? colorScheme.secondaryContainer : Colors.transparent;

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Tooltip(
          message: label,
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 48,
                child: Icon(icon, color: fg),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: fg, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: fg,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionModeMenuButton extends ConsumerWidget {
  const _ConnectionModeMenuButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsNotifierProvider).valueOrNull ?? const AppSettings();
    final mode = settings.connectionModeEnum;

    return PopupMenuButton<ConnectionMode>(
      tooltip: AppLocalizations.of(context)!.desktopConnectionMode,
      icon: Icon(
        mode == ConnectionMode.tun ? Icons.vpn_lock_outlined : Icons.lan_outlined,
        size: 22,
      ),
      onSelected: (next) => _applyMode(context, ref, settings, next),
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: ConnectionMode.proxy,
          checked: mode == ConnectionMode.proxy,
          child: const Text('Proxy'),
        ),
        CheckedPopupMenuItem(
          value: ConnectionMode.tun,
          checked: mode == ConnectionMode.tun,
          child: const Text('TUN'),
        ),
      ],
    );
  }
}

class _ConnectionModeChip extends ConsumerWidget {
  const _ConnectionModeChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsNotifierProvider).valueOrNull ?? const AppSettings();
    final mode = settings.connectionModeEnum;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppLocalizations.of(context)!.desktopModeShort,
          style: TextStyle(fontSize: 11, color: AppTheme.textLight(context)),
        ),
        const SizedBox(height: 6),
        SegmentedButton<ConnectionMode>(
          segments: const [
            ButtonSegment(
              value: ConnectionMode.proxy,
              label: Text('Proxy'),
              icon: Icon(Icons.lan_outlined, size: 16),
            ),
            ButtonSegment(
              value: ConnectionMode.tun,
              label: Text('TUN'),
              icon: Icon(Icons.vpn_lock_outlined, size: 16),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (selected) {
            _applyMode(context, ref, settings, selected.first);
          },
        ),
      ],
    );
  }
}

Future<void> _applyMode(
  BuildContext context,
  WidgetRef ref,
  AppSettings settings,
  ConnectionMode next,
) async {
  if (next == settings.connectionModeEnum) return;

  final vpn = ref.read(vpnStateProvider).valueOrNull;
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
      final l10n = AppLocalizations.of(context)!;
      final restart = await showDialog<bool>(
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
      if (restart != true) return;

      await ref.read(settingsNotifierProvider.notifier).save(
            settings.copyWith(connectionMode: ConnectionMode.tun.storageValue),
          );
      final ok = await WindowsDesktopService.restartAsAdministrator();
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.desktopTunAdminRestartFailed)),
        );
      }
      return;
    }
  }

  await ref.read(settingsNotifierProvider.notifier).save(
        settings.copyWith(connectionMode: next.storageValue),
      );
}
