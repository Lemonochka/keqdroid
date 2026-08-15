import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/server_flag.dart';
import 'package:keqdroid/models/server_name_utils.dart';

void main() {
  group('findFlags: региональные индикаторы', () {
    test('обычная страна → картинка', () {
      expect(firstFlagIn('🇷🇺 Москва'), const FlagArt('ru'));
      expect(firstFlagIn('Node 🇳🇱 01'), const FlagArt('nl'));
    });

    test('не-страны и зарезервированные коды тоже картинки', () {
      // Регресс: у CountryFlag.fromCountryCode этих кодов нет в таблице, и
      // вместо флага рисовался белый квадрат со знаком вопроса.
      expect(firstFlagIn('🇪🇺 Europe'), const FlagArt('eu'));
      expect(firstFlagIn('🇺🇳 UN'), const FlagArt('un'));
      expect(firstFlagIn('🇦🇨 Ascension'), const FlagArt('ac'));
      expect(firstFlagIn('🇪🇦 Ceuta'), const FlagArt('ea'));
      expect(firstFlagIn('🇮🇨 Canarias'), const FlagArt('ic'));
      expect(firstFlagIn('🇹🇦 Tristan'), const FlagArt('ta'));
      expect(firstFlagIn('🇨🇵 Clipperton'), const FlagArt('cp'));
      expect(firstFlagIn('🇩🇬 Diego Garcia'), const FlagArt('dg'));
      expect(firstFlagIn('🇽🇰 Kosovo'), const FlagArt('xk'));
    });

    test('несуществующая пара букв → сам эмодзи, а не чужой флаг', () {
      expect(firstFlagIn('🇶🇿 nowhere'), const FlagGlyph('🇶🇿'));
    });

    test('одинокая региональная буква флагом не считается', () {
      expect(firstFlagIn('🇷 half'), isNull);
    });
  });

  group('findFlags: флаги субъектов (тег-последовательности)', () {
    test('британские субъекты → свои картинки', () {
      expect(firstFlagIn('🏴󠁧󠁢󠁳󠁣󠁴󠁿 Scotland'), const FlagArt('gb-sct'));
      expect(firstFlagIn('🏴󠁧󠁢󠁷󠁬󠁳󠁿 Wales'), const FlagArt('gb-wls'));
      expect(firstFlagIn('🏴󠁧󠁢󠁥󠁮󠁧󠁿 England'), const FlagArt('gb-eng'));
      expect(firstFlagIn('🏴󠁧󠁢󠁮󠁩󠁲󠁿 N. Ireland'), const FlagArt('gb-nir'));
    });

    test('испанские субъекты → свои картинки', () {
      expect(firstFlagIn('🏴󠁥󠁳󠁣󠁴󠁿 Catalunya'), const FlagArt('es-ct'));
      expect(firstFlagIn('🏴󠁥󠁳󠁧󠁡󠁿 Galicia'), const FlagArt('es-ga'));
    });

    test('субъект без картинки → сам эмодзи целиком', () {
      const texas = '🏴󠁵󠁳󠁴󠁸󠁿';
      expect(firstFlagIn('$texas Dallas'), const FlagGlyph(texas));
    });

    test('незакрытая тег-последовательность → просто чёрный флаг', () {
      // Нет CANCEL TAG в конце: последовательность невалидна, но 🏴 показать
      // всё равно лучше, чем ничего.
      const broken = '\u{1F3F4}\u{E0067}\u{E0062}';
      expect(firstFlagIn(broken), const FlagGlyph('\u{1F3F4}'));
    });
  });

  group('findFlags: ZWJ и одиночные флаги', () {
    test('пиратский, радужный, трансовый', () {
      expect(firstFlagIn('🏴‍☠️ Pirate'), const FlagGlyph('🏴‍☠️'));
      expect(firstFlagIn('🏳️‍🌈 Pride'), const FlagGlyph('🏳️‍🌈'));
      expect(firstFlagIn('🏳️‍⚧️ Trans'), const FlagGlyph('🏳️‍⚧️'));
    });

    test('клетчатый, треугольный, скрещенные, белый, чёрный', () {
      expect(firstFlagIn('🏁 Fast'), const FlagGlyph('🏁'));
      expect(firstFlagIn('🚩 Marked'), const FlagGlyph('🚩'));
      expect(firstFlagIn('🎌 JP'), const FlagGlyph('🎌'));
      expect(firstFlagIn('🏳️ White'), const FlagGlyph('🏳️'));
      expect(firstFlagIn('🏴 Black'), const FlagGlyph('🏴'));
    });

    test('ZWJ-последовательность не рвётся на куски', () {
      final matches = findFlags('🏴‍☠️').toList();
      expect(matches.length, 1);
      expect(matches.single.flag, const FlagGlyph('🏴‍☠️'));
    });
  });

  test('флаги находятся по порядку, первый — главный', () {
    final flags = findFlags('🏳️‍🌈 mix 🇩🇪 и 🏁').map((m) => m.flag).toList();
    expect(flags, [
      const FlagGlyph('🏳️‍🌈'),
      const FlagArt('de'),
      const FlagGlyph('🏁'),
    ]);
  });

  test('в имени без флагов ничего не мерещится', () {
    expect(firstFlagIn('Cloudflare Warp-1'), isNull);
    expect(firstFlagIn('🚀 Fast node'), isNull);
    expect(firstFlagIn(''), isNull);
  });

  group('stripFlags', () {
    test('вырезает флаг любого вида', () {
      expect(stripFlags('🇷🇺 Москва').trim(), 'Москва');
      expect(stripFlags('🏴󠁧󠁢󠁳󠁣󠁴󠁿 Scotland').trim(), 'Scotland');
      expect(stripFlags('🏴‍☠️ Pirate').trim(), 'Pirate');
      expect(stripFlags('🏁 Fast').trim(), 'Fast');
    });

    test('не трогает не-флаговые эмодзи', () {
      expect(stripFlags('🚀 Fast node'), '🚀 Fast node');
    });

    test('схлопывает дыру, оставшуюся от вырезанного флага', () {
      expect(stripFlags('Node 🇩🇪 01'), 'Node 01');
    });
  });

  group('ServerNameUtils поверх флагов', () {
    test('countryCode есть только у страновых флагов', () {
      expect(ServerNameUtils.extractCountryCode('🇩🇪 Germany 01'), 'DE');
      // Субъект принадлежит стране — код у него её.
      expect(ServerNameUtils.extractCountryCode('🏴󠁧󠁢󠁳󠁣󠁴󠁿 Scotland'), 'GB');
      // Не-страна, но код региона у неё есть — он и возвращается.
      expect(ServerNameUtils.extractCountryCode('🇪🇺 Europe'), 'EU');
      // А у 🏴‍☠️ и 🏁 кода нет, и придумывать его не надо.
      expect(ServerNameUtils.extractCountryCode('🏴‍☠️ Pirate'), isNull);
      expect(ServerNameUtils.extractCountryCode('🏁 Fast'), isNull);
    });

    test('флаг из имени важнее догадки по названию страны', () {
      expect(
        ServerNameUtils.extractFlag('🏴‍☠️ Germany'),
        const FlagGlyph('🏴‍☠️'),
      );
    });

    test('без эмодзи флаг всё ещё угадывается по названию', () {
      expect(ServerNameUtils.extractFlag('Estonia | 2 | HY2'), const FlagArt('ee'));
      expect(ServerNameUtils.extractFlag('Cloudflare Warp-1'), isNull);
    });

    test('cleanDisplayName убирает флаг любого вида', () {
      expect(ServerNameUtils.cleanDisplayName('🏳️‍🌈 Pride node'), 'Pride node');
      expect(ServerNameUtils.cleanDisplayName('🇷🇺 Белый интернет #1'),
          'Белый интернет #1');
    });
  });
}
