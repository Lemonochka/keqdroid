import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/tunnel/linux_tunnel_backend.dart';

/// Беспарольный TUN держится на строках, которые живут в трёх местах: теле
/// обёртки, правиле polkit и проверке «установлено ли». Разойдись они — и
/// правило разрешало бы не тот файл, хелпер не узнавал бы сам себя, а старый
/// хелпер, запускавший от root что угодно, не снимался бы.
void main() {
  final body = LinuxTunnelBackend.tunWrapperBodyForTest;
  const helper = LinuxTunnelBackend.polkitHelperPathForTest;
  const mark = LinuxTunnelBackend.helperVersionMarkForTest;

  test('the wrapper knows its own installed path', () {
    expect(body, contains('HELPER=$helper\n'));
  });

  test('the polkit rule allows exactly that path', () {
    expect(
      LinuxTunnelBackend.polkitRuleForTest,
      contains('action.lookup("program") == "$helper"'),
    );
  });

  test('an installed helper carries the mark the app looks for', () {
    expect(body, contains(mark));
    // и снимается любой хелпер без этой метки
    expect(body, contains("grep -q '\\$mark'"));
  });

  test('without a password only the trusted copy of the core runs', () {
    expect(body, contains('|| exit 4'));
    expect(body, contains(r'SB=$CORES/$NAME'));
  });

  // хелпер без пароля зовёт любая программа пользователя: v5 обнулял от root любой файл из аргумента
  group('what the caller names cannot steer root', () {
    test('root writes only into its own run directory', () {
      expect(body, contains(r'RUN=/run/keqdroid/$OWNER'));
      expect(body, contains(r'LOGF=$RUN/core.log'));
      expect(body, isNot(contains(r'LOGF="$4"')));
      expect(body, isNot(contains(r'AUTHF=')));
    });

    test('the log with server addresses is readable only by its owner', () {
      expect(body, contains(r'chown "$OWNER" "$LOGF" && chmod 0600 "$LOGF"'));
    });

    test('paths from the caller are read with the caller rights', () {
      expect(body, contains(r'setpriv --reuid="$OWNER"'));
      expect(body, contains(r'as_owner cat -- "$CFG" >"$CONF"'));
      expect(body, contains(r'as_owner cat -- "$SB" | sha256sum'));
      // без setpriv беспарольный путь отказывает, а не читает правами root
      expect(body, contains('elif [ "\$0" = "\$HELPER" ]; then\n  exit 5'));
    });

    test('core kind and app pid accept nothing else', () {
      expect(
        body,
        contains(r'case "$KIND" in xray) NAME=keqrnel; EXT=json ;; mihomo) NAME=mihomo; EXT=yaml ;; *) exit 5 ;; esac'),
      );
      expect(body, contains(r'''case "$APPPID" in ''|*[!0-9]*) exit 5 ;; esac'''));
    });

    test('under systemd the core cannot write outside its run directory', () {
      expect(body, contains('-p ProtectSystem=strict'));
      expect(body, contains(r'-p ReadWritePaths="$RUN"'));
    });
  });

  group('the first password sets up passwordless TUN', () {
    test('and runs the core through the new helper right away', () async {
      final script =
          await LinuxTunnelBackend.installScriptForTest(runAfter: true);
      expect(script, contains("cat > '$helper'"));
      expect(script, contains('#!/bin/sh\n$body'));
      expect(script.trimRight(), endsWith("exec '$helper' \"\$@\""));
    });

    test('the switch in settings only installs', () async {
      final script =
          await LinuxTunnelBackend.installScriptForTest(runAfter: false);
      expect(script, contains("cat > '$helper'"));
      expect(script, isNot(contains('exec ')));
    });
  });
}
