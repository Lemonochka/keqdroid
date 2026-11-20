// изолятор, а не устаревшая пара LRE/PDF: та протекает на соседний текст
library;

import 'package:flutter/widgets.dart';

// кодами: невидимые управляющие символы в исходнике переставляют текст в редакторе и diff
final _lri = String.fromCharCode(0x2066); // LEFT-TO-RIGHT ISOLATE
final _pdi = String.fromCharCode(0x2069); // POP DIRECTIONAL ISOLATE

String ltrIsolate(String value) => value.isEmpty ? value : '$_lri$value$_pdi';

// в фарси поле пишет справа налево, и /path выглядит как path/
const TextDirection technicalInputDirection = TextDirection.ltr;

final _rtlLetter = RegExp('[֐-ࣿיִ-﷿ﹰ-﻿]');
final _letter = RegExp(r'\p{L}', unicode: true);

// по первой букве, как Android: иначе латинское имя в фарси обрезается не с того края
TextDirection contentDirection(String text, {required TextDirection fallback}) {
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    if (_rtlLetter.hasMatch(ch)) return TextDirection.rtl;
    if (_letter.hasMatch(ch)) return TextDirection.ltr;
  }
  return fallback;
}

TextAlign uiStartAlign(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl
    ? TextAlign.right
    : TextAlign.left;

// ltrIsolate не поможет, когда значение собрано из нескольких Text в Row, потому что Row зеркалится сам;
// невидимых символов не добавляет, поэтому годится и для копируемого текста
class LtrBlock extends StatelessWidget {
  final Widget child;

  const LtrBlock({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      Directionality(textDirection: TextDirection.ltr, child: child);
}
