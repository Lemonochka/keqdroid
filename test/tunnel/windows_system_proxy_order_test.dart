import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/tunnel/connection_mode.dart';
import 'package:keqdroid/tunnel/desktop_core_session.dart';
import 'package:keqdroid/tunnel/tunnel_session_request.dart';
import 'package:keqdroid/tunnel/windows_tunnel_backend.dart';

// видео 22.11: TUN выбрали, пока Proxy подключался. Раннер включает прокси в своём потоке,
// и выключение от стопа писало в реестр посреди включения
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('keqdroid_vpn_channel');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('стоп посреди включения прокси выключает его после включения', () async {
    final port = await freeLoopbackPort();
    final calls = <String>[];
    final entered = Completer<void>();
    final release = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'setSystemProxy') return null;
      if ((call.arguments as Map)['enabled'] != true) {
        calls.add('disable');
        return null;
      }
      calls.add('enable');
      entered.complete();
      await release.future;
      calls.add('enabled');
      return {'registryEnabled': true, 'registryServer': '127.0.0.1:$port'};
    });

    final backend = WindowsTunnelBackend();
    final applying = backend
        .debugApplySystemProxy(
          TunnelSessionRequest(
            mode: ConnectionMode.proxy,
            xrayConfig: '{}',
            httpPort: port,
          ),
        )
        .catchError((Object _) {});
    await entered.future;
    final stopping = backend.stopSession();
    await pumpEventQueue();
    expect(calls, ['enable'], reason: 'раннер ещё пишет включение');

    release.complete();
    await applying;
    await stopping;
    expect(calls, ['enable', 'enabled', 'disable']);
  });
}
