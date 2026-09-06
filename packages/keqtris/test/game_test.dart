import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqtris/keqtris.dart';

int _topRow(KeqtrisGame game) => game.activeCells.map((c) => c.row).reduce(min);

void main() {
  group('спавн', () {
    test('фигура появляется над видимым полем и сразу делает шаг вниз', () {
      final game = KeqtrisGame(random: Random(1));
      for (final cell in game.activeCells) {
        expect(cell.row, anyOf(kSpawnRow + 1, kSpawnRow + 2));
        expect(cell.col, inInclusiveRange(kSpawnColumn, kSpawnColumn + 3));
      }
      expect(game.preview, hasLength(PieceQueue.visibleLength));
      expect(game.holdPiece, isNull);
      expect(game.isGameOver, isFalse);
    });
  });

  group('гравитация', () {
    test('на первом уровне фигура идёт клетку в секунду', () {
      final game = KeqtrisGame(random: Random(2));
      game.debugPlace(Tetromino.o, row: kFirstVisibleRow, col: kSpawnColumn);

      game.update(const Duration(milliseconds: 999));
      expect(_topRow(game), kFirstVisibleRow);
      game.update(const Duration(milliseconds: 1));
      expect(_topRow(game), kFirstVisibleRow + 1);
    });

    test('ускорение идёт в двадцать раз быстрее', () {
      final game = KeqtrisGame(random: Random(3));
      game.debugPlace(Tetromino.o, row: kFirstVisibleRow, col: kSpawnColumn);

      game.press(GameInput.softDrop);
      game.update(const Duration(milliseconds: 250));

      expect(_topRow(game), kFirstVisibleRow + 5);
    });

    test('ускорение не выстреливает накопленной гравитацией', () {
      // Регрессия найденная на устройстве: накопитель хранил ВРЕМЯ, а не долю
      // клетки. Почти дозревший шаг обычной гравитации (900 мс из 1000) в
      // момент нажатия ускорения делился на новый интервал в 50 мс и выдавался
      // пачкой из восемнадцати шагов за кадр — кнопка ускорения работала как
      // hard drop.
      final game = KeqtrisGame(random: Random(4));
      game.debugPlace(Tetromino.o, row: kFirstVisibleRow, col: kSpawnColumn);

      game.update(const Duration(milliseconds: 900));
      final before = _topRow(game);
      expect(before, kFirstVisibleRow, reason: 'шаг ещё не дозрел');

      game.press(GameInput.softDrop);
      game.update(const Duration(milliseconds: 16));

      expect(_topRow(game) - before, 1, reason: 'один кадр — один шаг');
    });
  });

  group('hard drop', () {
    test('даёт два очка за клетку и фиксирует немедленно', () {
      final game = KeqtrisGame(random: Random(5));
      LockEvent? event;
      game.onLock = (e) => event = e;

      // O на пустом поле от строки 20 падает до 38: восемнадцать клеток.
      game.debugPlace(Tetromino.o, row: kFirstVisibleRow, col: kSpawnColumn);
      game.press(GameInput.hardDrop);

      expect(game.score, 18 * kHardDropScorePerCell);
      expect(event?.lines, 0);
    });
  });

  group('lock delay', () {
    test('фигура на опоре фиксируется через полсекунды, но не раньше', () {
      final game = KeqtrisGame(random: Random(6));
      var locked = false;
      game.onLock = (_) => locked = true;
      game.debugPlace(Tetromino.o, row: kTotalRows - 2, col: kSpawnColumn);

      game.update(const Duration(milliseconds: 499));
      expect(locked, isFalse, reason: 'до полусекунды фиксации быть не должно');
      game.update(const Duration(milliseconds: 2));
      expect(locked, isTrue);
    });

    test('перезапуски движением ограничены пятнадцатью', () {
      final game = KeqtrisGame(random: Random(7));
      var locked = false;
      game.onLock = (_) => locked = true;
      game.debugPlace(Tetromino.o, row: kTotalRows - 2, col: kSpawnColumn);

      // Каждый сдвиг перезапускает таймер — но только пока есть лимит.
      for (var i = 0; i < 40 && !locked; i++) {
        final input = i.isEven ? GameInput.left : GameInput.right;
        game.press(input);
        game.release(input);
        game.update(const Duration(milliseconds: 100));
      }
      expect(locked, isTrue, reason: 'бесконечная возня у пола недопустима');
    });

    test('на паузе не происходит ничего', () {
      final game = KeqtrisGame(random: Random(8));
      var locked = false;
      game.onLock = (_) => locked = true;
      game.debugPlace(Tetromino.o, row: kTotalRows - 2, col: kSpawnColumn);

      game.paused = true;
      game.update(const Duration(seconds: 10));
      expect(locked, isFalse);
      expect(game.score, 0);
    });
  });

  group('T-spin', () {
    /// Классический слот: три занятых угла бокса, оба передних снизу.
    KeqtrisGame buildSlot() {
      final game = KeqtrisGame(random: Random(9));
      final bottom = kTotalRows - 1;
      game.field.fill(bottom, 0, Tetromino.i);
      game.field.fill(bottom, 2, Tetromino.i);
      game.field.fill(bottom - 2, 2, Tetromino.i);
      for (var col = 3; col < kColumns; col++) {
        game.field.fill(bottom, col, Tetromino.i);
      }
      return game;
    }

    test('вращение в слот засчитывается полноценной прокруткой', () {
      final game = buildSlot();
      LockEvent? event;
      game.onLock = (e) => event = e;

      game.debugPlace(Tetromino.t, state: 1, row: kTotalRows - 3, col: 0);
      game.press(GameInput.rotateCw);
      expect(game.rotationState, 2, reason: 'вращение обязано пройти');

      game.press(GameInput.hardDrop);

      expect(event?.spin, SpinKind.full);
      expect(event?.lines, 1);
      expect(game.score, 800);
    });

    test('без вращения перед фиксацией прокрутка не засчитывается', () {
      final game = buildSlot();
      LockEvent? event;
      game.onLock = (e) => event = e;

      // Та же позиция, но приехали в неё не вращением.
      game.debugPlace(Tetromino.t, state: 2, row: kTotalRows - 3, col: 0);
      game.press(GameInput.hardDrop);

      expect(event?.spin, SpinKind.none);
      expect(game.score, 100, reason: 'обычный single, а не T-spin');
    });
  });

  group('конец партии', () {
    test('lock out: фигура зафиксировалась целиком над видимым полем', () {
      final game = KeqtrisGame(random: Random(10));
      game.field.fill(kFirstVisibleRow, kSpawnColumn + 1, Tetromino.i);
      game.field.fill(kFirstVisibleRow, kSpawnColumn + 2, Tetromino.i);

      game.debugPlace(Tetromino.o, row: kSpawnRow, col: kSpawnColumn);
      game.press(GameInput.hardDrop);

      expect(game.isGameOver, isTrue);
    });
  });

  group('hold', () {
    test('первый hold забирает фигуру и берёт следующую из очереди', () {
      final game = KeqtrisGame(random: Random(11));
      final held = game.piece;
      final next = game.preview.first;

      game.press(GameInput.hold);

      expect(game.holdPiece, held);
      expect(game.piece, next);
      expect(game.holdAvailable, isFalse, reason: 'до фиксации hold заблокирован');
    });

    test('после фиксации hold снова доступен', () {
      final game = KeqtrisGame(random: Random(12));
      game.press(GameInput.hold);
      expect(game.holdAvailable, isFalse);
      game.press(GameInput.hardDrop);
      expect(game.holdAvailable, isTrue);
    });
  });

  group('комбо и back-to-back', () {
    test('счёт растёт цепочкой тетрисов', () {
      final game = KeqtrisGame(random: Random(13));
      final events = <LockEvent>[];
      game.onLock = events.add;

      // Два тетриса подряд: колодец в колонке 9, вертикальная I.
      for (var round = 0; round < 2; round++) {
        for (var row = kTotalRows - 4; row < kTotalRows; row++) {
          for (var col = 0; col < kColumns - 1; col++) {
            game.field.fill(row, col, Tetromino.z);
          }
        }
        game.debugPlace(Tetromino.i, state: 1, row: kTotalRows - 8, col: 7);
        game.press(GameInput.hardDrop);
      }

      expect(events, hasLength(2));
      expect(events[0].lines, 4);
      expect(events[0].backToBack, isFalse, reason: 'первый тетрис цепочку начинает');
      expect(events[1].lines, 4);
      expect(events[1].backToBack, isTrue, reason: 'второй уже в цепочке');
      expect(events[1].combo, 1);
    });
  });

  group('рестарт', () {
    test('обнуляет всё', () {
      final game = KeqtrisGame(random: Random(14));
      game.debugPlace(Tetromino.o, row: kFirstVisibleRow, col: kSpawnColumn);
      game.press(GameInput.hardDrop);
      expect(game.score, greaterThan(0));

      game.restart();

      expect(game.score, 0);
      expect(game.lines, 0);
      expect(game.level, 1);
      expect(game.combo, -1);
      expect(game.holdPiece, isNull);
      expect(game.isGameOver, isFalse);
      expect(game.field.isEmpty, isTrue);
    });
  });
}
