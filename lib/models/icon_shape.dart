import 'package:androidx_graphics_shapes/material_shapes.dart';
import 'package:androidx_graphics_shapes/shapes.dart';
import 'package:flutter/material.dart';

/// Форма кружка под иконкой — как выбор формы иконок в Pixel Launcher.
///
/// Смысл ровно тот же, что у системной настройки: форма — самая заметная черта
/// «почерка» интерфейса, и одна и та же палитра с круглыми и со скруглённо-
/// квадратными значками читается как два разных приложения. Менять её должен
/// пользователь, а не тема.
///
/// Сами контуры берутся из [MaterialShapes] — это перенос
/// `androidx.graphics.shapes` (Apache-2.0), тот самый набор M3 Expressive, из
/// которого фигуры берёт и сам Android. Раньше здесь была своя тригонометрия:
/// радиус, гуляющий по кругу синусоидой. Она давала «примерно клевер», но
/// каждая фигура требовала подбора двух чисел на глаз, а вопросы вроде «почему
/// клевер мельче круга» приходилось решать заново для каждой. У официальных
/// фигур скругления посчитаны правильно и размеры согласованы между собой.
///
/// Значения — контракт хранилища: id уезжает в настройки, переименование
/// сбросит выбор на круг.
enum IconShape {
  circle('circle'),
  square('square'),
  slanted('slanted'),
  arch('arch'),
  pill('pill'),
  gem('gem'),
  sunny('sunny'),
  cookie('cookie'),
  clover('clover'),
  flower('flower'),
  puffy('puffy'),
  pebble('pebble');

  const IconShape(this.id);

  final String id;

  static IconShape fromId(String? id) {
    for (final shape in IconShape.values) {
      if (shape.id == id) return shape;
    }
    return IconShape.circle;
  }

  /// Контур из официального набора.
  RoundedPolygon get polygon => switch (this) {
        IconShape.circle => MaterialShapes.circle,
        IconShape.square => MaterialShapes.square,
        IconShape.slanted => MaterialShapes.slanted,
        IconShape.arch => MaterialShapes.arch,
        IconShape.pill => MaterialShapes.pill,
        IconShape.gem => MaterialShapes.gem,
        IconShape.sunny => MaterialShapes.sunny,
        IconShape.cookie => MaterialShapes.cookie7Sided,
        IconShape.clover => MaterialShapes.clover4Leaf,
        IconShape.flower => MaterialShapes.flower,
        IconShape.puffy => MaterialShapes.puffy,
        IconShape.pebble => MaterialShapes.softBurst,
      };

  /// Форма для контейнера диаметром [size].
  ///
  /// Размер параметром больше не нужен — фигуры нормализованы и растягиваются
  /// под любой прямоугольник сами, — но подпись оставлена: её ждут все места
  /// вызова, а лишний аргумент дешевле, чем правка десятка файлов.
  ShapeBorder border(double size) => RoundedPolygonBorder(polygon: polygon);
}
