part of '../settings_tab.dart';

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
    final source = _geosite
        ? widget.index.geositeCodes
        : widget.index.geoipCodes;
    final needle = _query.trim().toLowerCase();
    final list =
        source.where((c) => needle.isEmpty || c.contains(needle)).toList()
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
                  Icon(
                    Icons.travel_explore_rounded,
                    size: 18,
                    color: AppTheme.accent(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.settingsRoutingGeoPickerTitle,
                      style: Theme.of(context).textTheme
                          .emphasized(Theme.of(context).textTheme.titleMedium)
                          ?.copyWith(color: AppTheme.text(context)),
                    ),
                  ),
                  Text(
                    l10n.settingsRoutingItemCount(codes.length),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textLight(context),
                    ),
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
              TvTextField(
                autofocus: true,
                builder: (ctx, canRequestFocus) => TextField(
                  controller: _search,
                  canRequestFocus: canRequestFocus,
                  textDirection: technicalInputDirection,
                  autofocus: !TvFocus.enabled,
                  style: Theme.of(
                    ctx,
                  ).textTheme.bodyMedium?.copyWith(color: AppTheme.text(ctx)),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: l10n.settingsRoutingGeoPickerSearchHint,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: codes.isEmpty
                    ? Center(
                        child: Text(
                          l10n.settingsRoutingGeoPickerEmpty,
                          style: Theme.of(context).textTheme.bodySmall
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
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    fontFamily: 'monospace',
                                    color: AppTheme.text(context),
                                  ),
                            ),
                            trailing: Icon(
                              Icons.add_rounded,
                              size: 16,
                              color: AppTheme.accent(context),
                            ),
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
