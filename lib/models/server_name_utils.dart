class ServerNameUtils {
  static const Map<String, String> _keywords = {
    'россия': 'RU', 'германия': 'DE', 'нидерланды': 'NL', 'эстония': 'EE',
    'финляндия': 'FI', 'франция': 'FR', 'польша': 'PL', 'швеция': 'SE',
    'норвегия': 'NO', 'дания': 'DK', 'австрия': 'AT', 'швейцария': 'CH',
    'бельгия': 'BE', 'чехия': 'CZ', 'венгрия': 'HU', 'румыния': 'RO',
    'болгария': 'BG', 'греция': 'GR', 'италия': 'IT', 'испания': 'ES',
    'португалия': 'PT', 'великобритания': 'GB', 'ирландия': 'IE',
    'исландия': 'IS', 'латвия': 'LV', 'литва': 'LT', 'словакия': 'SK',
    'словения': 'SI', 'хорватия': 'HR', 'сербия': 'RS', 'молдова': 'MD',
    'украина': 'UA', 'беларусь': 'BY', 'казахстан': 'KZ', 'турция': 'TR',
    'израиль': 'IL', 'оаэ': 'AE', 'индия': 'IN', 'китай': 'CN',
    'япония': 'JP', 'корея': 'KR', 'сингапур': 'SG', 'гонконг': 'HK',
    'тайвань': 'TW', 'австралия': 'AU', 'новая зеландия': 'NZ',
    'канада': 'CA', 'сша': 'US', 'бразилия': 'BR', 'аргентина': 'AR',
    'мексика': 'MX', 'чили': 'CL', 'колумбия': 'CO', 'перу': 'PE',
    'южная африка': 'ZA', 'нигерия': 'NG', 'египет': 'EG', 'таиланд': 'TH',
    'вьетнам': 'VN', 'индонезия': 'ID', 'малайзия': 'MY', 'пакистан': 'PK',
    'иран': 'IR', 'саудовская аравия': 'SA', 'катар': 'QA', 'кувейт': 'KW',
    'russia': 'RU', 'germany': 'DE', 'deutsch': 'DE', 'netherlands': 'NL',
    'holland': 'NL', 'estonia': 'EE', 'finland': 'FI', 'france': 'FR',
    'poland': 'PL', 'sweden': 'SE', 'norway': 'NO', 'denmark': 'DK',
    'austria': 'AT', 'switzerland': 'CH', 'swiss': 'CH', 'belgium': 'BE',
    'czech': 'CZ', 'czechia': 'CZ', 'hungary': 'HU', 'romania': 'RO',
    'bulgaria': 'BG', 'greece': 'GR', 'italy': 'IT', 'spain': 'ES',
    'portugal': 'PT', 'britain': 'GB', 'england': 'GB', 'ireland': 'IE',
    'iceland': 'IS', 'latvia': 'LV', 'lithuania': 'LT', 'slovakia': 'SK',
    'slovenia': 'SI', 'croatia': 'HR', 'serbia': 'RS', 'moldova': 'MD',
    'ukraine': 'UA', 'belarus': 'BY', 'kazakhstan': 'KZ', 'turkey': 'TR',
    'turkiye': 'TR', 'israel': 'IL', 'uae': 'AE', 'dubai': 'AE',
    'india': 'IN', 'china': 'CN', 'japan': 'JP', 'korea': 'KR',
    'singapore': 'SG', 'hong kong': 'HK', 'hongkong': 'HK', 'taiwan': 'TW',
    'australia': 'AU', 'new zealand': 'NZ', 'canada': 'CA',
    'united states': 'US', 'usa': 'US', 'america': 'US', 'brazil': 'BR',
    'argentina': 'AR', 'mexico': 'MX', 'chile': 'CL', 'colombia': 'CO',
    'peru': 'PE', 'south africa': 'ZA', 'nigeria': 'NG', 'egypt': 'EG',
    'thailand': 'TH', 'vietnam': 'VN', 'indonesia': 'ID', 'malaysia': 'MY',
    'pakistan': 'PK', 'iran': 'IR', 'iraq': 'IQ', 'saudi': 'SA',
    'qatar': 'QA', 'kuwait': 'KW',
    'ru': 'RU', 'de': 'DE', 'nl': 'NL', 'ee': 'EE', 'fi': 'FI',
    'fr': 'FR', 'pl': 'PL', 'se': 'SE', 'dk': 'DK',
    'at': 'AT', 'ch': 'CH', 'be': 'BE', 'cz': 'CZ', 'hu': 'HU',
    'ro': 'RO', 'bg': 'BG', 'gr': 'GR', 'it': 'IT', 'es': 'ES',
    'pt': 'PT', 'gb': 'GB', 'uk': 'GB', 'ie': 'IE',
    'lv': 'LV', 'lt': 'LT', 'sk': 'SK', 'si': 'SI', 'hr': 'HR',
    'rs': 'RS', 'md': 'MD', 'ua': 'UA', 'by': 'BY', 'kz': 'KZ',
    'tr': 'TR', 'il': 'IL', 'ae': 'AE', 'cn': 'CN',
    'jp': 'JP', 'kr': 'KR', 'sg': 'SG', 'hk': 'HK', 'tw': 'TW',
    'au': 'AU', 'nz': 'NZ', 'ca': 'CA', 'us': 'US', 'br': 'BR',
    'ar': 'AR', 'mx': 'MX', 'cl': 'CL', 'co': 'CO', 'pe': 'PE',
    'za': 'ZA', 'ng': 'NG', 'eg': 'EG', 'th': 'TH', 'vn': 'VN',
    'my': 'MY', 'pk': 'PK', 'ir': 'IR', 'iq': 'IQ',
    'sa': 'SA', 'qa': 'QA', 'kw': 'KW',
    'est': 'EE', 'nld': 'NL', 'deu': 'DE', 'rus': 'RU', 'fra': 'FR',
    'pol': 'PL', 'swe': 'SE', 'nor': 'NO', 'dnk': 'DK', 'aut': 'AT',
    'che': 'CH', 'bel': 'BE', 'cze': 'CZ', 'hun': 'HU', 'rou': 'RO',
    'bgr': 'BG', 'grc': 'GR', 'ita': 'IT', 'esp': 'ES', 'prt': 'PT',
    'gbr': 'GB', 'irl': 'IE', 'isl': 'IS', 'lva': 'LV', 'ltu': 'LT',
    'svk': 'SK', 'svn': 'SI', 'hrv': 'HR', 'srb': 'RS', 'mda': 'MD',
    'ukr': 'UA', 'blr': 'BY', 'kaz': 'KZ', 'tur': 'TR', 'isr': 'IL',
    'are': 'AE', 'ind': 'IN', 'chn': 'CN', 'jpn': 'JP', 'kor': 'KR',
    'sgp': 'SG', 'hkg': 'HK', 'twn': 'TW', 'aus': 'AU', 'nzl': 'NZ',
    'can': 'CA', 'bra': 'BR', 'arg': 'AR', 'mex': 'MX',
    'chl': 'CL', 'col': 'CO', 'per': 'PE', 'zaf': 'ZA', 'nga': 'NG',
    'egy': 'EG', 'tha': 'TH', 'vnm': 'VN', 'idn': 'ID', 'mys': 'MY',
    'pak': 'PK', 'irn': 'IR', 'irq': 'IQ', 'sau': 'SA', 'qat': 'QA',
    'kwt': 'KW',
  };

  static const Map<String, String> _emojiToCode = {
    '🇷🇺': 'RU', '🇩🇪': 'DE', '🇳🇱': 'NL', '🇪🇪': 'EE', '🇫🇮': 'FI',
    '🇫🇷': 'FR', '🇵🇱': 'PL', '🇸🇪': 'SE', '🇳🇴': 'NO', '🇩🇰': 'DK',
    '🇦🇹': 'AT', '🇨🇭': 'CH', '🇧🇪': 'BE', '🇨🇿': 'CZ', '🇭🇺': 'HU',
    '🇷🇴': 'RO', '🇧🇬': 'BG', '🇬🇷': 'GR', '🇮🇹': 'IT', '🇪🇸': 'ES',
    '🇵🇹': 'PT', '🇬🇧': 'GB', '🇮🇪': 'IE', '🇮🇸': 'IS', '🇱🇻': 'LV',
    '🇱🇹': 'LT', '🇸🇰': 'SK', '🇸🇮': 'SI', '🇭🇷': 'HR', '🇷🇸': 'RS',
    '🇲🇩': 'MD', '🇺🇦': 'UA', '🇧🇾': 'BY', '🇰🇿': 'KZ', '🇹🇷': 'TR',
    '🇮🇱': 'IL', '🇦🇪': 'AE', '🇮🇳': 'IN', '🇨🇳': 'CN', '🇯🇵': 'JP',
    '🇰🇷': 'KR', '🇸🇬': 'SG', '🇭🇰': 'HK', '🇹🇼': 'TW', '🇦🇺': 'AU',
    '🇳🇿': 'NZ', '🇨🇦': 'CA', '🇺🇸': 'US', '🇧🇷': 'BR', '🇦🇷': 'AR',
    '🇲🇽': 'MX', '🇨🇱': 'CL', '🇨🇴': 'CO', '🇵🇪': 'PE', '🇿🇦': 'ZA',
    '🇳🇬': 'NG', '🇪🇬': 'EG', '🇹🇭': 'TH', '🇻🇳': 'VN', '🇮🇩': 'ID',
    '🇲🇾': 'MY', '🇵🇰': 'PK', '🇮🇷': 'IR', '🇮🇶': 'IQ', '🇸🇦': 'SA',
    '🇶🇦': 'QA', '🇰🇼': 'KW',
  };

  static String? extractCountryCode(String displayName) {
    if (displayName.isEmpty) return null;

    for (final entry in _emojiToCode.entries) {
      if (displayName.contains(entry.key)) return entry.value;
    }

    final lower = displayName.toLowerCase();
    final tokens = lower
        .replaceAll(RegExp(r'[|,\-_/\\]'), ' ')
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .map((s) => s.replaceAll(RegExp(r'[^a-zа-яё]'), ''))
        .where((s) => s.isNotEmpty)
        .toList();

    for (final tok in tokens) {
      if (tok.length == 2 || tok.length == 3) {
        final code = _keywords[tok];
        if (code != null) return code;
      }
    }

    final sortedKeys = _keywords.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in sortedKeys) {
      if (lower.contains(key)) return _keywords[key]!;
    }

    return null;
  }

  static String cleanDisplayName(String displayName) {
    var cleaned = displayName
        .replaceAll(RegExp(r'[\u{1F1E6}-\u{1F1FF}]', unicode: true), '')
        .trim();
    final match = RegExp(r'^[A-Z]{2}\s+(.+)$').firstMatch(cleaned);
    return match != null ? match.group(1)!.trim() : cleaned;
  }

  static String formatForDisplay(String displayName, {int maxLength = 30}) {
    final cleaned = cleanDisplayName(displayName);
    if (cleaned.length <= maxLength) return cleaned;
    return '${cleaned.substring(0, maxLength - 3)}...';
  }
}
