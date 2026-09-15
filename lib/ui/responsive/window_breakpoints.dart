import 'package:flutter/widgets.dart';

import '../../platform/platform_bootstrap.dart';

/// Брейкпоинты M3 по ширине окна (m3.material.io, Layout → Breakpoints).
abstract final class WindowBreakpoints {
  /// От этой ширины — «expanded»: телефон боком, планшет боком, раскрытый
  /// складной телефон.
  static const double expanded = 840;

  /// Телефон или планшет шириной от [expanded]: навигация уходит в рейку, а
  /// экран серверов встаёт двумя панелями.
  ///
  /// По ширине окна, а не по ориентации: разделённый экран и складной телефон
  /// меняют класс так же, как поворот. Десктоп сюда не входит — у него своя
  /// оболочка с боковой панелью и высокое окно.
  static bool isExpandedMobile(BuildContext context) =>
      !PlatformBootstrap.isDesktop &&
      MediaQuery.sizeOf(context).width >= expanded;
}
