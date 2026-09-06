import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqtris/keqtris.dart';

/// Клетки в стабильном порядке: сравнивать наборы позиций иначе бессмысленно —
/// порядок внутри фигуры зависит от того, сколько раз её повернули.
List<Cell> _sorted(List<Cell> cells) {
  final copy = [...cells];
  copy.sort((a, b) => a.row != b.row ? a.row - b.row : a.col - b.col);
  return copy;
}

void main() {
  group('фигуры', () {
    test('у каждой ровно четыре клетки в каждом состоянии', () {
      for (final piece in Tetromino.values) {
        for (var state = 0; state < 4; state++) {
          expect(piece.cellsAt(state), hasLength(4), reason: '$piece@$state');
        }
      }
    });

    test('T проходит четыре состояния и возвращается в исходное', () {
      expect(_sorted(Tetromino.t.cellsAt(1)), [
        (row: 0, col: 1),
        (row: 1, col: 1),
        (row: 1, col: 2),
        (row: 2, col: 1),
      ]);
      expect(_sorted(Tetromino.t.cellsAt(2)), [
        (row: 1, col: 0),
        (row: 1, col: 1),
        (row: 1, col: 2),
        (row: 2, col: 1),
      ]);
      expect(_sorted(Tetromino.t.cellsAt(4)), _sorted(Tetromino.t.cellsAt(0)));
    });

    test('I вращается внутри бокса 4×4 по строке 1 и колонке 2', () {
      expect(_sorted(Tetromino.i.cellsAt(0)), [
        (row: 1, col: 0),
        (row: 1, col: 1),
        (row: 1, col: 2),
        (row: 1, col: 3),
      ]);
      expect(_sorted(Tetromino.i.cellsAt(1)), [
        (row: 0, col: 2),
        (row: 1, col: 2),
        (row: 2, col: 2),
        (row: 3, col: 2),
      ]);
    });

    test('O не сдвигается ни в одном состоянии', () {
      for (var state = 0; state < 4; state++) {
        expect(
          _sorted(Tetromino.o.cellsAt(state)),
          _sorted(Tetromino.o.spawnCells),
        );
      }
      expect(Tetromino.o.rotates, isFalse);
    });
  });

  group('7-bag', () {
    test('каждая семёрка подряд содержит все семь фигур ровно по разу', () {
      final bag = SevenBag(random: Random(7));
      for (var round = 0; round < 50; round++) {
        final seven = [for (var i = 0; i < 7; i++) bag.next()];
        expect(seven.toSet(), Tetromino.values.toSet(), reason: 'мешок $round');
      }
    });

    test('между двумя одинаковыми фигурами не больше двенадцати чужих', () {
      // Главная гарантия 7-bag: засуха по I ограничена сверху, иначе игра
      // перестаёт быть про планирование.
      final bag = SevenBag(random: Random(42));
      final draws = [for (var i = 0; i < 700; i++) bag.next()];
      final lastSeen = <Tetromino, int>{};
      for (var i = 0; i < draws.length; i++) {
        final previous = lastSeen[draws[i]];
        if (previous != null) {
          expect(i - previous - 1, lessThanOrEqualTo(12), reason: 'позиция $i');
        }
        lastSeen[draws[i]] = i;
      }
    });
  });

  group('гравитация', () {
    test('на первом уровне ровно секунда на клетку', () {
      expect(gravityPerRow(1), const Duration(seconds: 1));
    });

    test('монотонно ускоряется на игровом диапазоне', () {
      var previous = gravityPerRow(1);
      for (var level = 2; level <= 25; level++) {
        final current = gravityPerRow(level);
        expect(current, lessThan(previous), reason: 'уровень $level');
        previous = current;
      }
    });

    test('никогда не обнуляется', () {
      // За двадцать восьмым уровнем формула уходит под микросекунду. Ноль там
      // означал бы деление на ноль в шаге гравитации, поэтому есть пол.
      for (var level = 1; level <= 100; level++) {
        expect(gravityPerRow(level).inMicroseconds, greaterThan(0));
      }
    });
  });

  group('очки', () {
    test('таблица без прокрутки', () {
      expect(lineClearScore(lines: 1, spin: SpinKind.none, level: 1), 100);
      expect(lineClearScore(lines: 2, spin: SpinKind.none, level: 1), 300);
      expect(lineClearScore(lines: 3, spin: SpinKind.none, level: 1), 500);
      expect(lineClearScore(lines: 4, spin: SpinKind.none, level: 1), 800);
    });

    test('таблицы прокруток', () {
      expect(lineClearScore(lines: 0, spin: SpinKind.full, level: 1), 400);
      expect(lineClearScore(lines: 1, spin: SpinKind.full, level: 1), 800);
      expect(lineClearScore(lines: 2, spin: SpinKind.full, level: 1), 1200);
      expect(lineClearScore(lines: 3, spin: SpinKind.full, level: 1), 1600);
      expect(lineClearScore(lines: 1, spin: SpinKind.mini, level: 1), 200);
    });

    test('уровень множит счёт', () {
      expect(lineClearScore(lines: 4, spin: SpinKind.none, level: 7), 5600);
    });

    test('сложные укладки — тетрис и T-spin с линиями', () {
      expect(isDifficultClear(lines: 4, spin: SpinKind.none), isTrue);
      expect(isDifficultClear(lines: 1, spin: SpinKind.full), isTrue);
      expect(isDifficultClear(lines: 1, spin: SpinKind.mini), isTrue);
      expect(isDifficultClear(lines: 3, spin: SpinKind.none), isFalse);
      // T-spin без линий цепочку не начинает: это не очистка.
      expect(isDifficultClear(lines: 0, spin: SpinKind.full), isFalse);
    });

    test('комбо: первая очистка бонуса не даёт', () {
      expect(comboScore(combo: 0, level: 1), 0);
      expect(comboScore(combo: 1, level: 1), 50);
      expect(comboScore(combo: 3, level: 2), 300);
    });

    test('perfect clear', () {
      expect(perfectClearScore(lines: 1, level: 1, backToBack: false), 800);
      expect(perfectClearScore(lines: 4, level: 1, backToBack: false), 2000);
      expect(perfectClearScore(lines: 4, level: 1, backToBack: true), 3200);
      expect(perfectClearScore(lines: 0, level: 5, backToBack: true), 0);
    });
  });

  group('стакан', () {
    test('полная строка убирается, всё что выше съезжает вниз', () {
      final field = Playfield();
      for (var col = 0; col < kColumns; col++) {
        field.fill(kTotalRows - 1, col, Tetromino.o);
      }
      field.fill(kTotalRows - 2, 0, Tetromino.i);

      expect(field.clearFullRows(), [kTotalRows - 1]);
      expect(field.at(kTotalRows - 1, 0), Tetromino.i);
      expect(field.at(kTotalRows - 2, 0), isNull);
    });

    test('несколько полных строк убираются за раз', () {
      final field = Playfield();
      for (final row in [kTotalRows - 1, kTotalRows - 2, kTotalRows - 4]) {
        for (var col = 0; col < kColumns; col++) {
          field.fill(row, col, Tetromino.o);
        }
      }
      field.fill(kTotalRows - 3, 5, Tetromino.z);

      expect(field.clearFullRows(), hasLength(3));
      // Единственная неполная строка осела на дно.
      expect(field.at(kTotalRows - 1, 5), Tetromino.z);
      expect(field.at(kTotalRows - 2, 5), isNull);
    });

    test('стены и пол блокируют', () {
      final field = Playfield();
      expect(field.isBlocked(30, -1), isTrue);
      expect(field.isBlocked(30, kColumns), isTrue);
      expect(field.isBlocked(kTotalRows, 0), isTrue);
      expect(field.isBlocked(0, 0), isFalse);
    });
  });
}
