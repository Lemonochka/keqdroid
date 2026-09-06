/// Клетка в координатах бокса фигуры или поля. Строки растут вниз.
typedef Cell = ({int row, int col});

/// Семь фигур Guideline.
///
/// Каждая описана только состоянием спавна внутри своего бокса — остальные три
/// поворота считаются из него вращением бокса. Так в коде нет двадцати восьми
/// рукописных наборов клеток, которые невозможно вычитать глазами.
enum Tetromino {
  i(
    box: 4,
    spawnCells: [
      (row: 1, col: 0),
      (row: 1, col: 1),
      (row: 1, col: 2),
      (row: 1, col: 3),
    ],
  ),
  j(
    box: 3,
    spawnCells: [
      (row: 0, col: 0),
      (row: 1, col: 0),
      (row: 1, col: 1),
      (row: 1, col: 2),
    ],
  ),
  l(
    box: 3,
    spawnCells: [
      (row: 0, col: 2),
      (row: 1, col: 0),
      (row: 1, col: 1),
      (row: 1, col: 2),
    ],
  ),
  o(
    box: 3,
    spawnCells: [
      (row: 0, col: 1),
      (row: 0, col: 2),
      (row: 1, col: 1),
      (row: 1, col: 2),
    ],
  ),
  s(
    box: 3,
    spawnCells: [
      (row: 0, col: 1),
      (row: 0, col: 2),
      (row: 1, col: 0),
      (row: 1, col: 1),
    ],
  ),
  t(
    box: 3,
    spawnCells: [
      (row: 0, col: 1),
      (row: 1, col: 0),
      (row: 1, col: 1),
      (row: 1, col: 2),
    ],
  ),
  z(
    box: 3,
    spawnCells: [
      (row: 0, col: 0),
      (row: 0, col: 1),
      (row: 1, col: 1),
      (row: 1, col: 2),
    ],
  );

  const Tetromino({required this.box, required this.spawnCells});

  /// Сторона квадратного бокса, внутри которого фигура вращается.
  final int box;

  /// Клетки в состоянии спавна.
  final List<Cell> spawnCells;

  /// O не вращается: в SRS её поворот вокруг собственного центра не сдвигает
  /// ни одной клетки, поэтому состояние для неё — просто счётчик.
  bool get rotates => this != Tetromino.o;

  /// Клетки во всех четырёх состояниях, посчитанные один раз на запуск.
  static final Map<Tetromino, List<List<Cell>>> _states = {
    for (final piece in values) piece: piece._buildStates(),
  };

  List<List<Cell>> _buildStates() {
    final states = <List<Cell>>[List.unmodifiable(spawnCells)];
    for (var i = 1; i < 4; i++) {
      states.add(
        List.unmodifiable(rotates ? _rotateCw(states[i - 1], box) : spawnCells),
      );
    }
    return List.unmodifiable(states);
  }

  /// Поворот бокса по часовой: клетка (r, c) уезжает в (c, N−1−r).
  static List<Cell> _rotateCw(List<Cell> cells, int box) => [
    for (final cell in cells) (row: cell.col, col: box - 1 - cell.row),
  ];

  /// Клетки фигуры в состоянии [state] (0, R, 2, L) в координатах бокса.
  List<Cell> cellsAt(int state) => _states[this]![state & 3];
}
