import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Ветка nix собирается из статических файлов в tool/nix/ и свежего source.json:
// здесь проверяем те контракты, без которых сломается запуск TUN или ярлыки в NixOS.
void main() {
  test('bootstrap source.json имеет валидную схему релиза и SRI-хеша', () {
    // Версию намеренно не сверяем с pubspec.yaml: nix.yml обновляет только ветку nix.
    final raw = File('tool/nix/nix/source.json').readAsStringSync();
    final json = jsonDecode(raw) as Map<String, dynamic>;

    expect(
      json['owner'],
      isA<String>().having((s) => s, 'non-empty', isNotEmpty),
    );
    expect(json['repo'], 'keqdroid');
    expect(json['version'], matches(RegExp(r'^[0-9]+\.[0-9]+(\.[0-9]+)?$')));
    final hash = json['hash'] as String;
    expect(hash, startsWith('sha256-'));
    expect(base64.decode(hash.substring('sha256-'.length)), hasLength(32));
  });

  test(
    'flake экспортирует пакеты, приложения, оверлей, модуль NixOS и форматтер',
    () {
      final flake = File('tool/nix/flake.nix').readAsStringSync();
      final lock =
          jsonDecode(File('tool/nix/flake.lock').readAsStringSync())
              as Map<String, dynamic>;

      expect(lock['version'], 7);
      expect((lock['nodes'] as Map<String, dynamic>)['nixpkgs'], isNotNull);

      for (final symbol in [
        'packages.\${system}',
        'apps.\${system}',
        'overlays',
        'nixosModules',
        'formatter.\${system}',
      ]) {
        expect(flake, contains(symbol));
      }
    },
  );

  test(
    'package.nix ставит /run/wrappers/bin первым в PATH и не тянет polkit из store',
    () {
      final pkg = File('tool/nix/nix/package.nix').readAsStringSync();

      expect(pkg, contains('--prefix PATH : /run/wrappers/bin'));
      expect(pkg, contains('--suffix PATH :'));
      expect(pkg, isNot(contains('polkit')));
    },
  );

  test(
    'ярлыки в package.nix повторяют схемы и StartupWMClass из package_linux.sh',
    () {
      final pkg = File('tool/nix/nix/package.nix').readAsStringSync();
      final linuxScript = File('tool/package_linux.sh').readAsStringSync();

      for (final scheme in [
        'x-scheme-handler/keqdroid',
        'x-scheme-handler/keqdis',
        'com.keqdroid.keqdroid',
      ]) {
        expect(linuxScript, contains(scheme));
        expect(pkg, contains(scheme));
      }
      // StartupWMClass должен быть только у основного ярлыка, иначе панель привяжет окно к скрытому двойнику
      expect('startupWMClass'.allMatches(pkg), hasLength(1));
    },
  );

  test(
    'module.nix мягко включает pkexec wrapper и не перезаписывает фаервол',
    () {
      final mod = File('tool/nix/nix/module.nix').readAsStringSync();

      expect(mod, contains('options.programs.keqdroid'));
      expect(mod, contains('options ? security.polkit.enablePkexecWrapper'));
      expect(mod, contains('enablePkexecWrapper = lib.mkDefault true;'));
      expect(
        RegExp(
          r'^\s*networking\.firewall\.checkReversePath\s*=(?!=)',
          multiLine: true,
        ).hasMatch(mod),
        isFalse,
      );
    },
  );

  test(
    'workflow nix.yml публикует все файлы из tool/nix и сгенерированный source.json',
    () {
      final workflow = File('.github/workflows/nix.yml').readAsStringSync();

      for (final repoPath in [
        'tool/nix/flake.nix',
        'tool/nix/flake.lock',
        'tool/nix/nix/package.nix',
        'tool/nix/nix/module.nix',
      ]) {
        expect(workflow, contains("'$repoPath'"));
      }
      for (final branchPath in [
        "['flake.nix', flakeNix]",
        "['flake.lock', flakeLock]",
        "['nix/package.nix', packageNix]",
        "['nix/module.nix', moduleNix]",
        "['nix/source.json', sourceJson]",
      ]) {
        expect(workflow, contains(branchPath));
      }
    },
  );
}
