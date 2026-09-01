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
                  Icon(Icons.travel_explore_rounded,
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
              ExpressiveConnectedButtons<bool>(
                segments: [
                  ExpressiveSegment(
                    value: true,
                    label: l10n.settingsRoutingGeoPickerGeosite,
                  ),
                  ExpressiveSegment(
                    value: false,
                    label: l10n.settingsRoutingGeoPickerGeoip,
                  ),
                ],
                selected: _geosite,
                onChanged: (v) => setState(() => _geosite = v),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _search,
                autofocus: true,
                style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppTheme.text(context)),
                // Рамка, заливка и цвета — из темы поля ввода.
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: l10n.settingsRoutingGeoPickerSearchHint,
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
                            trailing: Icon(Icons.add_rounded,
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
            // Связанная группа, а не чипы: у чипа в M3 роль фильтра, где
            // выбранных бывает несколько, а тип совпадения ровно один.
            ExpressiveConnectedButtons<RuleType>(
              segments: [
                for (final t in _types)
                  ExpressiveSegment(value: t, label: _ruleTypeLabel(l10n, t)),
              ],
              selected: _type,
              onChanged: (t) => setState(() => _type = t),
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
            // Действий тоже ровно одно. Смысловой цвет остаётся на иконках
            // невыбранных — на заливке акцента своего оттенка быть не может.
            ExpressiveConnectedButtons<RuleAction>(
              segments: [
                for (final a in _actions)
                  ExpressiveSegment(
                    value: a,
                    label: _ruleActionLabel(l10n, a),
                    icon: _ruleActionIcon(a),
                    iconColor: _ruleActionColor(context, a),
                  ),
              ],
              selected: _action,
              onChanged: (a) => setState(() => _action = a),
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
