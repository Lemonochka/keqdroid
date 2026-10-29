import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/desktop_screens_sweep.dart';

void main() {
  // ПК-оболочка строится по Platform.isWindows, на CI ubuntu её не собрать
  testWidgets(
      'экраны ПК не обрезаются: немецкий, окно 480x580, шрифт x1.3',
      skip: !Platform.isWindows, (tester) async {
    // минимальное окно из flutter_window.cpp и крупный шрифт Windows
    final found = await sweepDesktopScreens(
      tester,
      locale: 'de',
      window: const Size(480, 580),
      textScale: 1.3,
    );
    expect(
      found.entries.map((e) => '${e.key} — ${e.value.join(' | ')}'),
      isEmpty,
    );
  });
}
