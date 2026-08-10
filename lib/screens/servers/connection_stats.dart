part of '../servers_tab.dart';

String _formatVpnRate(int? bytesPerSec) {
  if (bytesPerSec == null || bytesPerSec <= 0) return '0 B/s';
  return '${_formatVpnBytes(bytesPerSec)}/s';
}

String _formatVpnBytes(int? bytes) {
  if (bytes == null || bytes <= 0) return '0 B';
  const kb = 1024.0;
  const mb = kb * 1024;
  const gb = mb * 1024;
  final b = bytes.toDouble();
  if (b >= gb) return '${(b / gb).toStringAsFixed(2)} GB';
  if (b >= mb) return '${(b / mb).toStringAsFixed(1)} MB';
  if (b >= kb) return '${(b / kb).toStringAsFixed(1)} KB';
  return '$bytes B';
}

String _formatVpnDuration(Duration? d) {
  if (d == null) return '0s';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

// Скорость и объём трафика под кнопкой подключения (все платформы; данные
// приходят в VpnState раз в секунду — те же, что видит уведомление на Android).
class _ConnectionStats extends ConsumerWidget {
  const _ConnectionStats({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Видимость чипов настраивается в Appearance: трафик (скорость + объём)
    // и время подключения — отдельными переключателями.
    final (showTraffic, showTime) = ref.watch(
      settingsNotifierProvider.select((async) {
        final s = async.value ?? const AppSettings();
        return (s.showTrafficStats, s.showConnectionTime);
      }),
    );
    if (!showTraffic && !showTime) return const SizedBox.shrink();

    final stats = ref.watch(
      vpnStateProvider.select((a) {
        final v = a.value;
        if (v == null) return (null, null, null, null);
        return (v.downloadSpeed, v.uploadSpeed, v.totalDownload, v.duration);
      }),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      // Все чипы — один семантический узел (см. комментарий в _ServerTile).
      child: MergeSemantics(
        // На узких экранах четыре чипа могут не влезть на пару пикселей
        // (RenderFlex overflow) — scaleDown чуть ужимает ряд вместо переноса.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showTraffic) ...[
                _statChip(
                  context,
                  icon: Icons.arrow_downward,
                  value: _formatVpnRate(stats.$1),
                ),
                const SizedBox(width: 8),
                _statChip(
                  context,
                  icon: Icons.arrow_upward,
                  value: _formatVpnRate(stats.$2),
                ),
                const SizedBox(width: 8),
                _statChip(
                  context,
                  label: context.l10n.statsInLabel,
                  value: _formatVpnBytes(stats.$3),
                ),
              ],
              if (showTraffic && showTime) const SizedBox(width: 8),
              if (showTime)
                _statChip(
                  context,
                  label: context.l10n.statsTimeLabel,
                  value: _formatVpnDuration(stats.$4),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statChip(
    BuildContext context, {
    IconData? icon,
    String? label,
    required String value,
  }) {
    final color = AppTheme.textLight(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(ExpressiveShape.small),
        border: Border.all(color: AppTheme.divider(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 12, color: color)
          else
            Text(
              label ?? '',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
            ),
          const SizedBox(width: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

