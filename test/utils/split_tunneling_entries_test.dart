import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_info.dart';
import 'package:keqdroid/utils/split_tunneling_entries.dart';

AppInfo _app(String pkg, {String? path}) =>
    AppInfo(packageName: pkg, appName: pkg, installPath: path);

void main() {
  group('splitEntryKey', () {
    test('регистр не создаёт второго приложения', () {
      expect(splitEntryKey('Discord.exe'), splitEntryKey('discord.exe'));
    });

    test('путь и голое имя — одна запись', () {
      expect(
        splitEntryKey(r'C:\Program Files\Discord\Discord.exe'),
        splitEntryKey('Discord.exe'),
      );
    });

    test('имя без расширения приводится к exe', () {
      expect(splitEntryKey('Discord'), splitEntryKey('Discord.exe'));
    });

    test('пустая строка остаётся пустой', () {
      expect(splitEntryKey('   '), isEmpty);
    });
  });

  group('dedupeSplitEntries', () {
    test('схлопывает записи, различающиеся только регистром', () {
      final out = dedupeSplitEntries([
        _app('Discord.exe', path: r'C:\Discord\Discord.exe'),
        _app('discord.exe'),
      ]);

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
      ]);

      expect(out, hasLength(1));
      expect(out.single.installPath, r'C:\Telegram\Telegram.exe');
    });

    test('порядок остальных записей сохраняется', () {
      final out = dedupeSplitEntries([
        _app('a.exe', path: 'a'),
        _app('b.exe', path: 'b'),
        _app('A.exe'),
        _app('c.exe', path: 'c'),
      ]);

      expect(out.map((e) => e.packageName), ['a.exe', 'b.exe', 'c.exe']);
    });

    test('разные приложения остаются разными', () {
      final out = dedupeSplitEntries([
        _app('Discord.exe', path: 'd'),
        _app('Telegram.exe', path: 't'),
      ]);

      expect(out, hasLength(2));
    });
  });
}
