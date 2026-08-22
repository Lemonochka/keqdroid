import 'dart:convert';

import '../models/app_settings.dart';
import '../models/xray_core_settings.dart';
import 'routing_entry.dart';
import 'socks5_credentials.dart';

/// Конфиг mihomo для роли «локальный SOCKS-листенер под нашим tun2socks».
///
/// Ядро НЕ владеет туннелем: TUN по-прежнему держит VpnService, пакеты в него
/// разбирает tun2socks и отдаёт сюда обычным SOCKS5. Для mihomo это ровно та же
/// схема, что у xray в [ConfigGeneratorV2] — меняется только синтаксис.
///
/// Отсюда три следствия, о которых стоит помнить:
///
///  * `fake-ip` и `dns-hijack` не работают. Оба живут в tun-инбаунде mihomo, а
///    его тут нет — значит DNS устройства идёт в туннель обычным трафиком, по
///    соединению на запрос, как у xray до перехвата порта 53. Когда/если ядро
///    переведут на fd-туннель, это включится само.
///  * Домен назначения ядро узнаёт ТОЛЬКО из `sniffer` (см. [buildSniffer]):
///    в SOCKS приезжает голый IP, и без него доменная половина правил не
///    срабатывает никогда.
///  * UDP работает через SOCKS5 UDP ASSOCIATE, поэтому у прокси всегда
///    `udp: true` — иначе mihomo молча отбросит UDP-сессии.
///
/// Формат: mihomo читает YAML через `yaml.v3`, а YAML 1.2 — надмножество JSON,
/// поэтому эмитим обычный JSON и не тащим YAML-райтер. Файл при этом всё равно
/// кладётся с расширением `.yaml`, как ядро и ожидает.
class MihomoConfigGen {
  /// Имя единственного прокси. Совпадает с тегом `proxy` у xray — так правила
  /// в обоих генераторах читаются одинаково.
  static const proxyName = 'proxy';


  /// Имена LAN-инбаундов и их набора правил. Совпадают по смыслу с тегами
  /// `socks-lan`/`http-lan` у xray, но с префиксом: имя листенера у mihomo
  /// попадает в метаданные соединения и видно на экране «Соединения».
  static const lanSocksListener = 'keq-lan-socks';
  static const lanHttpListener = 'keq-lan-http';
  static const lanRuleSet = 'keq-lan';

  static String generate(
    String input,
    AppSettings settings, {
    required int socksPort,
    String? resolvedServerIp,
    bool localInboundsNoAuth = false,
    int? apiPort,
    String apiSecret = '',
  }) =>
      const JsonEncoder.withIndent('  ').convert(
        build(
          input,
          settings,
          socksPort: socksPort,
          resolvedServerIp: resolvedServerIp,
          localInboundsNoAuth: localInboundsNoAuth,
          apiPort: apiPort,
          apiSecret: apiSecret,
        ),
      );

  /// [apiPort]/[apiSecret] — RESTful API ядра для экрана «Соединения».
  /// Поднимается только когда порт передали: пингу и спидтесту он не нужен.
  static Map<String, dynamic> build(
    String input,
    AppSettings settings, {
    required int socksPort,
    String? resolvedServerIp,
    bool localInboundsNoAuth = false,
    int? apiPort,
    String apiSecret = '',
  }) {
    final proxy = buildProxy(input.trim());
    final creds = Socks5Credentials();

    return <String, dynamic>{
      'socks-port': socksPort,
      // Слушаем только петлю: наружу инбаунд не смотрит, в него ходит
      // исключительно tun2socks с этого же устройства.
      'bind-address': '127.0.0.1',
      'allow-lan': false,
      'mode': 'rule',
      'log-level': _logLevel(settings.xrayCore.logLevel),
      // Семейство адресов берём оттуда же, откуда его берёт xray, — из
      // стратегии DNS-запросов. Глобальный `ipv6: false` у mihomo режет AAAA
      // независимо от `dns.ipv6`, так что разъехаться этим двум нельзя.
      'ipv6': settings.xrayCore.dnsQueryStrategy != 'UseIPv4',
      // Глобальная авторизация покрывает `socks-port`, то есть инбаунд под
      // tun2socks. LAN-листенеры из-под неё выведены своим `users` — см.
      // [buildLanListeners].
      if (!localInboundsNoAuth)
        'authentication': ['${creds.username}:${creds.password}'],
      // RESTful API ядра — источник для экрана «Соединения». Слушает петлю, а
      // она на Android общая для всех приложений, поэтому `secret` обязателен:
      // без него любое приложение на устройстве управляло бы туннелем. Порт
      // тоже не константа, а свободный на момент старта.
      if (apiPort != null) ...{
        'external-controller': '127.0.0.1:$apiPort',
        'secret': apiSecret,
      },
      // Базы geo — те же вшитые v2fly `.dat`, что и у xray: ядро запускается с
      // `-d <filesDir>` и берёт их оттуда. Автообновление глушим, иначе ядро
      // полезет в сеть за своими копиями ещё до того, как туннель поднялся.
      'geodata-mode': true,
      'geo-auto-update': false,
      // Поиск процесса-владельца соединения: у нас его знать неоткуда и незачем.
      // В инбаунд ходит один только tun2socks, то есть ВСЕ соединения приписаны
      // ему; правил `PROCESS-NAME` мы не генерируем, а дефолтный `strict` на
      // каждую сессию лезет в /proc. Сплит по приложениям делает не ядро, а
      // VpnService (addAllowed/DisallowedApplication) — см. KeqdisVpnService.
      'find-process-mode': 'off',
      'sniffer': buildSniffer(settings.xrayCore),
      'dns': buildDns(settings),
      if (settings.lanSharing) ...{
        'listeners': buildLanListeners(settings),
        'sub-rules': {lanRuleSet: buildLanRules()},
      },
      'proxies': [proxy],
      'rules': buildRules(
        settings,
        serverAddress: proxy['server']?.toString() ?? '',
        resolvedServerIp: resolvedServerIp,
      ),
    };
  }

  // ───────────────────────────── sniffer ─────────────────────────────

  /// Восстановление домена из уже установленного соединения — аналог
  /// `sniffing` на инбаунде xray.
  ///
  /// Без него доменные правила у mihomo не «работают хуже», а не работают
  /// вовсе: tun2socks отдаёт в SOCKS чистый `IP:port` (домен знает только само
  /// приложение), поэтому `DOMAIN-SUFFIX`, `DOMAIN-KEYWORD` и `GEOSITE` не с
  /// чем сравнивать — они молча промахиваются, и весь трафик проваливается в
  /// `MATCH`. Со стороны это выглядит как «списки обход/прокси не действуют,
  /// хотя у xray с теми же настройками действуют».
  ///
  /// `parse-pure-ip` для нашей схемы обязателен: по умолчанию mihomo нюхает
  /// только соединения, у которых имя хоста уже есть, а у нас его нет никогда.
  ///
  /// `override-destination` — зеркало `sniffingRouteOnly` у xray: `routeOnly`
  /// значит «домен только для выбора правила, соединяемся всё равно по IP».
  /// Значения инвертированы, потому что описывают одно и то же с разных
  /// сторон.
  ///
  /// Набор протоколов повторяет `destOverride` xray (`http`, `tls`, `quic`).
  ///
  /// Порты — ТОЛЬКО строки, включая одиночные. У mihomo это `[]string`
  /// (`RawSniffer.Sniff[].Ports`, разбирается `NewUnsignedRangesFromList`), и
  /// разбирает его yaml без послаблений по типам: число `80` роняет конфиг
  /// целиком с «cannot unmarshal !!int into string», то есть ядро не
  /// поднимется вообще. Послабление (`WeaklyTypedInput`) есть только у
  /// `listeners`, здесь его нет.
  static Map<String, dynamic> buildSniffer(XrayCoreSettings core) => {
        'enable': core.sniffingEnabled,
        'parse-pure-ip': true,
        'override-destination': !core.sniffingRouteOnly,
        'sniff': {
          'HTTP': {
            'ports': ['80', '8080-8880'],
          },
          'TLS': {
            'ports': ['443', '8443'],
          },
          'QUIC': {
            'ports': ['443', '8443'],
          },
        },
      };

  // ────────────────────────── LAN-раздача ──────────────────────────

  /// Инбаунды для раздачи прокси в локальную сеть — то же, что `socks-lan` и
  /// `http-lan` у xray.
  ///
  /// Про `users` тут всё держится на разнице между «пусто» и «нет ключа», и
  /// разница эта неочевидная: пустой список отдаёт mihomo `authStore.Nil`,
  /// то есть инбаунд без пароля; ОТСУТСТВУЮЩИЙ ключ отдаёт `authStore.Default`
  /// — глобальный `authentication`, а там лежат наши случайные креды для
  /// tun2socks. Забудь этот ключ — и раздача поднимется, но пустит в себя
  /// только приложение само, потому что пароля к ней нет ни у кого (см.
  /// `listener/inbound/auth.go`).
  ///
  /// `port` строкой: у mihomo это `string` (принимает и диапазоны), и хотя
  /// листенеры разбираются со слабой типизацией и число бы пережили, писать
  /// сразу в целевом типе честнее.
  ///
  /// `rule` привязывает инбаунд к отдельному набору правил [buildLanRules];
  /// mihomo подставляет его ВМЕСТО основного списка (`tunnel.getRules`).
  static List<Map<String, dynamic>> buildLanListeners(AppSettings settings) {
    final users = lanUsers(settings);
    return [
      {
        'name': lanSocksListener,
        'type': 'socks',
        'listen': '0.0.0.0',
        'port': '${settings.lanSocksPort}',
        'udp': true,
        'rule': lanRuleSet,
        'users': users,
      },
      {
        'name': lanHttpListener,
        'type': 'http',
        'listen': '0.0.0.0',
        'port': '${settings.lanHttpPort}',
        'rule': lanRuleSet,
        'users': users,
      },
    ];
  }

  /// Пара логин/пароль для LAN-инбаундов; пустой список — раздача без пароля.
  /// Условие то же, что у `_lanAuthEnabled` в xray-генераторе: пароль просят
  /// только когда заполнены ОБА поля.
  static List<Map<String, String>> lanUsers(AppSettings settings) {
    final user = settings.lanUsername.trim();
    final pass = settings.lanPassword;
    if (user.isEmpty || pass.isEmpty) return const [];
    return [
      {'username': user, 'password': pass},
    ];
  }

  /// Источники, которым раздача отвечает. Тот же список, что в правиле
  /// `lan-allow` у xray.
  static const _lanSourceRanges = [
    '10.0.0.0/8',
    '172.16.0.0/12',
    '192.168.0.0/16',
    '169.254.0.0/16',
    '127.0.0.0/8',
  ];

  /// Правила LAN-инбаундов.
  ///
  /// Инбаунд слушает `0.0.0.0`, то есть виден и из интернета, если устройство
  /// доступно снаружи. Поэтому список заканчивается `MATCH,REJECT`: без него
  /// не совпавшее ни с чем соединение уходит в `DIRECT` (так устроен
  /// `tunnel.match`), и раздача превращается в открытый прокси для всех.
  ///
  /// Цель для своих — `proxy`, а не финальный аутбаунд из настроек: xray в
  /// `lan-allow` отправляет LAN-трафик в туннель точно так же, мимо списков
  /// обхода. Раздают именно ради туннеля.
  static List<String> buildLanRules() => [
        for (final range in _lanSourceRanges) 'SRC-IP-CIDR,$range,$proxyName',
        'MATCH,REJECT',
      ];

  // ─────────────────────────────── DNS ───────────────────────────────

  /// Резолвер самого ядра — аналог `dns`-блока xray.
  ///
  /// Не косметика: без `enable` mihomo резолвит средствами Go, а на Android
  /// им резолвить нечем — `/etc/resolv.conf` там нет, и чистый Go-резолвер
  /// уходит на 127.0.0.1:53, где никто не отвечает. Домен сервера из ссылки
  /// (а он в ссылке почти всегда) превращается в «no such host» ещё до первого
  /// пакета.
  ///
  /// Чего этот блок НЕ делает — не перехватывает DNS устройства. Перехват
  /// живёт в tun-инбаунде mihomo, которого у нас нет (TUN держит VpnService),
  /// поэтому запросы системы по-прежнему уходят в туннель обычным трафиком —
  /// по соединению на запрос, как у xray до правила `dns-out`. Это единственное
  /// оставшееся расхождение с xray-путём, и лечится оно только fd-туннелем.
  static Map<String, dynamic> buildDns(AppSettings settings) {
    final core = settings.xrayCore;
    final servers = dnsServers(core);
    // Тот же смысл, что у `proxiedDoh` в xray-генераторе: перехват провайдером
    // имеет значение только там, где «всё остальное» и так идёт в туннель.
    final globalProxy =
        settings.finalOutbound == AppSettings.finalOutboundProxy;

    return <String, dynamic>{
      'enable': true,
      // AAAA спрашиваем только если этого просит стратегия запросов xray.
      'ipv6': core.dnsQueryStrategy != 'UseIPv4',
      // fake-ip без перехвата DNS бессмыслен: подменный адрес некому вернуть
      // системе, и он же приедет обратно в правила как «неизвестный IP».
      'enhanced-mode': 'normal',
      // Bootstrap: по ним резолвятся имена самих DoH-серверов. Всегда напрямую,
      // иначе первый же запрос упирается в курицу и яйцо.
      'default-nameserver': const ['1.1.1.1', '8.8.8.8'],
      // Адрес прокси-сервера — отдельной записью и всегда мимо туннеля (у xray
      // это `bootstrapDomains` со `skipFallback`): запрос по нему через прокси
      // означал бы круг.
      'proxy-server-nameserver': servers,
      'nameserver': servers,
      // `respect-rules` гоняет DNS ядра по тем же правилам, что и трафик, то
      // есть в туннель. Ровно то, что делает схема `https://` вместо
      // `https+local://` у xray.
      if (globalProxy) 'respect-rules': true,
      // Отключаемого кэша у mihomo нет вовсе (`dnsDisableCache` из настроек
      // xray сюда не переносится) — есть только выбор алгоритма вытеснения.
    };
  }

  /// Список DNS-серверов из настроек xray в синтаксисе mihomo.
  ///
  /// Схемы у ядер разные, а поле в настройках одно, поэтому переводим:
  ///
  ///  * `+local` у xray значит «мимо роутинга»; у mihomo это поведение по
  ///    умолчанию (обратное включает `respect-rules`), так что суффикс просто
  ///    снимаем.
  ///  * `localhost` (системный резолвер xray) → `system`.
  ///  * `h2c://` и `fakedns` mihomo не знает — выбрасываем: неизвестная схема
  ///    роняет разбор конфига целиком, а вместе с ним и подключение.
  ///
  /// Пустой результат — не повод остаться без резолвера: возвращаем тот же
  /// дефолт, что стоит в настройках xray.
  static List<String> dnsServers(XrayCoreSettings core) {
    const fallback = ['https://1.1.1.1/dns-query', 'https://8.8.8.8/dns-query'];
    if (!core.dnsUseCustom) return fallback;

    final out = <String>[];
    for (final raw in _parseList(core.dnsServers)) {
      final converted = _dnsAddress(raw);
      if (converted != null && !out.contains(converted)) out.add(converted);
    }
    return out.isEmpty ? fallback : out;
  }

  /// Схемы, которые mihomo принимает в `nameserver`.
  static const _dnsSchemes = {'https', 'tls', 'quic', 'tcp', 'udp', 'dhcp'};

  static String? _dnsAddress(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    if (v.toLowerCase() == 'localhost') return 'system';

    final scheme = RegExp(r'^([a-zA-Z0-9]+)(\+local)?://').firstMatch(v);
    if (scheme == null) {
      // Голый адрес — у обоих ядер это обычный UDP-резолвер.
      return v;
    }
    final name = scheme.group(1)!.toLowerCase();
    if (!_dnsSchemes.contains(name)) return null;
    return '$name://${v.substring(scheme.end)}';
  }

  /// `log-level` у mihomo свой: `silent|error|warning|info|debug`.
  /// Отличие от xray одно — `none` называется `silent`.
  static String _logLevel(String xrayLevel) =>
      xrayLevel == 'none' ? 'silent' : xrayLevel;

  // ───────────────────────────── прокси ─────────────────────────────

  /// Ссылка сервера → запись в `proxies`.
  static Map<String, dynamic> buildProxy(String link) {
    final lower = link.toLowerCase();
    if (lower.startsWith('vmess://')) return _vmess(link);
    if (lower.startsWith('vless://')) return _vless(link);
    if (lower.startsWith('trojan://')) return _trojan(link);
    if (lower.startsWith('ss://')) return _shadowsocks(link);
    if (lower.startsWith('hysteria2://') || lower.startsWith('hy2://')) {
      return _hysteria2(link);
    }
    final scheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):').firstMatch(link)?.group(1);
    throw ArgumentError(
      'mihomo: unsupported protocol${scheme != null ? ' ($scheme)' : ''}',
    );
  }

  static Uri _parse(String link) {
    try {
      return Uri.parse(link);
    } catch (_) {
      // Без самой ссылки: в ней UUID/пароль, а текст ошибки уходит в логи.
      throw ArgumentError('mihomo: invalid URI in server config');
    }
  }

  static String _param(Uri uri, String key, [String def = '']) {
    final all = uri.queryParametersAll[key];
    return (all != null && all.isNotEmpty) ? all.first : def;
  }

  static List<String>? _alpn(String raw) {
    final list = raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return list.isEmpty ? null : list;
  }

  /// Транспорт из ссылки → `network` + его `*-opts`.
  ///
  /// Незнакомый транспорт — ошибка, а не молчаливый откат на `tcp`. Откат уже
  /// стоил нам дня разбирательств: `type=xhttp` превращался в голый tcp, ядро
  /// поднималось как ни в чём не бывало, а сервер отвечал так, будто дело в
  /// ключах REALITY. Лучше честно сказать «не умею», чем собрать конфиг,
  /// который заведомо не тот сервер описывает.
  ///
  /// `skip-cert-verify` не выставляем никогда, даже когда ссылка просит
  /// (`insecure=1`): по той же причине, что и `allowInsecure` у xray — доверять
  /// любому сертификату это не «послабление», а дыра, и провайдеры пишут этот
  /// флаг копипастой. См. removed_tls_fields.dart.
  static void _applyTransport(
    Map<String, dynamic> out,
    Uri uri, {
    required String network,
    required String host,
  }) {
    switch (network) {
      // `raw` — новое имя `tcp` в xray; в ссылках встречаются оба.
      case '' || 'tcp' || 'raw':
        out['network'] = 'tcp';
      case 'ws':
        final path = _param(uri, 'path', '/');
        final wsHost = _param(uri, 'host', host);
        out['network'] = 'ws';
        out['ws-opts'] = {
          'path': path,
          if (wsHost.isNotEmpty) 'headers': {'Host': wsHost},
        };
      case 'grpc':
        out['network'] = 'grpc';
        out['grpc-opts'] = {
          'grpc-service-name': _param(uri, 'serviceName'),
        };
      case 'http' || 'h2':
        out['network'] = 'h2';
        out['h2-opts'] = {
          'path': _param(uri, 'path', '/'),
          if (host.isNotEmpty) 'host': [host],
        };
      case 'httpupgrade':
        out['network'] = 'ws';
        out['ws-opts'] = {
          'path': _param(uri, 'path', '/'),
          'v2ray-http-upgrade': true,
          if (host.isNotEmpty) 'headers': {'Host': _param(uri, 'host', host)},
        };
      // splithttp — прежнее имя того же транспорта, старые ссылки живы.
      case 'xhttp' || 'splithttp':
        out['network'] = 'xhttp';
        out['xhttp-opts'] = _xhttpOpts(uri);
      default:
        throw ArgumentError('mihomo: unsupported transport ($network)');
    }
  }

  /// `xhttp-opts` из ссылки.
  ///
  /// xray раскладывает настройки xhttp по двум местам: часть лежит обычными
  /// query-параметрами, часть — json-объектом в `extra` (туда клиенты кладут
  /// xmux и всё, чему не нашлось места в ссылке). Читаем оба, query главнее.
  ///
  /// `host` пустым не пишем: mihomo сам подставит sni, а следом адрес сервера —
  /// ровно как xray.
  static Map<String, dynamic> _xhttpOpts(Uri uri) {
    final extra = _extraObject(uri);

    String pick(String queryKey, String extraKey) {
      final fromQuery = _param(uri, queryKey).trim();
      if (fromQuery.isNotEmpty) return fromQuery;
      return extra[extraKey]?.toString().trim() ?? '';
    }

    final host = pick('host', 'host');
    final path = pick('path', 'path');
    final mode = pick('mode', 'mode');
    final padding = pick('x_padding_bytes', 'xPaddingBytes');
    final scMaxEachPost = pick('scMaxEachPostBytes', 'scMaxEachPostBytes');
    final scMinInterval = pick('scMinPostsIntervalMs', 'scMinPostsIntervalMs');
    final reuse = _xmux(extra['xmux']);

    return <String, dynamic>{
      'path': path.isEmpty ? '/' : path,
      if (host.isNotEmpty) 'host': host,
      if (mode.isNotEmpty) 'mode': mode,
      if (padding.isNotEmpty) 'x-padding-bytes': padding,
      if (scMaxEachPost.isNotEmpty) 'sc-max-each-post-bytes': scMaxEachPost,
      if (scMinInterval.isNotEmpty) 'sc-min-posts-interval-ms': scMinInterval,
      'reuse-settings': ?reuse,
    };
  }

  /// Содержимое `extra`. Мусор внутри — не повод ронять подключение целиком:
  /// это необязательный довесок, без него транспорт всё равно поднимется.
  static Map<String, dynamic> _extraObject(Uri uri) {
    final raw = _param(uri, 'extra').trim();
    if (raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    } catch (_) {
      return const {};
    }
  }

  /// xmux из `extra` → `reuse-settings`.
  ///
  /// Все поля, кроме `hKeepAlivePeriod`, у mihomo строковые: они принимают
  /// диапазоны вида `16-32`, а не только числа.
  static Map<String, dynamic>? _xmux(Object? xmux) {
    if (xmux is! Map) return null;
    String value(String key) => xmux[key]?.toString().trim() ?? '';

    final keepAlive = int.tryParse(value('hKeepAlivePeriod'));
    final out = <String, dynamic>{
      for (final field in const {
        'maxConcurrency': 'max-concurrency',
        'maxConnections': 'max-connections',
        'cMaxReuseTimes': 'c-max-reuse-times',
        'hMaxRequestTimes': 'h-max-request-times',
        'hMaxReusableSecs': 'h-max-reusable-secs',
      }.entries)
        if (value(field.key).isNotEmpty) field.value: value(field.key),
      'h-keep-alive-period': ?keepAlive,
    };
    return out.isEmpty ? null : out;
  }

  static Map<String, dynamic> _vless(String link) {
    final uri = _parse(link);
    final uuid = uri.userInfo;
    if (uuid.isEmpty) throw ArgumentError('VLESS requires UUID in userInfo');

    final security = _param(uri, 'security', 'none');
    final sni = _param(uri, 'sni', _param(uri, 'host', uri.host));
    final flow = _param(uri, 'flow');
    final fp = _param(uri, 'fp');

    final out = <String, dynamic>{
      'name': proxyName,
      'type': 'vless',
      'server': uri.host,
      'port': uri.port,
      'uuid': uuid,
      'udp': true,
      if (flow.isNotEmpty) 'flow': flow,
    };

    if (security == 'tls' || security == 'reality') {
      out['tls'] = true;
      if (sni.isNotEmpty) out['servername'] = sni;
      // Пустой `client-fingerprint` mihomo трактует как «без uTLS», а не как
      // chrome — в отличие от xray. Поэтому подставляем явно.
      out['client-fingerprint'] = fp.isNotEmpty ? fp : 'chrome';
      final alpn = _alpn(_param(uri, 'alpn'));
      if (alpn != null) out['alpn'] = alpn;
    }
    if (security == 'reality') {
      out['reality-opts'] = {
        'public-key': _param(uri, 'pbk'),
        'short-id': _param(uri, 'sid'),
      };
    }

    _applyTransport(out, uri, network: _param(uri, 'type', 'tcp'), host: sni);
    return out;
  }

  static Map<String, dynamic> _vmess(String link) {
    final payload = link.substring('vmess://'.length).trim();
    if (payload.isEmpty) throw ArgumentError('VMess payload is empty');
    var normalized = payload.replaceAll('-', '+').replaceAll('_', '/');
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    final decoded = jsonDecode(utf8.decode(base64.decode(normalized)));
    if (decoded is! Map) throw ArgumentError('Invalid VMess payload format');
    final cfg = Map<String, dynamic>.from(decoded);

    String s(String key, [String def = '']) => cfg[key]?.toString() ?? def;

    final host = s('add');
    final sni = s('sni', s('host'));
    final out = <String, dynamic>{
      'name': proxyName,
      'type': 'vmess',
      'server': host,
      'port': int.tryParse(s('port')) ?? 0,
      'uuid': s('id'),
      'alterId': int.tryParse(s('aid', '0')) ?? 0,
      'cipher': s('scy', s('security', 'auto')),
      'udp': true,
    };
    if (s('tls') == 'tls') {
      out['tls'] = true;
      if (sni.isNotEmpty) out['servername'] = sni;
      final fp = s('fp');
      out['client-fingerprint'] = fp.isNotEmpty ? fp : 'chrome';
      final alpn = _alpn(s('alpn'));
      if (alpn != null) out['alpn'] = alpn;
    }

    // vmess прячет транспорт в json, а не в query — собираем синтетический Uri,
    // чтобы не дублировать разбор `*-opts`.
    final net = s('net', 'tcp');
    final synthetic = Uri(
      scheme: 'vmess',
      host: host.isEmpty ? 'x' : host,
      queryParameters: {
        'type': net,
        'path': s('path', '/'),
        'host': s('host'),
        'serviceName': s('path'),
        // xhttp у vmess встречается редко, но его настройки лежат там же —
        // отдельными полями json, а не внутри `path`.
        'mode': s('mode'),
        'extra': s('extra'),
      },
    );
    _applyTransport(out, synthetic, network: net, host: sni);
    return out;
  }

  static Map<String, dynamic> _trojan(String link) {
    final uri = _parse(link);
    final password = uri.userInfo;
    if (password.isEmpty) throw ArgumentError('Trojan requires password');

    final sni = _param(uri, 'sni', uri.host);
    final fp = _param(uri, 'fp');
    final out = <String, dynamic>{
      'name': proxyName,
      'type': 'trojan',
      'server': uri.host,
      'port': uri.port,
      'password': password,
      'udp': true,
      if (sni.isNotEmpty) 'sni': sni,
      'client-fingerprint': fp.isNotEmpty ? fp : 'chrome',
    };
    final alpn = _alpn(_param(uri, 'alpn'));
    if (alpn != null) out['alpn'] = alpn;

    _applyTransport(out, uri, network: _param(uri, 'type', 'tcp'), host: sni);
    return out;
  }

  static Map<String, dynamic> _shadowsocks(String link) {
    // sip002 и старая форма: ss://base64(method:pass)@host:port и
    // ss://base64(method:pass@host:port).
    final withoutScheme = link.substring('ss://'.length).trim();
    final hashIdx = withoutScheme.indexOf('#');
    final beforeHash =
        hashIdx >= 0 ? withoutScheme.substring(0, hashIdx) : withoutScheme;
    final queryIdx = beforeHash.indexOf('?');
    final core = queryIdx >= 0 ? beforeHash.substring(0, queryIdx) : beforeHash;

    final atIdx = core.lastIndexOf('@');
    if (atIdx < 0) throw ArgumentError('Shadowsocks requires method:password');

    final userInfo = core.substring(0, atIdx);
    final hostPort = core.substring(atIdx + 1);

    String method;
    String password;
    if (userInfo.contains(':')) {
      final i = userInfo.indexOf(':');
      method = userInfo.substring(0, i);
      password = userInfo.substring(i + 1);
    } else {
      var n = userInfo.replaceAll('-', '+').replaceAll('_', '/');
      while (n.length % 4 != 0) {
        n += '=';
      }
      final decoded = utf8.decode(base64.decode(n));
      final i = decoded.indexOf(':');
      if (i <= 0) throw ArgumentError('Invalid Shadowsocks userInfo');
      method = decoded.substring(0, i);
      password = decoded.substring(i + 1);
    }

    final colon = hostPort.lastIndexOf(':');
    if (colon < 0) throw ArgumentError('Shadowsocks requires host:port');

    return <String, dynamic>{
      'name': proxyName,
      'type': 'ss',
      'server': hostPort.substring(0, colon),
      'port': int.tryParse(hostPort.substring(colon + 1)) ?? 0,
      'cipher': method,
      'password': password,
      'udp': true,
    };
  }

  static Map<String, dynamic> _hysteria2(String link) {
    final uri = _parse(link);
    var password = uri.userInfo;
    if (password.isEmpty) password = _param(uri, 'password', _param(uri, 'auth'));
    if (password.isEmpty) throw ArgumentError('Hysteria2 requires password');

    final sni = _param(uri, 'sni', uri.host);
    final obfs = _param(uri, 'obfs');
    final out = <String, dynamic>{
      'name': proxyName,
      'type': 'hysteria2',
      'server': uri.host,
      'port': uri.port,
      'password': password,
      if (sni.isNotEmpty) 'sni': sni,
      if (obfs.isNotEmpty) 'obfs': obfs,
      if (obfs.isNotEmpty)
        'obfs-password': _param(uri, 'obfs-password', _param(uri, 'obfsParam')),
    };
    final up = _param(uri, 'up');
    final down = _param(uri, 'down');
    if (up.isNotEmpty) out['up'] = up;
    if (down.isNotEmpty) out['down'] = down;
    final alpn = _alpn(_param(uri, 'alpn'));
    if (alpn != null) out['alpn'] = alpn;
    return out;
  }

  // ───────────────────────────── правила ─────────────────────────────

  static List<String> _parseList(String s) => s
      .split(RegExp(r'[\r\n,]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  /// Приватные и спец-диапазоны — всегда DIRECT. Тот же список, что у xray.
  static const _privateRanges = [
    '0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8',
    '169.254.0.0/16', '172.16.0.0/12', '192.168.0.0/16',
    '192.0.0.0/24', '198.51.100.0/24', '203.0.113.0/24',
  ];

  /// Правила mihomo: `ТИП,значение,цель[,no-resolve]`.
  ///
  /// Порядок повторяет xray-генератор, иначе одно и то же правило вело бы себя
  /// по-разному в зависимости от выбранного ядра: блок → сам сервер → обход →
  /// приватные сети → прокси → финал.
  ///
  /// `no-resolve` на пользовательских IP-правилах — не украшение, а зеркало
  /// `routingDomainStrategy` у xray. Обычно назначение и так приходит голым IP
  /// (tun2socks другого не умеет), резолвить нечего, и запрет резолва экономит
  /// запрос. Но со снятым `sniffingRouteOnly` ядро подменяет назначение на
  /// вынюханный домен — и тогда `IP-CIDR` с `no-resolve` промахивается мимо
  /// собственного адреса: ровно тот баг «корпоративный CIDR в обходе не
  /// работает», который у xray лечится переключением `AsIs` → `IPIfNonMatch`.
  /// Здесь то же лечение: разрешаем резолв, но лишь когда пользовательские
  /// IP-правила вообще есть — иначе резолвили бы каждый домен впустую.
  static List<String> buildRules(
    AppSettings settings, {
    required String serverAddress,
    String? resolvedServerIp,
  }) {
    final rules = <String>[];

    final hasUserIpRules = [
      settings.blockedRules,
      settings.directRules,
      settings.proxyRules,
    ].any((raw) => splitGeoipTokens(
          splitDomainsAndIps(_parseList(raw)).ips,
        ).plainIps.isNotEmpty);
    final resolveForIpRules =
        !settings.xrayCore.sniffingRouteOnly && hasUserIpRules;
    final ipSuffix = resolveForIpRules ? '' : ',no-resolve';

    void addGroup(String raw, String target) {
      final split = splitDomainsAndIps(_parseList(raw));
      final geo = splitGeoipTokens(split.ips);
      for (final d in split.domains) {
        rules.add('${_domainRule(d)},$target');
      }
      for (final code in geo.geoipCodes) {
        rules.add('GEOIP,$code,$target');
      }
      for (final ip in geo.plainIps) {
        rules.add('IP-CIDR,${_cidr(ip)},$target$ipSuffix');
      }
    }

    addGroup(settings.blockedRules, 'REJECT');

    // Сам сервер — мимо туннеля, иначе обращение к его адресу закольцуется.
    // Здесь `no-resolve` безусловен, и снимать его нельзя ни при каких
    // настройках: резолв ради правила, которое защищает от круга, — это тот же
    // круг, только на шаг раньше.
    if (serverAddress.isNotEmpty && !looksLikeIpOrCidr(serverAddress)) {
      rules.add('DOMAIN,$serverAddress,DIRECT');
    }
    for (final ip in [serverAddress, resolvedServerIp ?? '']) {
      if (ip.isNotEmpty && looksLikeIpOrCidr(ip)) {
        rules.add('IP-CIDR,${_cidr(ip)},DIRECT,no-resolve');
      }
    }

    addGroup(settings.directRules, 'DIRECT');
    // Приватные диапазоны xray под `AsIs` тоже по домену не проверяет, так что
    // резолв им не положен независимо от настроек снифинга.
    for (final range in _privateRanges) {
      rules.add('IP-CIDR,$range,DIRECT,no-resolve');
    }

    addGroup(settings.proxyRules, proxyName);

    rules.add('MATCH,${_finalTarget(settings.finalOutbound)}');
    return rules;
  }

  static String _finalTarget(String finalOutbound) => switch (finalOutbound) {
        AppSettings.finalOutboundDirect => 'DIRECT',
        AppSettings.finalOutboundBlock => 'REJECT',
        _ => proxyName,
      };

  /// Запись домена из наших списков → правило mihomo.
  ///
  /// Соответствие типов почти дословное; расходятся два случая. `regexp:`
  /// становится `DOMAIN-REGEX` — синтаксис регулярок у ядер разный (Go RE2 у
  /// mihomo против RE2 же у xray, но с другой обвязкой), так что сложное
  /// выражение может повести себя иначе. Голое слово без точки оба генератора
  /// считают ключевым словом, а не доменом: у xray это `regexp:.*\.name$`,
  /// здесь — `DOMAIN-KEYWORD`.
  static String _domainRule(String raw) {
    final v = raw.trim();
    final lower = v.toLowerCase();
    if (lower.startsWith('geosite:')) {
      return 'GEOSITE,${v.substring('geosite:'.length)}';
    }
    if (lower.startsWith('full:')) return 'DOMAIN,${v.substring('full:'.length)}';
    if (lower.startsWith('domain:')) {
      return 'DOMAIN-SUFFIX,${v.substring('domain:'.length)}';
    }
    if (lower.startsWith('regexp:')) {
      return 'DOMAIN-REGEX,${v.substring('regexp:'.length)}';
    }
    if (v.startsWith('.')) return 'DOMAIN-SUFFIX,${v.substring(1)}';
    // Голое имя без точки — это ключевое слово, а не домен: так его понимает и
    // xray-генератор (`regexp:.*\.name$`).
    if (!v.contains('.')) return 'DOMAIN-KEYWORD,$v';
    return 'DOMAIN-SUFFIX,$v';
  }

  /// mihomo требует у `IP-CIDR` именно префикс, голый адрес он не примет.
  static String _cidr(String raw) {
    final v = raw.trim();
    if (v.contains('/')) return v;
    return v.contains(':') ? '$v/128' : '$v/32';
  }
}
