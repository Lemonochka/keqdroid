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

/// Тикеров у кнопки ТРИ, а не один: свой на нажатие плюс два внутри
/// [ShapeMorphCycle] (морфинг фигуры и независимое вращение). С
/// `SingleTickerProviderStateMixin` это падало ассертом при первом же создании
/// цикла — то есть в debug фигур на кнопке не было вовсе, а в release ассерт
/// вырезан, и вместо падения ломался `TickerMode`: со скрытого экрана
/// продолжал тикать только последний созданный тикер.
class _ConnectButtonState extends State<_ConnectButton>
    with TickerProviderStateMixin {
  /// `XLargeIconButtonTokens.ContainerHeight`.
  static const double _size = 136;

  /// Углы включённого состояния — ОСОЗНАННОЕ отступление от спеки.
  ///
  /// Таблица углов кнопок-иконок даёт для размера XL квадратную форму в 28dp, и
  /// раньше стояло ровно оно. Формально верно, на глаз — нет: на стороне в
  /// 136dp это пятая часть, и включённая кнопка читается просто квадратом. На
  /// сорока восьми она остаётся отличимой от круга (в этом весь смысл смены
  /// формы), но перестаёт быть углом.
  ///
  /// 48 — не произвольное число, а `extraExtraLarge` нашей шкалы форм: шаг,
  /// заведённый как раз под «геройские» элементы, а кнопка подключения ровно
  /// такой и есть — единственный объект такого размера во всём приложении.
  static const double _selectedCorner = ExpressiveShape.extraExtraLarge;

  /// Нажатая форма. Спека сжимает XL с 28 до 16, то есть примерно на 40%; та же
  /// доля от сорока восьми — двадцать восемь. Так нажатие остаётся заметным и
  /// на круге, и на включённой форме.
  static const double _pressedCorner = ExpressiveShape.extraLarge;

  /// `XLargeIconButtonTokens.IconSize`.
  static const double _iconSize = 40;

  /// Unbounded — пружина M3E обязана перелетать за цель, иначе возврат формы
  /// выглядит как обычный ease.
  late final AnimationController _press = AnimationController.unbounded(
    vsync: this,
    value: 0,
  );

  /// Живёт только пока идёт подключение: на это время форма кнопки И ЕСТЬ
  /// индикатор загрузки.
  ///
  /// Фигура внутри статичного круга противоречила замыслу M3E — движение
  /// показывает индикатор, а рамка вокруг него стоит на месте и это движение
  /// гасит. Поэтому морфится сам элемент, а не картинка в нём.
  ShapeMorphCycle? _cycle;

  @override
  void initState() {
    super.initState();
    _syncCycle();
  }

  @override
  void didUpdateWidget(covariant _ConnectButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isConnecting != widget.isConnecting ||
        oldWidget.isConnected != widget.isConnected) {
      // Страховка от залипшего нажатия: системный диалог разрешения VPN
      // забирает окно, и `onTapUp`/`onTapCancel` до нас могут не дойти — кнопка
      // осталась бы поджатой и квадратной до следующего касания. К этому
      // моменту действие уже сработало, отпускать её в любом случае пора.
      _setPressed(false);
    }
    _syncCycle();
  }

  void _syncCycle() {
    if (widget.isConnecting) {
      final running = _cycle;
      if (running == null) {
        _cycle = ShapeMorphCycle(vsync: this);
      } else if (running.isSettling) {
        // Подключение возобновилось, пока фигура доезжала до круга. На ПЕРВОМ
        // подключении это штатный ход событий: система показывает диалог
        // разрешения VPN, статус на это время уходит из «подключается» и
        // возвращается только после согласия. Раньше `??=` подхватывал уже
        // доводящийся цикл, тот добегал до конца и обнулял себя — фигур на
        // кнопке не появлялось вовсе, оставалась статичная иконка.
        running.resume();
      }
      return;
    }
    // Подключение кончилось — не обрываем цикл на произвольной форме, а даём
    // фигуре доехать до круга и только потом убираем её. Иначе клевер скачком
    // превращался в иконку.
    final cycle = _cycle;
    if (cycle == null || cycle.isSettling) return;
    cycle.settle(
      onDone: () {
        if (!mounted) {
          cycle.dispose();
          return;
        }
        setState(() => _cycle = null);
        // Освобождаем НЕ сразу: AnimatedSwitcher ещё доигрывает исчезновение
        // старого кадра, а тот подписан на этот же цикл. Убить его в этот
        // момент значит дёргать мёртвый ChangeNotifier из живого билдера.
        Future.delayed(ExpressiveMotion.durationFast, cycle.dispose);
      },
    );
  }

  @override
  void dispose() {
    _cycle?.dispose();
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

  /// Выбранность toggle-кнопки: 0 — не выбрана, 1 — выбрана.
  ///
  /// Промежуточной ступени для «подключается» здесь нет и быть не должно: у
  /// toggle-кнопки ровно два состояния, а ожидание — это не третье состояние
  /// компонента, а работа индикатора внутри. Раньше здесь стояло 0.5, и
  /// кнопка застревала в форме и цвете, которых в спеке нет.
  double get _phase => widget.isConnected ? 1 : 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Стиль — filled, по FilledIconButtonTokens: не выбрана SurfaceContainer,
    // выбрана Primary.
    //
    // Тональный вариант отсюда убран намеренно. Он опирается на `Secondary`, а
    // эта роль генерируется из того же исходного цвета с СИЛЬНО пониженной
    // насыщенностью — на синей системной теме она уезжает в лавандовый. То
    // есть кнопка переставала быть синей не из-за ошибки, а по устройству
    // палитры: «вторичный» в M3 это не «тот же цвет потише», а отдельный тон.
    // Раз тема системная и синяя, кнопка обязана оставаться в семье `Primary`.
    final unselectedBg = scheme.surfaceContainer;
    final selectedBg = scheme.primary;

    return TweenAnimationBuilder<double>(
      tween: Tween(end: _phase),
      duration: ExpressiveMotion.durationDefault,
      curve: ExpressiveMotion.emphasized,
      builder: (context, phase, child) {
        final bg = Color.lerp(unselectedBg, selectedBg, phase)!;

        return AnimatedBuilder(
          animation: Listenable.merge([_press, _cycle]),
          builder: (context, _) {
            final t = _press.value.clamp(0.0, 1.0);
            final shape = _shape(t, phase);

            return Transform.scale(
              // Лёгкое поджатие вместе с морфом: у M3E нажатие уменьшает
              // площадь, а не только скругление.
              scale: 1 - 0.04 * t,
              child: DecoratedBox(
                // Форма без тени: у icon button нет высоты — ни в одном из
                // четырёх стилей. Тень (а до неё цветное сияние) была нашей
                // добавкой и делала из кнопки FAB, которым она не является.
                decoration: ShapeDecoration(shape: shape),
                child: Material(
                  color: bg,
                  // Обводки тоже нет: она есть только у outlined-стиля и там
                  // равна 3dp. У filled-кнопки её быть не должно.
                  shape: shape,
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

  /// Фигура внутри кнопки, пока идёт подключение.
  ///
  /// Это «contained loading indicator» из M3E, только крупный: круглая подложка
  /// (сама кнопка) и фигура внутри неё. Пропорция взята из спеки — 38 из 48, то
  /// есть [ShapeLoadingIndicator.activeScale]. Морфящаяся кнопка без подложки,
  /// которая была здесь до этого, замыслу компонента не отвечает: у него
  /// подложка есть, и она же даёт фигуре контраст на пёстром фоне.
  /// [cycle] передаётся аргументом, а не читается из поля.
  ///
  /// Иначе получается отложенная мина: AnimatedSwitcher доигрывает исчезновение
  /// СТАРОГО кадра уже после того, как поле обнулили, и `_cycle!` в его
  /// билдере падал бы на null. Исключение в build гасит render object молча —
  /// на экране это выглядело как мигание в момент подключения.
  Widget _morphFigure(BuildContext context, ShapeMorphCycle cycle) =>
      RepaintBoundary(
        key: const ValueKey('morph'),
        child: AnimatedBuilder(
          animation: cycle,
          builder: (context, _) => CustomPaint(
            size: const Size.square(_size),
            painter: MorphPainter(
              morph: cycle.morph,
              progress: cycle.progress,
              degrees: cycle.degrees,
              scale: ShapeLoadingIndicator.activeScale,
              // Цвет ВЫБРАННОЙ кнопки, а не «содержимое поверх контейнера».
              //
              // Роль `on*Container` существует ради контраста с фоном и оттого
              // всегда почти чёрная — для подписи это правильно, а для фигуры
              // в пол-кнопки давало тяжёлое пятно. Здесь фигура показывает, во
              // что кнопка вот-вот превратится, поэтому берёт её цвет.
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );

  /// Форма кнопки по правилам toggle icon button из M3 Expressive.
  ///
  /// У этого компонента форма меняется ДВАЖДЫ и по разным поводам:
  ///
  ///  * **при выборе** — покоящаяся форма невыбранной кнопки круглая, выбранной
  ///    квадратная (скруглённая). Это штатный индикатор состояния: он читается
  ///    боковым зрением и не зависит от цвета. Раньше состояние у нас выражал
  ///    только цвет заливки, а форма была кругом всегда;
  ///  * **при нажатии** — обе формы, и круглая, и квадратная, сходятся к одной
  ///    и той же нажатой. Поэтому press применяется ПОВЕРХ покоящейся, а не
  ///    вместо неё.
  ///
  /// [selected] — доля перехода в выбранное состояние, [press] — в нажатое.
  ShapeBorder _shape(
    double press,
    double selected, {
    BorderSide side = BorderSide.none,
  }) {
    final rest = ShapeBorder.lerp(
      CircleBorder(side: side),
      RoundedRectangleBorder(
        borderRadius: ExpressiveShape.radius(_selectedCorner),
        side: side,
      ),
      selected,
    )!;
    return ShapeBorder.lerp(
      rest,
      RoundedRectangleBorder(
        borderRadius: ExpressiveShape.radius(_pressedCorner),
        side: side,
      ),
      press,
    )!;
  }

  Widget _icon(BuildContext context) {
    // Не `isConnecting`, а наличие цикла: после успеха он ещё живёт, пока
    // фигура доезжает до круга (см. _syncCycle).
    final cycle = _cycle;
    return AnimatedSwitcher(
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
      child: cycle != null
          ? _morphFigure(context, cycle)
          // Outlined когда не выбрано, filled когда выбрано — прямая
          // рекомендация спеки для toggle-кнопок. Раньше обе иконки были
          // filled, и состояние держалось на одном цвете.
          : Icon(
              widget.isConnected
                  ? Icons.pause_rounded
                  : Icons.play_arrow_outlined,
              key: ValueKey(widget.isConnected ? 'pause' : 'play'),
              size: _iconSize,
              // FilledIconButtonTokens: не выбрана — OnSurfaceVariant,
              // выбрана — OnPrimary.
              color: widget.isConnected
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
    );
  }
}
