import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Горизонтальный список, который слушается мыши.
///
/// Flutter на десктопе не даёт листать такие списки ничем. Колесо: `Scrollable`
/// берёт из события дельту по своей оси, то есть `dx`, а обычное колесо шлёт
/// только `dy` — оси меняются местами лишь пока зажат Shift, о чём догадаться
/// нельзя. Перетаскивание: мыши нет в `dragDevices` десктопного
/// `ScrollBehavior`, список тянется пальцем и тачпадом, но не курсором.
///
/// На телефоне ни того ни другого не видно, поэтому горизонтальные ряды и
/// разъезжались по платформам: на Android листаются, на десктопе стоят намертво
/// и в узком окне уезжают за край без всякой возможности добраться до хвоста.
class HorizontalMouseScroll extends StatelessWidget {
  const HorizontalMouseScroll({
    super.key,
    required this.controller,
    required this.child,
  });

  /// Контроллер того самого горизонтального списка. Нужен именно он: колесо мы
  /// обрабатываем сами и двигаем позицию напрямую.
  final ScrollController controller;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.mouse,
        },
      ),
      child: Listener(onPointerSignal: _onPointerSignal, child: child),
    );
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // Только вертикальная дельта. Горизонтальную (наклон колеса, Shift,
    // жест тачпада) `Scrollable` разбирает сам, и вмешательство здесь просто
    // удвоило бы её.
    final delta = event.scrollDelta.dy;
    if (delta == 0 || !controller.hasClients) return;
    // Через позицию, а не `jumpTo`: `pointerScroll` — тот же вход, которым
    // пользуется сам `Scrollable`, поэтому список ведёт себя одинаково
    // независимо от того, кто ему передал щелчок колеса (в частности,
    // сглаживание `SmoothScrollController` остаётся в силе).
    controller.position.pointerScroll(delta);
  }
}
