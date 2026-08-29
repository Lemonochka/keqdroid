import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_logger.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_settings.dart';
import '../../models/server_item.dart';
import '../../providers/providers.dart';
import '../../services/vpn_engine.dart';
import '../../services/windows_desktop_service.dart';
import '../../shared/ui/server_avatar.dart';
import 'desktop_connection_mode.dart';

/// Минималистичное меню трея (как Discord): узкая колонка, тема приложения.
class TrayMenuScreen extends ConsumerStatefulWidget {
  const TrayMenuScreen({super.key});

  static const width = 288.0;
  static const borderRadius = 10.0;
  static const itemHeight = 34.0;
  static const groupHeaderHeight = 24.0;
  static const maxServerListHeight = 200.0;

  static double estimateHeight({
    required int serverCount,
    required bool serversExpanded,
    int groupCount = 0,
  }) {
    const status = 36.0;
    const connect = itemHeight;
    const modes = itemHeight * 2;
    const footer = itemHeight * 2;
    const dividers = 4.0; // 4 разделителя между секциями
    const bottomPad = 6.0;

    var serverBlock = itemHeight; // селектор активного сервера
    if (serversExpanded && serverCount > 0) {
      final headers = groupCount > 1 ? groupCount * groupHeaderHeight : 0.0;
      serverBlock += math.min(
        serverCount * itemHeight + headers,
        maxServerListHeight,
      );
    }

    return status + connect + modes + serverBlock + footer + dividers + bottomPad;
  }

  @override
  ConsumerState<TrayMenuScreen> createState() => _TrayMenuScreenState();
}

class _TrayMenuScreenState extends ConsumerState<TrayMenuScreen> {
  bool _busy = false;
  bool _serversExpanded = false;

  Future<void> _closeMenu() async {
    // Флаг снимаем синхронно, пока виджет точно смонтирован: иначе после
    // `await` он может деактивироваться и `ref` бросит "ref after unmount"
    // (а исключение прервёт вызывающий код — кнопки трея перестают работать).
    // Переходный overflow вкладок при узком окне отсекается порогом ширины
    // в DesktopHomeScreen, поэтому порядок здесь безопасен.
    ref.read(trayMenuVisibleProvider.notifier).set(false);
    if (Platform.isWindows) {
      await WindowsDesktopService.hideTrayMenu();
    }
  }

  Future<void> _syncPopupSize() async {
    if (!Platform.isWindows) return;
    final servers = ref.read(serversProvider).servers;
    await WindowsDesktopService.resizeTrayMenu(
      width: TrayMenuScreen.width,
      height: TrayMenuScreen.estimateHeight(
        serverCount: servers.length,
        serversExpanded: _serversExpanded,
        groupCount: _groupCount(servers),
      ),
    );
  }

  /// Кол-во групп: ручные (если есть) + по числу разных подписок.
  int _groupCount(List<ServerItem> servers) {
    final subs = <String>{};
    var hasManual = false;
    for (final s in servers) {
      final id = s.subscriptionId;
      if (id == null) {
        hasManual = true;
      } else {
        subs.add(id);
      }
    }
    return (hasManual ? 1 : 0) + subs.length;
  }

  Future<void> _openFullApp() async {
    await _closeMenu();
    if (Platform.isWindows) {
      await WindowsDesktopService.restoreMainWindow();
    }
  }

  Future<void> _exitApp() async {
    // Симметрично Linux (tray Quit → _disconnectForQuit): сначала рвём туннель,
    // иначе системный прокси остаётся указывать на мёртвый 127.0.0.1-порт и
    // после выхода ломает интернет во всей системе. Нотифаер читаем до
    // закрытия меню — после него виджет демонтируется и ref недоступен.
    final vpnNotifier = ref.read(vpnStateProvider.notifier);
    await _closeMenu();
    try {
      await vpnNotifier.disconnect();
    } catch (_) {
      // Выходим в любом случае; стартовая зачистка подберёт остатки.
    }
    if (Platform.isWindows) {
      await WindowsDesktopService.exitApp();
    }
  }

  Future<void> _toggleServersExpanded() async {
    setState(() => _serversExpanded = !_serversExpanded);
    await _syncPopupSize();
  }

  Future<void> _toggleVpn(VpnStatus status) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (status == VpnStatus.connected) {
        await ref.read(vpnStateProvider.notifier).disconnect();
      } else if (status == VpnStatus.connecting) {
        await ref.read(vpnStateProvider.notifier).cancelConnect();
      } else {
        final active = ref.read(serversProvider).activeServer;
        if (active == null) return;
        await ref.read(vpnStateProvider.notifier).connect();
      }
    } catch (e, st) {
      // В трее нет снекбаров — ошибку в лог, статус в шапке покажет «Ошибка».
      AppLogger.instance.warn(
        'Tray VPN toggle failed',
        error: e,
        stackTrace: st,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectServer(ServerItem server) async {
    if (_busy) return;
    final vpnStatus = ref.read(vpnStateProvider).value?.status;
    final tunnelActive = vpnStatus == VpnStatus.connected ||
        vpnStatus == VpnStatus.connecting;
    // Повторный тап по уже активному серверу не перезапускает туннель —
    // только сворачиваем список.
    if (tunnelActive &&
        server.id == ref.read(serversProvider).activeServer?.id) {
      if (_serversExpanded && mounted) {
        setState(() => _serversExpanded = false);
        await _syncPopupSize();
      }
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(serversProvider.notifier).setActive(server);
      if (tunnelActive) {
        await ref.read(vpnStateProvider.notifier).reconnectToActiveServer();
      }
      if (_serversExpanded && mounted) {
        setState(() => _serversExpanded = false);
        await _syncPopupSize();
      }
    } catch (e, st) {
      AppLogger.instance.warn(
        'Tray server select failed',
        error: e,
        stackTrace: st,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onModeSelected(
    ConnectionMode next,
    AppSettings settings,
  ) async {
    if (next == settings.connectionModeEnum) return;

    if (next == ConnectionMode.tun && Platform.isWindows) {
      final elevated = await WindowsDesktopService.isProcessElevated();
      if (!elevated) {
        if (!mounted) return;
        // Всё нужное берём ДО закрытия меню: при закрытии TrayMenuScreen
        // демонтируется (mounted == false, ref мёртв), поэтому диалог живёт
        // на корневом Navigator — он переживает закрытие меню.
        final navigator = Navigator.of(context, rootNavigator: true);
        final settingsNotifier = ref.read(settingsNotifierProvider.notifier);
        final vpnNotifier = ref.read(vpnStateProvider.notifier);
        final vpnStatus = ref.read(vpnStateProvider).value?.status;
        await _closeMenu();
        await WindowsDesktopService.restoreMainWindow();
        final navContext = navigator.context;
        if (!navContext.mounted) return;
        final restart = await showDesktopTunAdminDialog(navContext);
        if (restart != true) return;
        await stopSessionBeforeElevation(
          notifier: vpnNotifier,
          status: vpnStatus,
        );
        await settingsNotifier.save(
          settings.copyWith(
              connectionMode: ConnectionMode.tun.storageValue,
              connectionModeChosen: true,
            ),
        );
        final ok = await WindowsDesktopService.restartAsAdministrator();
        if (!ok && navContext.mounted) {
          ScaffoldMessenger.of(navContext).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(navContext)!.desktopTunAdminRestartFailed,
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

  /// Тот же кругляш, что в списке серверов: флажок любого вида, а без него —
  /// буква протокола. Свой вариант тут раньше умел только страновые флаги.
  /// У цепочки во флажке страна выхода, а значок показывает число узлов —
  /// иначе в трее она неотличима от обычного сервера той же страны.
  Widget _flagCircle(ServerItem server) => ServerAvatar(
        flag: server.flag,
        protocol: server.protocol,
        size: 20,
        chainHops: server.protocol == 'chain'
            ? server.chainConfig!.hops.length
            : null,
      );

  /// Серверы, сгруппированные по подпискам (ручные — отдельной группой).
  List<Widget> _buildGroupedServers({
    required List<ServerItem> servers,
    required ServerItem? active,
    required bool isVpnBusy,
    required Color itemFg,
    required Color mutedFg,
    required Color accent,
    required AppLocalizations l10n,
    required Map<String, String> subNames,
  }) {
    final manual = <ServerItem>[];
    final subOrder = <String>[];
    final bySub = <String, List<ServerItem>>{};
    for (final s in servers) {
      final id = s.subscriptionId;
      if (id == null) {
        manual.add(s);
      } else {
        (bySub[id] ??= (() {
          subOrder.add(id);
          return <ServerItem>[];
        })())
            .add(s);
      }
    }
    final groupCount = (manual.isNotEmpty ? 1 : 0) + subOrder.length;
    final showHeaders = groupCount > 1;

    int byName(ServerItem a, ServerItem b) =>
        a.cleanName.toLowerCase().compareTo(b.cleanName.toLowerCase());

    final widgets = <Widget>[];
    void addGroup(String? title, List<ServerItem> list) {
      if (list.isEmpty) return;
      if (showHeaders && title != null && title.isNotEmpty) {
        widgets.add(_TrayGroupHeader(title: title, color: mutedFg));
      }
      final sorted = [...list]..sort(byName);
      for (final s in sorted) {
        widgets.add(_TrayItem(
          label: s.cleanName,
          leading: _flagCircle(s),
          enabled: !isVpnBusy,
          selected: s.id == active?.id,
          indent: showHeaders ? 8 : 0,
          onTap: () => _selectServer(s),
          foregroundColor: itemFg,
          accentColor: accent,
          maxLines: 1,
        ));
      }
    }

    // Имя подписки: из subscriptionsProvider (надёжно), иначе из самого сервера,
    // иначе общий ярлык. У ServerItem.subscriptionName часто пусто.
    String subTitle(String id) {
      final fromProvider = subNames[id]?.trim() ?? '';
      if (fromProvider.isNotEmpty) return fromProvider;
      final fromServer = (bySub[id]!.first.subscriptionName ?? '').trim();
      if (fromServer.isNotEmpty) return fromServer;
      return l10n.subscriptionsTitle;
    }

    addGroup(l10n.serversManualServers, manual);
    // подписки — по алфавиту названия, для предсказуемого порядка
    final sortedSubs = [...subOrder]
      ..sort((a, b) => subTitle(a).toLowerCase().compareTo(subTitle(b).toLowerCase()));
    for (final id in sortedSubs) {
      addGroup(subTitle(id), bySub[id]!);
    }
    return widgets;
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
    // Надёжные имена подписок (у ServerItem.subscriptionName часто пусто).
    final subs = ref.watch(subscriptionsProvider).value ?? const [];
    final subNames = {for (final s in subs) s.id: s.name};
    // select по статусу: подписка на весь VpnState перестраивала бы открытое
    // меню на каждый секундный эмит телеметрии (скорость/время).
    final status = ref.watch(
      vpnStateProvider.select(
        (a) => a.value?.status ?? VpnStatus.disconnected,
      ),
    );
    final isVpnBusy = _busy ||
        status == VpnStatus.connecting ||
        status == VpnStatus.disconnecting;

    final isConnected =
        status == VpnStatus.connected || status == VpnStatus.connecting;
    final canConnect = active != null && !isVpnBusy;
    // «Отключить» доступен и во время connecting — это отмена попытки.
    final canDisconnect = !_busy &&
        (status == VpnStatus.connected || status == VpnStatus.connecting);

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
              // Заголовок убран (название приложения не нужно) — сразу компактный
              // статус с цветным индикатором.
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: switch (status) {
                          VpnStatus.connected => Colors.green,
                          VpnStatus.connecting ||
                          VpnStatus.disconnecting =>
                            Colors.orange,
                          VpnStatus.error => colorScheme.error,
                          _ => mutedFg,
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statusLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: itemFg,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const _TrayDivider(),
              _TrayItem(
                label: isConnected ? l10n.trayDisconnect : l10n.trayConnect,
                enabled: isConnected ? canDisconnect : canConnect,
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
                label: active?.cleanName ?? l10n.trayPickServer,
                leading: active != null ? _flagCircle(active) : null,
                enabled: !isVpnBusy && servers.isNotEmpty,
                trailing: servers.length > 1
                    ? Icon(
                        _serversExpanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 18,
                        color: mutedFg,
                      )
                    : null,
                onTap: servers.length > 1
                    ? () => _toggleServersExpanded()
                    : null,
                foregroundColor: itemFg,
                maxLines: 1,
              ),
              if (_serversExpanded && servers.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: TrayMenuScreen.maxServerListHeight,
                  ),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.zero,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _buildGroupedServers(
                        servers: servers,
                        active: active,
                        isVpnBusy: isVpnBusy,
                        itemFg: itemFg,
                        mutedFg: mutedFg,
                        accent: colorScheme.primary,
                        l10n: l10n,
                        subNames: subNames,
                      ),
                    ),
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

class _TrayGroupHeader extends StatelessWidget {
  final String title;
  final Color color;
  const _TrayGroupHeader({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 12, 2),
      child: Text(
        title.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, letterSpacing: 0.4),
      ),
    );
  }
}

class _TrayItem extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  final bool selected;
  final double indent;
  final Widget? leading;
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
    this.leading,
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
                if (leading != null) ...[
                  Opacity(opacity: enabled ? 1 : 0.4, child: leading!),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg, fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
                  ),
                ),
                if (selected && accentColor != null)
                  Icon(Icons.check_rounded, size: 16, color: accentColor),
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
