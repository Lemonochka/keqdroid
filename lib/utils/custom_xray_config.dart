import 'dart:convert';

import 'geo_asset_index.dart';
import 'geo_rule_sanitizer.dart';

/// Готовый конфиг xray в роли сервера — то, что провайдеры кладут в подписку
/// вместо ссылки: свои аутбаунды, свой роутинг, свой dns (в v2rayNG такой
/// сервер называется CUSTOM, имя лежит в корневом `remarks`).
///
/// Инбаунды автора не берём никогда: локальные порты и креды диктует
/// приложение — их ждёт нативная часть (tun2socks на Android, sing-box внутри
/// keqrnel на десктопе поднимает те же порты из xray-конфига). Всё остальное —
/// роутинг, dns, цепочки аутбаундов — остаётся авторским: в этом весь смысл
/// такого сервера.
class CustomXrayConfig {
  CustomXrayConfig._(this.json);

  /// Разобранный конфиг. Копия: [buildSessionConfig] правит её на месте.
  final Map<String, dynamic> json;

  /// Аутбаунды без адреса сервера — от них нечего брать как endpoint.
  static const _localOutboundProtocols = {
    'freedom',
    'blackhole',
    'dns',
    'loopback',
  };

  /// Корневые ключи, по которым конфиг узнаётся как xray-конфиг, а не как
  /// произвольный json из подписки (метаданные, ответ панели и т.п.).
  static const _requiredKey = 'outbounds';

  /// Имя сервера: v2rayNG держит его в корне конфига, и ядро лишний ключ
  /// игнорирует. Порядок — от самого распространённого к редкому.
  static const _remarkKeys = ['remarks', 'remark', 'ps', 'name', 'label'];

  /// Быстрая отсечка «это вообще json-объект, а не ссылка».
  static bool looksLikeJson(String raw) => raw.trimLeft().startsWith('{');

  /// Разбирает конфиг. null — это не пригодный xray-конфиг (не json, нет
  /// аутбаундов, sing-box). Причину для пользователя даёт [describeProblem].
  static CustomXrayConfig? tryParse(String raw) {
    if (!looksLikeJson(raw)) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on Object {
      return null;
    }
    if (decoded is! Map) return null;
    final map = _asStringMap(decoded);
    return _fromMap(map);
  }

  static CustomXrayConfig? _fromMap(Map<String, dynamic> map) {
    final outbounds = _outboundsOf(map);
    if (outbounds.isEmpty) return null;
    // sing-box описывает аутбаунд полем `type`, xray — `protocol`. Похожие
    // конфиги, но наше ядро исполняет только второй.
    if (!outbounds.any((o) => o.containsKey('protocol'))) return null;
    return CustomXrayConfig._(map);
  }

  /// Причина, почему json не годится сервером — для сообщения пользователю.
  /// null — годится.
  static String? describeProblem(String raw) {
    if (!looksLikeJson(raw)) return 'Not a JSON object';
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on Object catch (e) {
      return 'Invalid JSON: $e';
    }
    if (decoded is! Map) return 'JSON config must be an object';
    final map = _asStringMap(decoded);
    final outbounds = _outboundsOf(map);
    if (outbounds.isEmpty) {
      return 'JSON config has no "outbounds" — this is not an Xray config';
    }
    if (!outbounds.any((o) => o.containsKey('protocol'))) {
      return 'This looks like a sing-box config (outbounds use "type"). '
          'Only Xray JSON configs are supported.';
    }
    return null;
  }

  /// Все конфиги из одного payload: объект — один, массив — по элементу.
  /// Возвращает исходные json-строки (компактные), пригодные как config сервера.
  static List<String> extractConfigs(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on Object {
      return const [];
    }
    if (decoded is Map) {
      final config = _fromMap(_asStringMap(decoded));
      return config == null ? const [] : [config.encode()];
    }
    if (decoded is List) {
      final out = <String>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final config = _fromMap(_asStringMap(item));
        if (config != null) out.add(config.encode());
      }
      return out;
    }
    return const [];
  }

  /// Конфиг как текст для хранения/редактирования: с отступами, чтобы правка
  /// вручную в редакторе была читаемой.
  String encode() => const JsonEncoder.withIndent('  ').convert(json);

  /// Имя из корневого `remarks` (v2rayNG-совместимо). Пусто — имени нет.
  String get remarks {
    for (final key in _remarkKeys) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  /// Аутбаунд, который ядро считает основным: у xray это первый в списке (он
  /// же дефолтный, когда ни одно правило не совпало), но `freedom`/`blackhole`
  /// в начале списка встречаются — их пропускаем.
  Map<String, dynamic>? get primaryOutbound {
    final outbounds = _outboundsOf(json);
    for (final outbound in outbounds) {
      final protocol = outbound['protocol']?.toString().toLowerCase() ?? '';
      if (_localOutboundProtocols.contains(protocol)) continue;
      return outbound;
    }
    return outbounds.isEmpty ? null : outbounds.first;
  }

  /// Тег основного аутбаунда — им пингуем (весь трафик пробы уходит туда).
  String get primaryOutboundTag {
    final tag = primaryOutbound?['tag']?.toString().trim() ?? '';
    return tag.isEmpty ? 'proxy' : tag;
  }

  /// Адрес и порт сервера из основного аутбаунда. Нужны не для красоты:
  /// по адресу идёт tcp-пинг и исключение сервера из TUN на десктопе
  /// (`serverIpToExclude`), иначе коннект ядра к серверу зайдёт в петлю.
  ({String address, int port}) get endpoint {
    for (final outbound in _outboundsOf(json)) {
      final protocol = outbound['protocol']?.toString().toLowerCase() ?? '';
      if (_localOutboundProtocols.contains(protocol)) continue;
      final found = _endpointOf(outbound);
      if (found != null) return found;
    }
    return (address: '', port: 0);
  }

  String get address => endpoint.address;
  int get port => endpoint.port;

  /// Конфиг для сессии: авторские аутбаунды/роутинг/dns + наши инбаунды и
  /// уровень логов.
  ///
  /// [inbounds] — инбаунды приложения (их уже собрал генератор конфига).
  /// [lanRules] — правила, ограничивающие вход в LAN-инбаунды частными
  /// адресами; идут первыми, иначе открытый на 0.0.0.0 инбаунд пускал бы
  /// кого угодно (у автора конфига правил для наших тегов нет).
  /// [logLevel] — из настроек: без `info` ядро не печатает решения роутинга, и
  /// экран «Соединения» остаётся без правил.
  /// [geoIndex] — чем чистим `geoip:`/`geosite:`-коды, которых нет в
  /// поставляемых базах: один такой код роняет разбор ВСЕГО конфига, и
  /// подключение умирает с «SOCKS port not ready» (см. geo_rule_sanitizer).
  Map<String, dynamic> buildSessionConfig({
    required List<Map<String, dynamic>> inbounds,
    required String logLevel,
    List<Map<String, dynamic>> lanRules = const [],
    GeoAssetIndex? geoIndex,
  }) {
    final out = Map<String, dynamic>.from(json);
    // Наше поле имени ядру не нужно — не оставляем ему повода спорить.
    for (final key in _remarkKeys) {
      out.remove(key);
    }

    final log = Map<String, dynamic>.from(
      (out['log'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
    log['loglevel'] = logLevel;
    out['log'] = log;

    out['inbounds'] = inbounds;

    if (lanRules.isNotEmpty) {
      final routing = Map<String, dynamic>.from(
        (out['routing'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
      final rules = <Map<String, dynamic>>[
        ...lanRules,
        ...?_rulesOf(routing),
      ];
      routing['rules'] = rules;
      out['routing'] = routing;
    }

    if (geoIndex != null && !geoIndex.isEmpty) {
      stripUnknownGeoFromConfig(out, geoIndex);
    }
    return out;
  }

  /// Конфиг для эфемерного пинга: авторские аутбаунды (вместе с цепочкой), но
  /// роутинг наш — вся проба уходит в основной аутбаунд, иначе авторское
  /// правило могло бы увести её напрямую и «пинг сервера» мерил бы не сервер.
  Map<String, dynamic> buildPingConfig({
    required List<Map<String, dynamic>> inbounds,
    required List<Map<String, dynamic>> rules,
  }) {
    final outbounds = _outboundsOf(json);
    return <String, dynamic>{
      'log': {'loglevel': 'none'},
      'dns': {
        'servers': ['8.8.8.8', '1.1.1.1'],
        'queryStrategy': 'UseIPv4',
      },
      'inbounds': inbounds,
      'outbounds': outbounds,
      'routing': {
        'domainStrategy': 'AsIs',
        'rules': rules,
      },
    };
  }

  static Map<String, dynamic> _asStringMap(Map<dynamic, dynamic> raw) =>
      <String, dynamic>{for (final e in raw.entries) e.key.toString(): e.value};

  static List<Map<String, dynamic>> _outboundsOf(Map<String, dynamic> map) {
    final raw = map[_requiredKey];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map) _asStringMap(item),
    ];
  }

  static List<Map<String, dynamic>>? _rulesOf(Map<String, dynamic> routing) {
    final raw = routing['rules'];
    if (raw is! List) return null;
    return [
      for (final item in raw)
        if (item is Map) _asStringMap(item),
    ];
  }

  /// Адрес сервера из аутбаунда. Форм несколько: `vnext` (vless/vmess),
  /// `servers` (trojan/ss/socks/http), плоские `address`/`port` (так пишет наш
  /// генератор под xray 26+) и `peers[].endpoint` (wireguard).
  static ({String address, int port})? _endpointOf(
    Map<String, dynamic> outbound,
  ) {
    final settings = outbound['settings'];
    if (settings is! Map) return null;
    final s = _asStringMap(settings);

    for (final key in const ['vnext', 'servers']) {
      final list = s[key];
      if (list is! List) continue;
      for (final item in list) {
        if (item is! Map) continue;
        final entry = _endpointFields(_asStringMap(item));
        if (entry != null) return entry;
      }
    }

    final flat = _endpointFields(s);
    if (flat != null) return flat;

    final peers = s['peers'];
    if (peers is List) {
      for (final peer in peers) {
        if (peer is! Map) continue;
        final endpoint = _asStringMap(peer)['endpoint']?.toString() ?? '';
        final split = _splitHostPort(endpoint);
        if (split != null) return split;
      }
    }
    return null;
  }

  static ({String address, int port})? _endpointFields(
    Map<String, dynamic> map,
  ) {
    final address = (map['address'] ?? map['host'] ?? '').toString().trim();
    if (address.isEmpty) return null;
    final port = int.tryParse(map['port']?.toString() ?? '') ?? 0;
    return (address: address, port: port);
  }

  /// `host:port` / `[v6]:port` из wireguard-endpoint.
  static ({String address, int port})? _splitHostPort(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final colon = value.lastIndexOf(':');
    if (colon <= 0) return null;
    final host = value.substring(0, colon).replaceAll(RegExp(r'^\[|\]$'), '');
    final port = int.tryParse(value.substring(colon + 1)) ?? 0;
    if (host.isEmpty) return null;
    return (address: host, port: port);
  }
}

/// Выкидывает из готового конфига `geoip:`/`geosite:`-коды, которых нет в
/// поставляемых базах, — правит [config] на месте.
///
/// Своя реализация вместо [stripUnknownGeoTokens]: тот работает с текстовыми
/// списками настроек, а здесь коды разбросаны по правилам роутинга и dns
/// авторского конфига. Цена ошибки та же: неизвестный код роняет разбор всего
/// конфига, и ядро не поднимается вовсе.
///
/// Правило, у которого после чистки не осталось ни одного условия, удаляем
/// целиком — xray на «this rule has no effective fields» тоже выходит.
List<String> stripUnknownGeoFromConfig(
  Map<String, dynamic> config,
  GeoAssetIndex index,
) {
  final dropped = <String>[];
  if (index.isEmpty) return dropped;

  /// Чистит список токенов; null — списка не было, [] — не осталось ничего.
  List<String>? clean(Object? raw) {
    if (raw is! List) return null;
    final kept = <String>[];
    for (final item in raw) {
      final token = item?.toString().trim() ?? '';
      if (token.isEmpty) continue;
      if (isKnownGeoToken(token, index)) {
        kept.add(token);
      } else {
        dropped.add(token);
      }
    }
    return kept;
  }

  final routing = config['routing'];
  if (routing is Map) {
    final rules = routing['rules'];
    if (rules is List) {
      final keptRules = <Object?>[];
      for (final rule in rules) {
        if (rule is! Map) {
          keptRules.add(rule);
          continue;
        }
        var lostCondition = false;
        for (final field in const ['domain', 'ip']) {
          final original = rule[field];
          final cleaned = clean(original);
          if (cleaned == null) continue;
          if (cleaned.isEmpty) {
            rule.remove(field);
            if (original is List && original.isNotEmpty) lostCondition = true;
          } else {
            rule[field] = cleaned;
          }
        }
        // Условие вычистилось ЦЕЛИКОМ — правило удаляем, даже если другие
        // условия в нём остались: без вычищенного оно стало ШИРЕ задуманного.
        // `{ip: [geoip:sberbank], port: 443 → direct}` иначе превратилось бы в
        // «весь трафик на 443 напрямую». Урезать правило можно, расширять — нет.
        //
        // Правило вообще без условий тоже выкидываем: xray на таком выходит
        // с «this rule has no effective fields».
        if (lostCondition || !_ruleHasCondition(rule)) continue;
        keptRules.add(rule);
      }
      routing['rules'] = keptRules;
    }
  }

  final dns = config['dns'];
  if (dns is Map) {
    final servers = dns['servers'];
    if (servers is List) {
      final keptServers = <Object?>[];
      for (final server in servers) {
        if (server is! Map) {
          keptServers.add(server);
          continue;
        }
        final domains = clean(server['domains']);
        // Сервер с доменами — точечный: без них он стал бы общим для всех
        // запросов и подменил бы авторский порядок. Такой выкидываем целиком.
        if (domains != null && domains.isEmpty) continue;
        if (domains != null) server['domains'] = domains;
        // То же и с фильтром ответов: убрать пустой `expectIPs` значит принимать
        // от этого сервера любой адрес — шире, чем хотел автор.
        var lostFilter = false;
        for (final field in const ['expectIPs', 'expectedIPs']) {
          final original = server[field];
          final ips = clean(original);
          if (ips == null) continue;
          if (ips.isEmpty) {
            server.remove(field);
            if (original is List && original.isNotEmpty) lostFilter = true;
          } else {
            server[field] = ips;
          }
        }
        if (lostFilter) continue;
        keptServers.add(server);
      }
      dns['servers'] = keptServers;
    }
  }

  return dropped;
}

/// Поля-условия правила роутинга xray. Без хотя бы одного ядро отказывается
/// разбирать конфиг («this rule has no effective fields»). `ruleTag` и
/// `domainMatcher` условиями не являются — это метки, их тут нет намеренно.
bool _ruleHasCondition(Map<dynamic, dynamic> rule) => const [
      'domain',
      'ip',
      'port',
      'sourcePort',
      'network',
      'source',
      'user',
      'inboundTag',
      'protocol',
      'attrs',
    ].any((field) {
      final value = rule[field];
      if (value == null) return false;
      if (value is Iterable) return value.isNotEmpty;
      if (value is String) return value.trim().isNotEmpty;
      if (value is Map) return value.isNotEmpty;
      return true;
    });
