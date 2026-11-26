import 'package:flutter/material.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/connection_entry.dart';
import 'package:keqdroid/services/xray_access_log_parser.dart';
import 'package:keqdroid/shared/ui/accent_edge_card.dart';
import 'package:keqdroid/shared/ui/app_theme.dart';
import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:keqdroid/shared/ui/tv_focus.dart';

class ConnectionTile extends StatelessWidget {
  const ConnectionTile({
    super.key,
    required this.entry,
    required this.showProcess,
    required this.ruleInfoAvailable,
    this.onTap,
  });

  final ConnectionEntry entry;
  final bool showProcess;

  final bool ruleInfoAvailable;

  final VoidCallback? onTap;

  static Color verdictColor(BuildContext context, ConnectionVerdict verdict) =>
      switch (verdict) {
        ConnectionVerdict.proxied => AppTheme.accent(context),
        ConnectionVerdict.direct => AppTheme.green(context),
        ConnectionVerdict.blocked => AppTheme.red(context),
        ConnectionVerdict.viaCore => AppTheme.textLight(context),
        ConnectionVerdict.unknown => AppTheme.textLight(context),
      };

  static String verdictLabel(
    AppLocalizations l10n,
    ConnectionVerdict verdict,
  ) => switch (verdict) {
    ConnectionVerdict.proxied => l10n.connectionsVerdictProxy,
    ConnectionVerdict.direct => l10n.connectionsVerdictDirect,
    ConnectionVerdict.blocked => l10n.connectionsVerdictBlock,
    ConnectionVerdict.viaCore => l10n.connectionsVerdictCore,
    ConnectionVerdict.unknown => '—',
  };

  static String ruleLabel(
    AppLocalizations l10n,
    ConnectionEntry entry, {
    required bool ruleInfoAvailable,
  }) => entry.decidedByCore
      ? (ruleInfoAvailable
            ? l10n.connectionsRuleViaCoreUnseen
            : l10n.connectionsRuleViaCore)
      : switch (entry.rule) {
          '' =>
            ruleInfoAvailable && entry.outbound.isNotEmpty
                ? l10n.connectionsRuleDefault
                : '',
          final r when XrayAccessLogParser.isDefaultRoute(r) =>
            l10n.connectionsRuleDefault,
          final r => r,
        };

  static String formatBytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    if (value < 1024 * 1024 * 1024) {
      return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String formatTraffic(ConnectionEntry entry) =>
      '↓ ${formatBytes(entry.download ?? 0)}  ↑ ${formatBytes(entry.upload ?? 0)}';

  static String processName(String raw) {
    if (raw.isEmpty) return '';
    final normalized = raw.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    return slash >= 0 ? normalized.substring(slash + 1) : normalized;
  }

  static String formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  static Widget chip(BuildContext context, String label, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(ExpressiveShape.small),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme
              .emphasized(Theme.of(context).textTheme.labelSmall)
              ?.copyWith(color: color),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = verdictColor(context, entry.verdict);
    final process = processName(entry.process);
    final rule = ruleLabel(l10n, entry, ruleInfoAvailable: ruleInfoAvailable);

    final card = AccentEdgeCard(
      edgeColor: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  entry.target,
                  maxLines: 1,
                  onTap: onTap,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppTheme.text(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (entry.count > 1) ...[
                chip(context, '×${entry.count}', AppTheme.accent(context)),
                const SizedBox(width: 6),
              ],
              chip(
                context,
                entry.network.toUpperCase(),
                AppTheme.textLight(context),
              ),
              const SizedBox(width: 6),
              chip(context, verdictLabel(l10n, entry.verdict), color),
            ],
          ),
          if (entry.destIp.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              entry.destIp,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: AppTheme.textLight(context),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (entry.closed)
                _meta(context, Icons.link_off_rounded, l10n.connectionsClosed),
              if (showProcess && process.isNotEmpty)
                _meta(context, Icons.apps_rounded, process),
              if (rule.isNotEmpty) _meta(context, Icons.rule_rounded, rule),
              if (entry.outbound.isNotEmpty)
                _meta(context, Icons.call_split_rounded, entry.outbound),
              if (entry.inbound.isNotEmpty)
                _meta(context, Icons.login_rounded, entry.inbound),
              if (entry.source.isNotEmpty)
                _meta(context, Icons.computer_rounded, entry.source),
              if (entry.download != null || entry.upload != null)
                _meta(context, Icons.swap_vert_rounded, formatTraffic(entry)),
              if (entry.startedAt != null)
                _meta(
                  context,
                  Icons.schedule_rounded,
                  formatTime(entry.startedAt!),
                ),
            ],
          ),
        ],
      ),
    );
    if (onTap == null) return card;
    // рябь InkWell легла бы под непрозрачную заливку карточки
    final tappable = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: card,
      ),
    );
    if (!TvFocus.enabled) return tappable;
    return TvTappable(
      onTap: onTap,
      radius: BorderRadius.circular(14),
      child: tappable,
    );
  }

  Widget _meta(BuildContext context, IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: AppTheme.textLight(context)),
      const SizedBox(width: 4),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppTheme.textLight(context)),
        ),
      ),
    ],
  );
}
