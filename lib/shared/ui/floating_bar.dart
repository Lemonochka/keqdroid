import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../platform/platform_bootstrap.dart';
import '../../ui/responsive/window_breakpoints.dart';

enum LiquidBarStyle {
  mainland,
  islands;

  static LiquidBarStyle fromId(String id) => tryParse(id) ?? mainland;

  // legacy и незнакомое: прежняя нижняя панель
  static LiquidBarStyle? tryParse(String id) {
    // до 0.31 были лента и яркий плюс, сохранённые настройки ведут на материк
    if (id == 'strip' || id == 'brightPlus') return mainland;
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

  // боком лента стоит у края: кнопку и стрелку берёт она, но места снизу не занимает
  // и от прокрутки не прячется. на телевизоре прежняя панель, её водят пультом
  static bool onRail(BuildContext context) =>
      WindowBreakpoints.isExpandedMobile(context) &&
      !PlatformBootstrap.isTelevision &&
      styleOf(context) != null;

  // кнопка действия и стрелка прокрутки живут в ленте, снизу или сбоку
  static bool owns(BuildContext context) => shown(context) || onRail(context);

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
class FloatingBarHideOnScroll extends StatefulWidget {
  const FloatingBarHideOnScroll({super.key, required this.child});

  final Widget child;

  @override
  State<FloatingBarHideOnScroll> createState() => _FloatingBarHideOnScrollState();
}

class _FloatingBarHideOnScrollState extends State<FloatingBarHideOnScroll> {
  // по направлению пальца лента прыгала от каждого сдвига на пиксель туда-обратно:
  // уезжает и возвращается, только когда прокрутка в одну сторону набрала 40 dp
  static const _travel = 40.0;
  var _run = 0.0;
  // прыжок к активному серверу в счёт не идёт, только палец и его докатывание
  var _user = false;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    if (!n.metrics.hasContentDimensions ||
        n.metrics.pixels <= n.metrics.minScrollExtent) {
      _run = 0;
      FloatingBar.hidden.value = false;
      return false;
    }
    if (n is UserScrollNotification) {
      _user = n.direction != ScrollDirection.idle;
      return false;
    }
    if (n is ScrollUpdateNotification && _user) {
      final delta = n.scrollDelta ?? 0;
      _run = (_run >= 0) == (delta >= 0) ? _run + delta : delta;
      if (_run > _travel) {
        FloatingBar.hidden.value = true;
      } else if (_run < -_travel) {
        FloatingBar.hidden.value = false;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: widget.child,
    );
  }
}
