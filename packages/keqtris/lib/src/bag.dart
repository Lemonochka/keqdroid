import 'dart:math';

import 'tetromino.dart';

/// Рандомайзер 7-bag: фигуры выдаются перестановками полного набора из семи.
///
/// Это не украшение честности, а часть правил: игрок вправе рассчитывать, что
/// между двумя I пройдёт не больше двенадцати чужих фигур. Наивный
/// `random.nextInt` такой гарантии не даёт и ломает всё — от планирования до
/// колодцев.
class SevenBag {
  final Random _random;
  final List<Tetromino> _bag = [];

  SevenBag({Random? random}) : _random = random ?? Random();

  Tetromino next() {
    if (_bag.isEmpty) _refill();
    return _bag.removeLast();
  }

  void _refill() {
    _bag.addAll(Tetromino.values);
    _bag.shuffle(_random);
  }

  void reset() => _bag.clear();
}

/// Очередь ближайших фигур поверх мешка: игрок видит несколько следующих, а
/// сам мешок расходуется ровно на столько же вперёд.
class PieceQueue {
  /// Сколько фигур показывают игроку. Guideline допускает от одной до шести.
  static const int visibleLength = 5;

  final SevenBag _bag;
  final List<Tetromino> _queue = [];

  PieceQueue({Random? random}) : _bag = SevenBag(random: random) {
    _top();
  }

  /// Ближайшие фигуры, первая — следующая в игре.
  List<Tetromino> get preview => List.unmodifiable(_queue);

  Tetromino take() {
    final piece = _queue.removeAt(0);
    _top();
    return piece;
  }

  void _top() {
    while (_queue.length < visibleLength) {
      _queue.add(_bag.next());
    }
  }

  void reset() {
    _queue.clear();
    _bag.reset();
    _top();
  }
}
