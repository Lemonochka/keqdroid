import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/macos_dmg_updater.dart';
import 'package:path/path.dart' as p;

Directory _createFakeAppBundle(
  Directory parent, {
  String name = 'keqdroid.app',
  String version = '0.40.1',
}) {
  final app = Directory(p.join(parent.path, name));
  final macosDir = Directory(p.join(app.path, 'Contents', 'MacOS'))
    ..createSync(recursive: true);
  File(p.join(macosDir.path, 'keqdroid')).writeAsStringSync('bin-$version');
  File(p.join(app.path, 'Contents', 'Info.plist')).writeAsStringSync(
    '<plist><dict><key>CFBundleShortVersionString</key>'
    '<string>$version</string></dict></plist>',
  );
  return app;
}

void main() {
  late Directory tmp;
  final realExecutable = MacosDmgUpdater.executablePath;
  final realRunProcess = MacosDmgUpdater.runProcess;
  final realStartDetached = MacosDmgUpdater.startDetached;
  final realCleanup = MacosDmgUpdater.cleanupBeforeExit;
  final realExit = MacosDmgUpdater.exitProcess;
  final realTempDir = MacosDmgUpdater.tempDir;
  final realPid = MacosDmgUpdater.currentPid;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('keq_macos_dmg_upd_');
    MacosDmgUpdater.tempDir = () => tmp;
    MacosDmgUpdater.currentPid = () => 42424;
    MacosDmgUpdater.cleanupBeforeExit = () async {};
  });

  tearDown(() {
    MacosDmgUpdater.executablePath = realExecutable;
    MacosDmgUpdater.runProcess = realRunProcess;
    MacosDmgUpdater.startDetached = realStartDetached;
    MacosDmgUpdater.cleanupBeforeExit = realCleanup;
    MacosDmgUpdater.exitProcess = realExit;
    MacosDmgUpdater.tempDir = realTempDir;
    MacosDmgUpdater.currentPid = realPid;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('currentAppBundlePath', () {
    test('resolves a normal installed .app bundle', () {
      final app = _createFakeAppBundle(tmp);
      final exe = p.join(app.path, 'Contents', 'MacOS', 'keqdroid');
      expect(
        MacosDmgUpdater.currentAppBundlePath(resolvedExecutable: exe),
        app.path,
      );
    });

    test('rejects mounted /Volumes and Gatekeeper AppTranslocation paths', () {
      expect(
        MacosDmgUpdater.currentAppBundlePath(
          resolvedExecutable:
              '/Volumes/keqdroid 0.40.1/keqdroid.app/Contents/MacOS/keqdroid',
        ),
        isNull,
      );
      expect(
        MacosDmgUpdater.currentAppBundlePath(
          resolvedExecutable:
              '/private/var/folders/xx/AppTranslocation/ABC/d/keqdroid.app/Contents/MacOS/keqdroid',
        ),
        isNull,
      );
      expect(
        MacosDmgUpdater.currentAppBundlePath(
          resolvedExecutable: '/usr/local/bin/keqdroid',
        ),
        isNull,
      );
    });

    test('rejects symlinked .app bundles', () {
      if (Platform.isWindows) return;
      final real = _createFakeAppBundle(tmp, name: 'real.app');
      final link = Link(p.join(tmp.path, 'keqdroid.app'))
        ..createSync(real.path);
      final exe = p.join(link.path, 'Contents', 'MacOS', 'keqdroid');
      expect(
        MacosDmgUpdater.currentAppBundlePath(resolvedExecutable: exe),
        isNull,
      );
    });
  });

  group('findAppBundleInMount', () {
    test('finds keqdroid.app or single valid .app bundle', () {
      final mount = Directory(p.join(tmp.path, 'mnt'))..createSync();
      final app = _createFakeAppBundle(mount);
      expect(MacosDmgUpdater.findAppBundleInMount(mount), app.path);

      final empty = Directory(p.join(tmp.path, 'empty'))..createSync();
      expect(MacosDmgUpdater.findAppBundleInMount(empty), isNull);
    });
  });

  group('applyDmgUpdate (mocked tools)', () {
    test(
      'mounts with -nobrowse, stages via ditto, detaches, runs beforeRestart, launches detached swap and exits',
      () async {
        final installRoot = Directory(p.join(tmp.path, 'Apps'))..createSync();
        final installedApp = _createFakeAppBundle(installRoot, version: '0.40.1');
        final dmgFile = File(p.join(tmp.path, 'keqdroid-0.40.2.dmg'))
          ..writeAsStringSync('fake-dmg');

        MacosDmgUpdater.executablePath = () =>
            p.join(installedApp.path, 'Contents', 'MacOS', 'keqdroid');

        final calls = <String>[];
        final detachedArgs = <List<String>>[];
        final exitCodes = <int>[];

        MacosDmgUpdater.runProcess = (exe, args) async {
          calls.add('$exe ${args.join(' ')}');
          if (exe == '/usr/bin/hdiutil' && args.first == 'attach') {
            final mountPoint = args[args.indexOf('-mountpoint') + 1];
            _createFakeAppBundle(Directory(mountPoint), version: '0.40.2');
            return ProcessResult(0, 0, '', '');
          }
          if (exe == '/usr/bin/ditto') {
            final dst = args[1];
            _createFakeAppBundle(
              Directory(p.dirname(dst)),
              name: p.basename(dst),
              version: '0.40.2',
            );
            return ProcessResult(0, 0, '', '');
          }
          return ProcessResult(0, 0, '', '');
        };

        MacosDmgUpdater.startDetached = (exe, args) async {
          calls.add('detached:$exe');
          detachedArgs.add(args);
        };
        MacosDmgUpdater.exitProcess = exitCodes.add;

        final applied = await MacosDmgUpdater.applyDmgUpdate(
          dmgPath: dmgFile.path,
          beforeRestart: () async => calls.add('beforeRestart'),
        );

        expect(applied, isTrue);
        expect(exitCodes, [0]);
        expect(dmgFile.existsSync(), isFalse);

        // Verify silent mount flags and order of operations.
        expect(
          calls.first,
          allOf(
            contains('/usr/bin/hdiutil attach'),
            contains('-nobrowse'),
            contains('-readonly'),
            contains('-noautoopen'),
          ),
        );
        final detachIdx = calls.indexWhere((c) => c.contains('hdiutil detach'));
        final beforeRestartIdx = calls.indexOf('beforeRestart');
        final detachedIdx = calls.indexOf('detached:/bin/sh');
        expect(detachIdx, greaterThan(0));
        expect(beforeRestartIdx, greaterThan(detachIdx));
        expect(detachedIdx, greaterThan(beforeRestartIdx));

        // Detached script receives [script, pid, stagedApp, targetApp].
        final scriptArgs = detachedArgs.single;
        expect(scriptArgs[1], '42424');
        expect(p.dirname(scriptArgs[2]), installRoot.path);
        expect(scriptArgs[3], installedApp.path);
        expect(File(scriptArgs[0]).existsSync(), isTrue);
      },
    );

    test(
      'detaches DMG and cleans staging without calling beforeRestart when ditto fails',
      () async {
        final installRoot = Directory(p.join(tmp.path, 'Apps'))..createSync();
        final installedApp = _createFakeAppBundle(installRoot);
        final dmgFile = File(p.join(tmp.path, 'keqdroid.dmg'))
          ..writeAsStringSync('fake-dmg');

        MacosDmgUpdater.executablePath = () =>
            p.join(installedApp.path, 'Contents', 'MacOS', 'keqdroid');

        var detached = false;
        var beforeRestartCalled = false;
        var launchedScript = false;

        MacosDmgUpdater.runProcess = (exe, args) async {
          if (exe == '/usr/bin/hdiutil' && args.first == 'attach') {
            final mountPoint = args[args.indexOf('-mountpoint') + 1];
            _createFakeAppBundle(Directory(mountPoint), version: '0.40.2');
            return ProcessResult(0, 0, '', '');
          }
          if (exe == '/usr/bin/hdiutil' && args.first == 'detach') {
            detached = true;
            return ProcessResult(0, 0, '', '');
          }
          if (exe == '/usr/bin/ditto') {
            return ProcessResult(0, 1, '', 'No space left on device');
          }
          return ProcessResult(0, 0, '', '');
        };
        MacosDmgUpdater.startDetached = (_, _) async => launchedScript = true;
        MacosDmgUpdater.exitProcess = (_) {};

        await expectLater(
          MacosDmgUpdater.applyDmgUpdate(
            dmgPath: dmgFile.path,
            beforeRestart: () async => beforeRestartCalled = true,
          ),
          throwsA(isA<StateError>()),
        );

        expect(detached, isTrue);
        expect(beforeRestartCalled, isFalse);
        expect(launchedScript, isFalse);
        expect(
          installRoot
              .listSync()
              .where((e) => p.basename(e.path).startsWith('.keqdroid_update_')),
          isEmpty,
        );
      },
    );

    test(
      'returns false for fallback when running from a mounted /Volumes DMG',
      () async {
        final dmgFile = File(p.join(tmp.path, 'keqdroid.dmg'))
          ..writeAsStringSync('fake-dmg');
        MacosDmgUpdater.executablePath = () =>
            '/Volumes/keqdroid 0.40.1/keqdroid.app/Contents/MacOS/keqdroid';

        var ranProcess = false;
        MacosDmgUpdater.runProcess = (_, _) async {
          ranProcess = true;
          return ProcessResult(0, 0, '', '');
        };

        final applied = await MacosDmgUpdater.applyDmgUpdate(
          dmgPath: dmgFile.path,
        );
        expect(applied, isFalse);
        expect(ranProcess, isFalse);
        expect(dmgFile.existsSync(), isTrue);
      },
    );
  });

  group('real macOS integration', () {
    test(
      'updater shell script waits for PID, atomically swaps .app, and cleans up',
      () async {
        if (!Platform.isMacOS) return;

        final apps = Directory(p.join(tmp.path, 'Apps'))..createSync();
        final target = _createFakeAppBundle(apps, version: '0.40.1');
        final staged = _createFakeAppBundle(
          apps,
          name: '.keqdroid_update_test.app',
          version: '0.40.2',
        );
        final script = File(p.join(tmp.path, 'swap.sh'))
          ..writeAsStringSync(MacosDmgUpdater.updaterScript(relaunch: false));

        // Spawn a short-lived process to simulate the exiting app PID.
        final sleeper = await Process.start('/bin/sleep', ['0.3']);
        final res = await Process.run('/bin/sh', [
          script.path,
          '${sleeper.pid}',
          staged.path,
          target.path,
        ]);

        expect(res.exitCode, 0, reason: '${res.stderr}');
        expect(
          File(p.join(target.path, 'Contents', 'MacOS', 'keqdroid'))
              .readAsStringSync(),
          'bin-0.40.2',
        );
        expect(staged.existsSync(), isFalse);
        expect(script.existsSync(), isFalse);
        expect(
          apps.listSync().where((e) => e.path.contains('.old.')),
          isEmpty,
        );
      },
    );

    test(
      'mounts a real UDZO DMG silently via hdiutil and stages via ditto',
      () async {
        if (!Platform.isMacOS) return;

        final srcFolder = Directory(p.join(tmp.path, 'dmg_src'))..createSync();
        _createFakeAppBundle(srcFolder, version: '0.40.2');
        final dmgPath = p.join(tmp.path, 'test-update.dmg');

        final create = await Process.run('/usr/bin/hdiutil', [
          'create',
          '-volname',
          'keqdroid test',
          '-srcfolder',
          srcFolder.path,
          '-fs',
          'HFS+',
          '-format',
          'UDZO',
          '-ov',
          dmgPath,
        ]);
        expect(create.exitCode, 0, reason: '${create.stderr}');

        final installRoot = Directory(p.join(tmp.path, 'Installed'))
          ..createSync();
        final installedApp = _createFakeAppBundle(installRoot, version: '0.40.1');

        MacosDmgUpdater.executablePath = () =>
            p.join(installedApp.path, 'Contents', 'MacOS', 'keqdroid');
        MacosDmgUpdater.runProcess = realRunProcess;
        MacosDmgUpdater.exitProcess = (_) {};

        List<String>? capturedArgs;
        MacosDmgUpdater.startDetached = (_, args) async => capturedArgs = args;

        final applied = await MacosDmgUpdater.applyDmgUpdate(dmgPath: dmgPath);
        expect(applied, isTrue);
        expect(capturedArgs, isNotNull);
        expect(File(dmgPath).existsSync(), isFalse);

        final stagedApp = capturedArgs![2];
        expect(
          File(p.join(stagedApp, 'Contents', 'MacOS', 'keqdroid'))
              .readAsStringSync(),
          'bin-0.40.2',
        );
      },
    );
  });
}
