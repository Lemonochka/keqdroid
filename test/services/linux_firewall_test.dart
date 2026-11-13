import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/tun_settings.dart';
import 'package:keqdroid/services/linux_firewall.dart';
import 'package:path/path.dart' as p;

void main() {
  final realRun = LinuxFirewalls.run;
  final realPidFile = LinuxFirewalls.firewalldPidFile;
  late Directory tmp;
  late List<String> calls;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('keqdroid_fw_');
    LinuxFirewalls.firewalldPidFile = p.join(tmp.path, 'firewalld.pid');
    calls = [];
  });

  tearDown(() {
    LinuxFirewalls.run = realRun;
    LinuxFirewalls.firewalldPidFile = realPidFile;
    tmp.deleteSync(recursive: true);
  });

  void runReturns(int exitCode) {
    LinuxFirewalls.run = (exe, args) async {
      calls.add([exe, ...args].join(' '));
      return ProcessResult(0, exitCode, '', '');
    };
  }

  test('running firewalld is found without firewall-cmd and its polkit prompt',
      () async {
    runReturns(0);
    expect(await LinuxFirewalls.detect(), LinuxFirewall.firewalld);
    expect(calls, ['systemctl is-active --quiet firewalld']);
  });

  test('stopped firewalld is not reported', () async {
    runReturns(3);
    expect(await LinuxFirewalls.detect(), isNot(LinuxFirewall.firewalld));
    expect(calls.where((c) => c.startsWith('firewall-cmd')), isEmpty);
  });

  test('without systemd firewalld is found by its pid file', () async {
    LinuxFirewalls.run = (exe, args) async {
      calls.add(exe);
      throw ProcessException(exe, args);
    };
    File(LinuxFirewalls.firewalldPidFile).writeAsStringSync('1');
    expect(await LinuxFirewalls.detect(), LinuxFirewall.firewalld);
    expect(calls, ['systemctl']);
  });

  test('ufw counts as on only with ENABLED=yes', () {
    expect(LinuxFirewalls.ufwEnabled('# comment\nENABLED=yes\n'), isTrue);
    expect(LinuxFirewalls.ufwEnabled('ENABLED="yes"'), isTrue);
    expect(LinuxFirewalls.ufwEnabled('ENABLED=no\n'), isFalse);
    expect(LinuxFirewalls.ufwEnabled('#ENABLED=yes'), isFalse);
  });

  test('the command opens every shared port', () {
    expect(
      LinuxFirewalls.openCommand(LinuxFirewall.firewalld, [2080, 2081]),
      'sudo firewall-cmd --permanent --add-port=2080/tcp --add-port=2081/tcp '
      '&& sudo firewall-cmd --reload',
    );
    expect(
      LinuxFirewalls.openCommand(LinuxFirewall.ufw, [2080, 2081]),
      'sudo ufw allow 2080/tcp && sudo ufw allow 2081/tcp',
    );
  });

  group('TUN stack under a firewall', () {
    test('system and mixed fall back to gvisor while firewalld runs', () async {
      runReturns(0);
      for (final stack in [TunSettings.stackSystem, TunSettings.stackMixed]) {
        final picked = await LinuxFirewalls.tunStack(stack);
        expect(picked.stack, TunSettings.stackGvisor, reason: stack);
        expect(picked.blockedBy, LinuxFirewall.firewalld, reason: stack);
      }
    });

    test('without a firewall the chosen stack stays', () async {
      // ufw читается с диска машины, где идёт тест
      if (File('/etc/ufw/ufw.conf').existsSync()) return;
      runReturns(3);
      final picked = await LinuxFirewalls.tunStack(TunSettings.stackSystem);
      expect(picked.stack, TunSettings.stackSystem);
      expect(picked.blockedBy, isNull);
    });

    test('gvisor and mips keep TCP inside the core and ask nothing', () async {
      runReturns(0);
      for (final stack in [TunSettings.stackGvisor, TunSettings.stackMips]) {
        final picked = await LinuxFirewalls.tunStack(stack);
        expect(picked.stack, stack);
        expect(picked.blockedBy, isNull);
      }
      expect(calls, isEmpty);
    });
  });
}
