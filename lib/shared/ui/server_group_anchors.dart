import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// Якоря групп серверов: куда прыгает боковой навигатор.
///
/// Сайдбар и список серверов живут в РАЗНЫХ ветках дерева (`IndexedStack` в
/// десктопной оболочке), общего состояния у них нет, а прыгать надо к группе,
/// которая в этот момент может быть далеко за экраном. Отсюда реестр: каждая
/// группа кладёт сюда свой `BuildContext`, навигатор по нему считает смещение.
///
/// Почему не `GlobalKey` на группе: список серверов пересобирается через
/// `AnimatedSwitcher` при смене раскладки колонок, и на время кросс-фейда в
/// дереве живут ОБА поддерева — один и тот же `GlobalKey` в двух местах это
/// исключение. Контексты же спокойно сосуществуют: пришедший последним
/// перекрывает прежний, а уходящий снимает только СВОЮ запись (см.
/// [unregister]).
///
/// Почему не считать смещения самим (`SliverLayoutBuilder` +
/// `precedingScrollExtent`): его билдер зовётся на каждое изменение
/// `SliverConstraints`, то есть на каждый кадр прокрутки, — и перестраивал бы
/// всю группу целиком. Ровно та rebuild-буря, которую в этом списке уже чинили.
class ServerGroupAnchors {
  ServerGroupAnchors._();

  static final ServerGroupAnchors instance = ServerGroupAnchors._();

  final Map<String, BuildContext> _anchors = {};

  /// Сколько пикселей оставить над группой: сверху список накрыт градиентом,
  /// и выровненная «в ноль» шапка уехала бы под него. Ставит сам список — он
  /// один знает высоту своей шапки.
  double leadingInset = 0;

  /// Группа, на которой список стоит СЕЙЧАС, — то есть чья шапка занимает верх
  /// экрана. Именно её подсвечивает навигатор.
  ///
  /// Подсвечивать группу активного сервера, как было сначала, нельзя: активный
  /// сервер не двигается, и метка навсегда оставалась на своей группе, сколько
  /// бы ты ни прыгала. Наружу это выглядело как «прыжок не работает» — хотя
  /// список уезжал правильно.
  final ValueNotifier<String?> currentGroup = ValueNotifier<String?>(null);

  bool _updateScheduled = false;

  /// Просит пересчитать [currentGroup] в конце кадра.
  ///
  /// Не сразу: уведомления прокрутки прилетают и во время layout, а
  /// `ValueNotifier` дёргает слушателей синхронно — `setState` посреди layout
  /// это исключение. Заодно получается троттлинг: сколько бы уведомлений ни
  /// пришло за кадр, пересчёт будет один.
  void requestUpdate() {
    if (_updateScheduled) return;
    _updateScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      _recomputeCurrent();
    });
  }

  void _recomputeCurrent() {
    String? passed;
    double? passedDy;
    String? nearest;
    double? nearestDy;

    // Порог чуть ниже отступа шапки: после прыжка группа стоит ровно на
    // `leadingInset`, и без запаса она считалась бы «ещё не достигнутой».
    final threshold = leadingInset + 8;

    for (final entry in _anchors.entries) {
      final context = entry.value;
      if (!context.mounted) continue;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport == null) continue;
      final dy = box.localToGlobal(Offset.zero, ancestor: viewport).dy;

      if (dy <= threshold) {
        // Из уже проехавших верх — самая нижняя: она и занимает экран.
        if (passedDy == null || dy > passedDy) {
          passedDy = dy;
          passed = entry.key;
        }
      } else if (nearestDy == null || dy < nearestDy) {
        nearestDy = dy;
        nearest = entry.key;
      }
    }

    // Ни одна не проехала верх — список в самом начале, текущая та, что первой
    // идёт под шапкой.
    final next = passed ?? nearest;
    if (next != currentGroup.value) currentGroup.value = next;
  }

  /// Есть ли к чему прыгать. Пустой реестр означает, что список серверов ещё
  /// не построен (или групп нет вовсе) — навигатору тогда нечего показывать.
  bool get isEmpty => _anchors.isEmpty;

  void register(String groupKey, BuildContext context) {
    _anchors[groupKey] = context;
  }

  /// Снимает ТОЛЬКО свою запись: во время кросс-фейда раскладки уходящая
  /// группа диспоузится уже ПОСЛЕ того, как её сменщица зарегистрировалась, и
  /// безусловное удаление стёрло бы живой якорь.
  void unregister(String groupKey, BuildContext context) {
    if (identical(_anchors[groupKey], context)) _anchors.remove(groupKey);
  }

  /// Прокручивает список к группе. `false` — якоря нет (список не построен,
  /// группа исчезла), и вызывающий может решить, что делать дальше.
  Future<bool> jumpTo(
    String groupKey, {
    Duration duration = const Duration(milliseconds: 420),
    Curve curve = Curves.easeOutCubic,
  }) async {
    final context = _anchors[groupKey];
    if (context == null || !context.mounted) return false;

    final render = context.findRenderObject();
    if (render == null || !render.attached) return false;

    final position = Scrollable.maybeOf(context)?.position;
    final viewport = RenderAbstractViewport.maybeOf(render);
    if (position == null || viewport == null) return false;
    if (!position.hasContentDimensions) return false;

    final target = (viewport.getOffsetToReveal(render, 0).offset - leadingInset)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    // Уже там: анимация «на месте» выглядит как случайное вздрагивание списка.
    if ((target - position.pixels).abs() < 1) return true;

    await position.animateTo(target, duration: duration, curve: curve);
    return true;
  }
}

/// Оборачивает список серверов: задаёт отступ прыжка и следит, на какой группе
/// список стоит сейчас.
///
/// Слушатель прокрутки живёт здесь, а не в самом списке, ровно затем, чтобы
/// «прыжок» и «текущая группа» проверялись одним куском в тестах — а не
/// оказались двумя половинами, каждая из которых по отдельности работает.
class ServerGroupAnchorScope extends StatefulWidget {
  final double leadingInset;
  final Widget child;

  const ServerGroupAnchorScope({
    super.key,
    required this.leadingInset,
    required this.child,
  });

  @override
  State<ServerGroupAnchorScope> createState() => _ServerGroupAnchorScopeState();
}

class _ServerGroupAnchorScopeState extends State<ServerGroupAnchorScope> {
  @override
  void initState() {
    super.initState();
    _apply();
  }

  @override
  void didUpdateWidget(ServerGroupAnchorScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leadingInset != widget.leadingInset) _apply();
  }

  void _apply() {
    ServerGroupAnchors.instance
      ..leadingInset = widget.leadingInset
      ..requestUpdate();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        ServerGroupAnchors.instance.requestUpdate();
        // false — уведомление идёт дальше: на нём же держатся шапка и фейды.
        return false;
      },
      child: widget.child,
    );
  }
}

/// Помечает шапку группы как цель прыжка.
///
/// Регистрация идёт из `initState`/`dispose`, а не из `build`: билд у группы
/// случается на каждый пинг и на каждую смену активного сервера, и трогать
/// общий реестр так часто незачем.
class ServerGroupAnchor extends StatefulWidget {
  final String groupKey;
  final Widget child;

  const ServerGroupAnchor({
    super.key,
    required this.groupKey,
    required this.child,
  });

  @override
  State<ServerGroupAnchor> createState() => _ServerGroupAnchorState();
}

class _ServerGroupAnchorState extends State<ServerGroupAnchor> {
  @override
  void initState() {
    super.initState();
    ServerGroupAnchors.instance.register(widget.groupKey, context);
  }

  @override
  void didUpdateWidget(ServerGroupAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupKey == widget.groupKey) return;
    ServerGroupAnchors.instance.unregister(oldWidget.groupKey, context);
    ServerGroupAnchors.instance.register(widget.groupKey, context);
  }

  @override
  void dispose() {
    ServerGroupAnchors.instance.unregister(widget.groupKey, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
