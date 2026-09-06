import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/process_name_utils.dart';

void main() {
  group('normalizeProcessName режет путь независимо от платформы', () {
    // Раньше здесь стоял `p.basename`, который работает в стиле ТЕКУЩЕЙ
    // платформы. На Windows тесты проходили, на Linux — падали: `\`
    // разделителем там не считается, и виндовый путь возвращался целиком.
    //
    // Это не только про CI. Список сплит-туннелирования переезжает между
    // машинами резервной копией настроек, поэтому имя сюда приходит с чужой
    // платформы штатно, а не по недоразумению.
    test('виндовый путь', () {
      expect(
        normalizeProcessName(r'C:\Program Files\Discord\Discord.exe'),
        'Discord.exe',
      );
    });

    test('юниксовый путь', () {
      expect(normalizeProcessName('/usr/bin/discord'), 'discord.exe');
    });

    test('смешанные разделители — берём последний любой', () {
      expect(normalizeProcessName(r'C:/Games\Steam/steam.exe'), 'steam.exe');
    });

    test('кавычки вокруг пути снимаются', () {
      expect(normalizeProcessName(r'"C:\Apps\Foo.exe"'), 'Foo.exe');
    });
  });

  group('normalizeProcessName прочее', () {
    test('регистр сохраняется: sing-box сравнивает без приведения', () {
      expect(normalizeProcessName('Telegram.exe'), 'Telegram.exe');
    });

    test('имя без расширения получает .exe', () {
      expect(normalizeProcessName('Discord'), 'Discord.exe');
    });

    test('уже .exe второй раз не дописывается, регистр расширения не важен', () {
      expect(normalizeProcessName('Foo.EXE'), 'Foo.EXE');
    });

    test('пусто остаётся пустым', () {
      expect(normalizeProcessName('   '), isEmpty);
    });
  });

  group('processNameMatchVariants', () {
    test('имя в смешанном регистре едет двумя вариантами', () {
      expect(processNameMatchVariants('Telegram.exe'), [
        'Telegram.exe',
        'telegram.exe',
      ]);
    });

    test('имя и так в нижнем регистре — вариант один', () {
      expect(processNameMatchVariants('telegram.exe'), ['telegram.exe']);
    });

    test('пусто вариантов не даёт', () {
      expect(processNameMatchVariants('  '), isEmpty);
    });
  });
}
