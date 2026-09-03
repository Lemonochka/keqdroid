import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

const _kGreen = Color(0xFF6BAF92);
const _kOrange = Color(0xFFC49060);

class AppTheme {
  static ColorScheme _cs(BuildContext ctx) => Theme.of(ctx).colorScheme;

  static Color bg(BuildContext ctx) => _cs(ctx).surface;
  static Color card(BuildContext ctx) => _cs(ctx).surfaceContainerHigh;
  static Color inset(BuildContext ctx) => _cs(ctx).surfaceContainerLowest;
  static Color accent(BuildContext ctx) => _cs(ctx).primary;
  static Color text(BuildContext ctx) => _cs(ctx).onSurface;
  static Color textLight(BuildContext ctx) => _cs(ctx).onSurfaceVariant;
  static Color red(BuildContext ctx) => _cs(ctx).error;

  /// Текст и иконки ПОВЕРХ [red]. Белым тут не отделаться: в тёмной схеме
  /// `error` сам светло-красный, и белая надпись на нём почти не читается.
  static Color onRed(BuildContext ctx) => _cs(ctx).onError;
  static Color divider(BuildContext ctx) => _cs(ctx).outlineVariant;
  static Color accentContainer(BuildContext ctx) => _cs(ctx).primaryContainer;
  static Color onAccentContainer(BuildContext ctx) => _cs(ctx).onPrimaryContainer;
  static Color green(BuildContext ctx) => harmonize(ctx, _kGreen);
  static Color orange(BuildContext ctx) => harmonize(ctx, _kOrange);

  /// Подтягивает произвольный цвет к текущей схеме.
  ///
  /// M3 требует «designing with roles, never raw hexes». Там, где цвет несёт
  /// собственный смысл и ролью не заменяется (протоколы, статусы), спека
  /// разрешает свой цвет — но гармонизированный, иначе на цветной динамической
  /// теме он читается как чужеродный.
  static Color harmonize(BuildContext ctx, Color color) =>
      color.harmonizeWith(_cs(ctx).primary);
}
