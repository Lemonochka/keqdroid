import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/connection_entry.dart';
import 'package:keqdroid/screens/settings/connection_tile.dart';
import 'package:keqdroid/shared/ui/accent_edge_card.dart';
import 'package:keqdroid/shared/ui/app_theme.dart';
import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:keqdroid/shared/ui/liquid_toast.dart';
import 'package:keqdroid/utils/connection_route.dart';

class ConnectionField {
  const ConnectionField(
    this.value, {
    this.note,
    this.mono = false,
    this.leading,
  });

  final String value;
  final String? note;
  final bool mono;
  final Widget? leading;
}

class ConnectionListLine {
  const ConnectionListLine(this.name, this.match, {this.note});

  final String name;
  final ListMatch match;
  final String? note;
}

class ConnectionInsightView {
  const ConnectionInsightView({
    this.app,
    this.rule,
    this.exit,
    this.lists = const [],
  });

  final ConnectionField? app;
  final ConnectionField? rule;
  final ConnectionField? exit;
  final List<ConnectionListLine> lists;
}

class ConnectionDetailsSheet extends StatefulWidget {
  const ConnectionDetailsSheet({
    super.key,
    required this.entry,
    required this.live,
    required this.livenessKnown,
    required this.insight,
    this.pendingLists = const [],
    this.app,
    this.rule,
    this.exit,
    this.now = DateTime.now,
  });

  final ValueListenable<ConnectionEntry> entry;

  // снимок API ядра: в нём только живые соединения, у каждого свои байты
  final bool live;

  final bool livenessKnown;

  final Future<ConnectionInsightView> insight;

  // названия списков, пока база читается: шторка выезжает уже своей высоты и в конце не подпрыгивает
  final List<String> pendingLists;

  final ConnectionField? app;
  final ConnectionField? rule;
  final ConnectionField? exit;

  final DateTime Function() now;

  @override
  State<ConnectionDetailsSheet> createState() => _ConnectionDetailsSheetState();
}

class _ConnectionDetailsSheetState extends State<ConnectionDetailsSheet> {
  static const _shownMembers = 4;
  bool _allMembers = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ConnectionEntry>(
      valueListenable: widget.entry,
      // подпись к правилу или приложению приходит вместе со списками и добавляет строку
      builder: (context, entry, _) => AnimatedSize(
        duration: const Duration(milliseconds: 450),
        curve: const SpringCurve(
          ExpressiveMotion.spatialDefault,
          Duration(milliseconds: 450),
        ),
        alignment: Alignment.topCenter,
        child: FutureBuilder<ConnectionInsightView>(
          future: widget.insight,
          builder: (context, snap) => _content(context, entry, snap),
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    ConnectionEntry entry,
    AsyncSnapshot<ConnectionInsightView> snap,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final t = Theme.of(context).textTheme;
    final light = AppTheme.textLight(context);
    final text = AppTheme.text(context);
    final color = ConnectionTile.verdictColor(context, entry.verdict);
    final view = snap.data;
    final fields = _fields(l10n, entry, view);

    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Text(title, style: t.labelMedium?.copyWith(color: light)),
    );

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccentEdgeCard(
                edgeColor: color,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SelectableText(
                            entry.target,
                            style: t.titleSmall?.copyWith(color: text),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (entry.count > 1) ...[
                          ConnectionTile.chip(
                            context,
                            '×${entry.count}',
                            AppTheme.accent(context),
                          ),
                          const SizedBox(width: 6),
                        ],
                        ConnectionTile.chip(
                          context,
                          entry.network.toUpperCase(),
                          light,
                        ),
                        const SizedBox(width: 6),
                        ConnectionTile.chip(
                          context,
                          ConnectionTile.verdictLabel(l10n, entry.verdict),
                          color,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (final (icon, label, field) in fields)
                      _fieldRow(context, icon, label, field),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton.icon(
                        onPressed: () => _copy(context, entry, fields),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.content_copy_rounded, size: 16),
                        label: Text(l10n.connectionsDetailsCopy),
                      ),
                    ),
                  ],
                ),
              ),
              if (entry.members.isNotEmpty) ...[
                section(l10n.connectionsDetailsMembers(entry.members.length)),
                _plainCard(context, _members(context, l10n, entry.members)),
              ],
              section(l10n.connectionsDetailsLists),
              _plainCard(
                context,
                view == null
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          Visibility(
                            visible: false,
                            maintainSize: true,
                            maintainAnimation: true,
                            maintainState: true,
                            child: Column(
                              children: [
                                for (final name in widget.pendingLists)
                                  _listRow(
                                    context,
                                    ConnectionListLine(name, ListMatch.miss),
                                  ),
                              ],
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          for (final line in view.lists)
                            _listRow(context, line),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<(IconData, String, ConnectionField)> _fields(
    AppLocalizations l10n,
    ConnectionEntry entry,
    ConnectionInsightView? view,
  ) {
    final started = entry.startedAt;
    final app = view?.app ?? widget.app;
    final rule = view?.rule ?? widget.rule;
    final exit = view?.exit ?? widget.exit;
    return [
      if (entry.destIp.isNotEmpty)
        (
          Icons.public_rounded,
          l10n.connectionsDetailsIp,
          ConnectionField(entry.destIp, mono: true),
        ),
      if (app != null && app.value.isNotEmpty)
        (Icons.apps_rounded, l10n.connectionsDetailsApp, app),
      if (rule != null && rule.value.isNotEmpty)
        (Icons.rule_rounded, l10n.connectionsDetailsRule, rule),
      if (exit != null && exit.value.isNotEmpty)
        (Icons.call_split_rounded, l10n.connectionsDetailsExit, exit),
      if (entry.inbound.isNotEmpty)
        (
          Icons.login_rounded,
          l10n.connectionsDetailsInbound,
          ConnectionField(entry.inbound, mono: true),
        ),
      if (entry.members.isEmpty && entry.source.isNotEmpty)
        (
          Icons.computer_rounded,
          l10n.connectionsDetailsSource,
          ConnectionField(entry.source, mono: true),
        ),
      if (started != null)
        (
          Icons.schedule_rounded,
          entry.members.isEmpty
              ? l10n.connectionsDetailsStarted
              : l10n.connectionsDetailsFirst,
          ConnectionField(
            ConnectionTile.formatTime(started),
            mono: true,
            note: widget.live && !entry.closed
                ? l10n.connectionsDetailsOpenFor(
                    _clock(widget.now().difference(started)),
                  )
                : null,
          ),
        ),
      if (entry.download != null || entry.upload != null)
        (
          Icons.swap_vert_rounded,
          l10n.connectionsDetailsTraffic,
          ConnectionField(ConnectionTile.formatTraffic(entry), mono: true),
        ),
    ];
  }

  static String _clock(Duration d) {
    if (d.isNegative) return '00:00';
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0
        ? '${d.inHours}:$minutes:$seconds'
        : '$minutes:$seconds';
  }

  Widget _fieldRow(
    BuildContext context,
    IconData icon,
    String label,
    ConnectionField field,
  ) {
    final t = Theme.of(context).textTheme;
    final light = AppTheme.textLight(context);
    final text = AppTheme.text(context);
    final value = t.bodySmall?.copyWith(
      color: text,
      fontFamily: field.mono ? 'monospace' : null,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 13, color: light),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 88,
            child: Text(label, style: t.bodySmall?.copyWith(color: light)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (field.leading case final leading?) ...[
                      leading,
                      const SizedBox(width: 6),
                    ],
                    Flexible(child: SelectableText(field.value, style: value)),
                  ],
                ),
                if (field.note case final note?)
                  Text(note, style: t.bodySmall?.copyWith(color: light)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _members(
    BuildContext context,
    AppLocalizations l10n,
    List<ConnectionEntry> members,
  ) {
    final t = Theme.of(context).textTheme;
    final light = AppTheme.textLight(context);
    final text = AppTheme.text(context);
    final mono = t.bodySmall?.copyWith(fontFamily: 'monospace', color: text);
    final shown = _allMembers ? members : members.take(_shownMembers).toList();
    final hidden = members.length - shown.length;
    String state(ConnectionEntry m) {
      if (widget.live) return ConnectionTile.formatTraffic(m);
      if (!widget.livenessKnown) return '';
      return m.closed ? l10n.connectionsClosed : l10n.connectionsDetailsOpen;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final m in shown)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    m.startedAt == null
                        ? ''
                        : ConnectionTile.formatTime(m.startedAt!),
                    style: mono?.copyWith(color: light),
                  ),
                ),
                Expanded(
                  child: Text(
                    m.source,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  state(m),
                  style: (widget.live ? mono : t.bodySmall)?.copyWith(
                    color: m.closed ? light : text,
                  ),
                ),
              ],
            ),
          ),
        if (hidden > 0)
          TextButton(
            onPressed: () => setState(() => _allMembers = true),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
            child: Text(l10n.connectionsDetailsMore(hidden)),
          ),
      ],
    );
  }

  Widget _listRow(BuildContext context, ConnectionListLine line) {
    final t = Theme.of(context).textTheme;
    final light = AppTheme.textLight(context);
    final text = AppTheme.text(context);
    final hit = line.match == ListMatch.hit;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            switch (line.match) {
              ListMatch.hit => Icons.check_rounded,
              ListMatch.miss => Icons.remove_rounded,
              ListMatch.unknown => Icons.help_outline_rounded,
            },
            size: 15,
            color: hit ? text : light,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: line.name),
                  if (line.note case final note?)
                    TextSpan(
                      text: '  $note',
                      style: TextStyle(color: light),
                    ),
                ],
              ),
              style: t.bodySmall?.copyWith(color: hit ? text : light),
            ),
          ),
        ],
      ),
    );
  }

  Widget _plainCard(BuildContext context, Widget child) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppTheme.card(context),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppTheme.divider(context)),
    ),
    child: child,
  );

  Future<void> _copy(
    BuildContext context,
    ConnectionEntry entry,
    List<(IconData, String, ConnectionField)> fields,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final lines = [
      '${entry.target} ${entry.network.toUpperCase()} '
          '${ConnectionTile.verdictLabel(l10n, entry.verdict)}'
          '${entry.count > 1 ? ' ×${entry.count}' : ''}',
      for (final (_, label, field) in fields)
        '$label: ${field.value}${field.note == null ? '' : ' (${field.note})'}',
    ];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (!context.mounted) return;
    AppSnack.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.serversCopiedToClipboard)));
  }
}
