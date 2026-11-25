import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/shared/ui/expressive.dart';

abstract final class TvFocus {
  static bool get enabled => PlatformBootstrap.isTelevision;

  static const focusedScale = 1.05;

  static const double _maxScrollStep = 200;

  static Widget fab(WidgetBuilder builder) => TvFocusHighlight(
    radius: BorderRadius.circular(ExpressiveShape.largeIncreased),
    child: Builder(builder: builder),
  );

  // по умолчанию Slider забирает себе и стрелки вверх-вниз, и пульт не мог уйти с ползунка
  static Widget slider(Widget slider) => enabled
      ? Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(navigationMode: NavigationMode.directional),
            child: slider,
          ),
        )
      : slider;

  static ColorScheme invert(ColorScheme s) {
    final muted = Color.lerp(s.onInverseSurface, s.inverseSurface, 0.25)!;
    return s.copyWith(
      brightness: s.brightness == Brightness.light
          ? Brightness.dark
          : Brightness.light,
      surface: s.inverseSurface,
      onSurface: s.onInverseSurface,
      onSurfaceVariant: muted,
      surfaceContainerLowest: s.inverseSurface,
      surfaceContainerLow: s.inverseSurface,
      surfaceContainer: s.inverseSurface,
      surfaceContainerHigh: s.inverseSurface,
      surfaceContainerHighest: s.inverseSurface,
      primary: s.inversePrimary,
      primaryContainer: s.inverseSurface,
      onPrimaryContainer: s.onInverseSurface,
      secondaryContainer: s.inverseSurface,
      onSecondaryContainer: s.onInverseSurface,
      tertiaryContainer: s.inverseSurface,
      onTertiaryContainer: s.onInverseSurface,
      inverseSurface: s.surface,
      onInverseSurface: s.onSurface,
      inversePrimary: s.primary,
      outline: muted,
      outlineVariant: Color.lerp(s.onInverseSurface, s.inverseSurface, 0.6),
    );
  }

  static InputDecorationThemeData invertInputDecoration(
    InputDecorationThemeData base,
    ColorScheme inv,
  ) => base.copyWith(
    border: ExpressiveShape.inputBorder(Colors.transparent),
    enabledBorder: ExpressiveShape.inputBorder(Colors.transparent),
    focusedBorder: ExpressiveShape.inputBorder(inv.primary, width: 2),
    hintStyle: (base.hintStyle ?? const TextStyle()).copyWith(
      color: inv.onSurfaceVariant,
    ),
    helperStyle: (base.helperStyle ?? const TextStyle()).copyWith(
      color: inv.onSurfaceVariant,
    ),
    labelStyle: (base.labelStyle ?? const TextStyle()).copyWith(
      color: inv.onSurfaceVariant,
    ),
    floatingLabelStyle: (base.floatingLabelStyle ?? const TextStyle()).copyWith(
      color: inv.primary,
    ),
    prefixIconColor: inv.onSurfaceVariant,
    suffixIconColor: inv.onSurfaceVariant,
  );

  static ButtonStyle buttonStyle(ColorScheme s, [ButtonStyle? base]) {
    WidgetStateProperty<Color?> layered(
      Color focused,
      WidgetStateProperty<Color?>? under,
    ) => WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? focused
          : under?.resolve(states),
    );
    return (base ?? const ButtonStyle()).copyWith(
      backgroundColor: layered(s.inverseSurface, base?.backgroundColor),
      foregroundColor: layered(s.onInverseSurface, base?.foregroundColor),
      iconColor: layered(s.onInverseSurface, base?.iconColor),
      overlayColor: layered(Colors.transparent, base?.overlayColor),
    );
  }

  // цвет здесь: Icon и IconButton.color перебивают фокус, и тёмный значок терялся на тёмной заливке
  static ButtonStyle iconButtonStyle(
    BuildContext context, {
    Color? color,
    ButtonStyle? base,
  }) {
    final style = (base ?? const ButtonStyle()).copyWith(
      foregroundColor: color == null ? null : WidgetStatePropertyAll(color),
    );
    return enabled ? buttonStyle(Theme.of(context).colorScheme, style) : style;
  }

  // ленивый список не строит кнопки дальше cacheExtent, поэтому когда рядом цели нет, стрелка листает сам список
  static bool moveFocus(TraversalDirection direction) {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || focus.context == null) return false;
    if (!enabled ||
        direction == TraversalDirection.left ||
        direction == TraversalDirection.right) {
      return focus.focusInDirection(direction);
    }

    final scrollable = _findVerticalScrollable(focus);
    if (scrollable == null || !scrollable.position.hasPixels) {
      return focus.focusInDirection(direction);
    }
    final pos = scrollable.position;
    if (scrollable.resolvedPhysics != null &&
        !scrollable.resolvedPhysics!.shouldAcceptUserOffset(pos)) {
      return focus.focusInDirection(direction);
    }
    final box = scrollable.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return focus.focusInDirection(direction);
    }

    final viewport = box.localToGlobal(Offset.zero) & box.size;
    final step = math.min(_maxScrollStep, viewport.height * 0.45);
    final wantDown = direction == TraversalDirection.down;
    final signedStep =
        wantDown == (scrollable.axisDirection == AxisDirection.down)
        ? step
        : -step;
    final canScroll = signedStep > 0
        ? pos.pixels < pos.maxScrollExtent - 0.5
        : pos.pixels > pos.minScrollExtent + 0.5;

    final scope = focus.nearestScope;
    final current = scope?.focusedChild;
    if (scope != null && current != null) {
      if (_hasNearbyCandidate(
        scope,
        current,
        scrollable,
        viewport,
        wantDown,
        step,
        canScroll,
      )) {
        return _focusAvoidingPinnedBar(
          scope,
          current,
          focus,
          direction,
          wantDown: wantDown,
          canScroll: canScroll,
        );
      }
      if (canScroll) {
        _scrollBy(pos, signedStep);
        return true;
      }
      return focus.focusInDirection(direction);
    }

    if (scope != null) {
      final target = _visibleScrollCandidate(
        scope,
        scrollable,
        viewport,
        wantDown,
        step,
      );
      if (target != null) {
        FocusTraversalPolicy.defaultTraversalRequestFocusCallback(
          target,
          alignmentPolicy: wantDown
              ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
              : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        );
        return true;
      }
    }
    if (canScroll) {
      _scrollBy(pos, signedStep);
      return true;
    }
    return focus.focusInDirection(direction);
  }

  static void _scrollBy(ScrollPosition pos, double delta) {
    final target = (pos.pixels + delta).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    pos.moveTo(
      target,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
    );
  }

  static ScrollableState? _outerVerticalScrollable(BuildContext context) {
    var current = Scrollable.maybeOf(context, axis: Axis.vertical);
    while (current != null &&
        current.context.findAncestorWidgetOfExactType<EditableText>() != null) {
      final parent = _parentContext(current.context);
      current = parent == null
          ? null
          : Scrollable.maybeOf(parent, axis: Axis.vertical);
    }
    return current;
  }

  static BuildContext? _parentContext(BuildContext context) {
    BuildContext? parent;
    (context as Element).visitAncestorElements((el) {
      parent = el;
      return false;
    });
    return parent;
  }

  static ScrollableState? _findVerticalScrollable(FocusNode focus) {
    final direct = _outerVerticalScrollable(focus.context!);
    if (direct != null) return direct;
    final scopeCtx = focus.nearestScope?.context;
    if (scopeCtx == null) return null;
    ScrollableState? found;
    void visit(Element el) {
      if (found != null) return;
      final w = el.widget;
      if (w is ExcludeFocus && w.excluding) return;
      if (w is EditableText) return;
      if (el is StatefulElement && el.state is ScrollableState) {
        final s = el.state as ScrollableState;
        if (axisDirectionToAxis(s.axisDirection) == Axis.vertical &&
            s.position.hasPixels &&
            s.position.maxScrollExtent > s.position.minScrollExtent) {
          found = s;
          return;
        }
      }
      el.visitChildren(visit);
    }

    (scopeCtx as Element).visitChildren(visit);
    return found;
  }

  static bool _inPinnedAppBar(BuildContext context) =>
      context.findAncestorWidgetOfExactType<SliverAppBar>() != null;

  static bool _focusAvoidingPinnedBar(
    FocusScopeNode scope,
    FocusNode current,
    FocusNode focus,
    TraversalDirection direction, {
    required bool wantDown,
    required bool canScroll,
  }) {
    final currentInBar =
        current.context != null && _inPinnedAppBar(current.context!);
    if (wantDown || !canScroll || currentInBar) {
      return focus.focusInDirection(direction);
    }
    final barNodes = [
      for (final n in scope.traversalDescendants)
        if (n.context != null && _inPinnedAppBar(n.context!)) n,
    ];
    for (final n in barNodes) {
      n.skipTraversal = true;
    }
    try {
      return focus.focusInDirection(direction);
    } finally {
      for (final n in barNodes) {
        n.skipTraversal = false;
      }
    }
  }

  static bool _hasNearbyCandidate(
    FocusScopeNode scope,
    FocusNode current,
    ScrollableState scrollable,
    Rect viewport,
    bool wantDown,
    double step,
    bool canScroll,
  ) {
    final currentRect = current.rect;
    final currentInBar =
        current.context != null && _inPinnedAppBar(current.context!);
    var candidates = scope.traversalDescendants.where((node) {
      if (node == current || node.context == null) return false;
      // прибитая шапка висит наверху экрана и перехватила бы подъём раньше верхних строк списка
      if (!wantDown &&
          canScroll &&
          !currentInBar &&
          _inPinnedAppBar(node.context!)) {
        return false;
      }
      final r = node.rect;
      if (r == currentRect) return false;
      return wantDown
          ? r.center.dy >= currentRect.bottom
          : r.center.dy <= currentRect.top;
    }).toList();
    if (candidates.isEmpty) return false;

    if (current.context != null &&
        _outerVerticalScrollable(current.context!) == scrollable) {
      final inSame = candidates
          .where((n) => _outerVerticalScrollable(n.context!) == scrollable)
          .toList();
      if (inSame.isNotEmpty) candidates = inSame;
    }

    return candidates.any(
      (n) => wantDown
          ? n.rect.top <= viewport.bottom + step
          : n.rect.bottom >= viewport.top - step,
    );
  }

  static FocusNode? _visibleScrollCandidate(
    FocusScopeNode scope,
    ScrollableState scrollable,
    Rect viewport,
    bool wantDown,
    double step,
  ) {
    final topEdge = viewport.top + kToolbarHeight;
    final candidates = scope.traversalDescendants.where((n) {
      if (n.context == null) return false;
      if (_outerVerticalScrollable(n.context!) != scrollable) return false;
      final r = n.rect;
      return wantDown
          ? r.top >= topEdge && r.top <= viewport.bottom + step
          : r.bottom >= viewport.top - step && r.bottom <= viewport.bottom;
    }).toList();
    if (candidates.isEmpty) return null;
    candidates.sort(
      (a, b) => wantDown
          ? a.rect.top.compareTo(b.rect.top)
          : b.rect.bottom.compareTo(a.rect.bottom),
    );
    return candidates.first;
  }
}

class TvDirectionalFocusAction extends DirectionalFocusAction {
  @override
  void invoke(DirectionalFocusIntent intent) {
    if (!intent.ignoreTextFields) {
      TvFocus.moveFocus(intent.direction);
      return;
    }
    final primary = FocusManager.instance.primaryFocus;
    final ctx = primary?.context;
    if (ctx != null &&
        (ctx.widget is EditableText ||
            ctx.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return;
    }
    TvFocus.moveFocus(intent.direction);
  }
}

// на ТВ голый TextField сразу зовёт клавиатуру и запирает стрелки внутри строки, а Назад закрывает весь экран;
// здесь поле берёт фокус как кнопка, ввод открывает по OK, стрелки на краю текста и Назад выводят наружу
class TvTextField extends StatefulWidget {
  const TvTextField({
    super.key,
    required this.builder,
    this.radius,
    this.autofocus = false,
    this.enabled = true,
  });

  final Widget Function(BuildContext context, bool canRequestFocus) builder;
  final BorderRadiusGeometry? radius;
  final bool autofocus;
  final bool enabled;

  @override
  State<TvTextField> createState() => _TvTextFieldState();
}

class _TvTextFieldState extends State<TvTextField> {
  FocusNode? _navNode;
  bool _editing = false;
  bool _navPrimary = false;

  FocusNode get _effectiveNavNode {
    var node = _navNode;
    if (node == null) {
      node = FocusNode(debugLabel: 'TvTextField')
        ..addListener(_onNavFocusChange);
      _navNode = node;
    }
    return node;
  }

  @override
  void didUpdateWidget(covariant TvTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _editing) {
      _editing = false;
    }
  }

  @override
  void dispose() {
    _navNode?.removeListener(_onNavFocusChange);
    _navNode?.dispose();
    super.dispose();
  }

  void _onNavFocusChange() {
    final node = _navNode;
    final primary = node?.hasPrimaryFocus ?? false;
    if (primary != _navPrimary && mounted) {
      setState(() => _navPrimary = primary);
    }
    if (_editing && !(node?.hasFocus ?? false)) {
      _onInnerFocusLost();
    }
  }

  EditableTextState? _findEditableText() {
    if (!mounted) return null;
    EditableTextState? found;
    void visit(Element el) {
      if (found != null) return;
      if (el is StatefulElement && el.state is EditableTextState) {
        found = el.state as EditableTextState;
        return;
      }
      el.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return found;
  }

  void _startEditing() {
    if (!widget.enabled) return;
    if (_editing) {
      _findEditableText()?.requestKeyboard();
      return;
    }
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_editing) return;
      final editable = _findEditableText();
      if (editable == null || editable.widget.readOnly) {
        setState(() => _editing = false);
        _navNode?.requestFocus();
        return;
      }
      final ctrl = editable.widget.controller;
      if (!ctrl.selection.isValid) {
        ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
      }
      editable.requestKeyboard();
    });
  }

  void _stopEditing({required bool restoreNavFocus}) {
    if (!_editing) return;
    setState(() => _editing = false);
    if (restoreNavFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_editing && (_navNode?.canRequestFocus ?? false)) {
          _navNode!.requestFocus();
        }
      });
    }
  }

  void _onInnerFocusLost() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_editing) return;
      final editable = _findEditableText();
      if (editable != null && editable.widget.focusNode.hasFocus) return;
      final primary = FocusManager.instance.primaryFocus;
      final lostToScope = primary == null || primary is FocusScopeNode;
      _stopEditing(restoreNavFocus: lostToScope);
    });
  }

  bool _canMoveCaretVertically(bool forward) {
    final editable = _findEditableText();
    if (editable == null || editable.widget.maxLines == 1) return false;
    final value = editable.textEditingValue;
    if (value.text.isEmpty || !value.selection.isValid) return false;
    final run = editable.renderEditable.startVerticalCaretMovement(
      value.selection.extent,
    );
    return forward ? run.moveNext() : run.movePrevious();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    if (_editing) {
      if (key == LogicalKeyboardKey.escape && event is KeyDownEvent) {
        _stopEditing(restoreNavFocus: true);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        final forward = key == LogicalKeyboardKey.arrowDown;
        if (_canMoveCaretVertically(forward)) return KeyEventResult.ignored;
        final editableNode = _findEditableText()?.widget.focusNode;
        final dir = forward ? TraversalDirection.down : TraversalDirection.up;
        final moved = TvFocus.moveFocus(dir);
        if (moved) {
          setState(() => _editing = false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _editing) return;
            final pf = FocusManager.instance.primaryFocus;
            if (pf == null || pf is FocusScopeNode || pf == editableNode) {
              if (_navNode?.canRequestFocus ?? false) _navNode!.requestFocus();
            }
          });
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // кнопки suffixIcon лежат внутри прямоугольника поля, и штатный фильтр right их не видит
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final toEnd = rtl
        ? LogicalKeyboardKey.arrowLeft
        : LogicalKeyboardKey.arrowRight;
    final toStart = rtl
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowLeft;
    if (_navPrimary && key == toEnd) {
      final inner = node.descendants
          .where((n) => n.canRequestFocus)
          .firstOrNull;
      if (inner != null) {
        inner.requestFocus();
        return KeyEventResult.handled;
      }
    } else if (!_navPrimary && key == toStart) {
      if (node.canRequestFocus) {
        node.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (!TvFocus.enabled) return widget.builder(context, true);
    final navNode = _effectiveNavNode;

    return PopScope<Object?>(
      canPop: !_editing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _editing) _stopEditing(restoreNavFocus: true);
      },
      child: TvFocusHighlight(
        radius: widget.radius ?? ExpressiveShape.radius(ExpressiveShape.medium),
        own: true,
        suppressed: _editing || !_navPrimary,
        child: Actions(
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                if (!_editing && navNode.hasPrimaryFocus) _startEditing();
                return null;
              },
            ),
          },
          child: Focus(
            focusNode: navNode,
            autofocus: widget.autofocus,
            canRequestFocus: widget.enabled && !_editing,
            skipTraversal: !widget.enabled || _editing,
            onKeyEvent: _onKeyEvent,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: widget.enabled && !_editing ? _startEditing : null,
              child: ExcludeFocusTraversal(
                excluding: !_editing,
                child: Builder(builder: (ctx) => widget.builder(ctx, _editing)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// у голого GestureDetector фокуса нет: пульт его обходит, и OK ничего не нажимает
class TvTappable extends StatelessWidget {
  const TvTappable({
    super.key,
    required this.onTap,
    required this.child,
    this.radius,
    this.shape,
  });

  final VoidCallback? onTap;
  final Widget child;
  final BorderRadiusGeometry? radius;
  final ShapeBorder? shape;

  @override
  Widget build(BuildContext context) {
    final onTap = this.onTap;
    return TvFocusHighlight(
      radius: radius,
      shape: shape,
      child: FocusableActionDetector(
        enabled: onTap != null,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => onTap?.call(),
          ),
        },
        child: child,
      ),
    );
  }
}

// у кнопок Flutter OK пульта только нажимает, и на каждом повторе клавиши заново (Flutter 3.44);
// долгое нажатие решается по отпусканию, иначе посреди удержания повторы нажали бы то, что встало на место кнопки
class TvLongPress extends StatefulWidget {
  const TvLongPress({
    super.key,
    required this.onPressed,
    required this.onLongPress,
    required this.child,
  });

  final VoidCallback onPressed;
  final VoidCallback onLongPress;
  final Widget child;

  @override
  State<TvLongPress> createState() => _TvLongPressState();
}

class _TvLongPressState extends State<TvLongPress> {
  static final _keys = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.gameButtonA,
  };

  Timer? _hold;
  bool? _long;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_keys.contains(event.logicalKey)) return KeyEventResult.ignored;
    switch (event) {
      case KeyDownEvent():
        _long = false;
        _hold?.cancel();
        _hold = Timer(kLongPressTimeout, () => _long = true);
      case KeyUpEvent():
        final long = _long;
        _hold?.cancel();
        _long = null;
        if (long == null) return KeyEventResult.ignored;
        long ? widget.onLongPress() : widget.onPressed();
      default:
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: _onKey,
    child: widget.child,
  );
}

class TvFocusHighlight extends StatefulWidget {
  const TvFocusHighlight({
    super.key,
    required this.child,
    this.radius,
    this.shape,
    this.own = false,
    this.suppressed = false,
  });

  final Widget child;

  final BorderRadiusGeometry? radius;

  // заливка по фигуре, а не по скруглённому прямоугольнику
  final ShapeBorder? shape;

  // свой фокус у вложенного поля или строки внутри составной карточки группы
  final bool own;

  final bool suppressed;

  static Color? containerOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TvFocusScope>()?.container;

  @override
  State<TvFocusHighlight> createState() => _TvFocusHighlightState();
}

class _TvFocusHighlightState extends State<TvFocusHighlight>
    with SingleTickerProviderStateMixin {
  // не late: ленивое поле создалось бы в dispose посреди размонтирования и упало ассертом
  AnimationController? _lift;
  bool _subtreeFocused = false;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    if (TvFocus.enabled) _lift = AnimationController.unbounded(vsync: this);
  }

  @override
  void didUpdateWidget(covariant TvFocusHighlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.suppressed != widget.suppressed ||
        oldWidget.own != widget.own) {
      _syncShown();
    }
  }

  @override
  void dispose() {
    if (_subtreeFocused) {
      FocusManager.instance.removeListener(_onPrimaryFocusChanged);
    }
    _lift?.dispose();
    super.dispose();
  }

  void _onFocusChange(bool focused) {
    if (focused == _subtreeFocused || _lift == null) return;
    if (focused) {
      FocusManager.instance.addListener(_onPrimaryFocusChanged);
    } else {
      FocusManager.instance.removeListener(_onPrimaryFocusChanged);
    }
    _subtreeFocused = focused;
    _syncShown();
  }

  void _onPrimaryFocusChanged() {
    if (mounted) _syncShown();
  }

  bool _delegatedToInnerOwn() {
    final primaryCtx = FocusManager.instance.primaryFocus?.context;
    if (primaryCtx == null || !mounted) return false;
    var delegated = false;
    (primaryCtx as Element).visitAncestorElements((el) {
      if (identical(el, context)) return false;
      if (el is StatefulElement && el.state is _TvFocusHighlightState) {
        final inner = el.state as _TvFocusHighlightState;
        if (inner.widget.own) {
          delegated = true;
          return false;
        }
      }
      return true;
    });
    return delegated;
  }

  void _syncShown() {
    final lift = _lift;
    if (lift == null) return;
    final want =
        _subtreeFocused && !widget.suppressed && !_delegatedToInnerOwn();
    if (want == _shown) return;
    setState(() => _shown = want);
    ExpressiveMotion.springTo(
      lift,
      want ? 1 : 0,
      spring: ExpressiveMotion.spatialFast,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lift = _lift;
    if (lift == null) return widget.child;
    // вложенная пара подняла и залила бы элемент дважды
    if (!widget.own &&
        context.findAncestorStateOfType<_TvFocusHighlightState>() != null) {
      return widget.child;
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final inverted = _shown ? TvFocus.invert(scheme) : null;

    // структура одна в обоих состояниях: перестройка дерева на фокусе увела бы сам фокус
    final content = _TvFocusScope(
      container: _shown ? scheme.inverseSurface : null,
      child: Theme(
        data: theme.copyWith(
          focusColor: Colors.transparent,
          colorScheme: inverted ?? scheme,
          inputDecorationTheme: inverted == null
              ? theme.inputDecorationTheme
              : TvFocus.invertInputDecoration(
                  theme.inputDecorationTheme,
                  inverted,
                ),
        ),
        child: DecoratedBox(
          decoration: widget.shape == null
              ? BoxDecoration(
                  color: _shown ? scheme.inverseSurface : null,
                  borderRadius: widget.radius,
                )
              : ShapeDecoration(
                  color: _shown ? scheme.inverseSurface : null,
                  shape: widget.shape!,
                ),
          child: widget.child,
        ),
      ),
    );

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: _onFocusChange,
      child: AnimatedBuilder(
        animation: lift,
        builder: (context, child) => Transform.scale(
          scale: 1 + (TvFocus.focusedScale - 1) * lift.value,
          child: child,
        ),
        child: content,
      ),
    );
  }
}

class _TvFocusScope extends InheritedWidget {
  const _TvFocusScope({required this.container, required super.child});

  final Color? container;

  @override
  bool updateShouldNotify(_TvFocusScope oldWidget) =>
      container != oldWidget.container;
}
