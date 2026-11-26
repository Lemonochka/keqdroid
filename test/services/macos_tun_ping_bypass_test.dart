import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/ping_service.dart';

void main() {
  test('извлекает физический интерфейс из route -n get default на macOS', () {
    const wifiRoute = '''
   route to: default
destination: default
       mask: default
    gateway: 192.168.1.1
  interface: en0
      flags: <UP,GATEWAY,DONE,STATIC,PRCLONING,GLOBAL>
 recvpipe  sendpipe  ssthresh  rtt,msec    rttvar  hopcount      mtu     expire
       0         0         0         0         0         0      1500         0
''';
    expect(PingService.parseDarwinDefaultRouteInterface(wifiRoute), 'en0');
  });

  test('отбрасывает utun и петлю, чтобы пинг не ушёл обратно в туннель', () {
    expect(
      PingService.parseDarwinDefaultRouteInterface('  interface: utun99\n'),
      isNull,
    );
    expect(
      PingService.parseDarwinDefaultRouteInterface('  interface: utun4\n'),
      isNull,
    );
    expect(
      PingService.parseDarwinDefaultRouteInterface('  interface: lo0\n'),
      isNull,
    );
    expect(
      PingService.parseDarwinDefaultRouteInterface('route: writing to routing socket: not in table\n'),
      isNull,
    );
  });
}
