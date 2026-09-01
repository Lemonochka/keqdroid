import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Горизонтальный список, который слушается мыши.
///
/// Flutter по умолчанию не даёт листать горизонтальные списки на десктопе
/// НИКАК — ни колесом, ни перетаскиванием, и причины у этого разные:
///
///  * **колесо.** `Scrollable` берёт из события ту дельту, что совпадает с осью
///    списка, то есть `scrollDelta.dx`. Обычное колесо шлёт только `dy`, и
///    горизонтальный список на него не реагирует вовсе. Оси Flutter меняет
///    местами, лишь пока зажат модификатор (по умолчанию Shift) — то есть
///    работающий способ есть, но угадать его нельзя;
///  * **перетаскивание.** В `dragDevices` десктопного `ScrollBehavior` мыши
///    нет: список тянется пальцем, стилусом и тачпадом, но не курсором.
///
/// На телефоне ни то, ни другое не проявляется, поэтому горизонтальные ряды и
/// разъезжались по платформам: на Android листаются, на Windows и Linux стоят
/// намертво, а в узком окне ещё и уезжают за край без всякой возможности
/// добраться до хвоста.
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
