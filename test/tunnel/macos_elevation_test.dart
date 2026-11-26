import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/tunnel/macos_elevation.dart';

void main() {
  group('shell and AppleScript quoting', () {
    test(
      'quotes paths with spaces, quotes, dollars and backslashes safely',
      () {
        const tricky = r'''/Users/my user/it's "$HOME"\bin''';
        final quoted = posixShellQuote(tricky);
        expect(quoted, "'/Users/my user/it'\\''s \"\$HOME\"\\bin'");

        final cmd = appleScriptAdminCommand([tricky, 'install', '501']);
        expect(cmd, startsWith('do shell script "'));
        expect(cmd, endsWith('" with administrator privileges'));
        expect(cmd, contains(r'\"$HOME\"\\bin'));
      },
    );
  });

  group('planMacosAdminCommand', () {
    const argv = ['/App/Contents/Resources/bin/keqdroid-tun', 'install', '501'];

    test('runs binary directly when already root', () {
      final plan = planMacosAdminCommand(argv, asRoot: true);
      expect(plan.executable, argv.first);
      expect(plan.args, ['install', '501']);
      expect(plan.viaOsascript, isFalse);
    });

    test('prompts via osascript when not root', () {
      final plan = planMacosAdminCommand(argv, asRoot: false);
      expect(plan.executable, '/usr/bin/osascript');
      expect(plan.args.first, '-e');
      expect(plan.args[1], contains('with administrator privileges'));
      expect(plan.viaOsascript, isTrue);
    });

    test('recognizes AppleScript user cancel (-128)', () {
      expect(
        macosAdminCancelled('execution error: User canceled. (-128)'),
        isTrue,
      );
      expect(macosAdminCancelled('keqdroid-tun: launchctl failed'), isFalse);
    });
  });
}
