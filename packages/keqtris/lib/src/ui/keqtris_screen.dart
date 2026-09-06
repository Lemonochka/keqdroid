import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game.dart';
import '../rules.dart';
import '../tetromino.dart';
import 'board_painter.dart';
import 'skin.dart';

/// Подписи. По умолчанию английские: пакет не тянет за собой локализацию
/// приложения и не заводит свою — переводы передаёт хозяин экрана.
class KeqtrisLabels {
  final String title;
  final String score;
  final String best;
  final String lines;
  final String hold;
  final String next;
  final String gameOver;
  final String restart;
  final String newBest;

  const KeqtrisLabels({
    this.title = 'KEQTRIS',
    this.score = 'SCORE',
    this.best = 'BEST',
    this.lines = 'LINES',
    this.hold = 'HOLD',
    this.next = 'NEXT',
    this.gameOver = 'Game over',
    this.restart = 'Play again',
    this.newBest = 'New best',
  });
}

/// Экран игры.
///
/// Открывается как обычная страница поверх настроек, поэтому «пауза, пока не
/// смотрят» здесь достаётся даром: пока страницы нет на экране, каркас не
/// просит кадров, а без кадров движок не двигают.
class KeqtrisScreen extends StatefulWidget {
  /// Лучший результат за всё время. Показывается рядом с текущим счётом.
  final int bestScore;

  /// Зовётся по окончании партии с итоговым счётом. Сохранять его — дело
  /// хозяина экрана: пакет ничего не знает про хранилище приложения.
  final ValueChanged<int> onGameOver;

  final TetrisTuning tuning;
  final KeqtrisLabels labels;

  /// Отдача на действиях. Пакет не знает о настройках приложения — флаг
  /// приходит снаружи.
  final bool haptics;

  const KeqtrisScreen({
    super.key,
    required this.bestScore,
    required this.onGameOver,
    this.tuning = const TetrisTuning(),
    this.labels = const KeqtrisLabels(),
    this.haptics = false,
  });

  @override
  State<KeqtrisScreen> createState() => _KeqtrisScreenState();
}

class _KeqtrisScreenState extends State<KeqtrisScreen>
    with TickerProviderStateMixin {
  late final KeqtrisGame _game;
  late final Ticker _ticker;
  late final AnimationController _clearCtrl;
  final FocusNode _focus = FocusNode(debugLabel: 'keqtris');

  Duration _lastTick = Duration.zero;
  List<int> _clearedRows = const [];

  /// Счётчик кадров стакана.
  ///
  /// Отдельный [ValueNotifier], а не поле под `setState`: стакан меняется
  /// каждый кадр, а счёт, очередь и hold — раз в несколько секунд. Пересобирать
  /// из-за упавшей на клетку фигуры всю панель управления незачем.
  final ValueNotifier<int> _frame = ValueNotifier(0);

  // Снимок того, что показывают панели. Пока он не изменился, дерево не
  // перестраивается вовсе.
  int _hudScore = 0;
  int _hudLines = 0;
  Tetromino? _hudHold;
  bool _hudHoldAvailable = true;
  bool _hudGameOver = false;
  List<Tetromino> _hudPreview = const [];

  /// Рекорд, показываемый на экране: растёт прямо по ходу партии, как только
  /// счёт его перебил. Ждать конца партии, чтобы показать новый рекорд, —
  /// значит прятать от игрока единственное, ради чего он и играет.
  late int _best = widget.bestScore;
  bool _beatenThisGame = false;

  @override
  void initState() {
    super.initState();
    _game = KeqtrisGame(tuning: widget.tuning)..onLock = _onLock;
    _ticker = createTicker(_onTick)..start();
    _clearCtrl = AnimationController(
      vsync: this,
      duration: KeqtrisMotion.clearDuration,
      value: 1,
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clearCtrl.dispose();
    _frame.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    var dt = elapsed - _lastTick;
    _lastTick = elapsed;
    // После затора (открытая поверх шторка, смена темы) кадр приходит с
    // огромной дельтой. Отдать её движку — значит уронить фигуру на несколько
    // строк разом за кадр, которого игрок не видел.
    const maxStep = Duration(milliseconds: 100);
    if (dt > maxStep) dt = maxStep;
    _game.update(dt);
    _frame.value++;
    _syncHud();
  }

  /// Перестраивает дерево только когда изменилось что-то, что панели реально
  /// показывают.
  void _syncHud() {
    final preview = _game.preview;
    if (_hudScore == _game.score &&
        _hudLines == _game.lines &&
        _hudHold == _game.holdPiece &&
        _hudHoldAvailable == _game.holdAvailable &&
        _hudGameOver == _game.isGameOver &&
        listEquals(_hudPreview, preview)) {
      return;
    }
    final wasOver = _hudGameOver;
    setState(() {
      _hudScore = _game.score;
      _hudLines = _game.lines;
      _hudHold = _game.holdPiece;
      _hudHoldAvailable = _game.holdAvailable;
      _hudGameOver = _game.isGameOver;
      _hudPreview = preview;
      if (_game.score > _best) {
        _best = _game.score;
        _beatenThisGame = true;
      }
    });
    // Партия окончена — отдаём счёт наружу ровно один раз.
    if (!wasOver && _game.isGameOver) {
      _ticker.stop();
      widget.onGameOver(_game.score);
    }
  }

  void _onLock(LockEvent event) {
    if (event.lines > 0) {
      _clearedRows = event.clearedRows;
      _clearCtrl.forward(from: 0);
    }
    if (!widget.haptics) return;
    if (event.lines >= 4 || event.spin != SpinKind.none) {
      HapticFeedback.heavyImpact();
    } else if (event.lines > 0) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  void _press(GameInput input) {
    _game.press(input);
    if (widget.haptics) HapticFeedback.selectionClick();
    _frame.value++;
    _syncHud();
  }

  void _release(GameInput input) => _game.release(input);

  void _tap(GameInput input) {
    _press(input);
    _game.release(input);
  }

  void _restart() {
    _game.restart();
    _clearedRows = const [];
    _beatenThisGame = false;
    _lastTick = Duration.zero;
    if (!_ticker.isTicking) _ticker.start();
    _frame.value++;
    _syncHud();
  }

  // --- Клавиатура ------------------------------------------------------------

  // Не const: LogicalKeyboardKey переопределяет `==`, а такой тип константным
  // ключом карты быть не может.
  static final Map<LogicalKeyboardKey, GameInput> _keyMap = {
    LogicalKeyboardKey.arrowLeft: GameInput.left,
    LogicalKeyboardKey.arrowRight: GameInput.right,
    LogicalKeyboardKey.arrowDown: GameInput.softDrop,
    LogicalKeyboardKey.arrowUp: GameInput.rotateCw,
    LogicalKeyboardKey.keyX: GameInput.rotateCw,
    LogicalKeyboardKey.keyZ: GameInput.rotateCcw,
    LogicalKeyboardKey.controlLeft: GameInput.rotateCcw,
    LogicalKeyboardKey.space: GameInput.hardDrop,
    LogicalKeyboardKey.keyC: GameInput.hold,
    LogicalKeyboardKey.shiftLeft: GameInput.hold,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.keyR && event is KeyDownEvent) {
      _restart();
      return KeyEventResult.handled;
    }
    final input = _keyMap[event.logicalKey];
    if (input == null) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      _press(input);
    } else if (event is KeyUpEvent) {
      _release(input);
    }
    // Автоповтор системы глотаем молча: горизонтальным повтором заведует
    // собственный DAS/ARR, и второй источник повторов с ним бы дрался.
    return KeyEventResult.handled;
  }

  // --- Раскладка -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final skin = KeqtrisSkin.of(context);
    return Scaffold(
      backgroundColor: skin.scheme.surface,
      appBar: AppBar(
        backgroundColor: skin.scheme.surface,
        title: Text(widget.labels.title),
      ),
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              children: [
                _StatStrip(
                  skin: skin,
                  labels: widget.labels,
                  score: _hudScore,
                  best: _best,
                  lines: _hudLines,
                  beaten: _beatenThisGame,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Center(child: _buildBoard(skin))),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 62,
                        child: _SidePanel(
                          skin: skin,
                          labels: widget.labels,
                          hold: _hudHold,
                          holdAvailable: _hudHoldAvailable,
                          preview: _hudPreview,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _ControlPad(
                  skin: skin,
                  onPress: _press,
                  onRelease: _release,
                  onTap: _tap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBoard(KeqtrisSkin skin) {
    const radius = BorderRadius.all(Radius.circular(28));
    return AspectRatio(
      aspectRatio: kColumns / kVisibleRows,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: skin.well,
              borderRadius: radius,
              border: Border.all(color: skin.wellOutline),
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: RepaintBoundary(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _tap(GameInput.rotateCw),
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_frame, _clearCtrl]),
                    builder: (context, _) => CustomPaint(
                      // Без явного размера CustomPaint без ребёнка схлопнется
                      // в ноль: он берёт наименьший допустимый.
                      size: Size.infinite,
                      painter: BoardPainter(
                        game: _game,
                        skin: skin,
                        frame: _frame.value,
                        clearedRows: _clearedRows,
                        clearProgress: _clearCtrl.value,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_hudGameOver)
            _GameOverOverlay(
              skin: skin,
              labels: widget.labels,
              score: _hudScore,
              isBest: _beatenThisGame,
              onRestart: _restart,
            ),
        ],
      ),
    );
  }
}

/// Полоса счёта: ячейки равной доли ширины, чтобы числа не дёргали соседей при
/// росте разрядности.
class _StatStrip extends StatelessWidget {
  final KeqtrisSkin skin;
  final KeqtrisLabels labels;
  final int score;
  final int best;
  final int lines;
  final bool beaten;

  const _StatStrip({
    required this.skin,
    required this.labels,
    required this.score,
    required this.best,
    required this.lines,
    required this.beaten,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget cell(String label, String value, {bool accent = false}) => Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: text.labelSmall?.copyWith(
              color: accent ? skin.scheme.primary : skin.scheme.onSurfaceVariant,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            style: text.titleMedium?.copyWith(
              color: accent ? skin.scheme.primary : skin.scheme.onSurface,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: skin.scheme.surfaceContainer,
        borderRadius: const BorderRadius.all(Radius.circular(24)),
      ),
      child: Row(
        children: [
          cell(labels.score, '$score'),
          // Рекорд подсвечивается ровно в той партии, где его побили: иначе
          // момент, ради которого играют, ничем не отмечен.
          cell(labels.best, '$best', accent: beaten),
          cell(labels.lines, '$lines'),
        ],
      ),
    );
  }
}

/// Hold сверху, очередь под ним.
class _SidePanel extends StatelessWidget {
  final KeqtrisSkin skin;
  final KeqtrisLabels labels;
  final Tetromino? hold;
  final bool holdAvailable;
  final List<Tetromino> preview;

  const _SidePanel({
    required this.skin,
    required this.labels,
    required this.hold,
    required this.holdAvailable,
    required this.preview,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget caption(String value) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        value,
        style: text.labelSmall?.copyWith(
          color: skin.scheme.onSurfaceVariant,
          letterSpacing: 1.2,
        ),
      ),
    );

    Widget box(Tetromino? piece, {bool dimmed = false, double height = 40}) =>
        Container(
          height: height,
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: skin.scheme.surfaceContainerHigh,
            borderRadius: const BorderRadius.all(Radius.circular(16)),
          ),
          padding: const EdgeInsets.all(6),
          child: CustomPaint(
            size: Size.infinite,
            painter: PiecePainter(piece: piece, skin: skin, dimmed: dimmed),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        caption(labels.hold),
        // Использованный hold показывается приглушённым: правило «один раз до
        // фиксации» иначе выглядит поломкой кнопки.
        box(hold, dimmed: !holdAvailable),
        const SizedBox(height: 6),
        caption(labels.next),
        for (final piece in preview.take(4)) box(piece, height: 36),
      ],
    );
  }
}

class _GameOverOverlay extends StatelessWidget {
  final KeqtrisSkin skin;
  final KeqtrisLabels labels;
  final int score;
  final bool isBest;
  final VoidCallback onRestart;

  const _GameOverOverlay({
    required this.skin,
    required this.labels,
    required this.score,
    required this.isBest,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(28)),
      child: ColoredBox(
        // Затемнение только гасит стакан под карточкой. Текст на нём не живёт:
        // у затемнения нет своей on-роли, и любой подобранный цвет ломается на
        // другой яркости темы.
        color: skin.scheme.scrim.withValues(alpha: 0.55),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            decoration: BoxDecoration(
              color: skin.overlay,
              borderRadius: const BorderRadius.all(Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isBest ? labels.newBest : labels.gameOver,
                  textAlign: TextAlign.center,
                  style: text.headlineSmall?.copyWith(
                    // Новый рекорд — единственное, ради чего сюда смотрят
                    // дважды, поэтому он и единственное здесь цветное.
                    color: isBest ? skin.scheme.primary : skin.onOverlay,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$score',
                  style: text.headlineMedium?.copyWith(
                    color: skin.onOverlay,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(onPressed: onRestart, child: Text(labels.restart)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Экранные кнопки. Горизонталь и soft drop работают удержанием — повтор ведёт
/// движок своим DAS/ARR, поэтому кнопке достаточно сообщать нажатие и отпускание.
class _ControlPad extends StatelessWidget {
  final KeqtrisSkin skin;
  final void Function(GameInput) onPress;
  final void Function(GameInput) onRelease;
  final void Function(GameInput) onTap;

  const _ControlPad({
    required this.skin,
    required this.onPress,
    required this.onRelease,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            _PadButton(
              icon: Icons.swap_horiz_rounded,
              skin: skin,
              onTap: () => onTap(GameInput.hold),
            ),
            const SizedBox(width: 8),
            _PadButton(
              icon: Icons.rotate_left_rounded,
              skin: skin,
              onTap: () => onTap(GameInput.rotateCcw),
            ),
            const SizedBox(width: 8),
            _PadButton(
              icon: Icons.rotate_right_rounded,
              skin: skin,
              emphasized: true,
              onTap: () => onTap(GameInput.rotateCw),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _PadButton(
              icon: Icons.chevron_left_rounded,
              skin: skin,
              onPress: () => onPress(GameInput.left),
              onRelease: () => onRelease(GameInput.left),
            ),
            const SizedBox(width: 8),
            _PadButton(
              icon: Icons.keyboard_arrow_down_rounded,
              skin: skin,
              onPress: () => onPress(GameInput.softDrop),
              onRelease: () => onRelease(GameInput.softDrop),
            ),
            const SizedBox(width: 8),
            _PadButton(
              icon: Icons.chevron_right_rounded,
              skin: skin,
              onPress: () => onPress(GameInput.right),
              onRelease: () => onRelease(GameInput.right),
            ),
            const SizedBox(width: 8),
            _PadButton(
              icon: Icons.vertical_align_bottom_rounded,
              skin: skin,
              emphasized: true,
              onTap: () => onTap(GameInput.hardDrop),
            ),
          ],
        ),
      ],
    );
  }
}

class _PadButton extends StatefulWidget {
  final IconData icon;
  final KeqtrisSkin skin;
  final VoidCallback? onTap;
  final VoidCallback? onPress;
  final VoidCallback? onRelease;
  final bool emphasized;

  const _PadButton({
    required this.icon,
    required this.skin,
    this.onTap,
    this.onPress,
    this.onRelease,
    this.emphasized = false,
  });

  @override
  State<_PadButton> createState() => _PadButtonState();
}

class _PadButtonState extends State<_PadButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController.unbounded(
    vsync: this,
    value: 0,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _down() {
    KeqtrisMotion.springTo(_ctrl, 1);
    (widget.onPress ?? widget.onTap)?.call();
  }

  void _up() {
    KeqtrisMotion.springTo(_ctrl, 0);
    widget.onRelease?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = widget.skin.scheme;
    final background = widget.emphasized
        ? scheme.primaryContainer
        : scheme.secondaryContainer;
    final foreground = widget.emphasized
        ? scheme.onPrimaryContainer
        : scheme.onSecondaryContainer;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _down(),
        onTapUp: (_) => _up(),
        onTapCancel: _up,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            final t = _ctrl.value.clamp(0.0, 1.2);
            return Transform.scale(scale: 1 - t * 0.06, child: child);
          },
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              color: background,
              borderRadius: const BorderRadius.all(Radius.circular(20)),
            ),
            child: Icon(widget.icon, color: foreground, size: 26),
          ),
        ),
      ),
    );
  }
}
