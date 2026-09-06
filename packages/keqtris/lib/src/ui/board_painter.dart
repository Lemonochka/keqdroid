import 'package:flutter/material.dart';

import '../game.dart';
import '../rules.dart';
import '../tetromino.dart';
import 'skin.dart';

/// Скруглённые клетки и сетка стакана.
///
/// Рисуется только видимая часть поля: буфер над ней существует для правил, а
/// не для глаз. Фигура, наполовину уехавшая в буфер, обрезается ровно по
/// верхней кромке — это и есть та кромка, из-за которой поле 10×40, а не 10×20.
class BoardPainter extends CustomPainter {
  final KeqtrisGame game;
  final KeqtrisSkin skin;

  /// Строки, только что унесённые очисткой, и насколько вспышка отгорела
  /// (0 — только вспыхнула, 1 — погасла).
  ///
  /// К моменту, когда об очистке узнаёт интерфейс, движок уже сложил стакан:
  /// схлопывать нечего, самих клеток больше нет. Поэтому очистка показывается
  /// вспышкой на месте ушедших строк, а не анимацией их исчезновения.
  final List<int> clearedRows;
  final double clearProgress;

  /// Счётчик кадров: единственное, что заставляет [shouldRepaint] сказать «да»,
  /// когда всё состояние живёт в изменяемом [game].
  final int frame;

  const BoardPainter({
    required this.game,
    required this.skin,
    required this.frame,
    this.clearedRows = const [],
    this.clearProgress = 1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / kColumns;
    _paintGrid(canvas, size, cell);

    for (var row = kFirstVisibleRow; row < kTotalRows; row++) {
      for (var col = 0; col < kColumns; col++) {
        final piece = game.field.at(row, col);
        if (piece == null) continue;
        _paintCell(canvas, row, col, cell, skin.colorOf(piece));
      }
    }

    if (!game.isGameOver) {
      final active = game.activeCells.toSet();
      for (final ghost in game.ghostCells) {
        // Призрак под самой фигурой не рисуем: две рамки на одной клетке дают
        // грязь и ничего не сообщают.
        if (active.contains(ghost)) continue;
        _paintGhost(canvas, ghost.row, ghost.col, cell);
      }
      for (final pos in active) {
        _paintCell(canvas, pos.row, pos.col, cell, skin.colorOf(game.piece));
      }
    }

    _paintClearFlash(canvas, size, cell);
  }

  void _paintGrid(Canvas canvas, Size size, double cell) {
    final paint = Paint()
      ..color = skin.gridLine
      ..strokeWidth = 1;
    for (var col = 1; col < kColumns; col++) {
      final x = col * cell;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var row = 1; row < kVisibleRows; row++) {
      final y = row * cell;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _paintClearFlash(Canvas canvas, Size size, double cell) {
    if (clearedRows.isEmpty || clearProgress >= 1) return;
    final fade = 1 - clearProgress;
    for (final row in clearedRows) {
      if (row < kFirstVisibleRow) continue;
      final y = (row - kFirstVisibleRow) * cell;
      // Полоса расходится по вертикали и гаснет: короткая вспышка вместо
      // строки, исчезнувшей между двумя кадрами.
      final rect = Rect.fromLTWH(
        0,
        y,
        size.width,
        cell,
      ).inflate(cell * 0.25 * clearProgress);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.3)),
        Paint()
          ..color = skin.scheme.onSurface.withValues(alpha: 0.55 * fade * fade),
      );
    }
  }

  void _paintCell(Canvas canvas, int row, int col, double cell, Color color) {
    if (row < kFirstVisibleRow) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        _cellRect(row, col, cell),
        Radius.circular(cell * 0.26),
      ),
      Paint()..color = color,
    );
  }

  void _paintGhost(Canvas canvas, int row, int col, double cell) {
    if (row < kFirstVisibleRow) return;
    final rect = _cellRect(row, col, cell).deflate(cell * 0.06);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.22)),
      Paint()
        ..color = skin.ghost
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.09,
    );
  }

  Rect _cellRect(int row, int col, double cell) => Rect.fromLTWH(
    col * cell,
    (row - kFirstVisibleRow) * cell,
    cell,
    cell,
  ).deflate(cell * 0.055);

  @override
  bool shouldRepaint(BoardPainter old) =>
      old.frame != frame ||
      old.skin != skin ||
      old.clearProgress != clearProgress ||
      old.clearedRows != clearedRows;
}

/// Одна фигура, вписанная в свой прямоугольник. Панели hold и next.
class PiecePainter extends CustomPainter {
  final Tetromino? piece;
  final KeqtrisSkin skin;
  final bool dimmed;

  const PiecePainter({
    required this.piece,
    required this.skin,
    this.dimmed = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final shape = piece;
    if (shape == null) return;
    final cells = shape.cellsAt(0);

    // Фигуры разной ширины обязаны стоять по центру своей ячейки, иначе панель
    // next выглядит как список с разъехавшимися отступами.
    var minRow = kTotalRows, maxRow = 0, minCol = kColumns, maxCol = 0;
    for (final cell in cells) {
      minRow = cell.row < minRow ? cell.row : minRow;
      maxRow = cell.row > maxRow ? cell.row : maxRow;
      minCol = cell.col < minCol ? cell.col : minCol;
      maxCol = cell.col > maxCol ? cell.col : maxCol;
    }
    final wide = maxCol - minCol + 1;
    final tall = maxRow - minRow + 1;
    final cellSize = (size.width / wide).clamp(0.0, size.height / tall);
    final originX = (size.width - cellSize * wide) / 2;
    final originY = (size.height - cellSize * tall) / 2;

    var color = skin.colorOf(shape);
    if (dimmed) color = color.withValues(alpha: 0.35);

    for (final cell in cells) {
      final rect = Rect.fromLTWH(
        originX + (cell.col - minCol) * cellSize,
        originY + (cell.row - minRow) * cellSize,
        cellSize,
        cellSize,
      ).deflate(cellSize * 0.07);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cellSize * 0.26)),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(PiecePainter old) =>
      old.piece != piece || old.skin != skin || old.dimmed != dimmed;
}
