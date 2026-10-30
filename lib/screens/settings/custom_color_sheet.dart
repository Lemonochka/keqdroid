part of '../settings_tab.dart';

// применяем по кнопке: смена темы пересобирает всё дерево, 55 мс на Pixel 6a
Future<void> _showCustomColorSheet(
  BuildContext context, {
  required AppSettings current,
  required Future<void> Function(AppSettings) onSave,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _CustomColorSheet(current: current, onSave: onSave),
  );
}

class _CustomColorSheet extends StatefulWidget {
  final AppSettings current;
  final Future<void> Function(AppSettings) onSave;

  const _CustomColorSheet({required this.current, required this.onSave});

  @override
  State<_CustomColorSheet> createState() => _CustomColorSheetState();
}

class _CustomColorSheetState extends State<_CustomColorSheet> {
  // у серого нет оттенка, HCT отдаёт 0° (розовый). ниже этих порогов выбранный оттенок теряется
  static const double _minSaturation = 0.10;
  static const double _minValue = 0.15;

  late HSVColor _color;
  late DynamicSchemeVariant _variant;
  late final TextEditingController _hex;

  // без флага правка ходила по кругу поле - ползунок и переставляла курсор
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    final seed = parseThemeSeed(widget.current.customThemeSeed) ??
        kCustomThemeDefaultSeed;
    _color = _inRange(HSVColor.fromColor(seed));
    _variant = parseThemeVariant(widget.current.customThemeVariant);
    _hex = TextEditingController(text: formatThemeSeed(_color.toColor()));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  static HSVColor _inRange(HSVColor color) => color
      .withSaturation(color.saturation.clamp(_minSaturation, 1.0))
      .withValue(color.value.clamp(_minValue, 1.0));

  void _setColor(HSVColor value) {
    setState(() => _color = value);
    _syncing = true;
    _hex.text = formatThemeSeed(value.toColor());
    _syncing = false;
  }

  void _onHexChanged(String raw) {
    if (_syncing) return;
    final parsed = parseThemeSeed(raw);
    if (parsed == null) return;
    setState(() => _color = HSVColor.fromColor(parsed));
  }

  Future<void> _apply() async {
    await widget.onSave(widget.current.copyWith(
      themePresetId: kCustomThemePresetId,
      customThemeSeed: formatThemeSeed(_color.toColor()),
      customThemeVariant: _variant.name,
      followSystemTheme: false,
    ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final seed = _color.toColor();
    final preview = ColorScheme.fromSeed(
      seedColor: seed,
      brightness:
          widget.current.darkTheme ? Brightness.dark : Brightness.light,
      dynamicSchemeVariant: _variant,
    );

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Text(
                l10n.appearanceCustomColorSheetTitle,
                style: theme.textTheme.titleLarge,
              ),
            ),
            Flexible(
              child: SmoothScroll(
                builder: (context, controller) => ListView(
                  controller: controller,
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  children: [
                    Center(
                      child: _ThemeScreenMock(
                        scheme: widget.current.amoledBlack
                            ? applyAmoledBlack(preview)
                            : preview,
                        iconShape: ExpressiveIconShapeTheme.of(context),
                      ),
                    ),
                    const SizedBox(height: ExpressiveSpacing.large),
                    Text(
                      l10n.appearanceCustomColorVariant,
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: ExpressiveSpacing.small),
                    ExpressiveConnectedButtons<DynamicSchemeVariant>(
                      segments: [
                        ExpressiveSegment(
                          value: DynamicSchemeVariant.tonalSpot,
                          label: l10n.appearanceCustomColorVariantCalm,
                        ),
                        ExpressiveSegment(
                          value: DynamicSchemeVariant.vibrant,
                          label: l10n.appearanceCustomColorVariantVibrant,
                        ),
                        ExpressiveSegment(
                          value: DynamicSchemeVariant.fidelity,
                          label: l10n.appearanceCustomColorVariantExact,
                        ),
                      ],
                      selected: _variant,
                      onChanged: (v) => setState(() => _variant = v),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                      child: Text(
                        l10n.appearanceCustomColorVariantHint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.textLight(context),
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(height: ExpressiveSpacing.large),
                    _ColorSlider(
                      label: l10n.appearanceCustomColorHue,
                      value: _color.hue,
                      max: 360,
                      divisions: 360,
                      activeColor: seed,
                      onChanged: (v) => _setColor(_color.withHue(v)),
                    ),
                    _ColorSlider(
                      label: l10n.appearanceCustomColorSaturation,
                      value: _color.saturation,
                      min: _minSaturation,
                      max: 1,
                      divisions: 90,
                      activeColor: seed,
                      onChanged: (v) => _setColor(_color.withSaturation(v)),
                    ),
                    _ColorSlider(
                      label: l10n.appearanceCustomColorBrightness,
                      value: _color.value,
                      min: _minValue,
                      max: 1,
                      divisions: 85,
                      activeColor: seed,
                      onChanged: (v) => _setColor(_color.withValue(v)),
                    ),
                    const SizedBox(height: ExpressiveSpacing.small),
                    TextField(
                      controller: _hex,
                      textDirection: technicalInputDirection,
                      onChanged: _onHexChanged,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(6),
                        FilteringTextInputFormatter.allow(
                          RegExp('[0-9a-fA-F]'),
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: l10n.appearanceCustomColorHex,
                        prefixText: rtl ? null : '#  ',
                        suffixText: rtl ? '  #' : null,
                        helperText: l10n.appearanceCustomColorInvalid,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _apply,
                  child: Text(l10n.appearanceCustomColorApply),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final Color activeColor;
  final ValueChanged<double> onChanged;

  const _ColorSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.divisions,
    required this.activeColor,
    required this.onChanged,
    this.min = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        TvFocus.slider(
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            activeColor: activeColor,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
