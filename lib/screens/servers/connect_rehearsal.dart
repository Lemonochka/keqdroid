part of '../servers_tab.dart';

// Skia на Windows не хранит шейдеры между запусками: первое подключение собирало их 8-12 штук,
// 80-117 мс посреди анимации. копия один раз проигрывает подключение под вкладками, остаётся 2
class ConnectRehearsal extends ConsumerStatefulWidget {
  const ConnectRehearsal({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<ConnectRehearsal> createState() => _ConnectRehearsalState();
}

class _RehearsalVpn extends VpnStateNotifier {
  _RehearsalVpn(this.script);

  final ValueListenable<VpnState> script;

  @override
  Future<VpnState> build() async {
    void follow() => state = AsyncData(script.value);
    script.addListener(follow);
    ref.onDispose(() => script.removeListener(follow));
    return script.value;
  }
}

class _ConnectRehearsalState extends ConsumerState<ConnectRehearsal> {
  static const _pointer = 0x7ffffff0;

  final _clock = PacedClock()..repeat();
  final _plaque = GlobalKey();
  final _button = GlobalKey();
  final _script = ValueNotifier(VpnState.disconnected);
  final _timers = <Timer>[];
  HitTestResult? _pressed;
  Offset _at = Offset.zero;

  @override
  void initState() {
    super.initState();
    void at(int ms, VoidCallback f) => _timers.add(
      Timer(Duration(milliseconds: ms), () {
        if (mounted) f();
      }),
    );
    VpnState up(int s) => VpnState(
      status: VpnStatus.connected,
      downloadSpeed: 180000 + s * 40000,
      uploadSpeed: 30000 + s * 9000,
      totalDownload: s * 2000000,
      totalUpload: s * 300000,
      duration: Duration(seconds: s),
    );
    at(300, () => _press(down: true));
    at(600, () => _press(down: false));
    at(900, () => _press(down: true));
    at(960, () {
      _press(down: false);
      _script.value = VpnState.connecting;
    });
    at(1300, () => _script.value = up(1));
    at(2300, () => _script.value = up(2));
    at(3300, () => _script.value = up(3));
    // второй круг: нажатие на подключённую кнопку и повторное подключение собирали свои
    at(3600, () => _press(down: true));
    at(3660, () {
      _press(down: false);
      _script.value = const VpnState(status: VpnStatus.disconnecting);
    });
    at(4100, () => _script.value = VpnState.disconnected);
    at(5100, () => _press(down: true));
    at(5160, () {
      _press(down: false);
      _script.value = VpnState.connecting;
    });
    at(6200, () => _script.value = up(1));
    at(
      7200,
      () => _script.value = const VpnState(status: VpnStatus.disconnecting),
    );
    at(7600, () => _script.value = VpnState.disconnected);
    at(8600, widget.onDone);
  }

  // нажатие идёт по пути попадания в копию, мимо MouseTracker: он после каждого кадра заново ищет,
  // что под мышью, во всём окне, и мышь копии наводилась бы на настоящую кнопку
  void _press({required bool down}) {
    if (!down) {
      final hit = _pressed;
      _pressed = null;
      if (hit != null) {
        _send(
          hit,
          PointerUpEvent(
            pointer: _pointer,
            kind: PointerDeviceKind.mouse,
            position: _at,
          ),
        );
      }
      return;
    }
    RenderBox? button;
    void find(Element e) {
      if (button != null) return;
      if (e.widget is _ConnectButton) {
        button = e.renderObject as RenderBox?;
        return;
      }
      e.visitChildren(find);
    }

    context.visitChildElements(find);
    final b = button;
    if (b == null || !b.hasSize) return;
    final hit = BoxHitTestResult();
    _at = b.localToGlobal(b.size.center(Offset.zero));
    final found = hit.addWithPaintTransform(
      transform: b.getTransformTo(null),
      position: _at,
      hitTest: (result, local) => b.hitTest(result, position: local),
    );
    if (!found) return;
    hit.add(HitTestEntry(GestureBinding.instance));
    _pressed = hit;
    _send(
      hit,
      PointerDownEvent(
        pointer: _pointer,
        kind: PointerDeviceKind.mouse,
        position: _at,
        buttons: kPrimaryMouseButton,
      ),
    );
  }

  // как GestureBinding.dispatchEvent, только без MouseTracker
  void _send(HitTestResult hit, PointerEvent event) {
    for (final entry in hit.path) {
      entry.target.handleEvent(event.transformed(entry.transform), entry);
    }
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _clock.dispose();
    _script.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(serversProvider.select((s) => s.activeServer));
    final modern = ref.watch(
      settingsNotifierProvider.select(
        (a) => a.value?.modernConnectPanel ?? false,
      ),
    );
    final wantedColumns = ref.watch(
      settingsNotifierProvider.select(
        (a) => a.value == null ? 1 : ServerRow.wantedColumns(a.value!),
      ),
    );
    return ProviderScope(
      overrides: [vpnStateProvider.overrideWith(() => _RehearsalVpn(_script))],
      child: Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // раскладка как у вкладки: шейдер зависит и от того, где фигура лежит под обрезкой
            final width = min(
              constraints.maxWidth,
              DesktopBreakpoints.serversContentMaxWidth,
            );
            final inner = width - 2 * _listSideInset;
            final layout = _ServerListLayout.resolve(
              wantedColumns: wantedColumns,
              width: inner,
              textScaler: MediaQuery.textScalerOf(context),
            );
            final rowExtent = layout.isCards
                ? ServerRow.cardHeight(context)
                : ServerRow.height;
            final direction = Directionality.of(context);
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: width,
                child: Column(
                  children: [
                    _ConnectHeader(
                      waveCtrl: _clock,
                      onToggle: (_) {},
                      onJumpToActive: () {},
                      plaqueKey: _plaque,
                      buttonKey: _button,
                    ),
                    Expanded(
                      child: _ListEdgeFade(
                        underPanel: modern,
                        child: server == null
                            ? const SizedBox.expand()
                            : Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  _listSideInset,
                                  _listTopPadding + 96,
                                  _listSideInset,
                                  0,
                                ),
                                child: Align(
                                  alignment: Alignment.topLeft,
                                  child: SizedBox(
                                    width: inner / layout.columns,
                                    height: rowExtent,
                                    child: _ServerTile(
                                      server: server,
                                      isActive: true,
                                      layout: layout.rowLayout,
                                      height: rowExtent,
                                      radius:
                                          ExpressiveListSegment.segmentRadius(
                                            index: 0,
                                            count: 2,
                                            columns: layout.columns,
                                            endCorner:
                                                ExpressiveShape.extraLarge -
                                                ExpressiveListSegment.gap,
                                          ).resolve(direction),
                                      margin:
                                          ExpressiveListSegment.segmentMargin(
                                            index: 0,
                                            columns: layout.columns,
                                            spacing: layout.gap,
                                          ).resolve(direction),
                                      onTap: () {},
                                      onDelete: () {},
                                      onPing: () async {},
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
