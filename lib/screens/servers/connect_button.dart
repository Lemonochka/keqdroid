part of '../servers_tab.dart';

/// Главная кнопка подключения.
///
/// Три вещи, которых у неё не было и без которых M3 Expressive не читается:
///  - **state layer и рипл** — раньше это был [GestureDetector] поверх
///    [AnimatedContainer], то есть нажатие вообще ничем не отзывалось;
///  - **морфинг формы при нажатии** — круг поджимается в скруглённый квадрат и
///    пружиной возвращается обратно. Это подпись всего языка M3E;
///  - **единая фаза состояния** — цвета фона, обводки и свечения едут по одной
///    шкале idle → connecting → connected, поэтому переход всегда согласован.
class _ConnectButton extends StatefulWidget {
  final bool isConnected;
  final bool isConnecting;
  final VoidCallback? onTap;

  const _ConnectButton({
    required this.isConnected,
    required this.isConnecting,
    required this.onTap,
  });

  @override
  State<_ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<_ConnectButton>
    with SingleTickerProviderStateMixin {
  static const double _size = 130;

  /// Unbounded — пружина M3E обязана перелетать за цель, иначе возврат формы
  /// выглядит как обычный ease.
  late final AnimationController _press = AnimationController.unbounded(
    vsync: this,
    value: 0,
  );

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _setPressed(bool pressed) {
    ExpressiveMotion.springTo(
      _press,
      pressed ? 1 : 0,
      // Вниз — быстро и без отскока (палец ещё на экране), обратно — обычной
      // пространственной пружиной, чтобы отскок было видно.
      spring: pressed
          ? ExpressiveMotion.effectsFast
          : ExpressiveMotion.spatialDefault,
    );
  }

  /// idle → connecting → connected одной шкалой 0…1.
  double get _phase {
    if (widget.isConnected) return 1;
    if (widget.isConnecting) return 0.5;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final idleBg = AppTheme.card(context);
    final accent = AppTheme.accent(context);
    final busyBg = accent.withValues(alpha: 0.18);
    final connectedBg = AppTheme.accentContainer(context);
    final idleBorder = AppTheme.divider(context);
    final activeBorder = accent.withValues(alpha: 0.45);

    return TweenAnimationBuilder<double>(
      tween: Tween(end: _phase),
      duration: ExpressiveMotion.durationDefault,
      curve: ExpressiveMotion.emphasized,
      builder: (context, phase, child) {
        final bg = phase <= 0.5
            ? Color.lerp(idleBg, busyBg, phase * 2)!
            : Color.lerp(busyBg, connectedBg, (phase - 0.5) * 2)!;
        // Обводка и свечение переключаются на акцент уже в первой половине
        // шкалы: подключение должно быть видно сразу, а не по факту успеха.
        final borderColor = Color.lerp(idleBorder, activeBorder, phase * 2)!;
        final borderWidth = 1 + phase.clamp(0.0, 0.5) * 2;
        final glow = Color.lerp(idleBg, accent, phase * 2)!;

        return AnimatedBuilder(
          animation: _press,
          builder: (context, _) {
            final t = _press.value.clamp(0.0, 1.0);
            final shape = _shape(t);
            final bordered = _shape(
              t,
              side: BorderSide(color: borderColor, width: borderWidth),
            );

            final shadow = BoxShadow(
              color: glow.withValues(alpha: 0.35),
              blurRadius: 30,
              spreadRadius: 6,
            );

            return Transform.scale(
              // Лёгкое поджатие вместе с морфом: у M3E нажатие уменьшает
              // площадь, а не только скругление.
              scale: 1 - 0.04 * t,
              child: DecoratedBox(
                // Свечение размывается каждый кадр — кнопка непрерывно «дышит».
                // Круг у движка на быстром пути, произвольный path — нет,
                // поэтому ShapeDecoration включаем только на время морфа.
                decoration: t == 0
                    ? BoxDecoration(shape: BoxShape.circle, boxShadow: [shadow])
                    : ShapeDecoration(shape: shape, shadows: [shadow]),
                child: Material(
                  color: bg,
                  shape: bordered,
                  // Material сама доводит форму и цвет за 200 мс. Мы меняем их
                  // покадрово, поэтому её неявная анимация только тормозила бы
                  // морф, перезапускаясь на каждом кадре.
                  animationDuration: Duration.zero,
                  // Клип не нужен: рипл обрезает по customBorder сам, а лишний
                  // antiAlias-клип платился бы на каждом кадре дыхания.
                  child: InkWell(
                    onTap: widget.onTap == null
                        ? null
                        : () {
                            // Главное действие приложения — заметная отдача,
                            // а не лёгкий щелчок выбора.
                            AppHaptics.impact();
                            widget.onTap!();
                          },
                    onTapDown: (_) => _setPressed(true),
                    onTapUp: (_) => _setPressed(false),
                    onTapCancel: () => _setPressed(false),
                    customBorder: shape,
                    child: SizedBox(
                      width: _size,
                      height: _size,
                      child: child,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
      // Иконка от фазы не зависит — держим её вне обоих билдеров, чтобы не
      // пересобирать поддерево AnimatedSwitcher на каждом кадре.
      child: _icon(context),
    );
  }

  /// Круг → скруглённый квадрат. `ShapeBorder.lerp` умеет этот переход сам,
  /// отдельного shape-morph API во Flutter 3.44 нет.
  ShapeBorder _shape(double t, {BorderSide side = BorderSide.none}) =>
      ShapeBorder.lerp(
        CircleBorder(side: side),
        RoundedRectangleBorder(
          borderRadius: ExpressiveShape.radius(ExpressiveShape.extraExtraLarge),
          side: side,
        ),
        t,
      )!;

  Widget _icon(BuildContext context) => AnimatedSwitcher(
        duration: ExpressiveMotion.durationFast,
        switchInCurve: ExpressiveMotion.emphasizedDecelerate,
        switchOutCurve: ExpressiveMotion.emphasizedAccelerate,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.7, end: 1.0).animate(animation),
            child: child,
          ),
        ),
        child: widget.isConnecting
            ? Padding(
                key: const ValueKey('spinner'),
                padding: const EdgeInsets.all(36),
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppTheme.accent(context),
                ),
              )
            : Icon(
                widget.isConnected ? Icons.pause_rounded : Icons.play_arrow_rounded,
                key: ValueKey(widget.isConnected ? 'pause' : 'play'),
                size: 52,
                color: widget.isConnected
                    ? AppTheme.onAccentContainer(context)
                    : AppTheme.text(context),
              ),
      );
}
