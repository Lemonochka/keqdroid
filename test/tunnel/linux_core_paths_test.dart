import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/tunnel/linux_core_paths.dart';

// Ядро в кэше меняется только переименованием готового файла: прямая запись
// с обрезкой давала полузаписанный бинарь тем замерам, что запускали его в
// ту же секунду.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('keq_stage_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('the new file replaces the old one whole', () async {
    final path = '${tmp.path}/keqrnel';
    File(path).writeAsStringSync('old core');

    await LinuxCorePaths.replaceAtomically(
      path,
      (t) => File(t).writeAsString('new core'),
    );

    expect(File(path).readAsStringSync(), 'new core');
    expect(tmp.listSync(), hasLength(1));
  });

  test('a failed write leaves the old file and no temp behind', () async {
    final path = '${tmp.path}/keqrnel';
    File(path).writeAsStringSync('old core');

    await expectLater(
      LinuxCorePaths.replaceAtomically(path, (t) async {
        File(t).writeAsStringSync('half');
        throw const FileSystemException('disk full');
      }),
      throwsA(isA<FileSystemException>()),
    );

    expect(File(path).readAsStringSync(), 'old core');
    expect(tmp.listSync(), hasLength(1));
  });

  // Код работает только на Linux; Windows не даёт переименовать поверх файла,
  // который в ту же секунду заменяет другой поток.
  test(
    'parallel writers never leave a partial file',
    () async {
      final path = '${tmp.path}/keqrnel';
      final payload = List.filled(1 << 20, 'x').join();
      await Future.wait([
        for (var i = 0; i < 8; i++)
          LinuxCorePaths.replaceAtomically(
            path,
            (t) => File(t).writeAsString(payload),
          ),
      ]);
      expect(File(path).lengthSync(), payload.length);
      expect(tmp.listSync(), hasLength(1));
    },
    skip: Platform.isWindows ? 'rename is atomic only on POSIX' : false,
  );

  group('stageExecutable', () {
    late File core;

    setUp(() {
      LinuxCorePaths.cacheRootOverride = tmp.path;
      core = File('${tmp.path}/bundle-keqrnel')..writeAsStringSync('core v1');
    });
    tearDown(() => LinuxCorePaths.cacheRootOverride = null);

    // Раскладка, ждавшая сама себя, вешала подключение навсегда: ядро не
    // запускалось, а на экране висело Подключение….
    test('finishes, and so does the next call', () async {
      final first = await LinuxCorePaths.stageExecutable(
        core.path,
        'keqrnel',
      ).timeout(const Duration(seconds: 5));
      final second = await LinuxCorePaths.stageExecutable(
        core.path,
        'keqrnel',
      ).timeout(const Duration(seconds: 5));

      expect(first, second);
      expect(File(first).readAsStringSync(), 'core v1');
    });

    test('parallel callers share one copy', () async {
      final paths = await Future.wait([
        for (var i = 0; i < 5; i++)
          LinuxCorePaths.stageExecutable(core.path, 'keqrnel'),
      ]).timeout(const Duration(seconds: 5));

      expect(paths.toSet(), hasLength(1));
      expect(Directory('${tmp.path}/keqdroid/cores').listSync(), hasLength(1));
    });

    test('an updated core of another size replaces the cached one', () async {
      final staged = await LinuxCorePaths.stageExecutable(core.path, 'keqrnel');
      core.writeAsStringSync('core v2, longer');

      await LinuxCorePaths.stageExecutable(
        core.path,
        'keqrnel',
      ).timeout(const Duration(seconds: 5));

      expect(File(staged).readAsStringSync(), 'core v2, longer');
    });
  });

  group('findPkexec', () {
    // На NixOS security.polkit.enable кладёт в sw/bin бинарник без setuid,
    // который падает с кодом 127; живая обёртка лежит только в /run/wrappers/bin.
    test('prefers /run/wrappers/bin/pkexec over non-setuid PATH entry', () {
      final files = {
        '/run/current-system/sw/bin/pkexec',
        '/run/wrappers/bin/pkexec',
      };
      final found = LinuxCorePaths.findPkexec(
        pathEnvOverride: '/run/current-system/sw/bin:/usr/bin',
        fileExistsOverride: files.contains,
      );
      expect(found, '/run/wrappers/bin/pkexec');
    });

    test('finds /run/wrappers/bin/pkexec when session PATH is stripped', () {
      final files = {'/run/wrappers/bin/pkexec'};
      final found = LinuxCorePaths.findPkexec(
        pathEnvOverride: '',
        fileExistsOverride: files.contains,
      );
      expect(found, '/run/wrappers/bin/pkexec');
    });

    test('uses PATH entry on standard FHS systems', () {
      final files = {'/custom/bin/pkexec', '/usr/bin/pkexec'};
      final found = LinuxCorePaths.findPkexec(
        pathEnvOverride: ':/custom/bin:/usr/bin:',
        fileExistsOverride: files.contains,
      );
      expect(found, '/custom/bin/pkexec');
    });

    test('falls back to /usr/bin/pkexec when PATH is empty', () {
      final files = {'/usr/bin/pkexec'};
      final found = LinuxCorePaths.findPkexec(
        pathEnvOverride: '',
        fileExistsOverride: files.contains,
      );
      expect(found, '/usr/bin/pkexec');
    });

    test('returns null when polkit is absent everywhere', () {
      final found = LinuxCorePaths.findPkexec(
        pathEnvOverride: '/usr/bin:/bin',
        fileExistsOverride: (_) => false,
      );
      expect(found, isNull);
    });
  });
}
