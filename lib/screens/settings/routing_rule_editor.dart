part of '../settings_tab.dart';

/// Список доступных geo-кодов с поиском. Возвращает через `Navigator.pop`
/// готовый токен (`geosite:telegram` / `geoip:ru`).
class _GeoCodePickerSheet extends StatefulWidget {
  const _GeoCodePickerSheet({required this.index});

  final GeoAssetIndex index;

  @override
  State<_GeoCodePickerSheet> createState() => _GeoCodePickerSheetState();
}

class _GeoCodePickerSheetState extends State<_GeoCodePickerSheet> {
  final _search = TextEditingController();
  String _query = '';
  bool _geosite = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<String> get _codes {
    final source =
        _geosite ? widget.index.geositeCodes : widget.index.geoipCodes;
    final needle = _query.trim().toLowerCase();
    final list = source
        .where((c) => needle.isEmpty || c.contains(needle))
        .toList()
      ..sort();
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final codes = _codes;
    final prefix = _geosite ? 'geosite:' : 'geoip:';

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.travel_explore,
                      size: 18, color: AppTheme.accent(context)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.settingsRoutingGeoPickerTitle,
                      style: Theme.of(context)
                          .textTheme
                          .emphasized(Theme.of(context).textTheme.titleMedium)
                          ?.copyWith(color: AppTheme.text(context)),
                    ),
                  ),
                  Text(
                    l10n.settingsRoutingItemCount(codes.length),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppTheme.textLight(context)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _typeTab(
                      context,
                      label: l10n.settingsRoutingGeoPickerGeosite,
                      selected: _geosite,
                      onTap: () => setState(() => _geosite = true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _typeTab(
                      context,
                      label: l10n.settingsRoutingGeoPickerGeoip,
                      selected: !_geosite,
                      onTap: () => setState(() => _geosite = false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _search,
                autofocus: true,
                style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppTheme.text(context)),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: l10n.settingsRoutingGeoPickerSearchHint,
                  hintStyle: TextStyle(color: AppTheme.textLight(context)),
                  filled: true,
                  fillColor: AppTheme.inset(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ExpressiveShape.medium),
                    borderSide: BorderSide(color: AppTheme.divider(context)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ExpressiveShape.medium),
                    borderSide: BorderSide(color: AppTheme.divider(context)),
                  ),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: codes.isEmpty
                    ? Center(
                        child: Text(
                          l10n.settingsRoutingGeoPickerEmpty,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppTheme.textLight(context)),
                        ),
                      )
                    : ListView.builder(
                        itemCount: codes.length,
                        itemBuilder: (_, i) {
                          final code = codes[i];
                          return ListTile(
                            dense: true,
                            title: Text(
                              '$prefix$code',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    fontFamily: 'monospace',
                                    color: AppTheme.text(context),
                                  ),
                            ),
                            trailing: Icon(Icons.add,
                                size: 16, color: AppTheme.accent(context)),
                            onTap: () =>
                                Navigator.of(context).pop('$prefix$code'),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeTab(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final color = AppTheme.accent(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : AppTheme.bg(context),
          borderRadius: BorderRadius.circular(ExpressiveShape.medium),
          border: Border.all(
            color: selected ? color : AppTheme.divider(context),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? color : AppTheme.text(context),
              ),
        ),
      ),
    );
  }
}

/// Результат редактора правила: сохранить или удалить (null — отмена, из pop).
sealed class _RuleEditorResult {
  const _RuleEditorResult();
}

class _RuleSave extends _RuleEditorResult {
  final RoutingRule rule;
  const _RuleSave(this.rule);
}

class _RuleDelete extends _RuleEditorResult {
  const _RuleDelete();
}

/// Диалог создания/редактирования одного [RoutingRule]: имя, значения, тип
/// сопоставления и действие. Возвращает [_RuleEditorResult] через Navigator.pop.
class _RuleEditorDialog extends StatefulWidget {
  final RoutingRule? existing;
  const _RuleEditorDialog({this.existing});

  @override
  State<_RuleEditorDialog> createState() => _RuleEditorDialogState();
}

class _RuleEditorDialogState extends State<_RuleEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _values;
  late RuleType _type;
  late RuleAction _action;

  static const _types = [
    RuleType.domain,
    RuleType.ipCidr,
    RuleType.geoip,
    RuleType.geosite,
  ];
  static const _actions = [
    RuleAction.proxy,
    RuleAction.direct,
    RuleAction.block,
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _values = TextEditingController(text: e?.values.join('\n') ?? '');
    // processName в этом редакторе не предлагается — на всякий случай схлопываем
    // на domain, чтобы сегмент типа гарантированно имел выбранное значение.
    _type = (e != null && _types.contains(e.type)) ? e.type : RuleType.domain;
    _action = e?.action ?? RuleAction.proxy;
  }

  @override
  void dispose() {
    _name.dispose();
    _values.dispose();
    super.dispose();
  }

  List<String> _parseValues() => _values.text
      .split(RegExp(r'[\r\n,]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  void _save() {
    final values = _parseValues();
    if (values.isEmpty) return;
    final e = widget.existing;
    final rule = e == null
        ? RoutingRule.create(
            name: _name.text.trim(),
            type: _type,
            values: values,
            action: _action,
          )
        : e.copyWith(
            name: _name.text.trim(),
            type: _type,
            values: values,
            action: _action,
          );
    Navigator.pop<_RuleEditorResult>(context, _RuleSave(rule));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final accent = AppTheme.accent(context);
    final isEdit = widget.existing != null;
    return AlertDialog(
      backgroundColor: AppTheme.card(context),
      title: Text(
        isEdit
            ? l10n.settingsRoutingRuleEditTitle
            : l10n.settingsRoutingRuleNewTitle,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              style: TextStyle(color: AppTheme.text(context)),
              decoration: InputDecoration(
                isDense: true,
                labelText: l10n.settingsRoutingRuleName,
                hintText: l10n.settingsRoutingRuleNameHint,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _values,
              minLines: 2,
              maxLines: 5,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppTheme.text(context)),
              decoration: InputDecoration(
                isDense: true,
                labelText: l10n.settingsRoutingRuleValues,
                hintText: l10n.settingsRoutingRuleValuesHint,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.settingsRoutingRuleMatchBy,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: AppTheme.textLight(context)),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _types)
                  ChoiceChip(
                    label: Text(_ruleTypeLabel(l10n, t)),
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                    selectedColor: accent.withValues(alpha: 0.18),
                    labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: _type == t ? accent : AppTheme.text(context),
                          fontWeight:
                              _type == t ? FontWeight.w700 : FontWeight.w500,
                        ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              l10n.settingsRoutingRuleAction,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: AppTheme.textLight(context)),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in _actions)
                  ChoiceChip(
                    label: Text(_ruleActionLabel(l10n, a)),
                    selected: _action == a,
                    onSelected: (_) => setState(() => _action = a),
                    selectedColor:
                        _ruleActionColor(context, a).withValues(alpha: 0.18),
                    labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: _action == a
                              ? _ruleActionColor(context, a)
                              : AppTheme.text(context),
                          fontWeight:
                              _action == a ? FontWeight.w700 : FontWeight.w500,
                        ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (isEdit)
          TextButton(
            onPressed: () => Navigator.pop<_RuleEditorResult>(
                context, const _RuleDelete()),
            child: Text(
              l10n.subscriptionsDelete,
              style: TextStyle(color: AppTheme.red(context)),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.subscriptionsCancel),
        ),
        FilledButton(
          onPressed: _parseValues().isEmpty ? null : _save,
          child: Text(l10n.settingsRoutingRuleSave),
        ),
      ],
    );
  }
}
