import 'rules.dart';
import 'tetromino.dart';

/// Стакан: сетка [kColumns] × [kTotalRows], строка 0 — верх буфера.
///
/// Знает только про уложенные клетки. Активная фигура живёт в движке и попадает
/// сюда ровно один раз — на фиксации.
class Playfield {
  /// null — пусто; иначе фигура, из которой клетка родом (нужно для цвета).
  final List<Tetromino?> _cells;

  Playfield() : _cells = List<Tetromino?>.filled(kColumns * kTotalRows, null);

  Tetromino? at(int row, int col) => _cells[row * kColumns + col];

  /// Занята ли клетка для целей столкновения. Всё за пределами поля считается
  /// занятым — включая пространство над потолком буфера.
  bool isBlocked(int row, int col) {
    if (col < 0 || col >= kColumns) return true;
    if (row < 0 || row >= kTotalRows) return true;
    return at(row, col) != null;
  }

  /// Помещается ли фигура [piece] в состоянии [state] с верхним левым углом
  /// бокса в ([row], [col]).
  bool fits(Tetromino piece, int state, int row, int col) {
    for (final cell in piece.cellsAt(state)) {
      if (isBlocked(row + cell.row, col + cell.col)) return false;
    }
    return true;
  }

  /// Ставит одну клетку. Кроме укладки фигур пригодится тестам, которые
  /// собирают стакан руками.
  void fill(int row, int col, Tetromino? piece) {
    if (row < 0 || row >= kTotalRows || col < 0 || col >= kColumns) return;
    _cells[row * kColumns + col] = piece;
  }

  /// Кладёт фигуру в стакан.
  void lock(Tetromino piece, int state, int row, int col) {
    for (final cell in piece.cellsAt(state)) {
      fill(row + cell.row, col + cell.col, piece);
    }
  }

  /// Убирает заполненные строки, сдвигая всё что выше вниз. Возвращает индексы
  /// убранных строк — они нужны анимации, а не счёту.
  List<int> clearFullRows() {
    final cleared = <int>[];
    var write = kTotalRows - 1;
    for (var read = kTotalRows - 1; read >= 0; read--) {
      if (_isRowFull(read)) {
        cleared.add(read);
        continue;
      }
      if (write != read) _copyRow(from: read, to: write);
      write--;
    }
    for (var row = write; row >= 0; row--) {
      _fillRow(row, null);
    }
    return cleared;
  }

  /// Пусто ли поле целиком — условие perfect clear.
  bool get isEmpty => _cells.every((cell) => cell == null);

  bool _isRowFull(int row) {
    for (var col = 0; col < kColumns; col++) {
      if (at(row, col) == null) return false;
    }
    return true;
  }

  /// Строки не пересекаются: [write] отстаёт от [read] минимум на строку, то
  /// есть на [kColumns] элементов, поэтому копирование внутри одного списка
  /// безопасно.
  void _copyRow({required int from, required int to}) {
    _cells.setRange(
      to * kColumns,
      to * kColumns + kColumns,
      _cells,
      from * kColumns,
    );
  }

  void _fillRow(int row, Tetromino? value) {
    _cells.fillRange(row * kColumns, row * kColumns + kColumns, value);
  }

  /// Сбрасывает поле в пустое — для рестарта без пересоздания движка.
  void reset() => _cells.fillRange(0, _cells.length, null);
}
