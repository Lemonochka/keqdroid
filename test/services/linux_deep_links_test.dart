import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/platform/vpn_native_bridge.dart';
import 'package:keqdroid/services/linux_background_service.dart';
import 'package:keqdroid/services/linux_deep_links.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const windowChannel = MethodChannel('window_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final originalCommandLine = LinuxDeepLinks.commandLine;

  late List<String> windowCalls;

  setUp(() {
    LinuxDeepLinks.reset();
    windowCalls = [];
    messenger.setMockMethodCallHandler(windowChannel, (call) async {
      windowCalls.add(call.method);
      return true;
    });
  });

  tearDown(() {
    LinuxDeepLinks.reset();
    LinuxDeepLinks.commandLine = originalCommandLine;
    messenger.setMockMethodCallHandler(windowChannel, null);
  });

  group('fromCommandLine', () {
    test('takes the link the desktop entry passed as %u', () {
      expect(
        LinuxDeepLinks.fromCommandLine([
          '/opt/keqdroid/keqdroid',
          'keqdroid://install-config?url=https%3A%2F%2Fsub.example%2Fx',
          '',
        ]),
        'keqdroid://install-config?url=https%3A%2F%2Fsub.example%2Fx',
      );
    });

    test('knows the old keqdis scheme and ignores case', () {
      expect(
        LinuxDeepLinks.fromCommandLine(['k', 'KEQDIS://add?url=https://a.b']),
        'KEQDIS://add?url=https://a.b',
      );
    });

    test('ignores the binary itself, flags and foreign links', () {
      expect(
        LinuxDeepLinks.fromCommandLine([
          'keqdroid://looks-like-a-link-but-is-argv0',
          '--autostart',
          'https://example.com',
          'vless://uuid@host:443',
          '',
        ]),
        isNull,
      );
    });
  });

  test('a launch link waits for the servers tab and is taken once', () {
    LinuxDeepLinks.commandLine = () => [
      '/usr/bin/keqdroid',
      'keqdroid://add?url=https://s.example/1',
    ];
    LinuxDeepLinks.captureLaunchLink();
    expect(
      LinuxDeepLinks.takePending(),
      'keqdroid://add?url=https://s.example/1',
    );
    expect(LinuxDeepLinks.takePending(), isNull);
  });

  group('second launch', () {
    test('passes its link to the running app, or just asks to show it', () {
      expect(LinuxBackgroundService.peerMessage(null), 'show');
      expect(
        LinuxBackgroundService.peerMessage('keqdroid://add?url=https://s/1'),
        'link keqdroid://add?url=https://s/1',
      );
    });

    test('the running app shows its window and keeps the link', () async {
      final service = LinuxBackgroundService.forTesting();
      var notified = 0;
      LinuxDeepLinks.onArrived = () => notified++;

      service.handlePeerMessage('link keqdroid://add?url=https://s.example/3');
      await Future<void>.delayed(Duration.zero);

      expect(windowCalls, containsAllInOrder(['show', 'focus']));
      expect(notified, 1);
      expect(
        LinuxDeepLinks.takePending(),
        'keqdroid://add?url=https://s.example/3',
      );
    });

    test('the servers tab is told through the bridge', () async {
      final service = LinuxBackgroundService.forTesting();
      final arrived = <String>[];
      VpnNativeBridge.registerLaunchHandler((call) async {
        arrived.add(call.method);
      });
      addTearDown(() => VpnNativeBridge.registerLaunchHandler(null));

      service.handlePeerMessage('link keqdroid://add?url=https://s.example/2');
      await Future<void>.delayed(Duration.zero);

      expect(windowCalls, containsAllInOrder(['show', 'focus']));
      expect(arrived, ['onDeepLink']);
      expect(
        await VpnNativeBridge.getPendingDeepLink(),
        'keqdroid://add?url=https://s.example/2',
      );
    }, testOn: 'linux');

    test('an old "show" or junk only brings the window back', () async {
      final service = LinuxBackgroundService.forTesting();
      service.handlePeerMessage('show');
      service.handlePeerMessage('link https://evil.example');
      await Future<void>.delayed(Duration.zero);
      expect(windowCalls.where((c) => c == 'show'), hasLength(2));
      expect(LinuxDeepLinks.takePending(), isNull);
    });
  });
}
