import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/tunnel/macos_elevation.dart';
import 'package:keqdroid/tunnel/macos_tunnel_backend.dart';

void main() {
  group('shell and AppleScript quoting', () {
    test('quotes paths with spaces, quotes, dollars and backslashes safely', () {
      const tricky = r'''/Users/my user/it's "$HOME"\bin''';
      final quoted = posixShellQuote(tricky);
      expect(quoted, "'/Users/my user/it'\\''s \"\$HOME\"\\bin'");

      final cmd = appleScriptAdminCommand(['/bin/sh', tricky]);
      expect(cmd, startsWith('do shell script "'));
      expect(cmd, endsWith('" with administrator privileges'));
      expect(cmd, contains(r'\"$HOME\"\\bin'));
    });
  });

  group('planMacosElevation', () {
    const coreArgs = ['bin', 'cfg', 'geo', 'sent', '1234', 'xray', '501'];

    test('runs directly with sh when already root', () {
      final launch = planMacosElevation(
        coreArgs: coreArgs,
        wrapperScriptPath: '/tmp/wrap.sh',
        helperPath: MacosTunnelBackend.helperPathForTest,
        asRoot: true,
        passwordless: false,
      );
      expect(launch.executable, '/bin/sh');
      expect(launch.args.first, '/tmp/wrap.sh');
      expect(launch.viaOsascript, isFalse);
      expect(launch.viaSudo, isFalse);
    });

    test('uses sudo -n when passwordless helper is installed', () {
      final launch = planMacosElevation(
        coreArgs: coreArgs,
        wrapperScriptPath: '/tmp/wrap.sh',
        helperPath: MacosTunnelBackend.helperPathForTest,
        asRoot: false,
        passwordless: true,
      );
      expect(launch.executable, '/usr/bin/sudo');
      expect(launch.args.take(2), ['-n', MacosTunnelBackend.helperPathForTest]);
      expect(launch.viaSudo, isTrue);
      expect(launch.viaOsascript, isFalse);
    });

    test('uses osascript administrator privileges prompt by default', () {
      final launch = planMacosElevation(
        coreArgs: coreArgs,
        wrapperScriptPath: '/tmp/wrap.sh',
        helperPath: MacosTunnelBackend.helperPathForTest,
        asRoot: false,
        passwordless: false,
      );
      expect(launch.executable, '/usr/bin/osascript');
      expect(launch.args.first, '-e');
      expect(launch.args[1], contains('with administrator privileges'));
      expect(launch.viaOsascript, isTrue);
      expect(launch.viaSudo, isFalse);
    });
  });

  group('passwordless TUN helper contract', () {
    final body = MacosTunnelBackend.tunWrapperBodyForTest;
    const helper = MacosTunnelBackend.helperPathForTest;
    const mark = MacosTunnelBackend.helperVersionMarkForTest;

    test('wrapper knows its installed path and carries the version mark', () {
      expect(body, contains('HELPER=$helper\n'));
      expect(body, contains(mark));
    });

    test('sudoers rule grants NOPASSWD only to the exact helper path', () {
      expect(
        MacosTunnelBackend.sudoersRuleForTest,
        contains('%admin ALL=(root) NOPASSWD: $helper *'),
      );
    });

    test('verifies core SHA-256 against trusted copy and runs trusted binary', () {
      expect(body, contains('|| exit 4'));
      expect(body, contains(r'SB=$CORES/$NAME'));
    });

    test('root writes only under /var/run/keqdroid with owner-only core.log', () {
      expect(body, contains(r'RUN=/var/run/keqdroid/$OWNER'));
      expect(body, contains(r'chown "$OWNER" "$LOGF" && chmod 0600 "$LOGF"'));
      expect(body, contains(r'/usr/bin/sudo -u "#$OWNER"'));
    });

    test('install script validates sudoers with visudo before installing', () async {
      final installOnly = await MacosTunnelBackend.installScriptForTest(
        runAfter: false,
      );
      expect(installOnly, contains('/usr/sbin/visudo -cf'));
      expect(installOnly, isNot(contains('exec ')));

      final installAndRun = await MacosTunnelBackend.installScriptForTest(
        runAfter: true,
      );
      expect(installAndRun.trimRight(), endsWith("exec '$helper' \"\$@\""));
    });
  });
}
