// Определение страны сервера: флаг в названии, название страны или города, код вроде «DE-2»,
// поддомен вида «nl1.example.com». Если ничего не нашлось — страну узнаёт AppState по IP (country.is).
// Картинки флагов: assets/flags/<код>.png (проект flag-icons, лицензия MIT).

/// Коды, для которых есть картинка флага.
const flagCodes = <String>{
  'ad', 'ae', 'af', 'ag', 'ai', 'al', 'am', 'ao', 'aq', 'ar', 'as', 'at', 'au', 'aw', 'ax', 'az', 'ba', 'bb',
  'bd', 'be', 'bf', 'bg', 'bh', 'bi', 'bj', 'bl', 'bm', 'bn', 'bo', 'bq', 'br', 'bs', 'bt', 'bv', 'bw', 'by',
  'bz', 'ca', 'cc', 'cd', 'cf', 'cg', 'ch', 'ci', 'ck', 'cl', 'cm', 'cn', 'co', 'cp', 'cr', 'cu', 'cv', 'cw',
  'cx', 'cy', 'cz', 'de', 'dg', 'dj', 'dk', 'dm', 'do', 'dz', 'ec', 'ee', 'eg', 'eh', 'er', 'es', 'et', 'eu',
  'fi', 'fj', 'fk', 'fm', 'fo', 'fr', 'ga', 'gb', 'gb-eng', 'gb-sct', 'gb-wls', 'gd', 'ge', 'gf', 'gg', 'gh',
  'gi', 'gl', 'gm', 'gn', 'gp', 'gq', 'gr', 'gs', 'gt', 'gu', 'gw', 'gy', 'hk', 'hm', 'hn', 'hr', 'ht', 'hu',
  'ic', 'id', 'ie', 'il', 'im', 'in', 'io', 'iq', 'ir', 'is', 'it', 'je', 'jm', 'jo', 'jp', 'ke', 'kg', 'kh',
  'ki', 'km', 'kn', 'kp', 'kr', 'kw', 'ky', 'kz', 'la', 'lb', 'lc', 'li', 'lk', 'lr', 'ls', 'lt', 'lu', 'lv',
  'ly', 'ma', 'mc', 'md', 'me', 'mf', 'mg', 'mh', 'mk', 'ml', 'mm', 'mn', 'mo', 'mp', 'mq', 'mr', 'ms', 'mt',
  'mu', 'mv', 'mw', 'mx', 'my', 'mz', 'na', 'nc', 'ne', 'nf', 'ng', 'ni', 'nl', 'no', 'np', 'nr', 'nu', 'nz',
  'om', 'pa', 'pe', 'pf', 'pg', 'ph', 'pk', 'pl', 'pm', 'pn', 'pr', 'ps', 'pt', 'pw', 'py', 'qa', 're', 'ro',
  'rs', 'ru', 'rw', 'sa', 'sb', 'sc', 'sd', 'se', 'sg', 'sh', 'si', 'sj', 'sk', 'sl', 'sm', 'sn', 'so', 'sr',
  'ss', 'st', 'sv', 'sx', 'sy', 'sz', 'tc', 'td', 'tf', 'tg', 'th', 'tj', 'tk', 'tl', 'tm', 'tn', 'to', 'tr',
  'tt', 'tv', 'tw', 'tz', 'ua', 'ug', 'um', 'un', 'us', 'uy', 'uz', 'va', 'vc', 've', 'vg', 'vi', 'vn', 'vu',
  'wf', 'ws', 'xk', 'xx', 'ye', 'yt', 'za', 'zm', 'zw',
};

/// Путь к картинке флага или null.
String? flagAsset(String? code) {
  if (code == null) return null;
  final c = code.toLowerCase();
  return flagCodes.contains(c) ? 'assets/flags/$c.png' : null;
}

class Country {
  /// Код страны в нижнем регистре («nl», «gb-eng») или null.
  static String? detect(String name, {String host = ''}) {
    final key = '$name|$host';
    if (_cache.containsKey(key)) return _cache[key];
    final c = fromFlag(name) ?? fromWords(name) ?? fromCode(name) ?? fromHost(host);
    if (_cache.length > 2000) _cache.clear();
    return _cache[key] = c;
  }

  static final _cache = <String, String?>{};

  /// 🇳🇱 → nl, 🏴󠁧󠁢󠁥󠁮󠁧󠁿 → gb-eng. Флаг может стоять в любом месте названия.
  static String? fromFlag(String name) {
    final r = name.runes.toList();
    for (var i = 0; i < r.length; i++) {
      if (_ri(r[i]) && i + 1 < r.length && _ri(r[i + 1])) {
        final c = String.fromCharCodes([r[i] - 0x1F1E6 + 97, r[i + 1] - 0x1F1E6 + 97]);
        if (c == 'uk') return 'gb';
        if (flagCodes.contains(c)) return c;
        i++;
        continue;
      }
      // Флаги Англии, Шотландии, Уэльса: 🏴 + теги-буквы + завершающий тег.
      if (r[i] == 0x1F3F4) {
        final b = StringBuffer();
        var j = i + 1;
        while (j < r.length && r[j] >= 0xE0061 && r[j] <= 0xE007A) {
          b.writeCharCode(r[j] - 0xE0061 + 97);
          j++;
        }
        final t = b.toString();
        if (t.length > 2) {
          final c = '${t.substring(0, 2)}-${t.substring(2)}';
          if (flagCodes.contains(c)) return c;
        }
      }
    }
    return null;
  }

  static bool _ri(int c) => c >= 0x1F1E6 && c <= 0x1F1FF;

  /// Название страны или города на русском или английском (с учётом падежей: «в Германии»).
  static String? fromWords(String name) {
    final low = name.toLowerCase().replaceAll('ё', 'е');
    for (final e in _patterns) {
      if (e.$1.hasMatch(low)) return e.$2;
    }
    return null;
  }

  /// Готовые выражения: основа слова в начале слова; короткие и отмеченные — только целым словом.
  static final List<(RegExp, String)> _patterns = [
    for (final e in _words)
      (
        RegExp(
          '(?<![\\p{L}])${RegExp.escape(e.$1)}${e.$1.length < 4 || e.$3 ? '(?![\\p{L}])' : ''}',
          unicode: true,
        ),
        e.$2,
      ),
  ];

  /// Код страны отдельным словом: «NL 1», «[DE]», «US-West», «UK».
  static String? fromCode(String name) {
    for (final m in RegExp(r'(?<![A-Za-z])([A-Z]{2,3})(?![A-Za-z])').allMatches(name)) {
      final t = m.group(1)!;
      final alias = _codeAliases[t];
      if (alias != null) return alias;
      if (t.length != 2 || _notCodes.contains(t)) continue;
      final c = t.toLowerCase();
      if (flagCodes.contains(c)) return c;
    }
    // В начале названия строчными: «nl-2», «de1».
    final m = RegExp(r'^([a-z]{2})[-_ ]?\d').firstMatch(name.trim());
    if (m != null && flagCodes.contains(m.group(1)) && !_notCodes.contains(m.group(1)!.toUpperCase())) {
      return m.group(1);
    }
    return null;
  }

  /// Поддомен с кодом страны: nl1.example.com, de-fra.vpn.net.
  static String? fromHost(String host) {
    final parts = host.toLowerCase().split('.');
    if (parts.length < 3 || RegExp(r'^[\d.]+$').hasMatch(host) || host.contains(':')) return null;
    final m = RegExp(r'^([a-z]{2})(?:\d+|-[a-z0-9-]+)?$').firstMatch(parts.first);
    if (m == null) return null;
    final c = m.group(1)!;
    if (c == 'uk') return 'gb';
    if (_notHostCodes.contains(c) || !flagCodes.contains(c)) return null;
    return c;
  }

  static const _codeAliases = {
    'UK': 'gb', 'USA': 'us', 'UAE': 'ae', 'ENG': 'gb-eng', 'GER': 'de', 'RUS': 'ru', 'MSK': 'ru', 'SPB': 'ru',
    'AMS': 'nl', 'NYC': 'us', 'LA': 'us',
  };

  /// Двухбуквенные слова, которые часто встречаются в названиях, но не означают страну.
  /// «GB» почти всегда означает гигабайты («Осталось 50 GB»), «WS» — транспорт WebSocket.
  static const _notCodes = {'AI', 'TV', 'IO', 'OK', 'ID', 'PC', 'TM', 'GG', 'SU', 'GB', 'WS', 'PM', 'MS', 'FM', 'VC'};
  static const _notHostCodes = {
    'my', 'me', 'in', 'is', 'it', 'to', 'no', 'be', 'do', 'so', 'at', 'am', 'an', 'as', 'by', 'im',
    'io', 'tv', 'ai', 'ws', 'cc', 'co', 'id', 'gg', 'tm', 'vc', 'fm', 'la', 'mx', 'ms', 'cx', 'cf', 'ga',
  };

  /// (основа слова, код, только целым словом). Длинные основы проверяются раньше коротких.
  static final List<(String, String, bool)> _words = [
    ..._raw.map((e) => (e.$1, e.$2, e.$3)),
  ]..sort((a, b) => b.$1.length.compareTo(a.$1.length));

  static const List<(String, String, bool)> _raw = [
    // Европа
    ('нидерланд', 'nl', false), ('голланд', 'nl', false), ('netherlands', 'nl', false), ('holland', 'nl', false),
    ('dutch', 'nl', false), ('амстердам', 'nl', false), ('amsterdam', 'nl', false), ('роттердам', 'nl', false),
    ('rotterdam', 'nl', false),
    ('герман', 'de', false), ('germany', 'de', false), ('deutschland', 'de', false), ('франкфурт', 'de', false),
    ('frankfurt', 'de', false), ('берлин', 'de', false), ('berlin', 'de', false), ('мюнхен', 'de', false),
    ('munich', 'de', false), ('münchen', 'de', false), ('нюрнберг', 'de', false), ('nuremberg', 'de', false),
    ('nürnberg', 'de', false), ('фалькенштейн', 'de', false), ('falkenstein', 'de', false), ('дюссельдорф', 'de', false),
    ('düsseldorf', 'de', false), ('dusseldorf', 'de', false), ('гамбург', 'de', false), ('hamburg', 'de', false),
    ('эстон', 'ee', false), ('estonia', 'ee', false), ('таллин', 'ee', false), ('tallinn', 'ee', false),
    ('финлян', 'fi', false), ('finland', 'fi', false), ('suomi', 'fi', false), ('хельсинк', 'fi', false),
    ('helsinki', 'fi', false),
    ('швец', 'se', false), ('sweden', 'se', false), ('sverige', 'se', false), ('стокгольм', 'se', false),
    ('stockholm', 'se', false),
    ('норвег', 'no', false), ('norway', 'no', false), ('осло', 'no', true), ('oslo', 'no', true),
    ('дания', 'dk', true), ('дании', 'dk', true), ('датск', 'dk', false), ('denmark', 'dk', false),
    ('копенгаген', 'dk', false), ('copenhagen', 'dk', false),
    ('польш', 'pl', false), ('польск', 'pl', false), ('poland', 'pl', false), ('polska', 'pl', false),
    ('варшав', 'pl', false), ('warsaw', 'pl', false),
    ('франц', 'fr', false), ('france', 'fr', false), ('париж', 'fr', false), ('paris', 'fr', false),
    ('марсел', 'fr', false), ('marseille', 'fr', false),
    ('испан', 'es', false), ('spain', 'es', false), ('españa', 'es', false), ('мадрид', 'es', false),
    ('madrid', 'es', false), ('барселон', 'es', false), ('barcelona', 'es', false),
    ('итал', 'it', false), ('italy', 'it', false), ('italia', 'it', false), ('милан', 'it', false),
    ('milan', 'it', false), ('рим', 'it', true), ('rome', 'it', true),
    ('великобритан', 'gb', false), ('британ', 'gb', false), ('united kingdom', 'gb', false), ('britain', 'gb', false),
    ('англи', 'gb', false), ('england', 'gb', false), ('лондон', 'gb', false), ('london', 'gb', false),
    ('манчестер', 'gb', false), ('manchester', 'gb', false), ('шотланд', 'gb-sct', false), ('scotland', 'gb-sct', false),
    ('ирланд', 'ie', false), ('ireland', 'ie', false), ('дублин', 'ie', false), ('dublin', 'ie', false),
    ('исланд', 'is', false), ('iceland', 'is', false), ('рейкьявик', 'is', false), ('reykjavik', 'is', false),
    ('швейцар', 'ch', false), ('switzerland', 'ch', false), ('swiss', 'ch', false), ('цюрих', 'ch', false),
    ('zurich', 'ch', false), ('zürich', 'ch', false), ('женев', 'ch', false), ('geneva', 'ch', false),
    ('австри', 'at', false), ('austria', 'at', false), ('вена', 'at', true), ('вене', 'at', true),
    ('vienna', 'at', false), ('wien', 'at', true),
    ('бельги', 'be', false), ('belgium', 'be', false), ('брюссел', 'be', false), ('brussels', 'be', false),
    ('люксембург', 'lu', false), ('luxembourg', 'lu', false),
    ('чехи', 'cz', false), ('чешск', 'cz', false), ('czech', 'cz', false), ('прага', 'cz', true), ('праге', 'cz', true),
    ('prague', 'cz', false),
    ('словаки', 'sk', false), ('slovakia', 'sk', false), ('братислав', 'sk', false), ('bratislava', 'sk', false),
    ('словени', 'si', false), ('slovenia', 'si', false), ('любляна', 'si', false), ('ljubljana', 'si', false),
    ('венгр', 'hu', false), ('hungary', 'hu', false), ('будапешт', 'hu', false), ('budapest', 'hu', false),
    ('румын', 'ro', false), ('romania', 'ro', false), ('бухарест', 'ro', false), ('bucharest', 'ro', false),
    ('болгар', 'bg', false), ('bulgaria', 'bg', false), ('sofia', 'bg', false),
    ('серби', 'rs', false), ('serbia', 'rs', false), ('белград', 'rs', false), ('belgrade', 'rs', false),
    ('хорват', 'hr', false), ('croatia', 'hr', false), ('загреб', 'hr', false), ('zagreb', 'hr', false),
    ('черногор', 'me', false), ('montenegro', 'me', false),
    ('босни', 'ba', false), ('bosnia', 'ba', false), ('македони', 'mk', false), ('macedonia', 'mk', false),
    ('албани', 'al', false), ('albania', 'al', false),
    ('греци', 'gr', false), ('greece', 'gr', false), ('афин', 'gr', false), ('athens', 'gr', false),
    ('кипр', 'cy', false), ('cyprus', 'cy', false), ('мальт', 'mt', false), ('malta', 'mt', false),
    ('португал', 'pt', false), ('portugal', 'pt', false), ('лиссабон', 'pt', false), ('lisbon', 'pt', false),
    ('латви', 'lv', false), ('latvia', 'lv', false), ('рига', 'lv', true), ('риге', 'lv', true), ('riga', 'lv', true),
    ('литв', 'lt', false), ('lithuania', 'lt', false), ('вильнюс', 'lt', false), ('vilnius', 'lt', false),
    ('молдов', 'md', false), ('молдав', 'md', false), ('moldova', 'md', false), ('кишин', 'md', false),
    ('chisinau', 'md', false),
    ('украин', 'ua', false), ('ukraine', 'ua', false), ('киев', 'ua', false), ('kyiv', 'ua', false),
    ('kiev', 'ua', false),
    ('беларус', 'by', false), ('белорус', 'by', false), ('belarus', 'by', false), ('минск', 'by', false),
    ('minsk', 'by', false),
    ('росси', 'ru', false), ('russia', 'ru', false), ('рф', 'ru', true), ('москв', 'ru', false),
    ('moscow', 'ru', false), ('санкт-петербург', 'ru', false), ('петербург', 'ru', false), ('питер', 'ru', true),
    ('saint petersburg', 'ru', false), ('st. petersburg', 'ru', false),
    ('европ', 'eu', false), ('europe', 'eu', false),
    // Кавказ и Центральная Азия
    ('армени', 'am', false), ('armenia', 'am', false), ('ереван', 'am', false), ('yerevan', 'am', false),
    ('грузи', 'ge', false), ('georgia', 'ge', false), ('тбилиси', 'ge', false), ('tbilisi', 'ge', false),
    ('азербайджан', 'az', false), ('azerbaijan', 'az', false), ('баку', 'az', true), ('baku', 'az', true),
    ('казахстан', 'kz', false), ('kazakhstan', 'kz', false), ('алмат', 'kz', false), ('almaty', 'kz', false),
    ('астан', 'kz', false), ('astana', 'kz', false),
    ('узбекистан', 'uz', false), ('uzbekistan', 'uz', false), ('ташкент', 'uz', false), ('tashkent', 'uz', false),
    ('кыргызстан', 'kg', false), ('киргиз', 'kg', false), ('kyrgyzstan', 'kg', false), ('бишкек', 'kg', false),
    ('bishkek', 'kg', false),
    ('таджикистан', 'tj', false), ('tajikistan', 'tj', false), ('туркмен', 'tm', false), ('turkmenistan', 'tm', false),
    ('монгол', 'mn', false), ('mongolia', 'mn', false),
    // Ближний Восток
    ('турци', 'tr', false), ('turkey', 'tr', false), ('türkiye', 'tr', false), ('turkiye', 'tr', false),
    ('стамбул', 'tr', false), ('istanbul', 'tr', false), ('анкар', 'tr', false), ('ankara', 'tr', false),
    ('израил', 'il', false), ('israel', 'il', false), ('тель-авив', 'il', false), ('tel aviv', 'il', false),
    ('эмират', 'ae', false), ('оаэ', 'ae', true), ('emirates', 'ae', false), ('дубай', 'ae', false),
    ('dubai', 'ae', false),
    ('катар', 'qa', false), ('qatar', 'qa', false), ('саудовск', 'sa', false), ('saudi', 'sa', false),
    ('иран', 'ir', true), ('ирана', 'ir', true), ('iran', 'ir', true), ('ирак', 'iq', true), ('iraq', 'iq', true),
    ('египет', 'eg', false), ('египт', 'eg', false), ('egypt', 'eg', false),
    // Азия и Океания
    ('сингапур', 'sg', false), ('singapore', 'sg', false),
    ('гонконг', 'hk', false), ('hong kong', 'hk', false), ('hongkong', 'hk', false),
    ('япони', 'jp', false), ('japan', 'jp', false), ('токио', 'jp', false), ('tokyo', 'jp', false),
    ('осак', 'jp', false), ('osaka', 'jp', false),
    ('южная коре', 'kr', false), ('коре', 'kr', false), ('korea', 'kr', false), ('сеул', 'kr', false),
    ('seoul', 'kr', false),
    ('кита', 'cn', false), ('china', 'cn', false), ('шанха', 'cn', false), ('shanghai', 'cn', false),
    ('пекин', 'cn', false), ('beijing', 'cn', false),
    ('тайван', 'tw', false), ('taiwan', 'tw', false), ('тайбэй', 'tw', false), ('taipei', 'tw', false),
    ('индонез', 'id', false), ('indonesia', 'id', false), ('джакарт', 'id', false), ('jakarta', 'id', false),
    ('индии', 'in', true), ('индия', 'in', true), ('india', 'in', true), ('мумбаи', 'in', false),
    ('mumbai', 'in', false),
    ('вьетнам', 'vn', false), ('vietnam', 'vn', false), ('таиланд', 'th', false), ('тайланд', 'th', false),
    ('thailand', 'th', false), ('бангкок', 'th', false), ('bangkok', 'th', false),
    ('малайзи', 'my', false), ('malaysia', 'my', false), ('филиппин', 'ph', false), ('philippines', 'ph', false),
    ('пакистан', 'pk', false), ('pakistan', 'pk', false), ('бангладеш', 'bd', false), ('bangladesh', 'bd', false),
    ('австрали', 'au', false), ('australia', 'au', false), ('сидне', 'au', false), ('sydney', 'au', false),
    ('мельбурн', 'au', false), ('melbourne', 'au', false),
    ('новая зеланди', 'nz', false), ('новой зеланди', 'nz', false), ('new zealand', 'nz', false),
    // Америка и Африка
    ('сша', 'us', true), ('америк', 'us', false), ('united states', 'us', false), ('america', 'us', false),
    ('нью-йорк', 'us', false), ('new york', 'us', false), ('эшберн', 'us', false), ('ashburn', 'us', false),
    ('даллас', 'us', false), ('dallas', 'us', false), ('лос-андж', 'us', false), ('los angeles', 'us', false),
    ('майами', 'us', false), ('miami', 'us', false), ('чикаго', 'us', false), ('chicago', 'us', false),
    ('сиэтл', 'us', false), ('seattle', 'us', false), ('сан-франциско', 'us', false), ('san francisco', 'us', false),
    ('silicon valley', 'us', false), ('кремниев', 'us', false),
    ('канад', 'ca', false), ('canada', 'ca', false), ('торонто', 'ca', false), ('toronto', 'ca', false),
    ('монреал', 'ca', false), ('montreal', 'ca', false), ('ванкувер', 'ca', false), ('vancouver', 'ca', false),
    ('мексик', 'mx', false), ('mexico', 'mx', false), ('бразили', 'br', false), ('brazil', 'br', false),
    ('сан-паулу', 'br', false), ('sao paulo', 'br', false), ('são paulo', 'br', false),
    ('аргентин', 'ar', false), ('argentina', 'ar', false), ('чили', 'cl', true), ('chile', 'cl', true),
    ('колумби', 'co', false), ('colombia', 'co', false), ('перу', 'pe', true), ('peru', 'pe', true),
    ('юар', 'za', true), ('южная африк', 'za', false), ('south africa', 'za', false),
    ('нигери', 'ng', false), ('nigeria', 'ng', false), ('кения', 'ke', true), ('кении', 'ke', true), ('kenya', 'ke', false),
    ('марокко', 'ma', false), ('morocco', 'ma', false),
  ];
}
