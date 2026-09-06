import 'package:flutter_test/flutter_test.dart';
import 'package:keqtris/keqtris.dart';

/// Таблицы киков дословно, как они опубликованы: смещения `(x, y)`, y вверх.
///
/// Это не пересказ реализации своими словами, а второй экземпляр данных.
/// Ошибка в одной строке даёт фигуру, которая «иногда не крутится» в одном
/// конкретном углу стакана, — найти такое по симптому потом невозможно, а
/// расхождение с этой таблицей видно сразу.
const _published = {
  'JLSTZ': {
    '0>R': [(0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)],
    'R>0': [(0, 0), (1, 0), (1, -1), (0, 2), (1, 2)],
    'R>2': [(0, 0), (1, 0), (1, -1), (0, 2), (1, 2)],
    '2>R': [(0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)],
    '2>L': [(0, 0), (1, 0), (1, 1), (0, -2), (1, -2)],
    'L>2': [(0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)],
    'L>0': [(0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)],
    '0>L': [(0, 0), (1, 0), (1, 1), (0, -2), (1, -2)],
  },
  'I': {
    '0>R': [(0, 0), (-2, 0), (1, 0), (-2, -1), (1, 2)],
    'R>0': [(0, 0), (2, 0), (-1, 0), (2, 1), (-1, -2)],
    'R>2': [(0, 0), (-1, 0), (2, 0), (-1, 2), (2, -1)],
    '2>R': [(0, 0), (1, 0), (-2, 0), (1, -2), (-2, 1)],
    '2>L': [(0, 0), (2, 0), (-1, 0), (2, 1), (-1, -2)],
    'L>2': [(0, 0), (-2, 0), (1, 0), (-2, -1), (1, 2)],
    'L>0': [(0, 0), (1, 0), (-2, 0), (1, -2), (-2, 1)],
    '0>L': [(0, 0), (-1, 0), (2, 0), (-1, 2), (2, -1)],
  },
};

const _states = {'0': 0, 'R': 1, '2': 2, 'L': 3};

void main() {
  group('таблицы киков сходятся с опубликованными', () {
    for (final family in _published.entries) {
      final pieces = family.key == 'I'
          ? [Tetromino.i]
          : [Tetromino.j, Tetromino.l, Tetromino.s, Tetromino.t, Tetromino.z];

      for (final row in family.value.entries) {
        test('${family.key} ${row.key}', () {
          final parts = row.key.split('>');
          final from = _states[parts[0]]!;
          final to = _states[parts[1]]!;
          for (final piece in pieces) {
            final kicks = kicksFor(piece, from, to);
            expect(
              kicks.map((k) => (k.x, k.y)).toList(),
              row.value,
              reason: '$piece ${row.key}',
            );
          }
        });
      }
    }
  });

  group('устройство таблиц', () {
    test('O не отталкивается ни от чего', () {
      for (var from = 0; from < 4; from++) {
        for (final turn in [1, -1]) {
          final kicks = kicksFor(Tetromino.o, from, from + turn);
          expect(kicks, hasLength(1));
          expect(kicks.single.colOffset, 0);
          expect(kicks.single.rowOffset, 0);
        }
      }
    });

    test('ось строк перевёрнута относительно таблицы', () {
      // В источнике y растёт вверх, у поля строки растут вниз.
      const kick = SrsKick(-1, 2);
      expect(kick.colOffset, -1);
      expect(kick.rowOffset, -2);
    });
  });
}
