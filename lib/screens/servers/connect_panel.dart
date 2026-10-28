part of '../servers_tab.dart';

// режим «Модерн»: всё из шапки над списком собрано в одну панель, кнопка справа
class _ModernConnectPanel extends ConsumerWidget {
  const _ModernConnectPanel({
    required this.waveCtrl,
    required this.onToggle,
    required this.onJumpToActive,
    required this.buttonKey,
  });

  final AnimationController waveCtrl;

  final void Function(VpnStatus) onToggle;
  final VoidCallback onJumpToActive;
  final GlobalKey buttonKey;

  static const double _buttonSize = 120;
  static const double _margin = 16;
  static const double _gapBelow = 8;
  // в узкой панели рядом с кнопкой от имени оставалась одна буква: боком на планшете
  // колонка шапки 360 dp, то же на телефонах до 384 dp. Pixel 6a (411 dp) остаётся рядом
  static const double _minPlaqueWidth = 180;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnStatus = ref.watch(
      vpnStateProvider.select((a) => a.value?.status ?? VpnStatus.disconnected),
    );
    final vpnErrorMessage = ref.watch(
      vpnStateProvider.select((a) => a.value?.errorMessage),
    );
    final serverSwitchInProgress = ref.watch(vpnServerSwitchInProgressProvider);
    final activeServer = ref.watch(
      serversProvider.select((s) => s.activeServer),
    );
    final exitLookup = ref.watch(exitIpProvider);
    final exit = exitLookup.isLoading ? null : exitLookup.value;
    final halloween = ref.watch(halloweenActiveProvider);
    final (showTraffic, showSplit, showTime) = ref.watch(
      settingsNotifierProvider.select((async) {
        final s = async.value ?? const AppSettings();
        return (s.showTrafficStats, s.showTrafficSplit, s.showConnectionTime);
      }),
    );
    // боком три показателя трафика встают сеткой 2 на 2: время занимает пустую четвёртую ячейку
    final timeInStats = WindowBreakpoints.isExpandedMobile(context) &&
        showTraffic &&
        !showSplit;
    final hasStats = showTraffic || showSplit || (timeInStats && showTime);

    final isConnected =
        vpnStatus == VpnStatus.connected && !serverSwitchInProgress;
    final isConnecting =
        serverSwitchInProgress || vpnStatus == VpnStatus.connecting;
    final isError = vpnStatus == VpnStatus.error && !serverSwitchInProgress;

    // connecting тапабелен: это отмена попытки
    final VoidCallback? onTap =
        vpnStatus == VpnStatus.disconnecting ? null : () => onToggle(vpnStatus);

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final topPad = PlatformBootstrap.isDesktop
        ? 16.0
        : MediaQuery.paddingOf(context).top + 12;

    final button = halloween
        ? SizedBox.square(
            dimension: _buttonSize,
            child: FittedBox(
              child: PumpkinConnectButton(
                isConnected: isConnected,
                isConnecting: isConnecting,
                isError: isError,
                onTap: onTap,
              ),
            ),
          )
        : _ConnectButton(
            isConnected: isConnected,
            isConnecting: isConnecting,
            onTap: onTap,
            size: _buttonSize,
            // на подложке панели обычный серый кнопки сливался бы с ней
            idleColor: scheme.surfaceContainerHighest,
          );

    return Padding(
      padding: EdgeInsets.fromLTRB(_margin, topPad, _margin, _gapBelow),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: scheme.surfaceContainerLow,
          shape: ExpressiveShape.border(ExpressiveShape.extraLarge),
        ),
        child: ClipRRect(
          borderRadius: ExpressiveShape.radius(ExpressiveShape.extraLarge),
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: _HeaderLiquid(clock: waveCtrl, panel: true),
                ),
              ),
              Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, box) {
                      final server = activeServer != null
                          ? _ServerPingPlaque(
                              server: activeServer,
                              connected: isConnected,
                              exit: exit,
                              onJumpToActive: onJumpToActive,
                            )
                          : Text(
                              context.l10n.vpnSelectServer,
                              style: textTheme.bodyMedium?.copyWith(
                                color: AppTheme.textLight(context),
                              ),
                            );
                      final uptime = _StatsReveal(
                        shown: isConnected && !timeInStats && showTime,
                        alignment: AlignmentDirectional.bottomStart,
                        child: const _UptimeLine(),
                      );
                      final buttonBox = Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: ExpressiveSpacing.large,
                          end: ExpressiveSpacing.medium,
                        ),
                        child: KeyedSubtree(
                          key: buttonKey,
                          child: RepaintBoundary(child: button),
                        ),
                      );
                      final beside = box.maxWidth -
                          _buttonSize -
                          ExpressiveSpacing.large -
                          ExpressiveSpacing.medium;
                      if (beside < _minPlaqueWidth) {
                        // плашка над кнопкой, а не между кнопкой и трафиком: капля течёт из кнопки вниз
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            server,
                            const SizedBox(height: ExpressiveSpacing.small),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [Expanded(child: uptime), buttonBox],
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [server, uptime],
                            ),
                          ),
                          buttonBox,
                        ],
                      );
                    },
                  ),
                  if (isError && vpnErrorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: ExpressiveSpacing.small),
                      child: Text(
                        friendlyError(vpnErrorMessage, context),
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: AppTheme.red(context),
                        ),
                      ),
                    ),
                  _StatsBud(
                    shown: isConnected && hasStats,
                    source: halloween ? null : buttonKey,
                    // по вписанному кругу: кнопка в этот момент ещё перетекает из круга в квадрат
                    sourceRadius: _buttonSize / 2,
                    bead: 48,
                    neck: 30,
                    goo: 12,
                    sourceColor: isConnected
                        ? scheme.primary
                        : scheme.surfaceContainerHighest,
                    child: _ConnectionStats(fill: true, withTime: timeInStats),
                  ),
                  // место под воду у дна панели
                  const SizedBox(height: 36),
                ],
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}

// время под сервером: отдельной ячейкой оно занимало бы целую строку панели
class _UptimeLine extends ConsumerWidget {
  const _UptimeLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = ref.watch(
      settingsNotifierProvider.select(
        (async) => (async.value ?? const AppSettings()).showConnectionTime,
      ),
    );
    if (!show) return const SizedBox.shrink();
    final duration = ref.watch(
      vpnStateProvider.select((a) => a.value?.duration),
    );
    final textTheme = Theme.of(context).textTheme;
    final color = AppTheme.textLight(context);
    return Padding(
      padding: const EdgeInsets.only(top: ExpressiveSpacing.small),
      child: Semantics(
        label: context.l10n.statsTimeLabel,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.schedule_rounded,
              size: ExpressiveIconSize.inline,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(
              ltrIsolate(_formatVpnDuration(duration)),
              style: textTheme.labelLarge?.copyWith(
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
