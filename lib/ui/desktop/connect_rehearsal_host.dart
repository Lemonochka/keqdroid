import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../screens/servers_tab.dart';
import '../../shared/ui/app_theme.dart';
import '../../tunnel/tunnel_state.dart';

// под вкладками, а не над приложением: шейдеры копии совпадали с настоящими только здесь
class ConnectRehearsalHost extends ConsumerStatefulWidget {
  const ConnectRehearsalHost({
    super.key,
    required this.enabled,
    required this.child,
    this.startAfter = const Duration(seconds: 4),
  });

  final bool enabled;
  final Duration startAfter;
  final Widget child;

  @override
  ConsumerState<ConnectRehearsalHost> createState() =>
      _ConnectRehearsalHostState();
}

class _ConnectRehearsalHostState extends ConsumerState<ConnectRehearsalHost> {
  // пока рукой водят по окну, сборка шейдеров попала бы ей под руку
  static const _idle = Duration(milliseconds: 1500);

  Timer? _timer;
  Timer? _input;
  OverlayEntry? _entry;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    _listening = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    _timer = Timer(widget.startAfter, _tryStart);
  }

  void _onPointer(PointerEvent event) {
    if (event.pointer == ConnectRehearsal.pointerId) return;
    if (_entry != null &&
        (event is PointerDownEvent || event is PointerScrollEvent)) {
      _stop();
      return;
    }
    _input?.cancel();
    _input = Timer(_idle, () => _input = null);
  }

  void _unlisten() {
    if (!_listening) return;
    _listening = false;
    _input?.cancel();
    _input = null;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
  }

  void _tryStart() {
    _timer = null;
    if (!mounted) return;
    final status =
        ref.read(vpnStateProvider).value?.status ?? VpnStatus.disconnected;
    if (status != VpnStatus.disconnected) {
      _unlisten();
      return;
    }
    if (_input != null ||
        !ref.read(appLifecycleVisibleProvider) ||
        !ref.read(desktopWindowVisibleProvider)) {
      _timer = Timer(const Duration(seconds: 1), _tryStart);
      return;
    }
    ref.read(connectRehearsalProvider.notifier).set(true);
    setState(
      () => _entry = OverlayEntry(
        builder: (_) => ConnectRehearsal(onDone: _stop),
      ),
    );
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _unlisten();
    if (!mounted || _entry == null) return;
    ref.read(connectRehearsalProvider.notifier).set(false);
    setState(() => _entry = null);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _unlisten();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.enabled) {
      ref.listen(vpnStateProvider.select((a) => a.value?.status), (_, next) {
        if (next != null && next != VpnStatus.disconnected) _stop();
      });
    }
    final entry = _entry;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (entry != null) ...[
          IgnorePointer(
            child: ExcludeSemantics(
              child: ExcludeFocus(
                child: Overlay(key: ObjectKey(entry), initialEntries: [entry]),
              ),
            ),
          ),
          // при смене вкладок обе полупрозрачны, и копия мелькнула бы сквозь них
          ColoredBox(color: AppTheme.bg(context)),
        ],
        KeyedSubtree(key: const ValueKey('content'), child: widget.child),
      ],
    );
  }
}
