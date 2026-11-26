import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/tunnel/macos_system_proxy.dart';

class _ServiceProxy {
  bool webEnabled = false;
  String webServer = '';
  int webPort = 0;

  bool secureEnabled = false;
  String secureServer = '';
  int securePort = 0;

  bool socksEnabled = false;
  String socksServer = '';
  int socksPort = 0;

  List<String> bypass = ['169.254/16', '*.local'];
}

class _FakeNetworkSetup {
  _FakeNetworkSetup({Map<String, _ServiceProxy>? services})
    : services = services ?? {'Wi-Fi': _ServiceProxy(), 'Ethernet': _ServiceProxy()};

  final Map<String, _ServiceProxy> services;
  final List<String> disabledServices = const ['Thunderbolt Bridge'];
  final calls = <String>[];

  Future<ProcessResult?> run(String exe, List<String> args) async {
    calls.add('$exe ${args.join(' ')}');
    ProcessResult ok([String out = '']) => ProcessResult(0, 0, out, '');
    if (args.isEmpty) return ProcessResult(0, 1, '', 'missing args');
    final flag = args[0];
    if (flag == '-listallnetworkservices') {
      final lines = [
        'An asterisk (*) denotes that a network service is disabled.',
        ...services.keys,
        for (final d in disabledServices) '*$d',
      ];
      return ok('${lines.join('\n')}\n');
    }

    final svc = services[args[1]];
    if (svc == null) return ProcessResult(0, 4, '', 'unknown service');

    String format(bool enabled, String server, int port) =>
        'Enabled: ${enabled ? 'Yes' : 'No'}\n'
        'Server: $server\n'
        'Port: $port\n'
        'Authenticated Proxy Enabled: 0\n';

    switch (flag) {
      case '-getwebproxy':
        return ok(format(svc.webEnabled, svc.webServer, svc.webPort));
      case '-getsecurewebproxy':
        return ok(format(svc.secureEnabled, svc.secureServer, svc.securePort));
      case '-getsocksfirewallproxy':
        return ok(format(svc.socksEnabled, svc.socksServer, svc.socksPort));
      case '-getproxybypassdomains':
        return ok(
          svc.bypass.isEmpty
              ? "There aren't any Bypass Domains set on ${args[1]}.\n"
              : '${svc.bypass.join('\n')}\n',
        );
      case '-setwebproxy':
        svc.webEnabled = true;
        svc.webServer = args[2];
        svc.webPort = int.parse(args[3]);
        return ok();
      case '-setwebproxystate':
        svc.webEnabled = args[2] == 'on';
        return ok();
      case '-setsecurewebproxy':
        svc.secureEnabled = true;
        svc.secureServer = args[2];
        svc.securePort = int.parse(args[3]);
        return ok();
      case '-setsecurewebproxystate':
        svc.secureEnabled = args[2] == 'on';
        return ok();
      case '-setsocksfirewallproxy':
        svc.socksEnabled = true;
        svc.socksServer = args[2];
        svc.socksPort = int.parse(args[3]);
        return ok();
      case '-setsocksfirewallproxystate':
        svc.socksEnabled = args[2] == 'on';
        return ok();
      case '-setproxybypassdomains':
        final domains = args.sublist(2);
        svc.bypass = domains.length == 1 && domains.first == 'Empty'
            ? <String>[]
            : List<String>.from(domains);
        return ok();
    }
    return ProcessResult(0, 1, '', 'unsupported $flag');
  }
}

void main() {
  late Directory tmp;
  late File backup;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('keq_macos_proxy_');
    backup = File('${tmp.path}/system_proxy_backup.json');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  MacosSystemProxy proxyFor(_FakeNetworkSetup fake) =>
      MacosSystemProxy(run: fake.run, backupFile: backup);

  test('lists only enabled network services', () async {
    final fake = _FakeNetworkSetup();
    expect(await proxyFor(fake).listActiveServices(), ['Wi-Fi', 'Ethernet']);
  });

  test('points active services at local HTTP and SOCKS ports', () async {
    final fake = _FakeNetworkSetup();
    expect(await proxyFor(fake).enable(httpPort: 2081, socksPort: 2080), isTrue);

    for (final svc in fake.services.values) {
      expect(svc.webEnabled, isTrue);
      expect(svc.webServer, '127.0.0.1');
      expect(svc.webPort, 2081);
      expect(svc.secureEnabled, isTrue);
      expect(svc.securePort, 2081);
      expect(svc.socksEnabled, isTrue);
      expect(svc.socksPort, 2080);
      expect(svc.bypass, MacosSystemProxy.bypassDomains);
    }
  });

  test('restores previous user proxy and bypass domains on disable', () async {
    final wifi = _ServiceProxy()
      ..webEnabled = true
      ..webServer = 'proxy.corp.local'
      ..webPort = 3128
      ..bypass = ['corp.local'];
    final eth = _ServiceProxy()..bypass = [];
    final fake = _FakeNetworkSetup(services: {'Wi-Fi': wifi, 'Ethernet': eth});

    final proxy = proxyFor(fake);
    await proxy.enable(httpPort: 2081, socksPort: 2080);
    await proxy.disable();

    expect(wifi.webEnabled, isTrue);
    expect(wifi.webServer, 'proxy.corp.local');
    expect(wifi.webPort, 3128);
    expect(wifi.secureEnabled, isFalse);
    expect(wifi.socksEnabled, isFalse);
    expect(wifi.bypass, ['corp.local']);

    expect(eth.webEnabled, isFalse);
    expect(eth.bypass, isEmpty);
    expect(backup.existsSync(), isFalse);
  });

  test('preserves original snapshot across crash and second connect', () async {
    final wifi = _ServiceProxy()
      ..webEnabled = true
      ..webServer = 'orig.proxy'
      ..webPort = 8080;
    final fake = _FakeNetworkSetup(services: {'Wi-Fi': wifi});

    await proxyFor(fake).enable(httpPort: 2081, socksPort: 2080);
    await proxyFor(fake).enable(httpPort: 3081, socksPort: 3080);
    await proxyFor(fake).disable();

    expect(wifi.webEnabled, isTrue);
    expect(wifi.webServer, 'orig.proxy');
    expect(wifi.webPort, 8080);
  });

  test('does not clobber a proxy the user manually changed while connected', () async {
    final wifi = _ServiceProxy();
    final fake = _FakeNetworkSetup(services: {'Wi-Fi': wifi});

    final proxy = proxyFor(fake);
    await proxy.enable(httpPort: 2081, socksPort: 2080);

    wifi
      ..webServer = 'manual.corp'
      ..webPort = 9000
      ..secureEnabled = false
      ..socksEnabled = false;

    await proxy.disable();

    expect(wifi.webEnabled, isTrue);
    expect(wifi.webServer, 'manual.corp');
    expect(wifi.webPort, 9000);
  });

  test('clears unbacked leftover matching our loopback proxy and bypass list', () async {
    final wifi = _ServiceProxy()
      ..webEnabled = true
      ..webServer = '127.0.0.1'
      ..webPort = 2081
      ..bypass = List<String>.from(MacosSystemProxy.bypassDomains);
    final fake = _FakeNetworkSetup(services: {'Wi-Fi': wifi});

    await proxyFor(fake).disable();

    expect(wifi.webEnabled, isFalse);
    expect(wifi.secureEnabled, isFalse);
    expect(wifi.socksEnabled, isFalse);
    expect(wifi.bypass, isEmpty);
  });

  test('merges newly appeared network services into an existing backup after crash', () async {
    final wifi = _ServiceProxy()
      ..webEnabled = true
      ..webServer = 'orig.proxy'
      ..webPort = 8080;
    final fake = _FakeNetworkSetup(services: {'Wi-Fi': wifi});

    await proxyFor(fake).enable(httpPort: 2081, socksPort: 2080);

    // A new interface appears before reconnect after a crash.
    final usbLan = _ServiceProxy();
    fake.services['USB LAN'] = usbLan;

    await proxyFor(fake).enable(httpPort: 3081, socksPort: 3080);
    expect(usbLan.webEnabled, isTrue);
    expect(usbLan.webPort, 3081);

    await proxyFor(fake).disable();

    expect(wifi.webEnabled, isTrue);
    expect(wifi.webServer, 'orig.proxy');
    expect(wifi.webPort, 8080);
    expect(usbLan.webEnabled, isFalse);
    expect(usbLan.secureEnabled, isFalse);
    expect(usbLan.socksEnabled, isFalse);
  });

  test('does not clobber another local proxy on 127.0.0.1 with different ports', () async {
    final wifi = _ServiceProxy();
    final fake = _FakeNetworkSetup(services: {'Wi-Fi': wifi});

    final proxy = proxyFor(fake);
    await proxy.enable(httpPort: 2081, socksPort: 2080);

    // User switches to Charles/Proxyman on 127.0.0.1:8888 while connected.
    wifi
      ..webEnabled = true
      ..webServer = '127.0.0.1'
      ..webPort = 8888
      ..secureEnabled = true
      ..secureServer = '127.0.0.1'
      ..securePort = 8888
      ..socksEnabled = false;

    await proxy.disable();

    expect(wifi.webEnabled, isTrue);
    expect(wifi.webServer, '127.0.0.1');
    expect(wifi.webPort, 8888);
    expect(wifi.secureEnabled, isTrue);
    expect(wifi.securePort, 8888);
  });

  test('restores legacy backup JSON without applied port metadata', () async {
    final wifi = _ServiceProxy()
      ..webEnabled = true
      ..webServer = '127.0.0.1'
      ..webPort = 2081;
    final fake = _FakeNetworkSetup(services: {'Wi-Fi': wifi});

    backup.writeAsStringSync(
      jsonEncode({
        'Wi-Fi': {
          'web': {'enabled': false, 'server': '', 'port': 0},
          'secure': {'enabled': false, 'server': '', 'port': 0},
          'socks': {'enabled': false, 'server': '', 'port': 0},
          'bypass': <String>[],
        },
      }),
    );

    await proxyFor(fake).disable();
    expect(wifi.webEnabled, isFalse);
  });
}
