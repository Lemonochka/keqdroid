/// Флажок из имени сервера: картинка [FlagArt] или сам эмодзи [FlagGlyph].
///
/// Флаг-эмодзи — это не только «пара региональных букв». В юникоде их четыре
/// разных вида, и провайдеры пользуются всеми:
///
/// * пара региональных индикаторов — 🇷🇺, 🇳🇱, а также не-страны 🇪🇺, 🇺🇳 и
///   исключительно зарезервированные коды 🇦🇨, 🇪🇦, 🇮🇨, 🇹🇦, 🇨🇵, 🇩🇬;
/// * тег-последовательность (флаг субъекта) — 🏴 + невидимые тег-буквы:
///   Шотландия, Уэльс, Англия, Сев. Ирландия, Каталония, Галисия;
/// * ZWJ-последовательность — 🏴‍☠️, 🏳️‍🌈, 🏳️‍⚧️;
/// * одиночные флаги — 🏁, 🚩, 🎌, 🏳️, 🏴.
///
/// Поэтому разбор идёт по СТРУКТУРЕ последовательности, а не по списку
/// известных стран: любой существующий флаг опознаётся, даже если картинки для
/// него у нас нет — тогда рисуем сам эмодзи.
sealed class ServerFlag {
  const ServerFlag();
}

/// Флаг, для которого есть векторная картинка.
final class FlagArt extends ServerFlag {
  /// Имя ассета: `ru`, `gb-sct`, `eu`.
  final String code;

  const FlagArt(this.code);

  /// Путь к `.si`-ассету пакета `country_flags`.
  ///
  /// Картинку рисуем сами, минуя `CountryFlag.fromCountryCode`: его таблица
  /// знает только 254 кода из 266 положенных в пакет — нет `eu`, `un`, `ac`,
  /// `cp`, `dg`, `ea`, `ic`, `ta`, `xx`, `es-ct`, `es-ga`, — а на незнакомом
  /// коде виджет рисует белый квадрат со знаком вопроса. Что путь и список
  /// [flagArtCodes] сходятся с содержимым пакета, проверяет
  /// `test/models/server_flag_assets_test.dart`.
  String get assetPath => 'packages/country_flags/res/si/$code.si';

  /// Код региона (ISO alpha-2, в верхнем регистре); у флага субъекта — код
  /// страны, которой он принадлежит (`gb-sct` → `GB`). У 🏴‍☠️ и 🏁 кода нет.
  String? get countryCode {
    final base = code.split('-').first;
    return base.length == 2 ? base.toUpperCase() : null;
  }

  @override
  bool operator ==(Object other) => other is FlagArt && other.code == code;

  @override
  int get hashCode => Object.hash(FlagArt, code);

  @override
  String toString() => 'FlagArt($code)';
}

/// Флаг без картинки — рисуем сам эмодзи. Сюда попадают 🏴‍☠️, 🏳️‍🌈 и любой
/// флаг субъекта, которого нет в ассетах (🏴󠁵󠁳󠁴󠁸󠁿 и подобные).
final class FlagGlyph extends ServerFlag {
  final String emoji;

  const FlagGlyph(this.emoji);

  @override
  bool operator ==(Object other) => other is FlagGlyph && other.emoji == emoji;

  @override
  int get hashCode => Object.hash(FlagGlyph, emoji);

  @override
  String toString() => 'FlagGlyph($emoji)';
}

/// Найденный в строке флаг и его границы (в рунах, `end` не включается).
class FlagMatch {
  final ServerFlag flag;
  final int start;
  final int end;

  const FlagMatch(this.flag, this.start, this.end);
}

const _risFirst = 0x1F1E6; // 🇦
const _risLast = 0x1F1FF; // 🇿
const _tagBase = 0xE0000; // тег-символ = _tagBase + ascii
const _tagFirst = 0xE0020;
const _tagLast = 0xE007E;
const _tagTerm = 0xE007F; // CANCEL TAG
const _flagBlack = 0x1F3F4; // 🏴
const _flagWhite = 0x1F3F3; // 🏳
const _zwj = 0x200D;
const _vs16 = 0xFE0F;

/// 🏁 клетчатый, 🚩 треугольный, 🎌 скрещенные — самостоятельные флаги без
/// продолжения.
const _loneFlags = {0x1F3C1, 0x1F6A9, 0x1F38C};

/// Все флаги в строке, слева направо.
Iterable<FlagMatch> findFlags(String text) sync* {
  final runes = text.runes.toList(growable: false);
  var i = 0;
  while (i < runes.length) {
    final rune = runes[i];

    if (_isRegionalIndicator(rune)) {
      // Одинокая региональная буква флагом не является: показывать её как
      // страну нельзя, но и «съедать» следующий символ тоже.
      if (i + 1 < runes.length && _isRegionalIndicator(runes[i + 1])) {
        final code = String.fromCharCodes([
          0x61 + rune - _risFirst,
          0x61 + runes[i + 1] - _risFirst,
        ]);
        yield FlagMatch(_artOrGlyph(code, runes, i, i + 2), i, i + 2);
        i += 2;
        continue;
      }
      i++;
      continue;
    }

    if (rune == _flagBlack || rune == _flagWhite) {
      final tagged = rune == _flagBlack ? _readTags(runes, i) : null;
      if (tagged != null) {
        yield FlagMatch(
          _artOrGlyph(tagged.code, runes, i, tagged.end),
          i,
          tagged.end,
        );
        i = tagged.end;
        continue;
      }
      final end = _endOfZwjSequence(runes, i);
      yield FlagMatch(FlagGlyph(_slice(runes, i, end)), i, end);
      i = end;
      continue;
    }

    if (_loneFlags.contains(rune)) {
      final end = i + 1 < runes.length && runes[i + 1] == _vs16 ? i + 2 : i + 1;
      yield FlagMatch(FlagGlyph(_slice(runes, i, end)), i, end);
      i = end;
      continue;
    }

    i++;
  }
}

/// Первый флаг строки, если он там есть.
ServerFlag? firstFlagIn(String text) {
  for (final match in findFlags(text)) {
    return match.flag;
  }
  return null;
}

/// Строка без флагов: аватарка показывает флаг картинкой, дублировать его в
/// имени незачем. Пробелы, оставшиеся от вырезанного, схлопываются.
String stripFlags(String text) {
  final runes = text.runes.toList(growable: false);
  final drop = List<bool>.filled(runes.length, false);
  var found = false;

  for (final match in findFlags(text)) {
    found = true;
    for (var i = match.start; i < match.end; i++) {
      drop[i] = true;
    }
  }
  // Непарная региональная буква — обломок флага, а не буква имени.
  for (var i = 0; i < runes.length; i++) {
    if (_isRegionalIndicator(runes[i])) {
      drop[i] = true;
      found = true;
    }
  }
  if (!found) return text;

  final kept = <int>[];
  for (var i = 0; i < runes.length; i++) {
    if (!drop[i]) kept.add(runes[i]);
  }
  return String.fromCharCodes(kept).replaceAll(RegExp(r' {2,}'), ' ');
}

bool _isRegionalIndicator(int rune) => rune >= _risFirst && rune <= _risLast;

String _slice(List<int> runes, int start, int end) =>
    String.fromCharCodes(runes.getRange(start, end));

ServerFlag _artOrGlyph(String code, List<int> runes, int start, int end) =>
    flagArtCodes.contains(code)
    ? FlagArt(code)
    : FlagGlyph(_slice(runes, start, end));

/// 🏴 + тег-буквы + терминатор → код субъекта (`gbsct` → `gb-sct`).
/// null, если тегов нет или последовательность не закрыта.
({String code, int end})? _readTags(List<int> runes, int start) {
  final tags = StringBuffer();
  var i = start + 1;
  while (i < runes.length && runes[i] >= _tagFirst && runes[i] <= _tagLast) {
    tags.writeCharCode(runes[i] - _tagBase);
    i++;
  }
  if (tags.isEmpty || i >= runes.length || runes[i] != _tagTerm) return null;
  final raw = tags.toString().toLowerCase();
  return (
    code: raw.length > 2 ? '${raw.substring(0, 2)}-${raw.substring(2)}' : raw,
    end: i + 1,
  );
}

/// Конец последовательности вида «база (+ VS16) (+ ZWJ символ)*».
int _endOfZwjSequence(List<int> runes, int start) {
  var i = start + 1;
  if (i < runes.length && runes[i] == _vs16) i++;
  while (i + 1 < runes.length && runes[i] == _zwj) {
    i += 2;
    if (i < runes.length && runes[i] == _vs16) i++;
  }
  return i;
}

/// Коды, для которых в пакете `country_flags` лежит векторная картинка.
///
/// Список нужен ДО отрисовки: по нему решается, показать вектор или сам эмодзи.
/// Спрашивать сам пакет нельзя — его таблица кодов беднее набора ассетов.
final Set<String> flagArtCodes = Set.unmodifiable(_artCodes.split(' '));

const _artCodes =
    'ac ad ae af ag ai al am ao aq ar as at au aw ax az '
    'ba bb bd be bf bg bh bi bj bl bm bn bo bq br bs bt bv bw by bz '
    'ca cc cd cefta cf cg ch ci ck cl cm cn co cp cr cu cv cw cx cy cz '
    'de dg dj dk dm do dz ea ec ee eg eh er es es-ct es-ga et eu '
    'fi fj fk fm fo fr ga gb gb-eng gb-nir gb-sct gb-wls gd ge gf gg gh gi '
    'gl gm gn gp gq gr gs gt gu gw gy hk hm hn hr ht hu '
    'ic id ie il im in io iq ir is it je jm jo jp '
    'ke kg kh ki km kn kp kr kw ky kz la lb lc li lk lr ls lt lu lv ly '
    'ma mc md me mf mg mh mk ml mm mn mo mp mq mr ms mt mu mv mw mx my mz '
    'na nc ne nf ng ni nl no np nr nu nz om '
    'pa pe pf pg ph pk pl pm pn pr ps pt pw py qa re ro rs ru rw '
    'sa sb sc sd se sg sh si sj sk sl sm sn so sr ss st sv sx sy sz '
    'ta tc td tf tg th tj tk tl tm tn to tr tt tv tw tz '
    'ua ug um un us uy uz va vc ve vg vi vn vu wf ws xk xx ye yt za zm zw';
