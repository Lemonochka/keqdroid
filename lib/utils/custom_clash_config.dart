import 'dart:convert';

import 'package:yaml/yaml.dart';

/// Готовый конфиг Clash/mihomo в роли сервера — то, что панели отдают
/// clash-клиентам вместо списка ссылок: свои `proxies`, `proxy-groups`, `rules`
/// и `dns`. Аналог [CustomXrayConfig] на другом ядре: исполняет такой конфиг
/// только mihomo, xray его формата не знает вовсе.
///
/// Хранится и отдаётся ядру как JSON. YAML 1.2 — надмножество JSON, mihomo
/// разбирает его тем же парсером, а всё остальное приложение работает с
/// `jsonDecode` и не обязано знать про YAML. Разбор YAML нужен ровно один раз,
/// на импорте.
///
/// Инбаунды автора не берём никогда — порты и креды диктует приложение (их ждёт
/// tun2socks). Всё остальное авторское: за роутингом такой конфиг и берут.
class CustomClashConfig {
  CustomClashConfig._(this.map);

  /// Разобранный конфиг. [buildSessionConfig] работает с копией.
  final Map<String, dynamic> map;

  /// Ключ, по которому конфиг узнаётся: без прокси это не конфиг клиента, а
  /// что угодно ещё (метаданные подписки, ответ панели, кусок sing-box).
  static const _requiredKey = 'proxies';

  /// Имя профиля. У Clash своего поля нет, но панели повсеместно кладут его в
  /// корень — забираем те же ключи, что и у xray-конфига.
  static const _remarkKeys = ['remarks', 'remark', 'name', 'profile-name'];

  /// Ключи инбаундов и всего, что делает ядро сервером или владельцем TUN.
  ///
  /// `tun` — самый опасный: с ним ядро полезет поднимать СВОЁ устройство
  /// поверх того, которое уже держит VpnService, и сессия умрёт на старте.
  /// Порты — наши: в них ходит tun2socks с известными ему кредами.
  static const _strippedKeys = {
    'tun',
    'port',
    'socks-port',
    'mixed-port',
    'redir-port',
    'tproxy-port',
    'bind-address',
    'authentication',
    'skip-auth-prefixes',
    'lan-allowed-ips',
    'lan-disallowed-ips',
    'listeners',
    'external-controller',
    'external-controller-tls',
    'external-controller-unix',
    'external-controller-pipe',
    'external-controller-cors',
    'external-ui',
    'external-ui-url',
    'external-ui-name',
    'secret',
    'tls',
    'interface-name',
    'routing-mark',
    // Автообновление geo — это поход в сеть до того, как туннель поднялся.
    'geo-auto-update',
    'geo-update-interval',
    'geox-url',
  };

  /// Похоже ли на конфиг Clash. Дешёвая отсечка перед полным разбором: её
  /// зовут из `ServerItem.protocol`, то есть на каждую перерисовку плитки.
  static bool looksLikeClash(String raw) {
    final text = raw.trimLeft();
    if (text.isEmpty) return false;
    if (text.startsWith('{')) {
      // JSON-форма: `proxies` среди корневых ключей — либо `proxy-providers`,
      // когда узлы лежат за ссылкой и ключа `proxies` в конфиге нет вовсе.
      // Без второго варианта такой профиль, сохранённый сервером, переставал
      // узнаваться и уезжал в «неизвестный формат» — то есть на xray.
      return RegExp(r'"(proxies|proxy-providers)"\s*:').hasMatch(text);
    }
    // YAML: ключ верхнего уровня, то есть в начале строки и без отступа.
    return RegExp(r'^(proxies|proxy-groups|proxy-providers)\s*:', multiLine: true)
        .hasMatch(text);
  }

  /// Разбирает конфиг (YAML или JSON). null — не пригодный clash-конфиг.
  /// Причину для пользователя даёт [describeProblem].
  static CustomClashConfig? tryParse(String raw) {
    final decoded = _decode(raw);
    if (decoded == null) return null;
    return _fromMap(decoded);
  }

  static CustomClashConfig? _fromMap(Map<String, dynamic> map) {
    // У прокси Clash обязателен `type` и адрес: без них это не список серверов,
    // а что-то другое, случайно попавшее под тот же ключ.
    if (proxiesOf(map).any((p) =>
        p['type'] != null &&
        (p['server']?.toString().trim().isNotEmpty ?? false))) {
      return CustomClashConfig._(map);
    }
    // Узлы бывают не в конфиге, а за ним: `proxy-providers` — это ссылка на
    // список, который ядро скачивает само. Панели отдают такие профили
    // clash-клиентам сплошь и рядом, и внутри у них нет ни одного `proxies`.
    // Разбирать их на серверы нечем (списка ещё нет), зато mihomo исполняет
    // такой конфиг ровно так, как написал автор.
    if (usesProviderNodes(map)) return CustomClashConfig._(map);
    return null;
  }

  /// Узлы приезжают из `proxy-providers`, а не лежат в конфиге.
  ///
  /// Группы обязательны: правило роутинга должно куда-то указывать, а с
  /// провайдерами единственная осмысленная цель — группа. Без них
  /// [primaryTarget] вернул бы `DIRECT`, и весь трафик молча пошёл бы мимо
  /// туннеля — то есть подключение «работает», а прокси нет.
  static bool usesProviderNodes(Map<String, dynamic> map) {
    final providers = map['proxy-providers'];
    if (providers is! Map || providers.isEmpty) return false;
    final groups = map['proxy-groups'];
    return groups is List && groups.isNotEmpty;
  }

  /// Конфиг держит узлы в `proxy-providers`: своего адреса у него нет, и это
  /// не признак болванки — просто список ещё не скачан.
  bool get usesProviders => proxies.isEmpty && usesProviderNodes(map);

  /// Причина, почему конфиг не годится сервером — для сообщения пользователю.
  ///
  /// Текст обязан называть КОНКРЕТНУЮ причину: «формат не поддерживается» про
  /// Clash — прямая неправда, мы его исполняем, и с таким ответом непонятно,
  /// что вообще делать. Сорванный разбор отдаёт сообщение самого парсера: у
  /// панелей payload бывает битым, и это единственное, по чему видно, чем.
  static String? describeProblem(String raw) {
    final decoded = _decode(raw);
    if (decoded == null) {
      final reason = _decodeError(raw);
      return reason == null
          ? 'not a Clash config: expected a YAML or JSON object'
          : 'YAML could not be parsed ($reason)';
    }
    if (_fromMap(decoded) != null) return null;
    if (proxiesOf(decoded).isEmpty) {
      final providers = decoded['proxy-providers'];
      if (providers is Map && providers.isNotEmpty) {
        return 'nodes live in "proxy-providers" but the config has no '
            '"proxy-groups" to route through';
      }
      return 'no "proxies" and no "proxy-providers" — nothing to connect '
          'through';
    }
    return '"proxies" carry no type/server — this is not a proxy list';
  }

  /// Сообщение YAML-парсера, если разбор сорвался; null — разобралось (просто
  /// не в карту). Сообщения бывают многострочными и очень длинными — режем.
  static String? _decodeError(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return 'empty response';
    try {
      loadYaml(text);
      return null;
    } on Object catch (e) {
      final message = e.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      return message.length > 200 ? '${message.substring(0, 200)}…' : message;
    }
  }

  /// Все конфиги из одного payload подписки. У Clash это всегда один документ,
  /// но форма списка встречается у панелей, отдающих несколько профилей.
  static List<String> extractConfigs(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const [];
    final decoded = _decodeRaw(text);
    if (decoded is Map<String, dynamic>) {
      final config = _fromMap(decoded);
      return config == null ? const [] : [config.encode()];
    }
    if (decoded is List) {
      final out = <String>[];
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final config = _fromMap(item);
        if (config != null) out.add(config.encode());
      }
      return out;
    }
    return const [];
  }

  static Map<String, dynamic>? _decode(String raw) {
    final decoded = _decodeRaw(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  /// YAML или JSON → обычные dart-типы. Сначала JSON: он строже, быстрее и
  /// покрывает конфиги, которые панель отдаёт в json-форме.
  static Object? _decodeRaw(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('{') || text.startsWith('[')) {
      try {
        return _plain(jsonDecode(text));
      } on Object {
        // Не JSON — пробуем как YAML: он допускает то, что jsonDecode не берёт.
      }
    }
    try {
      return _plain(loadYaml(text));
    } on Object {
      return null;
    }
  }

  /// YamlMap/YamlList/скаляры → Map/List/скаляры. Ключи приводим к строкам:
  /// YAML разрешает и числовые, а дальше по коду везде строковые.
  static Object? _plain(Object? node) {
    if (node is Map) {
      return <String, dynamic>{
        for (final entry in node.entries)
          entry.key.toString(): _plain(entry.value),
      };
    }
    if (node is List) return [for (final item in node) _plain(item)];
    return node;
  }

  /// Конфиг как текст для хранения и правки руками.
  String encode() => const JsonEncoder.withIndent('  ').convert(map);

  static List<Map<String, dynamic>> proxiesOf(Map<String, dynamic> map) {
    final raw = map[_requiredKey];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map) item.cast<String, dynamic>(),
    ];
  }

  List<Map<String, dynamic>> get proxies => proxiesOf(map);

  String get remarks {
    for (final key in _remarkKeys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  /// Куда слать трафик, который наши правила отправляют в прокси.
  ///
  /// Правильный ответ — то же, что выбирает сам конфиг: первая группа
  /// (у панелей это селектор вида «Proxy»/«🚀 节点选择»), а если групп нет —
  /// первый прокси. Ссылаться на группу важнее, чем на узел: пользователь
  /// переключает узлы внутри неё, и правило обязано ехать за его выбором.
  String get primaryTarget {
    final groups = map['proxy-groups'];
    if (groups is List) {
      for (final group in groups) {
        if (group is! Map) continue;
        final name = group['name']?.toString().trim() ?? '';
        if (name.isNotEmpty) return name;
      }
    }
    final first = proxies.isEmpty ? null : proxies.first;
    final name = first?['name']?.toString().trim() ?? '';
    return name.isEmpty ? 'DIRECT' : name;
  }

  /// Адрес и порт первого прокси. По ним идёт tcp-пинг и исключение сервера из
  /// туннеля; для конфига с десятком узлов это лишь «первый», но другого
  /// осмысленного ответа у такого сервера нет.
  ({String address, int port}) get endpoint {
    for (final proxy in proxies) {
      final address = proxy['server']?.toString().trim() ?? '';
      if (address.isEmpty) continue;
      final port = int.tryParse(proxy['port']?.toString() ?? '') ?? 0;
      return (address: address, port: port);
    }
    return (address: '', port: 0);
  }

  String get address => endpoint.address;
  int get port => endpoint.port;

  /// Конфиг сессии: авторские прокси/группы/правила/dns + наши инбаунд,
  /// снифер, api и списки роутинга.
  ///
  /// [prependRules] — раньше авторских (защита LAN-инбаундов и сам сервер:
  /// правило против круга обязано решать первым).
  /// [appendRules] — после авторских, но ПЕРЕД их `MATCH`: правило после
  /// catch-all не сработает никогда, а в конфигах Clash catch-all есть почти
  /// всегда.
  Map<String, dynamic> buildSessionConfig({
    required Map<String, dynamic> inbound,
    required Map<String, dynamic> sniffer,
    required String logLevel,
    Map<String, dynamic>? dns,
    List<String> prependRules = const [],
    List<String> appendRules = const [],
    Map<String, dynamic> extra = const {},
  }) {
    final out = Map<String, dynamic>.from(map);
    for (final key in _remarkKeys) {
      out.remove(key);
    }
    for (final key in _strippedKeys) {
      out.remove(key);
    }

    out.addAll(inbound);
    out['log-level'] = logLevel;
    out['sniffer'] = sniffer;
    // Базы geo у нас вшитые (v2fly `.dat`), ядро берёт их из рабочего каталога.
    out['geodata-mode'] = true;
    out['geo-auto-update'] = false;
    out['find-process-mode'] = 'off';

    // DNS автора уважаем, но только если он включён: с выключенным ядро идёт в
    // системный резолвер, а на Android его нет (`/etc/resolv.conf` отсутствует),
    // и не резолвится даже адрес самого сервера.
    final authorDns = out['dns'];
    final authorDnsEnabled =
        authorDns is Map && authorDns['enable'] == true &&
            (authorDns['nameserver'] as List?)?.isNotEmpty == true;
    if (!authorDnsEnabled && dns != null) out['dns'] = dns;

    out['rules'] = _mergeRules(
      authorRules: _rulesOf(out),
      prepend: prependRules,
      append: appendRules,
    );

    out.addAll(extra);
    return out;
  }

  static List<String> _rulesOf(Map<String, dynamic> map) {
    final raw = map['rules'];
    if (raw is! List) return const [];
    return [for (final rule in raw) rule.toString()];
  }

  /// Склейка правил: наши защитные — первыми, наши списки — перед авторским
  /// `MATCH`, авторский `MATCH` остаётся последним. Своего `MATCH` не
  /// добавляем: у автора он почти всегда есть, а если нет — ядро само шлёт
  /// несовпавшее в `DIRECT` (`tunnel.match`), и это его решение, не наше.
  static List<String> _mergeRules({
    required List<String> authorRules,
    required List<String> prepend,
    required List<String> append,
  }) {
    final matchIndex = authorRules.indexWhere(
      (rule) => rule.trimLeft().toUpperCase().startsWith('MATCH'),
    );
    if (matchIndex < 0) {
      return [...prepend, ...authorRules, ...append];
    }
    return [
      ...prepend,
      ...authorRules.take(matchIndex),
      ...append,
      ...authorRules.skip(matchIndex),
    ];
  }
}
