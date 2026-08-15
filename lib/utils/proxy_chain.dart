import 'dart:convert';

/// Цепочка прокси — несколько серверов подряд: устройство подключается к
/// первому узлу, первый узел дотягивается до второго, и так до последнего;
/// последний и есть тот, чей адрес видят сайты.
///
/// ## Как это исполняется ядром
///
/// Цепочка целиком живёт в xray-части конфига и собирается через
/// `streamSettings.sockopt.dialerProxy` — тег ДРУГОГО аутбаунда, через который
/// этот аутбаунд дозванивается до своего сервера
/// (`transport/internet/dialer.go`, `DialSystem` → `redirect`). Роутинг при
/// этом не опрашивается: соединение уходит прямо в указанный хендлер, поэтому
/// правила «домен → proxy/direct» на внутренние звенья не влияют.
///
/// Соседний способ, `outbound.proxySettings.tag`, здесь не годится: без
/// `transportLayer: true` он выбрасывает собственный transport узла (REALITY,
/// XHTTP, sockopt), а с ним ядро всё равно переписывает настройку в
/// `sockopt.dialerProxy` (`infra/conf/xray.go`). Одновременно задавать оба поля
/// ядро запрещает («proxySettings.tag is conflicted with sockopt.dialerProxy»).
///
/// Ровно поэтому цепочка одинаково работает на обеих платформах: на Android
/// конфиг исполняет libxray, на десктопе — встроенный в keqrnel xray-инстанс
/// (`core.StartInstance` поверх того же xray-core), а sing-box-часть про
/// цепочку вообще не знает — для неё это всё тот же аутбаунд `proxy`.
///
/// ## Формат хранения
///
/// Цепочка живёт в списке серверов обычным [ServerItem]-ом, у которого в
/// `config` лежит `keqchain://<base64url(json)>`. Так она бесплатно получает
/// всё, что уже умеет список: выбор активного, закрепление, пинг, сортировку,
/// меню трея, хранение. json:
///
/// ```json
/// {"v":1,"name":"DE → JP","hops":[{"id":"<serverId>","name":"DE-1","config":"vless://…"}]}
/// ```
///
/// `id` — ссылка на сервер в списке, `config` — снимок его ссылки на момент
/// сборки. Снимок нужен, потому что узел может уехать вместе с подпиской: тогда
/// цепочка продолжает работать по последней известной ссылке, а не разваливается
/// (см. [refreshed] — она же подтягивает свежие ссылки, когда сервер на месте).
class ProxyChainConfig {
  static const String scheme = 'keqchain';
  static const String _prefix = '$scheme://';

  /// Разумный потолок. Каждое звено — это ещё один полный proxy-хоп: задержка
  /// складывается, и после 4–5 узлов цепочка обычно уже неюзабельна.
  static const int maxHops = 8;

  /// Протоколы, которые умеют быть узлом. `awg` идёт мимо xray-пайплайна
  /// (своё ядро владеет TUN/SOCKS), `custom` — это целый конфиг со своим
  /// роутингом, `chain` — сама цепочка; вкладывать их некуда.
  static const Set<String> hopProtocols = {
    'vless',
    'vmess',
    'trojan',
    'ss',
    'hysteria',
    'hysteria2',
    'hy2',
  };

  static bool canBeHop(String protocol) => hopProtocols.contains(protocol);

  final String name;
  final List<ProxyChainHop> hops;

  const ProxyChainConfig({required this.name, required this.hops});

  /// Быстрая отсечка по схеме — её зовут на каждую перерисовку тайла.
  static bool looksLikeChain(String raw) =>
      raw.trimLeft().toLowerCase().startsWith(_prefix);

  /// null — это не цепочка или она битая. Причину для пользователя даёт
  /// [describeProblem].
  static ProxyChainConfig? tryParse(String raw) {
    if (!looksLikeChain(raw)) return null;
    final Object? decoded;
    try {
      // normalize добивает padding и приводит алфавит к стандартному —
      // декодер dart:convert принимает оба, но без выравнивания длины падает.
      decoded = jsonDecode(
        utf8.decode(base64.decode(base64.normalize(_payloadOf(raw)))),
      );
    } on Object {
      return null;
    }
    if (decoded is! Map) return null;

    final rawHops = decoded['hops'];
    if (rawHops is! List) return null;

    final hops = <ProxyChainHop>[];
    for (final item in rawHops) {
      if (item is! Map) continue;
      final config = item['config']?.toString().trim() ?? '';
      if (config.isEmpty) continue;
      final id = item['id']?.toString().trim() ?? '';
      hops.add(ProxyChainHop(
        serverId: id.isEmpty ? null : id,
        name: item['name']?.toString().trim() ?? '',
        config: config,
      ));
    }
    if (hops.isEmpty) return null;

    return ProxyChainConfig(
      name: decoded['name']?.toString().trim() ?? '',
      hops: List.unmodifiable(hops),
    );
  }

  /// Почему строка не годится цепочкой — для сообщения пользователю.
  /// null — годится.
  static String? describeProblem(String raw) {
    if (!looksLikeChain(raw)) return 'Not a proxy chain link';
    final parsed = tryParse(raw);
    if (parsed == null) return 'Damaged proxy chain link';
    if (parsed.hops.length < 2) {
      return 'A proxy chain needs at least two nodes';
    }
    if (parsed.hops.length > maxHops) {
      return 'A proxy chain holds at most $maxHops nodes';
    }
    return null;
  }

  static String _payloadOf(String raw) {
    final trimmed = raw.trim();
    final body = trimmed.substring(_prefix.length);
    // Хвост после '#' — на случай, если ссылку прогнали через обработчик,
    // дописывающий фрагмент с именем: полезная нагрузка всё равно в base64.
    final hash = body.indexOf('#');
    return (hash >= 0 ? body.substring(0, hash) : body)
        .replaceAll(RegExp(r'\s+'), '');
  }

  String encode() {
    final json = jsonEncode({
      'v': 1,
      'name': name,
      'hops': [
        for (final hop in hops)
          {
            if (hop.serverId != null) 'id': hop.serverId,
            if (hop.name.isNotEmpty) 'name': hop.name,
            'config': hop.config,
          },
      ],
    });
    // Без '=' на конце: padding в URI выглядит мусором, а декодер его
    // восстанавливает сам (base64.normalize в tryParse).
    return '$_prefix${base64Url.encode(utf8.encode(json)).replaceAll('=', '')}';
  }

  ProxyChainConfig copyWith({String? name, List<ProxyChainHop>? hops}) =>
      ProxyChainConfig(name: name ?? this.name, hops: hops ?? this.hops);

  /// Узел, к которому подключается само устройство.
  ProxyChainHop get entry => hops.first;

  /// Узел, чей адрес видят сайты.
  ProxyChainHop get exit => hops.last;

  /// Подтягивает актуальные ссылки узлов из списка серверов.
  ///
  /// Подписка на обновлении переписывает ссылки своих серверов (ротация
  /// reality-параметров, смена порта), и снимок в цепочке протухает. Узлы,
  /// которых в списке уже нет, остаются на снимке — цепочка продолжает
  /// работать по последней известной ссылке.
  ///
  /// Возвращает `this`, если менять нечего: вызывающий по этому и решает,
  /// нужна ли запись в хранилище.
  ProxyChainConfig refreshed(
    Map<String, ({String config, String name})> live,
  ) {
    var changed = false;
    final updated = <ProxyChainHop>[];
    for (final hop in hops) {
      final id = hop.serverId;
      final actual = id == null ? null : live[id];
      if (actual == null ||
          (actual.config == hop.config && actual.name == hop.name)) {
        updated.add(hop);
        continue;
      }
      changed = true;
      updated.add(hop.copyWith(config: actual.config, name: actual.name));
    }
    return changed ? copyWith(hops: List.unmodifiable(updated)) : this;
  }

  @override
  String toString() => 'ProxyChainConfig($name, ${hops.length} hops)';
}

class ProxyChainHop {
  /// Сервер из списка, с которого узел скопирован. null — узла в списке нет
  /// (удалён вместе с подпиской или добавлен из чужой цепочки).
  final String? serverId;

  /// Имя на момент сборки цепочки — им подписан узел, пока сервер не найден.
  final String name;

  /// Снимок ссылки сервера. Именно из него собирается аутбаунд.
  final String config;

  const ProxyChainHop({
    required this.config,
    this.serverId,
    this.name = '',
  });

  ProxyChainHop copyWith({String? config, String? name}) => ProxyChainHop(
        serverId: serverId,
        name: name ?? this.name,
        config: config ?? this.config,
      );

  @override
  String toString() => 'ProxyChainHop($name)';
}
