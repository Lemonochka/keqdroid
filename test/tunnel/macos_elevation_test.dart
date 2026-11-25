import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/tunnel/macos_elevation.dart';
import 'package:keqdroid/tunnel/macos_tunnel_backend.dart';

void main() {
  group('shell and AppleScript quoting', () {
    test(
      'quotes paths with spaces, quotes, dollars and backslashes safely',
      () {
        const tricky = r'''/Users/my user/it's "$HOME"\bin''';
        final quoted = posixShellQuote(tricky);
        expect(quoted, "'/Users/my user/it'\\''s \"\$HOME\"\\bin'");

        final cmd = appleScriptAdminCommand(['/bin/sh', tricky]);
        expect(cmd, startsWith('do shell script "'));
        expect(cmd, endsWith('" with administrator privileges'));
        expect(cmd, contains(r'\"$HOME\"\\bin'));
      },
    );
  });

  group('planMacosElevation', () {
    const coreArgs = ['bin', 'cfg', 'geo', 'sent', '1234', 'xray', '501'];

    test('runs directly with sh when already root', () {
      final launch = planMacosElevation(
        coreArgs: coreArgs,
        wrapperScriptPath: '/tmp/wrap.sh',
        asRoot: true,
      );
      expect(launch.executable, '/bin/sh');
      expect(launch.args.first, '/tmp/wrap.sh');
      expect(launch.viaOsascript, isFalse);
    });

    test('always asks an administrator instead of using a sudoers helper', () {
      final launch = planMacosElevation(
        coreArgs: coreArgs,
        wrapperScriptPath: '/tmp/wrap.sh',
        asRoot: false,
      );
      expect(launch.executable, '/usr/bin/osascript');
      expect(launch.args.first, '-e');
      expect(launch.args[1], contains('with administrator privileges'));
      expect(launch.args.join(), isNot(contains('sudo')));
      expect(launch.viaOsascript, isTrue);
    });
  });

  group('root wrapper', () {
    final body = MacosTunnelBackend.tunWrapperBodyForTest;

    test('does not install or invoke a passwordless root helper', () {
      expect(body, isNot(contains('NOPASSWD')));
      expect(body, isNot(contains('sudoers')));
      expect(body, isNot(contains('/usr/local/libexec')));
    });

    test('reads caller paths as the user and protects config and log', () {
      expect(body, contains(r'RUN=/var/run/keqdroid/$OWNER'));
      expect(body, contains(r'chown "$OWNER" "$LOGF" && chmod 0600 "$LOGF"'));
      expect(body, contains(r'as_owner /bin/cat -- "$CFG" >"$CONF"'));
      expect(body, contains(r'chmod 0600 "$CONF"'));
      expect(body, contains(r'/usr/bin/sudo -u "#$OWNER"'));
    });
  });
}
