import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/hotkey_config.dart';
import 'package:keqdroid/services/hotkey_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late String backend;
  late List<List<Object?>> sent;
  late List<String> nativeFails;

  setUp(() {
    HotkeyService.resetForTesting();
    backend = 'x11';
    sent = [];
    nativeFails = [];
    messenger.setMockMethodCallHandler(HotkeyService.linuxChannel, (
      call,
    ) async {
      switch (call.method) {
        case 'getBackend':
          return backend;
        case 'setGlobalHotkeys':
          sent.add(call.arguments as List<Object?>);
          return nativeFails;
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(HotkeyService.linuxChannel, null);
    HotkeyService.resetForTesting();
  });

  const ctrlAltK = HotkeyBinding(ctrl: true, alt: true, key: 'keyK');

  group('key tables', () {
    test('every key the settings can record has a Linux code and a keysym', () {
      for (final token in HotkeyKeys.allTokens) {
        expect(HotkeyKeys.evdevFor(token), isNotNull, reason: token);
        expect(HotkeyKeys.keysymFor(token), isNotNull, reason: token);
      }
    });

    test('codes are the physical keys from input-event-codes.h', () {
      expect(HotkeyKeys.evdevFor('keyA'), 30);
      expect(HotkeyKeys.evdevFor('keyK'), 37);
      expect(HotkeyKeys.evdevFor('digit0'), 11);
      expect(HotkeyKeys.evdevFor('f11'), 87);
      expect(HotkeyKeys.evdevFor('arrowDown'), 108);
    });

    test('the portal trigger follows the shortcuts spec', () {
      expect(ctrlAltK.portalTrigger, 'CTRL+ALT+k');
      expect(
        const HotkeyBinding(
          shift: true,
          meta: true,
          key: 'pageUp',
        ).portalTrigger,
        'SHIFT+LOGO+Page_Up',
      );
      expect(const HotkeyBinding(key: 'f9').portalTrigger, 'F9');
      expect(
        const HotkeyBinding(ctrl: true, key: 'digit5').portalTrigger,
        'CTRL+5',
      );
    });

    test(
      'the portal id changes with the combination, not between launches',
      () {
        final id = ctrlAltK.portalId(HotkeyAction.toggleConnection);
        expect(id, 'toggleConnection_ctrl_alt_keyK');
        expect(ctrlAltK.portalId(HotkeyAction.toggleConnection), id);
        expect(
          const HotkeyBinding(
            ctrl: true,
            alt: true,
            key: 'keyL',
          ).portalId(HotkeyAction.toggleConnection),
          isNot(id),
        );
      },
    );
  });

  group('X11', () {
    test(
      'sends the physical key and modifiers, takes the key out of the window',
      () async {
        final failed = await HotkeyService.applyLinuxForTesting(
          {HotkeyAction.toggleConnection: ctrlAltK},
          descriptions: {HotkeyAction.toggleConnection: 'Connect'},
        );
        expect(failed, isEmpty);
        expect(HotkeyService.isGlobal, isTrue);
        expect(HotkeyService.systemConfirmsBindings, isFalse);
        expect(sent.single, [
          {
            'action': 'toggleConnection',
            'evdevCode': 37,
            'modifiers': 3,
            'portalId': 'toggleConnection_ctrl_alt_keyK',
            'trigger': 'CTRL+ALT+k',
            'description': 'Connect',
          },
        ]);
      },
    );

    test('a combination another client holds is reported as taken', () async {
      nativeFails = ['toggleConnection'];
      final failed = await HotkeyService.applyLinuxForTesting({
        HotkeyAction.toggleConnection: ctrlAltK,
      });
      expect(failed, ['toggleConnection']);
    });

    test('the same set twice reaches the runner once', () async {
      final bindings = {HotkeyAction.toggleWindow: ctrlAltK};
      await HotkeyService.applyLinuxForTesting(bindings);
      await HotkeyService.applyLinuxForTesting(bindings);
      expect(sent, hasLength(1));
    });

    test('a press from the runner reaches the action', () async {
      await HotkeyService.applyLinuxForTesting({
        HotkeyAction.toggleWindow: ctrlAltK,
      });
      final pressed = <HotkeyAction>[];
      HotkeyService.onPressed = pressed.add;
      await messenger.handlePlatformMessage(
        HotkeyService.linuxChannel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onHotkeyPressed', {'action': 'toggleWindow'}),
        ),
        (_) {},
      );
      expect(pressed, [HotkeyAction.toggleWindow]);

      HotkeyService.captureMode = true;
      HotkeyService.dispatchAction('toggleWindow');
      expect(pressed, hasLength(1), reason: 'recording a new combination');
    });
  });

  group('Wayland portal', () {
    setUp(() => backend = 'portal');

    test('a declined dialog is not called "taken by another app"', () async {
      nativeFails = ['toggleConnection'];
      final failed = await HotkeyService.applyLinuxForTesting({
        HotkeyAction.toggleConnection: ctrlAltK,
      });
      expect(failed, isEmpty);
      expect(HotkeyService.systemConfirmsBindings, isTrue);
    });

    test(
      'recording a combination keeps the session, so no new dialog',
      () async {
        await HotkeyService.applyLinuxForTesting({
          HotkeyAction.toggleConnection: ctrlAltK,
        });
        HotkeyService.captureMode = true;
        await HotkeyService.applyLinuxForTesting(const {});
        HotkeyService.captureMode = false;
        await HotkeyService.applyLinuxForTesting({
          HotkeyAction.toggleConnection: ctrlAltK,
        });
        expect(sent, hasLength(1));
      },
    );
  });

  test('without a backend hotkeys stay inside the window', () async {
    backend = 'none';
    final failed = await HotkeyService.applyLinuxForTesting({
      HotkeyAction.toggleConnection: ctrlAltK,
    });
    expect(failed, isEmpty);
    expect(sent, isEmpty);
    expect(HotkeyService.isGlobal, isFalse);
  }, testOn: 'linux');
}
