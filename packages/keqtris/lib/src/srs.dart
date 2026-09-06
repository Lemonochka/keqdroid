import 'tetromino.dart';

/// Super Rotation System: таблицы отталкивания от стен (wall kicks).
///
/// Числа записаны в опубликованном виде: смещение `(x, y)`, где x растёт
/// вправо, а **y растёт вверх**. У поля ось строк смотрит вниз, поэтому при
/// применении y меняет знак — см. [SrsKick.rowOffset]. Перевернуть таблицу под
/// координаты поля было бы удобнее в коде и невозможно сверить с источником,
/// поэтому знак живёт в одном месте, а таблица остаётся дословной.
///
/// Все шестнадцать строк сверены с независимой реализацией SRS, а не выписаны
/// по памяти: ошибка в одной строке даёт фигуру, которая «иногда не крутится»
/// в одном конкретном углу — искать такое потом невозможно.
class SrsKick {
  final int x;
  final int y;

  const SrsKick(this.x, this.y);

  /// Смещение по колонкам поля.
  int get colOffset => x;

  /// Смещение по строкам поля: ось перевёрнута относительно таблицы.
  int get rowOffset => -y;
}

/// Ключ перехода: из какого состояния в какое.
int _transition(int from, int to) => (from & 3) * 4 + (to & 3);

/// Таблица для J, L, S, T, Z.
const Map<int, List<SrsKick>> _jlstzKicks = {
  // 0 → R
  1: [SrsKick(0, 0), SrsKick(-1, 0), SrsKick(-1, 1), SrsKick(0, -2), SrsKick(-1, -2)],
  // R → 0
  4: [SrsKick(0, 0), SrsKick(1, 0), SrsKick(1, -1), SrsKick(0, 2), SrsKick(1, 2)],
  // R → 2
  6: [SrsKick(0, 0), SrsKick(1, 0), SrsKick(1, -1), SrsKick(0, 2), SrsKick(1, 2)],
  // 2 → R
  9: [SrsKick(0, 0), SrsKick(-1, 0), SrsKick(-1, 1), SrsKick(0, -2), SrsKick(-1, -2)],
  // 2 → L
  11: [SrsKick(0, 0), SrsKick(1, 0), SrsKick(1, 1), SrsKick(0, -2), SrsKick(1, -2)],
  // L → 2
  14: [SrsKick(0, 0), SrsKick(-1, 0), SrsKick(-1, -1), SrsKick(0, 2), SrsKick(-1, 2)],
  // L → 0
  12: [SrsKick(0, 0), SrsKick(-1, 0), SrsKick(-1, -1), SrsKick(0, 2), SrsKick(-1, 2)],
  // 0 → L
  3: [SrsKick(0, 0), SrsKick(1, 0), SrsKick(1, 1), SrsKick(0, -2), SrsKick(1, -2)],
};

/// Таблица для I — своя, и это не мелочь: именно она даёт I-фигуре
/// характерные подкаты на две клетки.
const Map<int, List<SrsKick>> _iKicks = {
  // 0 → R
  1: [SrsKick(0, 0), SrsKick(-2, 0), SrsKick(1, 0), SrsKick(-2, -1), SrsKick(1, 2)],
  // R → 0
  4: [SrsKick(0, 0), SrsKick(2, 0), SrsKick(-1, 0), SrsKick(2, 1), SrsKick(-1, -2)],
  // R → 2
  6: [SrsKick(0, 0), SrsKick(-1, 0), SrsKick(2, 0), SrsKick(-1, 2), SrsKick(2, -1)],
  // 2 → R
  9: [SrsKick(0, 0), SrsKick(1, 0), SrsKick(-2, 0), SrsKick(1, -2), SrsKick(-2, 1)],
  // 2 → L
  11: [SrsKick(0, 0), SrsKick(2, 0), SrsKick(-1, 0), SrsKick(2, 1), SrsKick(-1, -2)],
  // L → 2
  14: [SrsKick(0, 0), SrsKick(-2, 0), SrsKick(1, 0), SrsKick(-2, -1), SrsKick(1, 2)],
  // L → 0
  12: [SrsKick(0, 0), SrsKick(1, 0), SrsKick(-2, 0), SrsKick(1, -2), SrsKick(-2, 1)],
  // 0 → L
  3: [SrsKick(0, 0), SrsKick(-1, 0), SrsKick(2, 0), SrsKick(-1, 2), SrsKick(2, -1)],
};

/// Единственный нулевой сдвиг: O не отталкивается ни от чего.
const List<SrsKick> _noKicks = [SrsKick(0, 0)];

/// Последовательность попыток для перехода [from] → [to].
///
/// Порядок значим: индекс сработавшей попытки — часть правила распознавания
/// T-spin, последняя попытка засчитывает полноценную прокрутку.
List<SrsKick> kicksFor(Tetromino piece, int from, int to) {
  if (!piece.rotates) return _noKicks;
  final table = piece == Tetromino.i ? _iKicks : _jlstzKicks;
  return table[_transition(from, to)]!;
}

/// Индекс последней попытки. Вращение, прошедшее только на ней, считается
/// полноценным T-spin независимо от расположения углов.
const int kLastKickIndex = 4;
