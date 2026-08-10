import 'package:flutter/material.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/connection_entry.dart';
import 'package:keqdroid/services/connections_service.dart';
import 'package:keqdroid/shared/ui/accent_edge_card.dart';
import 'package:keqdroid/shared/ui/app_theme.dart';
import 'package:keqdroid/shared/ui/expressive.dart';

/// Одна строка экрана «Соединения»: куда идёт трафик, каким инбаундом пришёл,
/// по какому правилу ушёл и чем это кончилось.
///
/// Живёт в вертикальном списке, то есть высота приходит неограниченной —
/// внутри не должно быть ничего, что растягивается по входящим constraint'ам.
class ConnectionTile extends StatelessWidget {
  const ConnectionTile({
    super.key,
    required this.entry,
    required this.showProcess,
    required this.ruleInfoAvailable,
  });

  final ConnectionEntry entry;
  final bool showProcess;

  /// false — источник вообще не знает правил (access-лог ниже уровня Info):
  /// пустое правило тогда значит «неизвестно», а не «сработал catch-all».
  final bool ruleInfoAvailable;

  Color _verdictColor(BuildContext context) => switch (entry.verdict) {
        ConnectionVerdict.proxied => AppTheme.accent(context),
        ConnectionVerdict.direct => AppTheme.green(context),
        ConnectionVerdict.blocked => AppTheme.red(context),
        ConnectionVerdict.viaCore => AppTheme.textLight(context),
        ConnectionVerdict.unknown => AppTheme.textLight(context),
      };

  String _verdictLabel(AppLocalizations l10n) => switch (entry.verdict) {
        ConnectionVerdict.proxied => l10n.connectionsVerdictProxy,
        ConnectionVerdict.direct => l10n.connectionsVerdictDirect,
        ConnectionVerdict.blocked => l10n.connectionsVerdictBlock,
        ConnectionVerdict.viaCore => l10n.connectionsVerdictCore,
        ConnectionVerdict.unknown => '—',
      };

  static String _bytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    if (value < 1024 * 1024 * 1024) {
      return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Только имя исполняемого файла: полный путь съедает всю строку.
  static String _processName(String raw) {
    if (raw.isEmpty) return '';
    final normalized = raw.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    return slash >= 0 ? normalized.substring(slash + 1) : normalized;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = _verdictColor(context);
    final process = _processName(entry.process);
    // «Правила нет» и «правило неизвестно» — разные вещи, и путать их нельзя:
    // соединение, отданное встроенному движку, до сих пор показывалось как
    // «без правила, ушло в прокси», хотя движок мог увести его в direct.
    final rule = entry.decidedByCore
        ? l10n.connectionsRuleViaCore
        : switch (entry.rule) {
            '' => ruleInfoAvailable && entry.outbound.isNotEmpty
                ? l10n.connectionsRuleDefault
                : '',
            final r when XrayAccessLogParser.isDefaultRoute(r) =>
              l10n.connectionsRuleDefault,
            final r => r,
          };

    return AccentEdgeCard(
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
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: AppTheme.text(context)),
                ),
              ),
              const SizedBox(width: 8),
              _chip(context, entry.network.toUpperCase(),
                  AppTheme.textLight(context)),
              const SizedBox(width: 6),
              _chip(context, _verdictLabel(l10n), color),
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
                _meta(context, Icons.link_off, l10n.connectionsClosed),
              if (showProcess && process.isNotEmpty)
                _meta(context, Icons.apps, process),
              if (rule.isNotEmpty) _meta(context, Icons.rule, rule),
              if (entry.outbound.isNotEmpty)
                _meta(context, Icons.call_split, entry.outbound),
              if (entry.inbound.isNotEmpty)
                _meta(context, Icons.login, entry.inbound),
              if (entry.source.isNotEmpty)
                _meta(context, Icons.computer, entry.source),
              if (entry.download != null || entry.upload != null)
                _meta(
                  context,
                  Icons.swap_vert,
                  '↓ ${_bytes(entry.download ?? 0)}  ↑ ${_bytes(entry.upload ?? 0)}',
                ),
              if (entry.startedAt != null)
                _meta(
                  context,
                  Icons.schedule,
                  _formatTime(entry.startedAt!),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  Widget _chip(BuildContext context, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: Theme.of(context)
              .textTheme
              .emphasized(Theme.of(context).textTheme.labelSmall)
              ?.copyWith(color: color),
        ),
      );

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
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppTheme.textLight(context)),
            ),
          ),
        ],
      );
}
