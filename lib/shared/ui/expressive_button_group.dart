import 'package:flutter/material.dart';

import 'expressive.dart';
import 'haptics.dart';

/// Один вариант в [ExpressiveConnectedButtons].
class ExpressiveSegment<T> {
  const ExpressiveSegment({
    required this.value,
    required this.label,
    this.icon,
    this.iconColor,
  });

  final T value;
  final String label;
  final IconData? icon;

  /// Цвет иконки в НЕвыбранном состоянии.
  ///
  /// Нужен там, где варианты сами по себе цветные по смыслу — «блокировать»
  /// красным, «мимо VPN» зелёным. У выбранного цвет всё равно уходит в
  /// `onPrimary`: он на заливке акцента, и своего оттенка там быть не может.
  /// Так смысловая раскраска остаётся видна, а контракт цветов компонента не
  /// ломается.
  final Color? iconColor;
}

/// Связанная группа кнопок — замена устаревшего `SegmentedButton`.
///
/// Выбранная плитка меняет форму на пилюлю и заливается акцентом. Форма здесь и
/// есть индикатор выбора: он виден боковым зрением и на монохромном экране, а у
/// сегментированной кнопки выбор отличался только заливкой да галочкой, которая
/// ещё и съедала ширину подписи.
///
/// Числа из спеки: зазор [_gap] одинаковый на любом размере, внешние углы
/// крайних кнопок полные, внутренние почти квадратные ([_innerCorner]). Соседи
/// на нажатие не реагируют — раздвигаются они только в обычной группе, не в
/// связанной.
///
/// Ширины равные: группа стоит в узком сайдбаре, и плитки по содержимому
/// прыгали бы на каждом переключении — «TUN» вдвое короче «Proxy».
class ExpressiveConnectedButtons<T> extends StatelessWidget {
  const ExpressiveConnectedButtons({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.height = 40,
  });

  final List<ExpressiveSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final double height;

  /// Зазор между плитками — 2dp, как велит спека связанной группы на любом её
  /// размере. Группа остаётся единым элементом, а не россыпью кнопок.
  static const double _gap = ExpressiveSpacing.hairline;

  /// Углы на стыках. 8dp — значение спеки для размеров S и M (высота 40 и 56).
  static const double _innerCorner = ExpressiveShape.small;

  /// Радиус пилюли — геометрический, половина высоты, а не признак
  /// [ExpressiveShape.full].
  ///
  /// Разница видна только в анимации, и она решающая. `full` рисуется радиусом
  /// 999, а движок всё равно зажимает его половиной высоты, то есть 20. Лерп от
  /// 999 к 8 почти всю дорогу держится выше этого потолка — кнопка стоит
  /// пилюлей, — и вся видимая часть перехода сваливается в последние проценты
  /// шкалы. Со стороны это то, чем и выглядело: снятая с выбора кнопка
  /// возвращала форму рывком. От 20 к 8 морфинг идёт весь, с первого кадра.
  static double _pillCorner(double height) => height / 2;

  /// Форма кнопки [index] из [count] в покоящемся (невыбранном) состоянии.
  static BorderRadius _restRadius(int index, int count, double height) {
    final outer = Radius.circular(_pillCorner(height));
    const inner = Radius.circular(_innerCorner);
    return BorderRadius.horizontal(
      left: index == 0 ? outer : inner,
      right: index == count - 1 ? outer : inner,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0) const SizedBox(width: _gap),
            Expanded(
              child: _Segment(
                segment: segments[i],
                selected: segments[i].value == selected,
                radius: _restRadius(i, segments.length, height),
                pillCorner: _pillCorner(height),
                scheme: scheme,
                onTap: () {
                  if (segments[i].value == selected) return;
                  AppHaptics.selection();
                  onChanged(segments[i].value);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Плитка группы: форма, заливка и обе анимации.
///
/// Движение пружинное, а не по кривой с длительностью, и пружины разные. Форма
/// слегка перелетает цель — это и есть физика, по которой узнаётся M3E; ровная
/// `emphasized`-кривая давала правильную геометрию и никакого характера. Цвет,
/// наоборот, задемпфирован критически: колебание яркости читается дефектом.
/// У нажатия пружина своя — вниз быстро и без отскока, пока палец на экране,
/// обратно с отдачей; кнопка при этом и поджимается, и становится квадратнее.
class _Segment<T> extends StatefulWidget {
  const _Segment({
    required this.segment,
    required this.selected,
    required this.radius,
    required this.pillCorner,
    required this.scheme,
    required this.onTap,
  });

  final ExpressiveSegment<T> segment;
  final bool selected;
  final BorderRadius radius;

  /// Углы выбранной кнопки. Приезжают числом, а не берутся из
  /// [ExpressiveShape.full] — см. `_pillCorner`.
  final double pillCorner;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  State<_Segment<T>> createState() => _SegmentState<T>();
}

class _SegmentState<T> extends State<_Segment<T>>
    with TickerProviderStateMixin {
  late final AnimationController _shape = AnimationController.unbounded(
    vsync: this,
  )..value = widget.selected ? 1 : 0;
  late final AnimationController _tint = AnimationController.unbounded(
    vsync: this,
  )..value = widget.selected ? 1 : 0;
  late final AnimationController _press = AnimationController.unbounded(
    vsync: this,
  );

  @override
  void didUpdateWidget(covariant _Segment<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected == widget.selected) return;
    final target = widget.selected ? 1.0 : 0.0;
    ExpressiveMotion.springTo(
      _shape,
      target,
      spring: ExpressiveMotion.spatialDefault,
    );
    ExpressiveMotion.springTo(
      _tint,
      target,
      spring: ExpressiveMotion.effectsDefault,
    );
  }

  @override
  void dispose() {
    _shape.dispose();
    _tint.dispose();
    _press.dispose();
    super.dispose();
  }

  void _setPressed(bool pressed) {
    ExpressiveMotion.springTo(
      _press,
      pressed ? 1 : 0,
      spring: pressed
          ? ExpressiveMotion.effectsFast
          : ExpressiveMotion.spatialDefault,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = widget.scheme;
    final textTheme = Theme.of(context).textTheme;
    final labelBase = textTheme.labelLarge ?? const TextStyle();
    final selectedRadius = BorderRadius.circular(widget.pillCorner);

    // Стиль filled-кнопки: невыбранная на поверхности, выбранная на `primary`.
    // Уровень `surfaceContainerHighest` — потому что группа живёт в шторке
    // (`surfaceContainerLow`), и на шаг выше она бы с неё не считывалась.
    final restStyle = labelBase.copyWith(color: scheme.onSurfaceVariant);
    final selectedStyle = textTheme
        .emphasized(labelBase)!
        .copyWith(color: scheme.onPrimary);

    return AnimatedBuilder(
      animation: Listenable.merge([_shape, _tint, _press]),
      builder: (context, _) {
        // Пружина перелетает за единицу — форме и цвету это лишнее, отдача
        // остаётся во времени возврата.
        final shapeT = _shape.value.clamp(0.0, 1.0);
        final tint = _tint.value.clamp(0.0, 1.0);
        final press = _press.value.clamp(0.0, 1.0);

        final rest = BorderRadius.lerp(widget.radius, selectedRadius, shapeT)!;
        final radius = BorderRadius.lerp(
          rest,
          ExpressiveShape.pressedRadius(rest),
          press,
        )!;
        final shape = RoundedRectangleBorder(borderRadius: radius);
        final iconColor = Color.lerp(
          widget.segment.iconColor ?? scheme.onSurfaceVariant,
          scheme.onPrimary,
          tint,
        )!;

        return Transform.scale(
          // Поджатие вместе с морфом. Без него нажатие по уже выбранной
          // пилюле не отзывалось ничем: её углы морфить некуда.
          scale: 1 - 0.04 * press,
          child: Material(
            color: Color.lerp(
              scheme.surfaceContainerHighest,
              scheme.primary,
              tint,
            ),
            shape: shape,
            clipBehavior: Clip.antiAlias,
            // Material сама доводит форму и цвет за 200 мс, а мы меняем их
            // покадрово — её неявная анимация только перезапускалась бы.
            animationDuration: Duration.zero,
            child: InkWell(
              onTap: widget.onTap,
              onTapDown: (_) => _setPressed(true),
              onTapUp: (_) => _setPressed(false),
              onTapCancel: () => _setPressed(false),
              customBorder: shape,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.segment.icon != null) ...[
                      Icon(
                        widget.segment.icon,
                        size: ExpressiveIconSize.inline,
                        color: iconColor,
                      ),
                      const SizedBox(width: ExpressiveSpacing.small),
                    ],
                    Flexible(
                      child: Text(
                        widget.segment.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // Вес и цвет едут одним лерпом: выбранное состояние
                        // весит больше — это роль усиленного варианта у M3E.
                        style: TextStyle.lerp(restStyle, selectedStyle, tint),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
