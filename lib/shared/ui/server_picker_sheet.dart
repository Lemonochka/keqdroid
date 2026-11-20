import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_settings.dart';
import '../../l10n/app_localizations.dart';
import '../../models/server_item.dart';
import '../../models/subscription.dart';
import '../../providers/providers.dart';
import '../../services/ping_service.dart';
import '../../utils/server_sort.dart';
import '../extensions/build_context_l10n.dart';
import 'app_theme.dart';
import 'expressive.dart';
import 'server_row.dart';

// плоский список, чтобы ListView.builder строил строки лениво: их бывают сотни
sealed class _PickerEntry {
  const _PickerEntry();
}

final class _PickerHeader extends _PickerEntry {
  final String title;
  final int count;

  const _PickerHeader(this.title, this.count);
}

final class _PickerServer extends _PickerEntry {
  final ServerItem server;

  const _PickerServer(this.server);
}

// По подпискам, иначе одинаковые имена из разных подписок не отличить. Подписки и настройки через watch:
// на несозданном асинхронном провайдере read вернёт пустоту, и группы схлопнутся в ручные
class ServerPickerSheet extends ConsumerStatefulWidget {
  final String title;
  final String searchHint;
  final String emptyText;
  final List<ServerItem> candidates;

  final String? selectedId;

  const ServerPickerSheet({
    super.key,
    required this.title,
    required this.searchHint,
    required this.emptyText,
    required this.candidates,
    this.selectedId,
  });

  @override
  ConsumerState<ServerPickerSheet> createState() => _ServerPickerSheetState();
}

class _ServerPickerSheetState extends ConsumerState<ServerPickerSheet> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<ServerItem> get _filtered {
    final needle = _query.text.trim().toLowerCase();
    if (needle.isEmpty) return widget.candidates;
    return widget.candidates
        .where((s) =>
            s.displayName.toLowerCase().contains(needle) ||
            s.address.toLowerCase().contains(needle))
        .toList();
  }

  // порядок внутри группы из её же сортировки, иначе список выглядел бы чужим
  List<_PickerEntry> _entries(
    List<ServerItem> servers,
    AppLocalizations l10n,
    List<Subscription> subs,
    Map<String, String> sortModes,
  ) {
    final bySub = <String?, List<ServerItem>>{};
    for (final s in servers) {
      bySub.putIfAbsent(s.subscriptionId, () => []).add(s);
    }

    final entries = <_PickerEntry>[];
    void addGroup(String title, String groupKey, List<ServerItem>? group) {
      if (group == null || group.isEmpty) return;
      final sorted =
          sortServersBy(group, ServerSortMode.fromName(sortModes[groupKey]));
      entries.add(_PickerHeader(title, sorted.length));
      entries.addAll(sorted.map(_PickerServer.new));
    }

    for (final sub in subs) {
      addGroup(sub.name, sub.id, bySub[sub.id]);
    }
    const manualKey = ServersNotifier.manualGroupKey;
    addGroup(l10n.serversManualGroup, manualKey, bySub[null]);
    // подписку могли удалить, а серверы остаться: из выбора они пропадать не должны
    final known = {for (final sub in subs) sub.id};
    for (final entry in bySub.entries) {
      final id = entry.key;
      if (id == null || known.contains(id)) continue;
      addGroup(l10n.serversManualGroup, manualKey, entry.value);
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final subs = ref.watch(subscriptionsProvider).value ?? const [];
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();
    final sortModes = ref.watch(serverSortModesProvider);
    final items = _entries(_filtered, l10n, subs, sortModes);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  widget.title,
                  style: theme.textTheme
                      .emphasized(theme.textTheme.titleMedium)
                      ?.copyWith(color: AppTheme.text(context)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _query,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: widget.searchHint,
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: AppTheme.inset(context),
                    border: OutlineInputBorder(
                      borderRadius:
                          ExpressiveShape.radius(ExpressiveShape.medium),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 16, 32, 40),
                  child: Text(
                    widget.emptyText,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppTheme.textLight(context)),
                  ),
                )
              else
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppTheme.card(context),
                        borderRadius:
                            ExpressiveShape.radius(ExpressiveShape.extraLarge),
                        border: Border.all(color: AppTheme.divider(context)),
                      ),
                      child: ClipRRect(
                        borderRadius:
                            ExpressiveShape.radius(ExpressiveShape.extraLarge),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: items.length,
                          itemBuilder: (context, i) => switch (items[i]) {
                            _PickerHeader(:final title, :final count) =>
                              _groupHeader(title, count),
                            _PickerServer(:final server) =>
                              _pickerRow(server, settings),
                          },
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupHeader(String title, int count) => Container(
        height: 38,
        width: double.infinity,
        color: AppTheme.inset(context),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: AlignmentDirectional.centerStart,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: AppTheme.textLight(context)),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: AppTheme.textLight(context)),
            ),
          ],
        ),
      );

  Widget _pickerRow(ServerItem server, AppSettings settings) => SizedBox(
        height: ServerRow.height,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => Navigator.of(context).pop(server),
            child: ServerRow(
              server: server,
              pingMs: server.pingMs,
              lastTestedAt: server.lastTestedAt,
              pingColorType:
                  PingService.pingColorTypeForServer(server, settings),
              trailing: Icon(
                server.id == widget.selectedId
                    ? Icons.check_circle_rounded
                    : Icons.add_circle_outline_rounded,
                color: AppTheme.accent(context),
              ),
            ),
          ),
        ),
      );
}
