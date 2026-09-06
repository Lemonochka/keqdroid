import 'dart:math';

import 'bag.dart';
import 'playfield.dart';
import 'rules.dart';
import 'srs.dart';
import 'tetromino.dart';

/// Действия игрока. Движок не знает ни про клавиши, ни про жесты — только про
/// эти семь намерений.
enum GameInput { left, right, softDrop, hardDrop, rotateCw, rotateCcw, hold }

/// Чем закончилась укладка фигуры. Отдаётся наружу для отдачи и анимации; на
/// счёт уже учтено внутри.
class LockEvent {
  final Tetromino piece;
  final int lines;
  final SpinKind spin;
  final bool backToBack;
  final int combo;
  final bool perfectClear;
  final bool levelUp;
  final List<int> clearedRows;

  const LockEvent({
    required this.piece,
    required this.lines,
    required this.spin,
    required this.backToBack,
    required this.combo,
    required this.perfectClear,
    required this.levelUp,
    required this.clearedRows,
  });
}

/// Ядро игры: чистый Dart, ни одного импорта Flutter.
///
/// Машина состояний, которую двигают снаружи: [update] на каждый кадр,
/// [press]/[release] на ввод. Собственного таймера у неё нет намеренно —
/// именно поэтому «игра стоит, пока экран закрыт» здесь не костыль, а
/// отсутствие вызовов.
class KeqtrisGame {
  final TetrisTuning tuning;
  final Playfield field = Playfield();
  final PieceQueue _queue;

  /// Вызывается на каждой фиксации фигуры.
  void Function(LockEvent event)? onLock;

  KeqtrisGame({this.tuning = const TetrisTuning(), Random? random})
    : _queue = PieceQueue(random: random) {
    _spawnNext();
  }

  // --- Активная фигура -------------------------------------------------------

  late Tetromino _piece;
  int _state = 0;
  int _row = kSpawnRow;
  int _col = kSpawnColumn;

  Tetromino get piece => _piece;
  int get rotationState => _state;

  // --- Прогресс --------------------------------------------------------------

  int _score = 0;
  int _lines = 0;
  int _level = 1;
  int _combo = -1;
  bool _backToBack = false;
  bool _gameOver = false;

  int get score => _score;
  int get lines => _lines;
  int get level => _level;
  int get combo => _combo;
  bool get backToBack => _backToBack;
  bool get isGameOver => _gameOver;

  /// Пока true, [update] не делает ничего. Игра стоит там, где стояла.
  bool paused = false;

  // --- Hold ------------------------------------------------------------------

  Tetromino? _hold;
  bool _holdUsed = false;

  Tetromino? get holdPiece => _hold;
  bool get holdAvailable => !_holdUsed;

  /// Ближайшие фигуры, первая — следующая в игре.
  List<Tetromino> get preview => _queue.preview;

  // --- Тайминги --------------------------------------------------------------

  /// Насколько фигура прошла до следующей клетки, долей от 0 до 1.
  ///
  /// Именно доля, а не накопленное время, и это принципиально: интервал падения
  /// меняется на лету (soft drop делит его на двадцать). Копили бы время —
  /// накопленное под медленную гравитацию в момент нажатия ускорения поделилось
  /// бы на новый, короткий интервал и выдалось пачкой шагов за один кадр:
  /// фигура улетала бы в самый низ, как от hard drop.
  double _dropProgress = 0;
  Duration _lockTimer = Duration.zero;
  int _lockResets = 0;
  int _lowestRow = kSpawnRow;

  final Set<GameInput> _held = {};
  int _direction = 0;
  Duration _autoShiftTimer = Duration.zero;

  /// Последним удавшимся действием было вращение — обязательное условие
  /// засчитывания T-spin.
  bool _lastActionWasRotation = false;

  /// Индекс сработавшей попытки в таблице кика последнего вращения.
  int _lastKickIndex = 0;

  // --- Кадр ------------------------------------------------------------------

  void update(Duration dt) {
    if (paused || _gameOver || dt <= Duration.zero) return;
    _updateAutoShift(dt);
    _updateGravity(dt);
    _updateLockDelay(dt);
  }

  void _updateAutoShift(Duration dt) {
    if (_direction == 0) return;
    final arr = tuning.arr > Duration.zero
        ? tuning.arr
        : const Duration(milliseconds: 1);
    _autoShiftTimer -= dt;
    // Больше kColumns сдвигов за кадр смысла не имеют: фигура упрётся в стену.
    var guard = kColumns;
    while (_autoShiftTimer <= Duration.zero && guard-- > 0) {
      _shift(_direction);
      _autoShiftTimer += arr;
    }
    if (_autoShiftTimer <= Duration.zero) _autoShiftTimer = arr;
  }

  void _updateGravity(Duration dt) {
    final interval = _dropInterval();
    _dropProgress += dt.inMicroseconds / interval.inMicroseconds;
    // Ограничение шагов за кадр — страховка от гравитации, которая на высоких
    // уровнях меньше микросекунды.
    var guard = kTotalRows;
    while (_dropProgress >= 1 && guard-- > 0) {
      _dropProgress -= 1;
      if (!_moveDown()) {
        _dropProgress = 0;
        break;
      }
      if (_held.contains(GameInput.softDrop)) {
        _score += kSoftDropScorePerCell;
      }
    }
  }

  Duration _dropInterval() {
    final base = gravityPerRow(_level);
    if (!_held.contains(GameInput.softDrop)) return base;
    final micros = base.inMicroseconds ~/ tuning.softDropFactor;
    return Duration(microseconds: max(1, micros));
  }

  void _updateLockDelay(Duration dt) {
    if (!_isGrounded) {
      _lockTimer = Duration.zero;
      return;
    }
    _lockTimer += dt;
    if (_lockTimer >= tuning.lockDelay) _lockPiece();
  }

  bool get _isGrounded => !field.fits(_piece, _state, _row + 1, _col);

  // --- Ввод ------------------------------------------------------------------

  void press(GameInput input) {
    if (_gameOver) return;
    _held.add(input);
    switch (input) {
      case GameInput.left:
        _startAutoShift(-1);
      case GameInput.right:
        _startAutoShift(1);
      case GameInput.rotateCw:
        _rotate(1);
      case GameInput.rotateCcw:
        _rotate(-1);
      case GameInput.hardDrop:
        _hardDrop();
      case GameInput.hold:
        _swapHold();
      case GameInput.softDrop:
        // Soft drop работает удержанием — на самом нажатии делать нечего.
        break;
    }
  }

  void release(GameInput input) {
    _held.remove(input);
    if (input == GameInput.left && _direction == -1) {
      _startAutoShift(_held.contains(GameInput.right) ? 1 : 0);
    } else if (input == GameInput.right && _direction == 1) {
      _startAutoShift(_held.contains(GameInput.left) ? -1 : 0);
    }
  }

  /// Отпускает всё разом. Нужно на уходе с экрана: иначе зажатая на момент
  /// ухода кнопка осталась бы зажатой навсегда.
  void releaseAll() {
    _held.clear();
    _direction = 0;
  }

  void _startAutoShift(int direction) {
    _direction = direction;
    if (direction == 0) return;
    _shift(direction);
    _autoShiftTimer = tuning.das;
  }

  // --- Движение --------------------------------------------------------------

  bool _shift(int direction) {
    if (!field.fits(_piece, _state, _row, _col + direction)) return false;
    _col += direction;
    _lastActionWasRotation = false;
    _onSuccessfulMove();
    return true;
  }

  bool _moveDown() {
    if (!field.fits(_piece, _state, _row + 1, _col)) return false;
    _row++;
    _lastActionWasRotation = false;
    if (_row > _lowestRow) {
      // Новая нижняя точка обнуляет счётчик перезапусков: лимит в 15 ресетов
      // ограничивает возню на одной высоте, а не спуск.
      _lowestRow = _row;
      _lockResets = 0;
      _lockTimer = Duration.zero;
    }
    return true;
  }

  bool _rotate(int turn) {
    if (!_piece.rotates) {
      _state = (_state + turn) & 3;
      return true;
    }
    final target = (_state + turn) & 3;
    final kicks = kicksFor(_piece, _state, target);
    for (var i = 0; i < kicks.length; i++) {
      final row = _row + kicks[i].rowOffset;
      final col = _col + kicks[i].colOffset;
      if (!field.fits(_piece, target, row, col)) continue;
      _state = target;
      _row = row;
      _col = col;
      _lastActionWasRotation = true;
      _lastKickIndex = i;
      _onSuccessfulMove();
      return true;
    }
    return false;
  }

  /// Удавшееся движение у земли перезапускает lock delay — но не бесконечно.
  void _onSuccessfulMove() {
    if (!_isGrounded) return;
    if (_lockResets >= kMaxLockResets) return;
    _lockResets++;
    _lockTimer = Duration.zero;
  }

  void _hardDrop() {
    var dropped = 0;
    while (field.fits(_piece, _state, _row + 1, _col)) {
      _row++;
      dropped++;
    }
    if (dropped > 0) {
      _score += dropped * kHardDropScorePerCell;
      _lastActionWasRotation = false;
    }
    _lockPiece();
  }

  void _swapHold() {
    if (_holdUsed) return;
    final previous = _hold;
    _hold = _piece;
    _holdUsed = true;
    if (previous != null) {
      _placeAtSpawn(previous);
    } else {
      _spawnNext(keepHoldLock: true);
    }
  }

  // --- Фиксация --------------------------------------------------------------

  void _lockPiece() {
    final spin = _detectSpin();
    field.lock(_piece, _state, _row, _col);

    // Lock out: фигура целиком осталась над видимым полем.
    final lockedOut = _piece
        .cellsAt(_state)
        .every((cell) => _row + cell.row < kFirstVisibleRow);

    final clearedRows = field.clearFullRows();
    final cleared = clearedRows.length;

    var gained = lineClearScore(lines: cleared, spin: spin, level: _level);
    final difficult = isDifficultClear(lines: cleared, spin: spin);
    final chained = difficult && _backToBack;
    if (chained) gained = (gained * kBackToBackMultiplier).round();
    if (cleared > 0) _backToBack = difficult;

    if (cleared > 0) {
      _combo++;
      gained += comboScore(combo: _combo, level: _level);
    } else {
      _combo = -1;
    }

    final perfect = cleared > 0 && field.isEmpty;
    if (perfect) {
      gained += perfectClearScore(
        lines: cleared,
        level: _level,
        backToBack: chained,
      );
    }

    _score += gained;

    final previousLevel = _level;
    _lines += cleared;
    _level = 1 + _lines ~/ kLinesPerLevel;

    onLock?.call(
      LockEvent(
        piece: _piece,
        lines: cleared,
        spin: spin,
        backToBack: chained,
        combo: _combo,
        perfectClear: perfect,
        levelUp: _level != previousLevel,
        clearedRows: clearedRows,
      ),
    );

    if (lockedOut) {
      _gameOver = true;
      return;
    }
    _spawnNext();
  }

  /// Распознавание T-spin по правилу трёх углов.
  SpinKind _detectSpin() {
    if (_piece != Tetromino.t || !_lastActionWasRotation) return SpinKind.none;

    // Углы бокса 3×3. Порядок важен: передние зависят от того, куда смотрит T.
    const corners = [
      (row: 0, col: 0),
      (row: 0, col: 2),
      (row: 2, col: 0),
      (row: 2, col: 2),
    ];
    const frontsByState = [
      [0, 1], // T смотрит вверх — передние верхние
      [1, 3], // вправо — правые
      [2, 3], // вниз — нижние
      [0, 2], // влево — левые
    ];

    var occupied = 0;
    var frontOccupied = 0;
    final fronts = frontsByState[_state];
    for (var i = 0; i < corners.length; i++) {
      final blocked = field.isBlocked(
        _row + corners[i].row,
        _col + corners[i].col,
      );
      if (!blocked) continue;
      occupied++;
      if (fronts.contains(i)) frontOccupied++;
    }

    if (occupied < 3) return SpinKind.none;
    if (frontOccupied == 2) return SpinKind.full;
    // Вращение, прошедшее только последней попыткой кика, засчитывается
    // полноценным — иначе классические подкаты T в колодец считались бы mini.
    if (_lastKickIndex == kLastKickIndex) return SpinKind.full;
    return SpinKind.mini;
  }

  // --- Спавн -----------------------------------------------------------------

  void _spawnNext({bool keepHoldLock = false}) {
    if (!keepHoldLock) _holdUsed = false;
    _placeAtSpawn(_queue.take());
  }

  void _placeAtSpawn(Tetromino piece) {
    _piece = piece;
    _state = 0;
    _row = kSpawnRow;
    _col = kSpawnColumn;
    _dropProgress = 0;
    _lockTimer = Duration.zero;
    _lockResets = 0;
    _lowestRow = kSpawnRow;
    _lastActionWasRotation = false;
    _lastKickIndex = 0;

    // Block out: место спавна занято — партия окончена.
    if (!field.fits(_piece, _state, _row, _col)) {
      _gameOver = true;
      return;
    }
    // Guideline: сразу после спавна фигура делает шаг вниз, если может.
    if (field.fits(_piece, _state, _row + 1, _col)) {
      _row++;
      _lowestRow = _row;
    }
  }

  // --- Вид для интерфейса ----------------------------------------------------

  /// Клетки активной фигуры в координатах поля.
  List<Cell> get activeCells => [
    for (final cell in _piece.cellsAt(_state))
      (row: _row + cell.row, col: _col + cell.col),
  ];

  /// Клетки призрака — куда фигура упадёт по hard drop.
  List<Cell> get ghostCells {
    var row = _row;
    while (field.fits(_piece, _state, row + 1, _col)) {
      row++;
    }
    return [
      for (final cell in _piece.cellsAt(_state))
        (row: row + cell.row, col: _col + cell.col),
    ];
  }

  /// Ставит конкретную фигуру в конкретную позицию, минуя очередь и спавн.
  ///
  /// Существует ради тестов, которые проверяют распознавание прокруток и lock
  /// delay на собранных вручную стаканах: дожидаться нужной фигуры из мешка —
  /// значит проверять рандомайзер вместо правила.
  void debugPlace(
    Tetromino piece, {
    int state = 0,
    required int row,
    required int col,
  }) {
    _piece = piece;
    _state = state & 3;
    _row = row;
    _col = col;
    _dropProgress = 0;
    _lockTimer = Duration.zero;
    _lockResets = 0;
    _lowestRow = row;
    _lastActionWasRotation = false;
    _lastKickIndex = 0;
  }

  void restart() {
    field.reset();
    _queue.reset();
    _score = 0;
    _lines = 0;
    _level = 1;
    _combo = -1;
    _backToBack = false;
    _gameOver = false;
    _hold = null;
    _holdUsed = false;
    _dropProgress = 0;
    _autoShiftTimer = Duration.zero;
    releaseAll();
    _spawnNext();
  }
}
