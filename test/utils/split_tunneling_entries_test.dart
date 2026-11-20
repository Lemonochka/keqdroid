import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_info.dart';
import 'package:keqdroid/utils/split_tunnel_routing.dart';
import 'package:keqdroid/utils/split_tunneling_entries.dart';

AppInfo _app(String pkg, {String? path}) =>
    AppInfo(packageName: pkg, appName: pkg, installPath: path);

const _discord = AppInfo(
  packageName: 'Discord.exe',
  appName: 'Discord',
  installPath: r'C:\Users\u\AppData\Local\Discord\app-1.0\Discord.exe',
);

void main() {
  group('запись совпадает со строкой', () {
    test('имя — с любой программой этого имени, без учёта регистра', () {
      expect(splitEntryMatches('Discord.exe', _discord, windows: true), isTrue);
      // Так писала старая версия.
      expect(splitEntryMatches('discord.exe', _discord, windows: true), isTrue);
      expect(splitEntryMatches('Discord', _discord, windows: true), isTrue);
    });

    test('путь — только с этим файлом', () {
      expect(
        splitEntryMatches(_discord.installPath!, _discord, windows: true),
        isTrue,
      );
      // На Windows путь от регистра не зависит.
      expect(
        splitEntryMatches(
          r'c:\users\u\appdata\local\discord\APP-1.0\discord.exe',
          _discord,
          windows: true,
        ),
        isTrue,
      );
      expect(
        splitEntryMatches(
          r'C:\Games\Other\Discord.exe',
          _discord,
          windows: true,
        ),
        isFalse,
      );
    });

    test('на Linux регистр пути различается', () {
      const app = AppInfo(
        packageName: 'tool',
        appName: 'tool',
        installPath: '/opt/App/tool',
      );
      expect(splitEntryMatches('/opt/App/tool', app, windows: false), isTrue);
      expect(splitEntryMatches('/opt/app/tool', app, windows: false), isFalse);
    });

    // Прежняя версия приписывала .exe к вписанному руками на любой системе.
    // На Linux такая запись указывает на ту же программу, и в правила ядра она уходит
    // без суффикса, иначе не совпала бы ни с одним процессом.
    test(
      'на Linux сохранённое с .exe отмечает свою строку и едет без .exe',
      () {
        expect(
          splitEntryMatches('firefox.exe', _app('firefox'), windows: false),
          isTrue,
        );
        expect(
          processNamesForSplit(
            includePackages: {'firefox.exe'},
            excludePackages: const {},
            windows: false,
          ),
          ['firefox'],
        );
      },
    );

    test('путь у строки без пути не совпадает', () {
      expect(
        splitEntryMatches(r'C:\a\x.exe', _app('x.exe'), windows: true),
        isFalse,
      );
    });
  });

  test('SplitSelection отмечает строку по пути или по имени', () {
    final byPath = SplitSelection({_discord.installPath!}, windows: true);
    final byName = SplitSelection({'discord.exe'}, windows: true);
    const other = AppInfo(
      packageName: 'Discord.exe',
      appName: 'Discord',
      installPath: r'C:\Elsewhere\Discord.exe',
    );

    expect(byPath.covers(_discord), isTrue);
    expect(byPath.covers(other), isFalse);
    expect(byName.covers(_discord), isTrue);
    expect(byName.covers(other), isTrue);
  });

  group('строка для записи вне списка', () {
    test('путь даёт строку с этим путём и именем файла', () {
      final stub = splitStubForEntry(r'C:\Games\Update.exe', windows: true);
      expect(stub.packageName, 'Update.exe');
      expect(stub.installPath, r'C:\Games\Update.exe');
    });

    test('имя даёт строку без пути', () {
      final stub = splitStubForEntry('Update', windows: true);
      expect(stub.packageName, 'Update.exe');
      expect(stub.installPath, isNull);
    });
  });

  group('dedupeSplitEntries', () {
    test('схлопывает записи, различающиеся только регистром', () {
      final out = dedupeSplitEntries([
        _app('Discord.exe', path: r'C:\Discord\Discord.exe'),
        _app('discord.exe'),
      ], windows: true);

      expect(out, hasLength(1));
      expect(out.single.installPath, isNotNull);
    });

    test('заглушка уступает записи с путём независимо от порядка', () {
      // Ровно этот случай и рисовал близнеца: заглушка, собранная из
      // сохранённого имени, приписывалась В НАЧАЛО списка, а живая строка с
      // путём и иконкой оставалась ниже.
      final out = dedupeSplitEntries([
        _app('Telegram.exe'),
        _app('Telegram.exe', path: r'C:\Telegram\Telegram.exe'),
      ], windows: true);

      expect(out, hasLength(1));
      expect(out.single.installPath, r'C:\Telegram\Telegram.exe');
    });

    test('одно имя с разными путями — разные программы', () {
      final out = dedupeSplitEntries([
        _app('Update.exe', path: r'C:\A\Update.exe'),
        _app('Update.exe', path: r'C:\B\Update.exe'),
        _app('Update.exe', path: r'c:\a\update.exe'),
      ], windows: true);

      expect(out.map((e) => e.installPath), [
        r'C:\A\Update.exe',
        r'C:\B\Update.exe',
      ]);
    });

    test('порядок остальных записей сохраняется', () {
      final out = dedupeSplitEntries([
        _app('a.exe', path: 'a'),
        _app('b.exe', path: 'b'),
        _app('A.exe'),
        _app('c.exe', path: 'c'),
      ], windows: true);

      expect(out.map((e) => e.packageName), ['a.exe', 'b.exe', 'c.exe']);
    });

    test('разные приложения остаются разными', () {
      final out = dedupeSplitEntries([
        _app('Discord.exe', path: 'd'),
        _app('Telegram.exe', path: 't'),
      ], windows: true);

      expect(out, hasLength(2));
    });
  });
}
