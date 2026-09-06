import 'dart:math' as math;

/// Числа и таблицы Tetris Guideline.
///
/// Спека держится отдельно от движка намеренно: эти константы сверяют глазами
/// с источником, а не вычитывают между строк игровой логики. Если поведение
/// разошлось с оригиналом — сначала смотреть сюда.

/// Ширина поля.
const int kColumns = 10;

/// Полная высота: 20 видимых строк плюс 20 строк буфера над ними. Буфер не
/// украшение — в нём происходит спавн и в него уходят вращения у потолка.
const int kTotalRows = 40;

/// Сколько строк показывают игроку.
const int kVisibleRows = 20;

/// Индекс первой видимой строки при отсчёте сверху вниз.
const int kFirstVisibleRow = kTotalRows - kVisibleRows;

/// Колонка левого края спавн-бокса. Одна и та же для всех фигур: у 3×3-бокса
/// это колонки 4–6 в терминах Guideline, у 4×4 (только I) — 4–7.
const int kSpawnColumn = 3;

/// Строка верха спавн-бокса. Фигура появляется целиком над видимым полем и
/// въезжает в кадр первым же шагом гравитации — как в Guideline.
const int kSpawnRow = kFirstVisibleRow - 2;

/// Сколько линий закрывают уровень (fixed goal).
const int kLinesPerLevel = 10;

/// Сколько раз lock delay можно перезапустить движением, прежде чем фигура
/// зафиксируется принудительно. Без лимита фигуру можно крутить вечно.
const int kMaxLockResets = 15;

/// Настройки, которые Guideline не фиксирует и которые принято отдавать игроку.
class TetrisTuning {
  /// Задержка перед автоповтором горизонтального движения.
  final Duration das;

  /// Период автоповтора после [das].
  final Duration arr;

  /// Сколько фигура лежит на опоре перед фиксацией.
  final Duration lockDelay;

  /// Во сколько раз soft drop быстрее текущей гравитации.
  final int softDropFactor;

  const TetrisTuning({
    this.das = const Duration(milliseconds: 183),
    this.arr = const Duration(milliseconds: 33),
    this.lockDelay = const Duration(milliseconds: 500),
    this.softDropFactor = 20,
  });
}

/// Время падения на клетку: `(0.8 − (level − 1) × 0.007) ^ (level − 1)` секунд.
///
/// К двадцать девятому уровню это уходит под микросекунду, поэтому результат
/// прижат снизу к единице: ноль превратил бы шаг гравитации в деление на ноль.
Duration gravityPerRow(int level) {
  final base = 0.8 - (level - 1) * 0.007;
  final seconds = math.pow(base.clamp(0.0001, 0.8), level - 1).toDouble();
  final micros = (seconds * Duration.microsecondsPerSecond).round();
  return Duration(microseconds: math.max(1, micros));
}

/// Вид прокрутки, распознанный на фиксации фигуры.
enum SpinKind {
  /// Обычная укладка.
  none,

  /// Mini T-spin: три угла заняты, но передних из них только один.
  mini,

  /// Полноценный T-spin: три угла заняты, включая оба передних.
  full,
}

/// Очки за очистку линий. Индекс — число линий (0…4).
const List<int> _plainClear = [0, 100, 300, 500, 800];
const List<int> _miniSpinClear = [100, 200, 400, 0, 0];
const List<int> _fullSpinClear = [400, 800, 1200, 1600, 0];

/// Очки за укладку без учёта комбо, back-to-back и perfect clear.
int lineClearScore({
  required int lines,
  required SpinKind spin,
  required int level,
}) {
  assert(lines >= 0 && lines <= 4);
  final table = switch (spin) {
    SpinKind.none => _plainClear,
    SpinKind.mini => _miniSpinClear,
    SpinKind.full => _fullSpinClear,
  };
  return table[lines] * level;
}

/// «Сложная» укладка: тетрис или любой T-spin с линиями. Только такие
/// продолжают цепочку back-to-back, и только им достаётся её множитель.
bool isDifficultClear({required int lines, required SpinKind spin}) =>
    lines == 4 || (spin != SpinKind.none && lines > 0);

/// Множитель back-to-back.
const double kBackToBackMultiplier = 1.5;

/// Очки за комбо: 50 × длина комбо × уровень.
int comboScore({required int combo, required int level}) =>
    combo > 0 ? 50 * combo * level : 0;

/// Очки за perfect clear (поле пусто после укладки). Индекс — число линий.
const List<int> _perfectClear = [0, 800, 1200, 1800, 2000];

/// Тетрис-perfect clear в цепочке back-to-back оценивается отдельной ставкой,
/// а не множителем — поэтому у него собственное число.
const int _perfectClearB2BTetris = 3200;

int perfectClearScore({
  required int lines,
  required int level,
  required bool backToBack,
}) {
  if (lines <= 0) return 0;
  if (lines == 4 && backToBack) return _perfectClearB2BTetris * level;
  return _perfectClear[lines] * level;
}

/// Очки за клетку soft drop.
const int kSoftDropScorePerCell = 1;

/// Очки за клетку hard drop.
const int kHardDropScorePerCell = 2;
