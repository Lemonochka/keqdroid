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
    final (showTraffic, showTime, showSplit) = ref.watch(
      settingsNotifierProvider.select((async) {
        final s = async.value ?? const AppSettings();
        return (s.showTrafficStats, s.showConnectionTime, s.showTrafficSplit);
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

    // Разбивка идёт своим каналом, а не через VpnState: её умеет считать одно
    // ядро из нескольких, и наливать её в общее состояние туннеля значило бы
    // тащить через все бэкенды поле, которое почти везде пустое.
    // `null` — ядро разбивку не отдаёт, и чипы остаются обычными.
    final split = showTraffic && showSplit
        ? ref.watch(trafficSplitProvider).value
        : null;

    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: ExpressiveSpacing.medium),
      child: StatStrip(
        metrics: [
          if (showTraffic) ...[
            if (split != null) ...[
              _splitRate(
                l10n,
                icon: Icons.arrow_downward_rounded,
                label: l10n.statsDownloadLabel,
                viaVpn: split.vpnDownload,
                direct: split.directDownload,
              ),
              _splitRate(
                l10n,
                icon: Icons.arrow_upward_rounded,
                label: l10n.statsUploadLabel,
                viaVpn: split.vpnUpload,
                direct: split.directUpload,
              ),
            ] else ...[
              StatMetric(
                icon: Icons.arrow_downward_rounded,
                label: l10n.statsDownloadLabel,
                value: _formatVpnRate(stats.$1),
                template: _kRateTemplate,
              ),
              StatMetric(
                icon: Icons.arrow_upward_rounded,
                label: l10n.statsUploadLabel,
                value: _formatVpnRate(stats.$2),
                template: _kRateTemplate,
              ),
            ],
            StatMetric(
              icon: Icons.data_usage_rounded,
              label: l10n.statsInLabel,
              value: _formatVpnBytes(stats.$3),
              template: _kBytesTemplate,
            ),
          ],
          if (showTime)
            StatMetric(
              icon: Icons.schedule_rounded,
              label: l10n.statsTimeLabel,
              value: _formatVpnDuration(stats.$4),
              template: _kDurationTemplate,
            ),
        ],
      ),
    );
  }
}

/// Ячейка «скорость в туннель / скорость мимо туннеля».
///
/// Сверху идёт туннель: ради него приложение и запущено, а мимо него уходит
/// то, что развели правилами, — это поправка к главному числу, а не равное ему.
StatMetric _splitRate(
  AppLocalizations l10n, {
  required IconData icon,
  required String label,
  required int viaVpn,
  required int direct,
}) =>
    StatMetric.split(
      icon: icon,
      label: label,
      lines: [
        StatValue(
          tag: l10n.statsSplitVpnTag,
          value: _formatVpnRate(viaVpn),
          template: _kRateTemplate,
        ),
        StatValue(
          tag: l10n.statsSplitDirectTag,
          value: _formatVpnRate(direct),
          template: _kRateTemplate,
        ),
      ],
    );

/// Самые широкие значения, какие может показать каждый чип.
///
/// Ширина слота считается по ним, а не по тому, что приехало в эту секунду:
/// иначе чип дышит на каждом обновлении, а вместе с ним переезжает и весь ряд.
const _kRateTemplate = '999.9 MB/s';
const _kBytesTemplate = '999.99 GB';
const _kDurationTemplate = '59m 59s';

