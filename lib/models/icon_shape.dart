import 'package:androidx_graphics_shapes/material_shapes.dart';
import 'package:androidx_graphics_shapes/shapes.dart';
import 'package:flutter/material.dart';

// id лежат в настройках, переименование сбросит выбор на круг
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

  ShapeBorder border(double size) => RoundedPolygonBorder(polygon: polygon);
}
