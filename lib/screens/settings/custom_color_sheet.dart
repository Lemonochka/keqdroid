part of '../settings_tab.dart';

/// Подбор своего цвета темы.
///
/// Тремя ползунками, а не палитрой-квадратом: квадрат с пипеткой пришлось бы
/// рисовать самим, а M3 такого органа управления не знает вовсе — в отличие от
/// ползунка, который здесь тот же самый, что у размера интерфейса.
///
/// Ползунков три, но работают они ровно настолько, насколько позволяет вариант
/// палитры, — поэтому он выбирается здесь же, над ними.
///
/// Правки живут в шторке и уезжают в настройки по «Применить», а не сразу.
/// Смена темы пересобирает всё дерево виджетов (замер — 55 мс на Pixel 6a), и
/// применять её на каждый кадр перетаскивания значит показывать рывки вместо
/// цвета. Образец при этом обновляется непрерывно: считается одна схема, а не
/// две темы, и это единицы миллисекунд.
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
  /// Ниже этого ползунки не опускаются, и это не вкусовщина, а замер.
  ///
  /// Палитру Material строит из ОТТЕНКА сида, а у чёрного, белого и серого
  /// оттенка нет: конвертер отдаёт для них 0° либо 209.5° — что угодно, только
  /// не выбранное человеком. Отсюда и «выкрутил всё в ноль, получил розовый»:
  /// ноль градусов в HCT это красно-розовый угол.
  ///
  /// Порог взят по замеру, где оттенок ещё доезжает до палитры: при
  /// насыщенности 0.03 и яркости 0.06 все четыре пробных оттенка (0/90/210/300)
  /// дали одну и ту же схему — на такой темноте 8-битный цвет округляется в
  /// один и тот же серый. При 0.10/0.15 оттенки расходятся честно.
  static const double _minSaturation = 0.10;
  static const double _minValue = 0.15;

  late HSVColor _color;
  late DynamicSchemeVariant _variant;
  late final TextEditingController _hex;

  /// Ползунок правит поле, поле правит ползунок — и без флага каждая правка
  /// возвращалась бы вторым кругом обратно, переставляя курсор в поле.
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    final seed = parseThemeSeed(widget.current.customThemeSeed) ??
        kCustomThemeDefaultSeed;
    // В диапазон ползунков: иначе сохранённый когда-то чёрный открывал бы
    // шторку с бегунками на краю и палитрой, к этому краю не относящейся.
    _color = _inRange(HSVColor.fromColor(seed));
    _variant = parseThemeVariant(widget.current.customThemeVariant);
    _hex = TextEditingController(text: formatThemeSeed(_color.toColor()));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  /// Цвет, из которого палитра ещё получается осмысленной.
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
    // Выбор своего цвета выключает системные цвета по той же причине, что и
    // выбор готового пресета: пока они включены, палитра берётся у системы, и
    // тап выглядел бы «ничего не делает».
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
                  // Иначе список забирает всю высоту, отпущенную шторке, и на
                  // высоком экране получается панель во весь рост с пустотой
                  // между полем и кнопкой. С shrinkWrap шторка ровно по
                  // содержимому, а прокрутка появляется, когда оно не влезло.
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
                    // Вариант стоит НАД ползунками, потому что решает, что
                    // они делают. На `tonalSpot` Material приводит цвет к своим
                    // тонам, и до палитры доезжает почти один оттенок: замер
                    // сдвига `primary` (сумма по каналам, 0..765) при уходе
                    // насыщенности с 0.9 на 0.15 — 28, при уходе яркости с 0.9
                    // на 0.25 — 7. Два ползунка из трёх не делали ничего. На
                    // `fidelity` те же движения дают 147 и 224.
                    //
                    // Почему выбор, а не просто перевод всех своих тем на
                    // `fidelity`: в тёмной схеме он кладёт сид в контейнеры на
                    // полной насыщенности, и экран светится целиком — ровно то,
                    // из-за чего у пресетов умолчанием стоит `tonalSpot` (см.
                    // ThemePreset.variant). Здесь оно тоже остаётся прежним.
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
                    // Подпись тем же приёмом, что пояснения на экране тем:
                    // bodySmall приглушённым цветом с отступом 4 слева — так
                    // она читается продолжением группы, а не отдельным абзацем.
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
                      // Целые градусы: доли градуса на глаз неотличимы, а
                      // деления дают ползунку внятные остановки.
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
                      onChanged: _onHexChanged,
                      textCapitalization: TextCapitalization.characters,
                      // Ровно шесть цифр и только шестнадцатеричные: иначе
                      // строка растёт бесконечно, а разбор молча не срабатывает
                      // — снаружи это «ввожу код, ничего не происходит».
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(6),
                        FilteringTextInputFormatter.allow(
                          RegExp('[0-9a-fA-F]'),
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: l10n.appearanceCustomColorHex,
                        prefixText: '#  ',
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

/// Строка «подпись — ползунок». Ползунок штатный: обновлённую отрисовку M3 ему
/// даёт тема приложения (`SliderThemeData(year2023: false)`), поэтому своей
/// геометрии тут нет и быть не должно.
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
        Slider(
          // Набранный руками hex может лежать вне шкалы (чёрный, белый) —
          // ползунок тогда встаёт на край, а цвет остаётся тем, что набрали.
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          // Ползунок красится набранным цветом — на нём и видно, что крутишь.
          activeColor: activeColor,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
