import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

// не GlobalKey: на кросс-фейде AnimatedSwitcher в дереве два поддерева, и один ключ в двух местах это исключение
class ServerGroupAnchors {
  ServerGroupAnchors._();

  static final ServerGroupAnchors instance = ServerGroupAnchors._();

  final Map<String, BuildContext> _anchors = {};

  double leadingInset = 0;

  final ValueNotifier<String?> currentGroup = ValueNotifier<String?>(null);

  bool _updateScheduled = false;

  // в конце кадра: уведомления прокрутки прилетают и во время layout
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
    String? lowest;
    double? lowestDy;
    var atEnd = false;

    // с запасом: после прыжка группа стоит ровно на leadingInset
    final threshold = leadingInset + 8;

    for (final entry in _anchors.entries) {
      final context = entry.value;
      if (!context.mounted) continue;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport == null) continue;
      final dy = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (viewport is RenderViewportBase) {
        final offset = viewport.offset;
        if (offset is ScrollPosition &&
            offset.hasContentDimensions &&
            offset.maxScrollExtent > 0 &&
            offset.pixels >= offset.maxScrollExtent - 1) {
          atEnd = true;
        }
        if (dy < viewport.size.height && (lowestDy == null || dy > lowestDy)) {
          lowestDy = dy;
          lowest = entry.key;
        }
      }

      if (dy <= threshold) {
        if (passedDy == null || dy > passedDy) {
          passedDy = dy;
          passed = entry.key;
        }
      } else if (nearestDy == null || dy < nearestDy) {
        nearestDy = dy;
        nearest = entry.key;
      }
    }

    // у конца списка короткая последняя группа до верха не доезжает: переход к ней из карусели
    // иначе тут же откатывался на предыдущую
    final next = atEnd && lowest != null ? lowest : passed ?? nearest;
    if (next != currentGroup.value) currentGroup.value = next;
  }

  bool get isEmpty => _anchors.isEmpty;

  void register(String groupKey, BuildContext context) {
    _anchors[groupKey] = context;
  }

  // снимаем только свою запись: на кросс-фейде сменщица регистрируется раньше, чем уходящая диспоузится
  void unregister(String groupKey, BuildContext context) {
    if (identical(_anchors[groupKey], context)) _anchors.remove(groupKey);
  }

  ({String serverId, String groupKey, double? offsetInGroup})? _activeServer;

  void registerActiveServer({
    required String serverId,
    required String groupKey,
    required double? offsetInGroup,
  }) {
    _activeServer = (
      serverId: serverId,
      groupKey: groupKey,
      offsetInGroup: offsetInGroup,
    );
  }

  void unregisterActiveServer(String groupKey) {
    if (_activeServer?.groupKey == groupKey) _activeServer = null;
  }

  ({String groupKey, bool collapsed})? placeOfServer(String serverId) {
    final active = _activeServer;
    if (active == null || active.serverId != serverId) return null;
    return (
      groupKey: active.groupKey,
      collapsed: active.offsetInGroup == null,
    );
  }

  Future<bool> jumpToServer(
    String serverId, {
    Duration duration = const Duration(milliseconds: 420),
    Curve curve = Curves.easeOutCubic,
  }) async {
    final active = _activeServer;
    if (active == null || active.serverId != serverId) return false;
    final offsetInGroup = active.offsetInGroup;
    if (offsetInGroup == null) return false;
    return jumpTo(
      active.groupKey,
      extraOffset: offsetInGroup,
      duration: duration,
      curve: curve,
    );
  }

  Future<bool> jumpTo(
    String groupKey, {
    double extraOffset = 0,
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

    final target =
        (viewport.getOffsetToReveal(render, 0).offset + extraOffset -
                leadingInset)
            .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 1) return true;

    await position.animateTo(target, duration: duration, curve: curve);
    return true;
  }
}

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
        return false;
      },
      child: widget.child,
    );
  }
}

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
