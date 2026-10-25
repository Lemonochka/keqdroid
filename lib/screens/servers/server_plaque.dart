part of '../servers_tab.dart';

const double _plaqueHeight = 44;
const Radius _plaqueOuter = Radius.circular(_plaqueHeight / 2);
const Radius _plaqueInner = Radius.circular(ExpressiveShape.small);

Widget _plaqueSegment({
  required Color color,
  required BorderRadius radius,
  required Widget child,
  VoidCallback? onTap,
  String? tooltip,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 12),
}) {
  final shape = RoundedRectangleBorder(borderRadius: radius);
  final segment = Material(
    color: color,
    shape: shape,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      customBorder: shape,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _plaqueHeight),
        child: Padding(
          padding: padding,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: 1,
            heightFactor: 1,
            child: child,
          ),
        ),
      ),
    ),
  );
  if (tooltip == null) return segment;
  return Tooltip(
    message: tooltip,
    waitDuration: const Duration(milliseconds: 600),
    child: Semantics(button: true, label: tooltip, child: segment),
  );
}

// та же половина с именем, что была чипом: по флагу показывает IP выхода
Widget _plaqueServerSegment(
  BuildContext context, {
  required ServerItem server,
  required bool connected,
  required ExitIp? exit,
  required VoidCallback onJumpToActive,
  required BorderRadius radius,
  required int maxLines,
}) {
  final scheme = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;
  final name = ServerNameUtils.formatForDisplay(
    ServerNameUtils.cleanDisplayName(server.displayName),
  );
  return ConnectedStatusChip(
    label: name,
    exit: connected ? exit : null,
    onJumpToActive: onJumpToActive,
    textStyle: textTheme.emphasized(textTheme.titleSmall),
    verticalPadding: 8,
    borderRadius: radius,
    color: connected ? scheme.secondaryContainer : scheme.surfaceContainerHighest,
    foregroundColor:
        connected ? scheme.onSecondaryContainer : scheme.onSurface,
    fallbackFlag: server.flag,
    fallbackProtocol: server.protocol,
    maxLines: maxLines,
    minHeight: _plaqueHeight,
    textAlign: TextAlign.start,
  );
}

class _ServerPingPlaque extends ConsumerWidget {
  const _ServerPingPlaque({
    required this.server,
    required this.connected,
    required this.exit,
    required this.onJumpToActive,
  });

  final ServerItem server;
  final bool connected;
  final ExitIp? exit;
  final VoidCallback onJumpToActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(
      settingsNotifierProvider.select((a) => a.value ?? const AppSettings()),
    );
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final pingMs = server.pingMs;
    final pingType = PingService.pingColorTypeForServer(server, settings);
    final pingText = pingMs != null
        ? PingService.formatPingValue(pingMs, pingType)
        : (server.lastTestedAt != null ? 'N/A' : '—');
    final pingColor = pingMs != null
        ? pingQualityColor(context, pingMs, pingType)
        : AppTheme.textLight(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ExpressiveSpacing.extraSmall),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: _plaqueServerSegment(
                context,
                server: server,
                connected: connected,
                exit: exit,
                onJumpToActive: onJumpToActive,
                radius: const BorderRadiusDirectional.horizontal(
                  start: _plaqueOuter,
                  end: _plaqueInner,
                ).resolve(Directionality.of(context)),
                maxLines: 2,
              ),
            ),
            const SizedBox(width: ExpressiveSpacing.hairline),
            _plaqueSegment(
              color: scheme.surfaceContainerHighest,
              radius: const BorderRadiusDirectional.horizontal(
                start: _plaqueInner,
                end: _plaqueOuter,
              ).resolve(Directionality.of(context)),
              onTap: () => ref.read(serversProvider.notifier).pingSingle(server.id),
              tooltip: context.l10n.serversPingServer,
              padding: const EdgeInsetsDirectional.only(start: 10, end: 12),
              child: Text(
                ltrIsolate(pingText),
                style: textTheme
                    .emphasized(textTheme.labelMedium)
                    ?.copyWith(color: pingColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// легаси: прежнее «Подключено к: X» двумя половинами
class _StatusServerPlaque extends StatelessWidget {
  const _StatusServerPlaque({
    required this.server,
    required this.status,
    required this.exit,
    required this.onJumpToActive,
  });

  final ServerItem server;
  final VpnStatus status;
  final ExitIp? exit;
  final VoidCallback onJumpToActive;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final connected = status == VpnStatus.connected;
    final label = switch (status) {
      VpnStatus.connected => l10n.trayStatusConnected,
      VpnStatus.connecting => l10n.vpnConnecting,
      VpnStatus.disconnecting => l10n.vpnDisconnecting,
      _ => l10n.trayStatusDisconnected,
    };
    final direction = Directionality.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ExpressiveSpacing.extraSmall),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _plaqueSegment(
              color: connected
                  ? scheme.secondaryContainer
                  : scheme.surfaceContainerHighest,
              radius: const BorderRadiusDirectional.horizontal(
                start: _plaqueOuter,
                end: _plaqueInner,
              ).resolve(direction),
              padding: const EdgeInsetsDirectional.only(start: 16, end: 12),
              child: Text(
                label,
                style: textTheme.emphasized(textTheme.labelLarge)?.copyWith(
                  color: connected
                      ? scheme.onSecondaryContainer
                      : AppTheme.textLight(context),
                ),
              ),
            ),
            const SizedBox(width: ExpressiveSpacing.hairline),
            Flexible(
              child: _plaqueServerSegment(
                context,
                server: server,
                connected: connected,
                exit: exit,
                onJumpToActive: onJumpToActive,
                radius: const BorderRadiusDirectional.horizontal(
                  start: _plaqueInner,
                  end: _plaqueOuter,
                ).resolve(direction),
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// волна живёт в фоне шапки: в панели полосой у дна, в легаси под кнопкой
class _HeaderLiquid extends ConsumerWidget {
  const _HeaderLiquid({
    required this.clock,
    required this.panel,
    this.shapesTop = 0,
    this.overhang = 0,
  });

  final AnimationController clock;
  final bool panel;
  final double shapesTop;
  final double overhang;

  static const _panelLevels = LiquidLevels(
    idle: 12,
    busy: 44,
    quiet: 36,
    loud: 44,
    inDp: true,
  );
  static const _legacyLevels = LiquidLevels(
    idle: 0.08,
    busy: 0.36,
    quiet: 0.3,
    loud: 0.36,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(vpnStateProvider.select((s) => s.value?.status));
    final switching = ref.watch(vpnServerSwitchInProgressProvider);
    final server = ref.watch(serversProvider.select((s) => s.activeServer));
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();
    final showTraffic = settings.showTrafficStats || settings.showTrafficSplit;
    // вода идёт за трафиком и при скрытом счётчике: скорость приходит всегда
    final bytesPerSec = ref.watch(
      vpnStateProvider.select((s) {
        final v = s.value;
        return (v?.downloadSpeed ?? 0) + (v?.uploadSpeed ?? 0);
      }),
    );
    final phase = switch (status) {
      VpnStatus.connecting || VpnStatus.disconnecting => LiquidPhase.busy,
      VpnStatus.connected =>
        switching ? LiquidPhase.busy : LiquidPhase.active,
      _ => LiquidPhase.idle,
    };
    final active = phase != LiquidPhase.idle;
    // у тыквы в легаси своё небо вокруг
    final halloween = ref.watch(halloweenActiveProvider);
    final scheme = Theme.of(context).colorScheme;
    final wave = TweenAnimationBuilder<Color?>(
      tween: ColorTween(
        end: active ? scheme.primary : AppTheme.textLight(context),
      ),
      duration: ExpressiveMotion.durationDefault,
      builder: (context, shapeColor, _) => LiquidWave(
        clock: clock,
        phase: phase,
        levels: panel ? _panelLevels : _legacyLevels,
        load: LiquidWaveSim.loadFor(bytesPerSec),
        color: _latencyColor(context, server, settings),
        fade: !panel,
        shapePresets: panel
            ? panelLiquidShapes
            : halloween
                ? const []
                : legacyLiquidShapes,
        shapeColor: shapeColor!,
        // строка метрик стоит прямо над водой
        lowZoneFree: !(phase == LiquidPhase.active && showTraffic),
        shapesTop: shapesTop,
        overhang: overhang,
        splashFromEnd: panel
            ? 20 +
                ExpressiveSpacing.medium +
                _ModernConnectPanel._buttonSize / 2
            : null,
      ),
    );
    if (panel) return wave;
    // шапка уже экрана (телефон боком, широкое окно): вода гаснет к бокам, а не обрывается
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth < MediaQuery.sizeOf(context).width - 1
              ? EdgeFadeMask(side: 40, child: wave)
              : wave,
    );
  }
}

Color _latencyColor(
  BuildContext context,
  ServerItem? server,
  AppSettings settings,
) {
  if (!settings.waveLatencyColor) return AppTheme.accent(context);
  final ping = server?.pingMs;
  if (server == null || ping == null || ping <= 0) {
    return AppTheme.accent(context);
  }
  final type = PingService.pingColorTypeForServer(server, settings);
  return switch (PingService.pingLatencyQuality(ping, type)) {
    PingLatencyQuality.good => AppTheme.green(context),
    PingLatencyQuality.fair => AppTheme.orange(context),
    PingLatencyQuality.poor => AppTheme.red(context),
  };
}
