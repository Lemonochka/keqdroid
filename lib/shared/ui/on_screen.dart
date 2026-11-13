import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

// на Android общий TickerMode свёрнутое приложение не гасит, только вкладки
bool onScreen(ValueListenable<TickerModeData>? ticking) {
  final app = WidgetsBinding.instance.lifecycleState;
  return (ticking?.value.enabled ?? true) &&
      app != AppLifecycleState.hidden &&
      app != AppLifecycleState.paused &&
      app != AppLifecycleState.detached;
}
