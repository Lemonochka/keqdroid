import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/linux_install.dart';

void main() {
  const exe = '/opt/keqdroid/keqdroid';

  Future<LinuxInstallKind> classify({
    String? appImage,
    String? owner,
    bool writable = true,
  }) {
    return LinuxInstall.classify(
      appImagePath: appImage,
      executable: exe,
      owns: (tool, args) async {
        // Спрашивают про сам исполняемый файл, а не про имя пакета.
        expect(args.last, exe);
        return tool == owner;
      },
      writable: (dir) {
        expect(dir, '/opt/keqdroid');
        return writable;
      },
    );
  }

  test(
    'AppImage узнаётся по переменной рантайма, менеджеры не спрашиваются',
    () async {
      expect(
        await classify(
          appImage: '/home/u/keqdroid.AppImage',
          owner: 'dpkg-query',
        ),
        LinuxInstallKind.appImage,
      );
    },
  );

  test('пакет узнаётся по тому, какой менеджер владеет файлом', () async {
    expect(await classify(owner: 'dpkg-query'), LinuxInstallKind.deb);
    expect(await classify(owner: 'rpm'), LinuxInstallKind.rpm);
    expect(await classify(owner: 'pacman'), LinuxInstallKind.pacman);
  });

  test(
    'ничей файл — распакованный архив; без записи — только для чтения',
    () async {
      expect(await classify(), LinuxInstallKind.portable);
      expect(await classify(writable: false), LinuxInstallKind.readOnly);
    },
  );

  test('RPM 6 пропускает только отсутствующую OpenPGP-подпись', () {
    expect(LinuxInstall.packageInstallCommand('/tmp/k.rpm'), [
      'rpm',
      '-U',
      '--nosignature',
      '/tmp/k.rpm',
    ]);
    expect(LinuxInstall.packageInstallCommand('/tmp/k.deb'), [
      'apt-get',
      'install',
      '-y',
      '/tmp/k.deb',
    ]);
  });

  group('пакет на системе из образа', () {
    tearDown(() => LinuxInstall.imageBasedSystem = () => false);

    test('rpm на Silverblue и подобных не ставим через rpm -U', () {
      LinuxInstall.imageBasedSystem = () => true;
      expect(
        LinuxInstall.packageInstallBlocker('/tmp/keqdroid_update.rpm'),
        contains('rpm-ostree'),
      );
    });

    test('на обычной системе и для deb ничего не мешает', () {
      LinuxInstall.imageBasedSystem = () => false;
      expect(LinuxInstall.packageInstallBlocker('/tmp/k.rpm'), isNull);
      LinuxInstall.imageBasedSystem = () => true;
      expect(LinuxInstall.packageInstallBlocker('/tmp/k.deb'), isNull);
    });
  });

  group('package install elevation', () {
    final realPkexecPath = LinuxInstall.pkexecPath;
    final realRunProcess = LinuxInstall.runProcess;

    tearDown(() {
      LinuxInstall.pkexecPath = realPkexecPath;
      LinuxInstall.runProcess = realRunProcess;
    });

    test('uses the same resolved pkexec as the TUN backend', () async {
      LinuxInstall.pkexecPath = () => '/run/wrappers/bin/pkexec';
      String? executable;
      List<String>? arguments;
      LinuxInstall.runProcess = (exe, args) async {
        executable = exe;
        arguments = args;
        return ProcessResult(0, 126, '', '');
      };

      final installed = await LinuxInstall.installPackage('/tmp/k.deb');

      expect(installed, isFalse);
      expect(executable, '/run/wrappers/bin/pkexec');
      expect(arguments, ['apt-get', 'install', '-y', '/tmp/k.deb']);
    });
  });
}
