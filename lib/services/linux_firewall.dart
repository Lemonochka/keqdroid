import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/tun_settings.dart';

enum LinuxFirewall { firewalld, ufw }

class LinuxFirewalls {
  LinuxFirewalls._();

  @visibleForTesting
  static Future<ProcessResult> Function(String, List<String>) run = Process.run;

  @visibleForTesting
  static String firewalldPidFile = '/var/run/firewalld.pid';

  // ufw status требует root, поэтому читаем его конфиг
  static Future<LinuxFirewall?> detect() async {
    if (await _firewalldRunning()) return LinuxFirewall.firewalld;
    try {
      final conf = await File('/etc/ufw/ufw.conf').readAsString();
      if (ufwEnabled(conf)) return LinuxFirewall.ufw;
    } catch (_) {}
    return null;
  }

  // не firewall-cmd --state: firewalld 2.5 проверяет чтение свойства по D-Bus правом config,
  // и polkit спрашивал пароль на каждом запуске, карточка строится вместе со скрытой вкладкой настроек
  static Future<bool> _firewalldRunning() async {
    try {
      final r = await run('systemctl', ['is-active', '--quiet', 'firewalld']);
      if (r.exitCode == 0) return true;
    } on ProcessException {
      // без systemd
    }
    // под systemd firewalld идёт с --nopid, pid-файл бывает только без него
    return File(firewalldPidFile).existsSync();
  }

  // system и mixed у mihomo принимают TCP из tun через INPUT, и запрет новых входящих в ufw и firewalld его режет:
  // ядро живо, а TCP не идёт. gvisor и mips держат TCP у себя, проверено стендом 13.11.2026
  static Future<({String stack, LinuxFirewall? blockedBy})> tunStack(
    String stack,
  ) async {
    if (stack != TunSettings.stackSystem && stack != TunSettings.stackMixed) {
      return (stack: stack, blockedBy: null);
    }
    final firewall = await detect();
    if (firewall == null) return (stack: stack, blockedBy: null);
    return (stack: TunSettings.stackGvisor, blockedBy: firewall);
  }

  @visibleForTesting
  static bool ufwEnabled(String conf) => conf
      .split('\n')
      .map((l) => l.trim().replaceAll('"', '').replaceAll("'", ''))
      .any((l) => l.toLowerCase() == 'enabled=yes');

  static String openCommand(LinuxFirewall firewall, List<int> ports) =>
      switch (firewall) {
        LinuxFirewall.firewalld =>
          'sudo firewall-cmd --permanent '
              '${ports.map((p) => '--add-port=$p/tcp').join(' ')} '
              '&& sudo firewall-cmd --reload',
        LinuxFirewall.ufw =>
          ports.map((p) => 'sudo ufw allow $p/tcp').join(' && '),
      };
}
