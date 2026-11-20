import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/process_name_utils.dart';

void main() {
  group('normalizeProcessName режет путь независимо от платформы', () {
    // Раньше здесь стоял p.basename, который работает в стиле текущей
    // платформы. На Windows тесты проходили, на Linux падали: \
    // разделителем там не считается, и виндовый путь возвращался целиком.
    //
    // Это не только про CI. Список сплит-туннелирования переезжает между
    // машинами резервной копией настроек, поэтому имя сюда приходит с чужой
    // платформы штатно, а не по недоразумению.
    test('виндовый путь', () {
      expect(
        normalizeProcessName(
          r'C:\Program Files\Discord\Discord.exe',
          windows: true,
        ),
        'Discord.exe',
      );
    });

    test('юниксовый путь', () {
      expect(
        normalizeProcessName('/usr/bin/discord', windows: true),
        'discord.exe',
      );
    });

    test('смешанные разделители — берём последний любой', () {
      expect(
        normalizeProcessName(r'C:/Games\Steam/steam.exe', windows: true),
        'steam.exe',
      );
    });

    test('кавычки вокруг пути снимаются', () {
      expect(
        normalizeProcessName(r'"C:\Apps\Foo.exe"', windows: true),
        'Foo.exe',
      );
    });
  });

  group('normalizeProcessName прочее', () {
    test('регистр сохраняется: на Linux ядро сравнивает имя точно', () {
      expect(
        normalizeProcessName('Telegram.exe', windows: true),
        'Telegram.exe',
      );
    });

    test('имя без расширения получает .exe', () {
      expect(normalizeProcessName('Discord', windows: true), 'Discord.exe');
    });

    test(
      'уже .exe второй раз не дописывается, регистр расширения не важен',
      () {
        expect(normalizeProcessName('Foo.EXE', windows: true), 'Foo.EXE');
      },
    );

    test('пусто остаётся пустым', () {
      expect(normalizeProcessName('   '), isEmpty);
    });
  });

  // На Linux имя процесса совпадает с именем файла как есть: с дописанным .exe правило
  // ядра не совпадало ни разу.
  group('normalizeProcessName на Linux', () {
    test('расширение не дописывается', () {
      expect(normalizeProcessName('firefox', windows: false), 'firefox');
    });

    test('путь режется до имени файла', () {
      expect(
        normalizeProcessName('/usr/lib/firefox/firefox', windows: false),
        'firefox',
      );
    });

    // Прежняя версия приписывала .exe к вписанному руками на любой системе,
    // и такие записи лежат в сохранённых списках.
    test('сохранённый с .exe снимается до имени файла', () {
      expect(normalizeProcessName('firefox.exe', windows: false), 'firefox');
      expect(normalizeProcessName('Firefox.EXE', windows: false), 'Firefox');
    });
  });

  group('запись с путём', () {
    test('путь — с любой косой, имя — без', () {
      expect(isProcessPathEntry(r'C:\Apps\a.exe'), isTrue);
      expect(isProcessPathEntry('/usr/bin/curl'), isTrue);
      expect(isProcessPathEntry('curl'), isFalse);
      expect(isProcessPathEntry('Discord.exe'), isFalse);
    });

    test('на Windows путь приводится к обратным косым, кавычки снимаются', () {
      expect(
        normalizeProcessPath('"C:/Apps/a.exe"', windows: true),
        r'C:\Apps\a.exe',
      );
      expect(
        normalizeProcessPath('/usr/bin/curl', windows: false),
        '/usr/bin/curl',
      );
    });
  });

  group('регулярка ядра', () {
    // Ядро сравнивает регуляркой: точка без кодирования ловила бы любой
    // символ, а запятая разрезала бы правило mihomo на поля.
    test('всё, кроме латиницы и цифр, кодируется', () {
      expect(processRegexLiteral('a,b (x).exe'), r'a\x2cb\x20\x28x\x29\x2eexe');
      expect(processRegexLiteral('Телега.exe'), r'Телега\x2eexe');
    });

    test('путь ловит обе косые и не ловит соседний файл', () {
      final re = RegExp(
        '^${processPathPattern(r'C:\Apps\a.exe')}\$',
        caseSensitive: false,
      );
      expect(re.hasMatch(r'C:\Apps\a.exe'), isTrue);
      expect(re.hasMatch('C:/Apps/a.exe'), isTrue);
      expect(re.hasMatch(r'c:\apps\A.EXE'), isTrue);
      expect(re.hasMatch(r'C:\Apps\aXexe'), isFalse);
      expect(re.hasMatch(r'C:\Other\a.exe'), isFalse);
    });
  });
}
