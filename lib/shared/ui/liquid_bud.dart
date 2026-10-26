import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// капля, которая вытекает из одной плашки и раздувается в другую
class LiquidBud {
  static ui.FragmentProgram? _program;
  static Future<void>? _loading;

  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      _program = await ui.FragmentProgram.fromAsset('shaders/liquid_bud.frag');
    } catch (_) {}
  }

  static ui.FragmentShader? newShader() => _program?.fragmentShader();

  // источник не закрашивается: под ним настоящая плашка, видны только перемычка и капля
  static void paint(
    Canvas canvas,
    ui.FragmentShader shader, {
    required double devicePixelRatio,
    required Rect source,
    required double sourceRadius,
    required Rect bud,
    required double budRadius,
    required double goo,
    required Color sourceColor,
    required Color budColor,
  }) {
    var i = 0;
    void put(double v) => shader.setFloat(i++, v);
    void rect(Rect r) {
      put(r.left);
      put(r.top);
      put(r.right);
      put(r.bottom);
    }
    void color(Color c) {
      put(c.r);
      put(c.g);
      put(c.b);
      put(c.a);
    }

    final bounds = source.expandToInclude(bud).inflate(goo + 2);
    put(bounds.width);
    put(bounds.height);
    put(devicePixelRatio);
    rect(source);
    put(sourceRadius);
    rect(bud);
    put(budRadius);
    put(goo);
    color(sourceColor);
    color(budColor);
    canvas.drawRect(bounds, Paint()..shader = shader);
  }
}
