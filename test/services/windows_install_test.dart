import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/windows_install.dart';
import 'package:keqdroid/services/windows_setup_updater.dart';

void main() {
  group('папка из записи Uninstall', () {
    test('та же папка, как её пишет Inno: с косой чертой в конце', () {
      expect(
        WindowsInstall.isSameInstallDir(
          r'C:\Program Files\keqdroid\',
          r'C:\Program Files\keqdroid',
        ),
        isTrue,
      );
      expect(
        WindowsInstall.isSameInstallDir(
          'C:\\Program Files\\KEQDROID\n',
          r'c:\program files\keqdroid',
        ),
        isTrue,
      );
    });

    test('портабельная копия в другой папке установленной не считается', () {
      expect(
        WindowsInstall.isSameInstallDir(
          r'C:\Program Files\keqdroid\',
          r'D:\Apps\keqdroid',
        ),
        isFalse,
      );
      expect(
        WindowsInstall.isSameInstallDir(
          r'C:\Program Files\keqdroid\',
          r'C:\Program Files\keqdroid-old',
        ),
        isFalse,
      );
      expect(WindowsInstall.isSameInstallDir(null, r'C:\x'), isFalse);
      expect(WindowsInstall.isSameInstallDir('  ', r'C:\x'), isFalse);
    });
  });

  group('установщик и приложение говорят об одном', () {
    final iss = File('windows/installer/keqdroid.iss').readAsStringSync();

    test('AppId записи Uninstall тот же, что ищет апдейтер', () {
      final id = RegExp(r'^AppId=\{\{([0-9A-F-]{36})\}', multiLine: true)
          .firstMatch(iss)!
          .group(1)!;
      final dart =
          File('lib/services/windows_install.dart').readAsStringSync();
      expect(dart, contains('{$id}_is1'));
    });

    test('AppMutex тот же, что держит раннер', () {
      final mutex =
          RegExp(r'^AppMutex=(.+)$', multiLine: true).firstMatch(iss)!.group(1)!;
      final main = File('windows/runner/main.cpp').readAsStringSync();
      expect(
        main,
        contains('kSingleInstanceMutex[] = L"${mutex.trim().replaceAll(r'\', r'\\')}"'),
      );
    });

    test('имя файла установщика апдейтер узнаёт', () {
      final base = RegExp(r'^OutputBaseFilename=(.+)$', multiLine: true)
          .firstMatch(iss)!
          .group(1)!
          .trim();
      expect('$base.exe', endsWith(WindowsInstall.setupSuffix));
      expect(base, startsWith('keqdroid-windows-x64-'));
    });
  });

  group('скрипт тихой установки', () {
    test('только ASCII: Windows PowerShell 5.1 читает .ps1 в кодировке системы', () {
      expect(
        WindowsSetupUpdater.script.codeUnits.where((c) => c > 0x7e && c != 0x0a),
        isEmpty,
      );
    });

    test('ставит молча и возвращает приложение при любом исходе', () {
      const s = WindowsSetupUpdater.script;
      for (final flag in ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART']) {
        expect(s, contains(flag));
      }
      final setup = s.indexOf(r'Start-Process -FilePath $Setup');
      final relaunch = s.indexOf(r'Start-Process -FilePath $ExePath');
      expect(s.indexOf('Get-Process -Id'), lessThan(setup));
      expect(setup, lessThan(relaunch));
      // перезапуск не внутри try установки: упавший установщик его не пропускает
      expect(s.substring(setup, relaunch), contains('} catch {'));
    });
  });
}
