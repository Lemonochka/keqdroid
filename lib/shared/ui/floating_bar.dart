import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../platform/platform_bootstrap.dart';
import '../../ui/responsive/window_breakpoints.dart';
import 'smooth_fade.dart';

enum LiquidBarStyle {
  strip,
  brightPlus,
  islands;

  static LiquidBarStyle fromId(String id) => tryParse(id) ?? strip;

  // legacy и незнакомое: прежняя нижняя панель
  static LiquidBarStyle? tryParse(String id) {
    for (final style in values) {
      if (style.name == id) return style;
    }
    return null;
  }
}

// стиль главного экрана для всего под ним; без него и с null нижняя панель прежняя
class FloatingBarScope extends InheritedWidget {
  const FloatingBarScope({super.key, required this.style, required super.child});

  final LiquidBarStyle? style;

  @override
  bool updateShouldNotify(FloatingBarScope old) => old.style != style;
}

// что стоит в плитках по бокам ленты на вкладке настроек
class FloatingSide {
  const FloatingSide({
    required this.owner,
    required this.start,
    required this.end,
    this.startColor,
    this.startTooltip,
    this.onStartTap,
  });

  final Object owner;
  final Widget start;
  final Widget end;

  // плитка версии сама показывает состояние цветом, без значка
  final Color? startColor;
  final String? startTooltip;
  final VoidCallback? onStartTap;
}

class FloatingJump {
  const FloatingJump({required this.up, required this.onTap});

  final bool up;
  final VoidCallback onTap;
}

// в Модерне нижняя навигация висит лентой над краем экрана, кнопка действия вкладки
// стоит с ней в ряд, стрелка прокрутки с другой стороны. без тени
abstract final class FloatingBar {
  static const height = 64.0;
  static const margin = 16.0;
  static const bottomMargin = 24.0;

  static LiquidBarStyle? styleOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FloatingBarScope>()?.style;

  static bool shown(BuildContext context) =>
      !PlatformBootstrap.isDesktop &&
      !WindowBreakpoints.isExpandedMobile(context) &&
      styleOf(context) != null;

  // стрелка в конец и наверх: список кладёт сюда, панель рисует её у себя
  static final jump = ValueNotifier<FloatingJump?>(null);

  // версия и кнопка проверки: настройки кладут сюда, панель поднимает их из края
  static final side = ValueNotifier<FloatingSide?>(null);

  static double clearance(BuildContext context) =>
      shown(context) ? bottomMargin + height + bottomInset.value : 0;

  // системный отступ снизу знает только панель: в теле Scaffold он уже обнулён
  static final bottomInset = ValueNotifier<double>(0);

  // прокрутка вниз прячет панель, вверх и смена вкладки возвращают
  static final hidden = ValueNotifier<bool>(false);

  // действие кнопки по вкладке: страница кладёт сюда своё при сборке
  static final actions = <int, VoidCallback>{};

  static ui.FragmentProgram? _bar;
  static ui.FragmentProgram? _drop;
  static Future<void>? _loading;

  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      _bar = await ui.FragmentProgram.fromAsset('shaders/liquid_bar.frag');
      _drop = await ui.FragmentProgram.fromAsset('shaders/liquid_drop.frag');
    } catch (_) {}
  }

  static ui.FragmentShader? newBarShader() => _bar?.fragmentShader();

  static ui.FragmentShader? newDropShader() => _drop?.fragmentShader();

  // лента на текущем экране: уведомления встают над ней. держит та панель, что поставила
  static final barOnScreen = ValueNotifier<Object?>(null);

  // плитки ленты ярче карточек и фона: в тёмной теме даже Highest с ними сливался
  static Color tileColor(ColorScheme cs) =>
      Color.alphaBlend(cs.onSurface.withValues(alpha: 0.06), cs.surfaceContainerHighest);
}

// как у кнопки раньше: вниз прячет, вверх и у самого верха возвращает
class FloatingBarHideOnScroll extends StatelessWidget {
  const FloatingBarHideOnScroll({super.key, required this.child});

  final Widget child;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    if (n is UserScrollNotification) {
      switch (n.direction) {
        case ScrollDirection.reverse:
          FloatingBar.hidden.value = true;
        case ScrollDirection.forward:
          FloatingBar.hidden.value = false;
        case ScrollDirection.idle:
          break;
      }
    } else if ((n is ScrollUpdateNotification || n is ScrollEndNotification) &&
        (!n.metrics.hasContentDimensions ||
            n.metrics.pixels <= n.metrics.minScrollExtent)) {
      FloatingBar.hidden.value = false;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: child,
    );
  }
}

// список под плавающей лентой гаснет у низа, как список серверов. системный отступ
// здесь уже снял SafeArea: прятать его второй раз значило гасить на 24 dp выше серверов
class FloatingBarFade extends StatelessWidget {
  const FloatingBarFade({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!FloatingBar.shown(context)) return child;
    return EdgeFadeMask(bottom: 28, child: child);
  }
}
