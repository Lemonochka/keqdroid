import 'dart:convert';
import 'dart:io' show InternetAddress;

import '../models/app_settings.dart';
import '../models/xray_core_settings.dart';
import '../utils/custom_xray_config.dart';
import '../utils/geo_asset_index.dart';
import '../utils/hysteria_uri.dart';
import '../utils/proxy_chain.dart';
import '../utils/routing_entry.dart';
import '../utils/socks5_credentials.dart';
import '../utils/tls_fingerprint.dart';

/// builds client outbound json for xray 26.x. a few quirks: the core reads an
/// empty fingerprint as chrome, so we fill our own; never emit allowInsecure at
/// all; echConfigList is a string not an array; hysteria2 uses network
/// "hysteria" not "quic".
class ConfigGeneratorV2 {
  static String generateConfig(
    String input,
    AppSettings settings, {
    String? resolvedServerIp,
    /// windows system proxy can't pass socks5 creds — use noauth on localhost.
    bool localInboundsNoAuth = false,
    /// Туннель держит само ядро: в конфиг добавляется tun-инбаунд, а
    /// дескриптор ему передаёт нативная часть через переменную окружения.
    bool nativeTunInbound = false,
    /// Индекс поставляемых geo-баз. Нужен только готовым (custom) конфигам: их
    /// правила приходят от провайдера, а неизвестный `geosite:`-код роняет
    /// разбор всего конфига. Для ссылок списки чистит GeoAssetService заранее.
    GeoAssetIndex? geoIndex,
  }) {
    return const JsonEncoder.withIndent('  ').convert(
      _buildXrayConfig(
        input,
        settings,
        resolvedServerIp: resolvedServerIp,
        localInboundsNoAuth: localInboundsNoAuth,
        nativeTunInbound: nativeTunInbound,
        geoIndex: geoIndex,
      ),
    );
  }

  /// minimal xray config for ephemeral url ping (local proxy, no auth).
  ///
  /// [httpInbound] picks the local probe transport: HTTP (`PROXY` directive) on
  /// desktop, where dart:io HttpClient cannot speak SOCKS; SOCKS on Android, where
  /// the Java probe uses Proxy.Type.SOCKS. The caller passes this per-platform.
  static String generatePingConfig(
    String input,
    AppSettings settings, {
    required int socksPort,
    String? resolvedServerIp,
    bool httpInbound = false,
  }) {
    return jsonEncode(
      _buildXrayConfig(
        input,
        settings,
        resolvedServerIp: resolvedServerIp,
        pingSocksPort: socksPort,
        pingHttpInbound: httpInbound,
      ),
    );
  }

  /// Запасной localhost-порт для временного ядра замера. Рабочий путь порт не
  /// берёт отсюда: [PingService] выделяет свободный на каждый замер, потому что
  /// на общей константе соседние ядра путались между собой. Остаётся дефолтом
  /// для вызовов, которым порт не передали.
  static const int ephemeralPingPort = 28150;

  /// IP-литерал (IPv4 или IPv6). Regex только под IPv4 пропускал IPv6-адреса,
  /// из-за чего direct-правило для сервера с IPv6 строилось как нерабочее
  /// domain-правило и трафик к серверу мог закольцеваться через туннель.
  static bool _isIpLiteral(String value) =>
      InternetAddress.tryParse(value.trim()) != null;

  /// Приватные/LAN/спец-диапазоны — всегда direct. Единый список, чтобы
  /// проверка «есть ли пользовательские IP-правила» и итоговое direct-правило
  /// не разъезжались при правках.
  static const Set<String> _basePrivateRanges = {
    '0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8',
    '169.254.0.0/16', '172.16.0.0/12', '172.19.0.0/30',
    '192.0.0.0/24', '192.168.0.0/16',
    '198.51.100.0/24', '203.0.113.0/24',
    '::1/128', 'fc00::/7', 'fe80::/10',
  };

  /// DNS-адрес, который VpnService отдаёт системе на Android — второй хост
  /// подсети TUN (`KeqdisVpnService.TUN_DNS_ADDRESS`, держать в паре с ним).
  /// Слушать на нём некому и не должно: запрос приходит в tun-инбаунд и обязан
  /// попасть в перехват, а не наружу.
  static const String _androidTunDns = '172.19.0.2';

  /// Заглушка на случай, если нативная часть не перепишет `mtu` своим числом.
  /// Настоящее значение принадлежит ей: интерфейс поднимает она, и число
  /// обязано совпасть с тем, что она поставила через `setMtu`.
  static const int _defaultTunMtu = 1400;

  /// Имя tun-инбаунда. На Android оно косметическое — интерфейс уже поднят
  /// VpnService, и ядро печатает это имя только в двух строчках лога.
  ///
  /// Но задать его обязательно. Пустое имя ядро понимает как «придумай сам» и
  /// идёт перебирать занятые имена через `net.Interfaces()`, а тот на Android
  /// ходит в netlink, куда untrusted-приложение не пускают: разбор падает на
  /// `netlinkrib: permission denied` — и падает целиком, вместе со всем
  /// конфигом, а не только этим инбаундом.
  static const String _tunInterfaceName = 'keqtun0';

  /// Пароль на LAN-инбаунды включается только полной парой логин+пароль:
  /// половинчатый ввод даёт noauth, а не пустой логин/пароль в accounts.
  static bool _lanAuthEnabled(AppSettings settings) =>
      settings.lanUsername.trim().isNotEmpty && settings.lanPassword.isNotEmpty;

  static List<String>? _splitAlpn(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final list = raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return list.isEmpty ? null : list;
  }

  /// ws и httpupgrade поверх TLS: пару `h2,http/1.1` из ссылки сводим к одному
  /// `http/1.1`.
  ///
  /// Оба транспорта поднимаются апгрейдом соединения по HTTP/1.1, и если сервер
  /// выберет по ALPN h2, апгрейда не будет — снаружи это «ссылка не работает»
  /// без внятной ошибки. Ядро подставляет `http/1.1` само (`WithNextProto` в
  /// `transport/internet/tls/config.go`), но только когда alpn в конфиге пуст:
  /// пришедшую из ссылки пару оно оставляет как есть.
  ///
  /// Срабатывает ровно на эту пару целиком. Одиночный `alpn=h2` пользователь мог
  /// поставить осознанно — решать за него мы не будем.
  static List<String> _alpnForNetwork(String network, List<String> alpn) =>
      (network == 'ws' || network == 'httpupgrade') &&
              alpn.length == 2 &&
              alpn[0] == 'h2' &&
              alpn[1] == 'http/1.1'
          ? const ['http/1.1']
          : alpn;

  /// Клиентский TLS: имена полей — как в `infra/conf` ядра.
  ///
  /// Без `fp` в ссылке пишем [defaultTlsFingerprint]: пустое поле ядро читает
  /// как Chrome. Кроме hysteria — там рукопожатие QUIC, и отпечаток ядро не
  /// применяет.
  ///
  /// `allowInsecure` не эмитим никогда, даже когда ссылка просит. Ядро это поле
  /// снесло, и разбор конфига падает целиком: один сервер с `insecure=1` лишал
  /// связи всю подписку, а наружу это выглядело как «SOCKS port not ready».
  ///
  /// Замены, которые ядро предлагает вместо него, ссылки передают, и мы их
  /// читаем: `pcs` → `pinnedPeerCertSha256`, `vcn` → `verifyPeerCertByName`.
  /// Панели выдают их вместе с чужим `sni`: в ClientHello уходит маскировочное
  /// имя, а сертификат сверяется с настоящим. Пока мы их выбрасывали, ядро
  /// проверяло сертификат по маскировочному имени и роняло рукопожатие.
  /// а остальные хотя бы не тянут за собой всю подписку.
  static Map<String, dynamic> _tlsClientSettings({
    required String serverName,
    required String network,
    String fingerprint = '',
    String? alpnQuery,
    String? echConfigList,
    String? pinnedPeerCertSha256,
    String? verifyPeerCertByName,
  }) {
    final tls = <String, dynamic>{
      'serverName': serverName,
    };
    final fp = fingerprint.trim();
    if (fp.isNotEmpty) {
      tls['fingerprint'] = fp;
    } else if (network != 'hysteria') {
      tls['fingerprint'] = defaultTlsFingerprint;
    }
    final alpn = _splitAlpn(alpnQuery);
    if (alpn != null) tls['alpn'] = _alpnForNetwork(network, alpn);
    final ech = echConfigList?.trim() ?? '';
    if (ech.isNotEmpty) tls['echConfigList'] = ech;
    final pin = pinnedPeerCertSha256?.trim() ?? '';
    if (pin.isNotEmpty) tls['pinnedPeerCertSha256'] = pin;
    final verifyName = verifyPeerCertByName?.trim() ?? '';
    if (verifyName.isNotEmpty) tls['verifyPeerCertByName'] = verifyName;
    return tls;
  }

  /// Значение параметра запроса без подмены `+` на пробел.
  ///
  /// `Uri.decodeComponent` в отличие от `decodeQueryComponent` `+` не трогает —
  /// то есть читает запрос по RFC 3986, а не по правилам формы.
  static String _rawQueryParam(Uri uri, String key, String def) {
    for (final pair in uri.query.split('&')) {
      final eq = pair.indexOf('=');
      if (eq < 0) continue;
      if (Uri.decodeComponent(pair.substring(0, eq)) != key) continue;
      final value = Uri.decodeComponent(pair.substring(eq + 1));
      if (value.isNotEmpty) return value;
    }
    return def;
  }

  static String _decodeBase64UrlCompat(String input) {
    var normalized = input.trim().replaceAll('-', '+').replaceAll('_', '/');
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    return utf8.decode(base64.decode(normalized));
  }

  /// base64-json из vmess-ссылки, либо `null` — если ссылка второго вида.
  ///
  /// У vmess два формата: старый v2rayN (base64 от json) и AEAD стандарта #716
  /// (`vmess://uuid@host:port?...`), который по строению ничем не отличается от
  /// vless-ссылки. Второй мы разбирали как base64, он не декодировался, и
  /// сервер не собирался вовсе. Различаем как само ядро mihomo
  /// (`converter.go`): не вышло base64 — значит ссылка.
  static Map<String, dynamic>? _parseVmessPayload(String input) {
    final payload = input.substring('vmess://'.length).trim();
    if (payload.isEmpty) {
      throw ArgumentError('VMess payload is empty');
    }
    try {
      final parsed = jsonDecode(_decodeBase64UrlCompat(payload));
      if (parsed is Map<String, dynamic>) return parsed;
    } catch (_) {
      // Ниже решаем по виду payload, а не по тексту чужой ошибки.
    }
    // `@` в base64 не встречается: у AEAD там UUID пользователя перед адресом.
    if (payload.contains('@')) return null;
    throw ArgumentError('Invalid VMess payload format');
  }

  static Map<String, dynamic> _buildXrayConfig(
    String input,
    AppSettings settings, {
    String? resolvedServerIp,
    int? pingSocksPort,
    bool pingHttpInbound = false,
    bool localInboundsNoAuth = false,
    /// Туннель держит само ядро: в конфиг добавляется tun-инбаунд, а
    /// дескриптор ему передаёт нативная часть через переменную окружения.
    bool nativeTunInbound = false,
    GeoAssetIndex? geoIndex,
  }) {
    final trimmed = input.trim();

    // Цепочка серверов вместо одного: аутбаунды всех узлов + dialerProxy.
    final chain = ProxyChainConfig.tryParse(trimmed);
    if (chain != null) {
      return _buildChainConfig(
        chain,
        settings,
        resolvedServerIp: resolvedServerIp,
        pingSocksPort: pingSocksPort,
        pingHttpInbound: pingHttpInbound,
        localInboundsNoAuth: localInboundsNoAuth,
        nativeTunInbound: nativeTunInbound,
      );
    }

    // Готовый конфиг ядра вместо ссылки: аутбаунды/роутинг/dns берём авторские,
    // подменяем только инбаунды (их порты и креды диктует приложение).
    final custom = CustomXrayConfig.tryParse(trimmed);
    if (custom != null) {
      return _buildCustomConfig(
        custom,
        settings,
        resolvedServerIp: resolvedServerIp,
        pingSocksPort: pingSocksPort,
        pingHttpInbound: pingHttpInbound,
        localInboundsNoAuth: localInboundsNoAuth,
        nativeTunInbound: nativeTunInbound,
        geoIndex: geoIndex,
      );
    }

    final link = _buildLinkOutbound(trimmed, settings);
    _applyMux(link.outbound, settings.xrayCore);

    return _wrapConfig(
      [link.outbound],
      settings,
      resolvedServerIp ?? link.address,
      link.port,
      originalServerAddress: link.address,
      pingSocksPort: pingSocksPort,
      pingHttpInbound: pingHttpInbound,
      localInboundsNoAuth: localInboundsNoAuth,
      nativeTunInbound: nativeTunInbound,
    );
  }

  /// Аутбаунд одной серверной ссылки (`vless://`, `vmess://`, …) плюс её
  /// адрес и порт. Общая часть для одиночного сервера и для узла цепочки.
  /// Тег всегда `proxy` — вызывающий переименовывает его под своё место.
  static ({Map<String, dynamic> outbound, String address, int port})
      _buildLinkOutbound(String trimmed, AppSettings settings) {
    final bool isVmess = trimmed.toLowerCase().startsWith('vmess://');
    final lowerTrimmed = trimmed.toLowerCase();
    final bool isHysteria = lowerTrimmed.startsWith('hysteria://') ||
        lowerTrimmed.startsWith('hysteria2://') ||
        lowerTrimmed.startsWith('hy2://');

    Uri uri;
    Map<String, dynamic>? vmessConfig;

    try {
      if (isVmess) {
        vmessConfig = _parseVmessPayload(trimmed);
        // AEAD-ссылку разбираем как обычную: адрес, uuid и параметры лежат в
        // ней самой, и дальше её ведёт тот же путь, что и vless.
        uri = vmessConfig != null ? Uri.parse('vmess://proxy') : Uri.parse(trimmed);
      } else if (isHysteria) {
        // Перебор портов hysteria2 пишут прямо в адресе (`host:20000-20050`), а
        // такой порт `Uri.parse` не берёт: раньше ссылка разваливалась целиком.
        uri = Uri.parse(HysteriaLinkParams.splitPorts(trimmed).$1);
      } else {
        uri = Uri.parse(trimmed);
      }
    } catch (e) {
      // Без самого конфига: он содержит UUID/пароль и уходил бы в логи/Crashlytics.
      final scheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):').firstMatch(trimmed)?.group(1);
      throw ArgumentError(
        'Invalid URI format in server config'
        '${scheme != null ? ' (scheme: $scheme)' : ''}',
      );
    }

    final scheme = isVmess ? 'vmess' : uri.scheme.toLowerCase();
    final address =
        vmessConfig != null ? (vmessConfig['add']?.toString() ?? '') : uri.host;
    final port = vmessConfig != null
        ? int.tryParse(vmessConfig['port']?.toString() ?? '') ?? 0
        : uri.port;

    String getParam(String key, [String def = '']) {
      if (vmessConfig != null) {
        if (key == 'type' && vmessConfig.containsKey('net')) {
          final value = vmessConfig['net'];
          return value == null ? def : value.toString();
        }
        final value = vmessConfig[key];
        if (value != null) return value.toString();
      }
      // base64 в запросе ссылки: `Uri.queryParameters` разбирает его по
      // правилам HTML-формы, где `+` означает пробел. Панели сплошь не
      // кодируют `+` как `%2B`, и значение приезжало испорченным — ядру это
      // неотличимо от неверного ключа, оно просто не подключается.
      // `fm` — json масок, в нём тоже бывает base64.
      if (key == 'ech' || key == 'pcs' || key == 'fm') {
        return _rawQueryParam(uri, key, def);
      }
      final val = uri.queryParametersAll[key];
      return (val != null && val.isNotEmpty) ? val.first : def;
    }

    final networkType = getParam('type', isHysteria ? 'hysteria' : 'tcp');

    final Map<String, dynamic> outbound;
    Map<String, dynamic> streamSettings = {'network': networkType};

    if (scheme == 'vless') {
      outbound = _buildVlessOutbound(uri, getParam, address, port, streamSettings);
    } else if (scheme == 'trojan') {
      outbound = _buildTrojanOutbound(uri, getParam, vmessConfig, address, port, streamSettings);
    } else if (scheme == 'ss') {
      outbound = _buildShadowsocksOutbound(uri, getParam, address, port);
    } else if (scheme == 'vmess') {
      outbound = _buildVmessOutbound(uri, vmessConfig, getParam, address, port, streamSettings);
    } else if (isHysteria) {
      outbound = _buildHysteriaOutbound(
          uri, trimmed, getParam, address, port, streamSettings);
    } else {
      throw ArgumentError('Unsupported protocol: $scheme');
    }

    _applyXrayStreamExtras(outbound, settings.xrayCore);
    _applyServerDomainStrategy(outbound, address, settings.xrayCore);

    return (outbound: outbound, address: address, port: port);
  }

  /// Адрес сервера резолвит встроенный DNS ядра, а не резолвер его процесса.
  ///
  /// Иначе домен сервера уходит в системный резолвер Go, а на Android он почти
  /// не отвечает: `/etc/resolv.conf` там нет, и в логах бесконечное «operation
  /// was canceled» — трафик стоит, хотя сервер жив. `domainStrategy` переводит
  /// резолв на dns-блок конфига, то есть на тот же путь, которым ходят
  /// остальные домены; в mihomo ту же дыру закрывает `proxy-server-nameserver`.
  ///
  /// Семейство адресов берём от queryStrategy: просить A+AAAA, когда DNS
  /// настроен отдавать только A, значит впустую ждать вторую половину ответа.
  /// Адрес-IP не трогаем — резолвить там нечего.
  static void _applyServerDomainStrategy(
    Map<String, dynamic> outbound,
    String address,
    XrayCoreSettings core,
  ) {
    if (address.isEmpty || _isIpLiteral(address)) return;
    final stream = Map<String, dynamic>.from(
      (outbound['streamSettings'] as Map<String, dynamic>?) ??
          const <String, dynamic>{},
    );
    final sockopt = Map<String, dynamic>.from(
      (stream['sockopt'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
    );
    sockopt['domainStrategy'] = switch (core.dnsQueryStrategy) {
      'UseIPv4' => 'UseIPv4',
      'UseIPv6' => 'UseIPv6',
      _ => 'UseIP',
    };
    stream['sockopt'] = sockopt;
    outbound['streamSettings'] = stream;
  }

  /// Префикс тегов промежуточных узлов цепочки. Выходной узел остаётся
  /// `proxy` — на этот тег смотрят все правила роутинга и sing-box-часть.
  static const String _chainHopTagPrefix = 'chain-';

  /// Цепочка серверов в роли одного «сервера».
  ///
  /// Каждому узлу — свой аутбаунд; узел `i` дозванивается до своего сервера
  /// через узел `i-1` (`streamSettings.sockopt.dialerProxy`). Роутинг про
  /// внутренние звенья не знает и знать не должен: он направляет трафик в
  /// `proxy` (выходной узел), а тот уже сам тянет за собой всю цепочку.
  /// Подробнее про выбор dialerProxy — в [ProxyChainConfig].
  ///
  /// Наружу из процесса уходит только соединение до входного узла — поэтому
  /// [resolvedServerIp] относится к нему, и обход туннеля строится по нему же.
  static Map<String, dynamic> _buildChainConfig(
    ProxyChainConfig chain,
    AppSettings settings, {
    String? resolvedServerIp,
    int? pingSocksPort,
    bool pingHttpInbound = false,
    bool localInboundsNoAuth = false,
    /// Туннель держит само ядро: в конфиг добавляется tun-инбаунд, а
    /// дескриптор ему передаёт нативная часть через переменную окружения.
    bool nativeTunInbound = false,
  }) {
    if (chain.hops.isEmpty) {
      throw ArgumentError('Proxy chain has no nodes');
    }

    final built = [
      for (final hop in chain.hops) _buildLinkOutbound(hop.config, settings),
    ];

    final outbounds = <Map<String, dynamic>>[];
    for (var i = 0; i < built.length; i++) {
      final isExit = i == built.length - 1;
      final outbound = built[i].outbound;
      outbound['tag'] = isExit ? 'proxy' : '$_chainHopTagPrefix$i';
      if (i > 0) {
        _applyDialerProxy(outbound, '$_chainHopTagPrefix${i - 1}');
      }
      outbounds.add(outbound);
    }

    // Выходной узел — первым: в xray первый аутбаунд считается основным, и
    // всё, что не попало ни в одно правило, уходит именно в него.
    final exit = outbounds.removeLast();

    // Мультиплексор — только на выходном узле. На промежуточных звеньях он
    // мультиплексировал бы одно-единственное соединение (следующее звено
    // дозванивается через dialerProxy), то есть добавлял бы слой ни за чем.
    _applyMux(exit, settings.xrayCore);

    return _wrapConfig(
      [exit, ...outbounds],
      settings,
      resolvedServerIp ?? built.first.address,
      built.first.port,
      originalServerAddress: built.first.address,
      // Адреса остальных узлов: правило «сам сервер — мимо туннеля» должно
      // накрывать всю цепочку, иначе обращение к адресу промежуточного узла
      // (тот же адрес панели провайдера) закольцуется через неё же.
      extraServerAddresses: [
        for (var i = 1; i < built.length; i++) built[i].address,
      ],
      pingSocksPort: pingSocksPort,
      pingHttpInbound: pingHttpInbound,
      localInboundsNoAuth: localInboundsNoAuth,
      nativeTunInbound: nativeTunInbound,
    );
  }

  /// Подключает аутбаунд к предыдущему узлу цепочки.
  static void _applyDialerProxy(Map<String, dynamic> outbound, String tag) {
    final stream = Map<String, dynamic>.from(
      (outbound['streamSettings'] as Map<String, dynamic>?) ??
          const <String, dynamic>{},
    );
    final sockopt = Map<String, dynamic>.from(
      (stream['sockopt'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
    );
    sockopt['dialerProxy'] = tag;
    // Адрес этого узла резолвит предыдущий: соединение до него идёт уже
    // внутри чужого туннеля, и локальный резолв тут ничего не решает —
    // только заставляет ядро ждать ответа, который не нужен.
    sockopt.remove('domainStrategy');
    stream['sockopt'] = sockopt;

    // Перебор портов hysteria оставляем только внешнему узлу. Отказа «udphop
    // requires being at the outermost level», на который тут ссылались, в xray
    // 26.7.28 нет — такой остался у масок xicmp и realm, — но перебор за
    // dialerProxy не проверен ни на устройстве, ни по коду дозвона. Поэтому как
    // и прежде: базовый порт из ссылки рабочий, перебор отбрасываем.
    final finalmask = stream['finalmask'];
    if (finalmask is Map) {
      final quicParams = finalmask['quicParams'];
      if (quicParams is Map) {
        quicParams.remove('udpHop');
        if (quicParams.isEmpty) finalmask.remove('quicParams');
      }
      if (finalmask.isEmpty) stream.remove('finalmask');
    }

    outbound['streamSettings'] = stream;
  }

  /// Тег freedom-аутбаунда, который режет ClientHello.
  static const String _fragmentTag = 'fragment';

  /// Включает фрагментацию и возвращает аутбаунд, который её исполняет
  /// (`null` — выключена или применять её не к чему).
  ///
  /// Подцепляется к самому внешнему аутбаунду — тому, который реально
  /// открывает сокет наружу. В цепочке это входной узел: у остальных уже стоит
  /// свой `dialerProxy` на предыдущее звено, и вторая подмена просто разорвала
  /// бы цепочку. Резать имеет смысл только внешний сокет: пакеты внутренних
  /// звеньев уже едут внутри чужого шифрованного потока, и DPI провайдера их
  /// всё равно не разбирает.
  static Map<String, dynamic>? _applyFragment(
    List<Map<String, dynamic>> proxyOutbounds,
    XrayCoreSettings core,
  ) {
    final fragment = core.buildFragmentMap();
    if (fragment == null) return null;

    for (final outbound in proxyOutbounds) {
      final stream = outbound['streamSettings'] as Map<String, dynamic>?;
      final sockopt = stream?['sockopt'] as Map<String, dynamic>?;
      final dialer = sockopt?['dialerProxy']?.toString() ?? '';
      // Уже дозванивается через другое звено — значит не внешний.
      if (dialer.isNotEmpty) continue;
      // UDP-транспорт резать нечем: фрагментатор режет ClientHello в потоке
      // TCP, а у hysteria и mKCP такого потока нет вовсе.
      if (_isDatagramOutbound(outbound)) return null;

      final newStream = Map<String, dynamic>.from(
        stream ?? const <String, dynamic>{},
      );
      final newSockopt = Map<String, dynamic>.from(
        sockopt ?? const <String, dynamic>{},
      );
      newSockopt['dialerProxy'] = _fragmentTag;
      // `domainStrategy` отсюда не убираем, в отличие от цепочки: там адрес
      // резолвит предыдущий узел удалённо, а тут дозвон остаётся локальным,
      // просто уходит на аутбаунд ниже. Он же и резолвит — своей настройкой.
      newStream['sockopt'] = newSockopt;
      outbound['streamSettings'] = newStream;

      return {
        'protocol': 'freedom',
        'tag': _fragmentTag,
        'settings': {
          // Тот же резолв, что и у прокси-аутбаунда без фрагментации: домен
          // сервера должен идти через DNS-блок конфига, а не через системный
          // резолвер Go — на Android его просто нет (см.
          // [_applyServerDomainStrategy]).
          'domainStrategy': _freedomDomainStrategy(core),
          'fragment': fragment,
        },
      };
    }
    return null;
  }

  /// Семейство адресов для резолва внутри freedom — из queryStrategy DNS,
  /// как и в [_applyServerDomainStrategy].
  static String _freedomDomainStrategy(XrayCoreSettings core) =>
      switch (core.dnsQueryStrategy) {
        'UseIPv4' => 'UseIPv4',
        'UseIPv6' => 'UseIPv6',
        _ => 'UseIP',
      };

  /// Шум перед первым UDP-пакетом — единственное, что у нас есть для
  /// UDP-серверов: фрагментировать там нечего.
  ///
  /// Ставится на тот же аутбаунд, что и фрагментация: внешний (без
  /// `dialerProxy`) и датаграммный. Внутри цепочки шуметь бессмысленно — там
  /// «сокет» это предыдущее звено, а не сеть.
  ///
  /// Если у hysteria уже есть салмандер из ссылки, шум дописывается следом:
  /// список `udp` ядро оборачивает с конца (`slices.Backward`), поэтому
  /// последний в списке оказывается ближе всего к проводу — мусор уходит ровно
  /// таким, каким его задали, а не обфусцированным поверх.
  static void _applyUdpNoise(
    List<Map<String, dynamic>> proxyOutbounds,
    XrayCoreSettings core,
  ) {
    final noise = core.buildNoiseItem();
    if (noise == null) return;

    for (final outbound in proxyOutbounds) {
      final stream = outbound['streamSettings'];
      if (stream is! Map<String, dynamic>) continue;
      final dialer = (stream['sockopt'] as Map<String, dynamic>?)?['dialerProxy']
              ?.toString() ??
          '';
      if (dialer.isNotEmpty) continue;
      if (!_isDatagramOutbound(outbound)) continue;

      final finalmask = Map<String, dynamic>.from(
        (stream['finalmask'] as Map<String, dynamic>?) ?? {},
      );
      final udp = [
        ...((finalmask['udp'] as List?) ?? const []),
        noise,
      ];
      finalmask['udp'] = udp;
      stream['finalmask'] = finalmask;
    }
  }

  /// Едет ли аутбаунд по UDP: hysteria2 (`network: hysteria`) и mKCP/QUIC из
  /// параметра `type` ссылки.
  static bool _isDatagramOutbound(Map<String, dynamic> outbound) {
    if (outbound['protocol'] == 'hysteria') return true;
    final network = (outbound['streamSettings']
                as Map<String, dynamic>?)?['network']
            ?.toString()
            .toLowerCase() ??
        '';
    return const {'hysteria', 'kcp', 'mkcp', 'quic'}.contains(network);
  }

  /// Разделители списков правил — и запятая, и перевод строки: UI обещает «по
  /// одному в строке или через запятую», а сплит только по ',' склеивал
  /// построчные записи в один несрабатывающий токен.
  static List<String> _parseRuleList(String s) => s
      .split(RegExp(r'[\r\n,]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  /// Пользовательская запись домена → форма, понятная роутингу xray.
  static List<String> _normalizeDomains(List<String> domains) =>
      domains.map((d) {
        final c = d.trim().toLowerCase();
        if (c.startsWith('domain:') ||
            c.startsWith('full:') ||
            c.startsWith('regexp:') ||
            c.startsWith('geosite:')) {
          return c;
        }
        if (!c.contains('.')) return 'regexp:.*\\.$c\$';
        if (c.startsWith('.')) return 'domain:${c.substring(1)}';
        return 'domain:$c';
      }).toList();

  /// Тег freedom-аутбаунда, который мы дописываем в конфиг пробы: собственного
  /// `direct` у автора может не быть, а правила «сервер и приватные сети —
  /// напрямую» пингу нужны.
  static const _pingDirectTag = 'keq-ping-direct';

  /// Тег freedom-аутбаунда для пользовательских direct-правил в готовом
  /// конфиге — на случай, если своего freedom у автора нет.
  static const _customDirectTag = 'keq-direct';

  /// Тег blackhole-аутбаунда для запрета входа в LAN-инбаунды: в авторском
  /// конфиге blackhole тоже бывает не заведён.
  static const _customBlockTag = 'keq-block';

  /// Тег `dns`-аутбаунда для перехвата DNS устройства в готовом конфиге —
  /// на случай, если своего у автора нет.
  static const _customDnsTag = 'keq-dns-out';

  /// Готовый конфиг ядра в роли сервера.
  ///
  /// Меняем немногое: инбаунды на свои, `log.loglevel` из настроек (ниже `info`
  /// ядро не печатает решения роутинга, и экран «Соединения» остаётся без
  /// правил), а при включённом LAN-шаринге первыми ставим правила «в наши
  /// LAN-инбаунды только с частных адресов» — у автора правил для этих тегов
  /// нет, а инбаунд слушает 0.0.0.0. Ещё вычищаем `geoip:`/`geosite:`-коды,
  /// которых нет в поставляемых базах: один такой роняет разбор всего конфига.
  ///
  /// Роутинг, dns и цепочки аутбаундов остаются авторскими: в этом весь смысл
  /// такого сервера («сервера с готовым роутингом» в подписках провайдеров).
  static Map<String, dynamic> _buildCustomConfig(
    CustomXrayConfig custom,
    AppSettings settings, {
    String? resolvedServerIp,
    int? pingSocksPort,
    bool pingHttpInbound = false,
    bool localInboundsNoAuth = false,
    /// Туннель держит само ядро: в конфиг добавляется tun-инбаунд, а
    /// дескриптор ему передаёт нативная часть через переменную окружения.
    bool nativeTunInbound = false,
    GeoAssetIndex? geoIndex,
  }) {
    final inbounds = _buildInbounds(
      settings,
      pingSocksPort: pingSocksPort,
      pingHttpInbound: pingHttpInbound,
      localInboundsNoAuth: localInboundsNoAuth,
      nativeTunInbound: nativeTunInbound,
    );

    if (pingSocksPort != null) {
      final serverAddress = resolvedServerIp?.trim().isNotEmpty == true
          ? resolvedServerIp!.trim()
          : custom.address;
      final config = custom.buildPingConfig(
        inbounds: inbounds,
        rules: _customPingRules(
          serverAddress: serverAddress,
          originalAddress: custom.address,
          proxyTag: custom.primaryOutboundTag,
        ),
      );
      // Свой freedom, чтобы direct-правила пробы точно во что-то указывали.
      config['outbounds'] = [
        ...(config['outbounds'] as List),
        {'protocol': 'freedom', 'tag': _pingDirectTag},
      ];
      return config;
    }

    final lanRules = <Map<String, dynamic>>[];
    var blockTag = _existingOutboundTag(custom, 'blackhole');
    if (settings.lanSharing) {
      blockTag ??= _customBlockTag;
      lanRules.addAll([
        {
          'type': 'field',
          'ruleTag': 'lan-allow',
          'inboundTag': ['socks-lan', 'http-lan'],
          'source': [
            '10.0.0.0/8',
            '172.16.0.0/12',
            '192.168.0.0/16',
            '169.254.0.0/16',
            '127.0.0.0/8',
          ],
          'outboundTag': custom.primaryOutboundTag,
        },
        {
          'type': 'field',
          'ruleTag': 'lan-deny',
          'inboundTag': ['socks-lan', 'http-lan'],
          'network': 'tcp,udp',
          'outboundTag': blockTag,
        },
      ]);
    }

    // Пользовательские списки роутинга — после авторских правил.
    //
    // Готовый конфиг берут ровно ради его роутинга: провайдер уже разложил, что
    // идёт напрямую (банки, госуслуги, локальные сервисы), а что в туннель.
    // Когда наши списки решали раньше, дефолтный «обход» из настроек перебивал
    // эту раскладку, и от кастомного конфига оставались одни аутбаунды.
    //
    // Своё при этом не пропадает: у авторов почти никогда нет catch-all, и всё,
    // что провайдер не назвал, по-прежнему решают списки приложения. Если же
    // catch-all у автора есть — он и должен побеждать, за этим сервер и брали.
    final directTag =
        _existingOutboundTag(custom, 'freedom') ?? _customDirectTag;
    final userRules = _customUserRules(
      settings,
      directTag: directTag,
      proxyTag: custom.primaryOutboundTag,
      blockTag: blockTag ?? _customBlockTag,
    );

    // DNS устройства отвечает ядро, а не сервер на том конце туннеля, — и в
    // готовом конфиге это приходится дописывать за автора.
    //
    // Перехват DNS у автора висит на его инбаунде: `dokodemo-door` с тегом
    // `dns-in` и правило `inboundTag: [dns-in] -> dns-out`. Инбаунды мы
    // заменяем своими (см. [_buildInbounds]), и вместе с `dns-in` умирает
    // правило: сработать ему теперь не на чем. Дальше запрос к 8.8.8.8:53
    // (этот адрес TUN отдаёт системе) не ловит ни одно авторское правило и
    // падает в наш `final`. С финалом «блок» это выглядит как «в кастомном
    // конфиге не работает вообще ничего, даже то, что сам он ведёт напрямую»:
    // без резолва нет и соединений, по которым авторские правила могли бы
    // сработать.
    //
    // после авторских правил: если автор DNS всё-таки разложил сам (`port: 53`
    // или catch-all), решает он — принцип готового конфига не меняем.
    //
    // `inboundTag` тут обязателен. Без него правило поймает и запросы самого
    // ядра к своему upstream — их ядро тоже отправляет через роутинг, — и
    // `dns`-аутбаунд начнёт отвечать сам себе по кругу.
    // Чем `dns`-аутбаунд будет отвечать, если своего блока у автора нет.
    final fallbackDns = settings.xrayCore.buildDnsBlock(
      directDomains: _normalizeDomains(
        splitDomainsAndIps(_parseRuleList(settings.directRules)).domains,
      ),
      bootstrapDomains: [
        if (custom.address.trim().isNotEmpty && !_isIpLiteral(custom.address))
          'full:${custom.address.trim()}',
      ],
      proxiedDoh: settings.finalOutbound == AppSettings.finalOutboundProxy,
    );
    // Авторский блок плюс наш резерв в хвосте — см. [CustomXrayConfig.mergeDns].
    // Считается тем же методом, что кладётся в конфиг, иначе проверки ниже
    // (fakedns, «резолверу нужен роутинг») судили бы о другом dns-блоке.
    final effectiveDns =
        CustomXrayConfig.mergeDns(custom.authorDns, fallbackDns) ?? fallbackDns;

    // fakedns — единственный случай, когда перехват DNS всё ломает, а не чинит.
    // Ядро отдало бы приложению адрес из фейкового пула, а достать из такого
    // адреса домен обратно умеет только снифер с `fakedns` в `destOverride` —
    // у нас его нет (`XrayCoreSettings.buildSniffing`). Тогда не сработало бы
    // ни одно доменное правило автора. Конфиг с fakedns оставляем как был:
    // DNS идёт мимо нашего перехвата, ровно как до его появления.
    final usesFakeDns = custom.json.containsKey('fakedns') ||
        _dnsUsesFakeIp(effectiveDns);

    final dnsOutTag = _existingOutboundTag(custom, 'dns') ?? _customDnsTag;
    final inboundTags = <String>[
      for (final inbound in inbounds)
        if (inbound['tag'] is String) inbound['tag'] as String,
    ];
    final interceptDns = !usesFakeDns && inboundTags.isNotEmpty;
    final dnsRules = <Map<String, dynamic>>[
      if (interceptDns)
        {
          'type': 'field',
          'ruleTag': 'dns-out',
          'inboundTag': inboundTags,
          'port': '53',
          'network': 'tcp,udp',
          'outboundTag': dnsOutTag,
        },
    ];

    // Тот же перехват, но по служебному адресу TUN — и он обязан стоять перед
    // авторскими правилами, в отличие от общего выше.
    //
    // Системный резолвер на Android ходит на адрес из [_androidTunDns], а он
    // лежит в приватном диапазоне. Авторское `geoip:private -> direct` есть
    // почти в каждом готовом конфиге, и оно забирает запрос себе раньше:
    // ядро честно открывает сокет на 172.19.0.2:53 наружу, где никто не
    // слушает, и резолва нет вовсе — снаружи это «подключился, а интернета
    // нет». Ровно та же грабля, что у sing-box на десктопе (см. hijack-dns по
    // порту в singbox_tun_config).
    //
    // Принцип «автор разложил DNS сам — решает он» это не ломает: правило
    // матчит один служебный адрес, которого в авторском конфиге быть не может,
    // а общий перехват по порту 53 остаётся после авторских правил.
    final tunDnsRules = <Map<String, dynamic>>[
      if (interceptDns)
        {
          'type': 'field',
          'ruleTag': 'dns-out-tun',
          'inboundTag': inboundTags,
          'ip': ['$_androidTunDns/32'],
          'port': '53',
          'network': 'tcp,udp',
          'outboundTag': dnsOutTag,
        },
    ];

    // Финальное правило — в самый конец. У автора почти всегда есть свой
    // catch-all, и тогда наше не сработает вовсе; но если его нет, «остальной
    // трафик» из настроек должен решать он, а не молчаливый дефолт ядра
    // («первый аутбаунд в списке»).
    final finalTag = switch (settings.finalOutbound) {
      AppSettings.finalOutboundDirect => directTag,
      AppSettings.finalOutboundBlock => blockTag ?? _customBlockTag,
      _ => custom.primaryOutboundTag,
    };

    // Собственные запросы ядра к своему upstream в блок пускать нельзя.
    //
    // Авторский `dns.servers` — это чаще всего обычный UDP-53, а такой запрос
    // ядро отправляет через роутинг (для того и существует форма `+local`).
    // С финалом «блок» ядро блокирует собственный резолвер: молчит не только
    // перехваченный выше DNS устройства, но и `domainStrategy: IPIfNonMatch`
    // (в готовых конфигах он стоит почти всегда), то есть авторские
    // ip-правила по доменам разваливаются следом.
    //
    // Ловим такие запросы перед `final` и уводим напрямую — ровно так же
    // ходит DoH сгенерированных конфигов. Правило добавляем, только если
    // резолверу действительно нужен роутинг: у `https+local`/`localhost`
    // запросы идут мимо него, и «блок» остаётся буквальным.
    //
    // Когда перехвата нет (fakedns), это же правило спасает DNS самого
    // устройства: без него он падал бы в `final`, то есть в блок.
    final resolverNeedsRouting = _dnsGoesThroughRouting(effectiveDns);
    final resolverRules = <Map<String, dynamic>>[
      if ((resolverNeedsRouting || !interceptDns) &&
          settings.finalOutbound == AppSettings.finalOutboundBlock)
        {
          'type': 'field',
          'ruleTag': 'dns-resolver',
          'port': '53',
          'network': 'tcp,udp',
          'outboundTag': directTag,
        },
    ];

    final appendRules = <Map<String, dynamic>>[
      ...dnsRules,
      ...userRules,
      ...resolverRules,
      {
        'type': 'field',
        'ruleTag': 'final',
        'network': 'tcp,udp',
        'outboundTag': finalTag,
      },
    ];

    final usedTags = <String>{
      for (final rule in appendRules) rule['outboundTag'] as String,
      if (settings.lanSharing) blockTag ?? _customBlockTag,
    };

    final config = custom.buildSessionConfig(
      inbounds: inbounds,
      logLevel: settings.xrayCore.logLevel,
      // Подставится, только если своего dns-блока у автора нет: отвечать на
      // перехваченный выше DNS `dns`-аутбаунду больше нечем, а его дефолт
      // (`localhost`) на Android не резолвит ничего — системного резолвера
      // там нет.
      dns: fallbackDns,
      // LAN-правила остаются перед авторскими, и это не вкусовщина: инбаунд
      // LAN-прокси слушает 0.0.0.0, а `lan-deny` отсекает всё, что пришло в
      // него не из локальной сети. Пропусти вперёд авторское правило — и любой
      // запрос снаружи, попавший под него, уедет в туннель раньше запрета,
      // то есть прокси станет открытым для интернета.
      prependRules: [...lanRules, ...tunDnsRules],
      appendRules: appendRules,
      geoIndex: geoIndex,
    );

    // Дописываем только те аутбаунды, на которые реально кто-то ссылается:
    // правило с несуществующим тегом роняет разбор всего конфига.
    final extraOutbounds = <Map<String, dynamic>>[
      if (usedTags.contains(_customBlockTag))
        {'protocol': 'blackhole', 'tag': _customBlockTag},
      if (usedTags.contains(_customDirectTag))
        {'protocol': 'freedom', 'tag': _customDirectTag},
      if (usedTags.contains(_customDnsTag))
        {
          'protocol': 'dns',
          'tag': _customDnsTag,
          // Не-A/AAAA запросы отклоняем явно: это и так дефолт ядра, но смена
          // дефолта наверху не должна молча поменять наше поведение.
          'settings': {'nonIPQuery': 'reject'},
        },
    ];
    if (extraOutbounds.isNotEmpty) {
      config['outbounds'] = [
        ...(config['outbounds'] as List),
        ...extraOutbounds,
      ];
    }
    return config;
  }

  /// Отвечает ли dns-блок адресами из фейкового пула.
  static bool _dnsUsesFakeIp(Map<String, dynamic> dns) {
    final servers = dns['servers'];
    if (servers is! List) return false;
    return servers.any((server) {
      final address = switch (server) {
        String s => s,
        Map m => m['address']?.toString() ?? '',
        _ => '',
      };
      return address.trim().toLowerCase() == 'fakedns';
    });
  }

  /// Пойдут ли запросы встроенного резолвера через роутинг.
  ///
  /// В xray это решает форма адреса: `localhost` (системный резолвер), `fakedns`
  /// и любая схема с суффиксом `+local` отправляют запрос мимо роутинга, всё
  /// остальное — обычный UDP-53, `https://`, `tcp://` — идёт через него и
  /// попадает под наши правила наравне с трафиком приложений.
  static bool _dnsGoesThroughRouting(Map<String, dynamic> dns) {
    final servers = dns['servers'];
    if (servers is! List) return false;
    for (final server in servers) {
      final address = switch (server) {
        String s => s,
        Map m => m['address']?.toString() ?? '',
        _ => '',
      }
          .trim()
          .toLowerCase();
      if (address.isEmpty) continue;
      if (address == 'localhost' || address == 'fakedns') continue;
      final scheme = RegExp(r'^([a-z][a-z0-9.+-]*)://').firstMatch(address);
      if (scheme != null) {
        final name = scheme.group(1)!;
        // `dhcp` спрашивает адрес резолвера у системы, а не по сети.
        if (name.endsWith('+local') || name == 'dhcp') continue;
      }
      return true;
    }
    return false;
  }

  /// Правила из пользовательских списков для готового (custom) конфига.
  ///
  /// Порядок тот же, что и в сгенерированном конфиге ([_wrapConfig]): блок,
  /// обход, прокси — иначе одно и то же правило вело бы себя по-разному в
  /// зависимости от типа сервера. Приватные диапазоны сюда не добавляем: у
  /// автора для них своё правило, а наше перебило бы его.
  static List<Map<String, dynamic>> _customUserRules(
    AppSettings settings, {
    required String directTag,
    required String proxyTag,
    required String blockTag,
  }) {
    final rules = <Map<String, dynamic>>[];

    void addGroup(String source, String outboundTag, String tagPrefix) {
      final split = splitDomainsAndIps(_parseRuleList(source));
      final geo = splitGeoipTokens(split.ips);
      final domains = _normalizeDomains(split.domains);
      final ips = geo.plainIps
          .where((e) => !e.trim().toLowerCase().startsWith('geoip:'))
          .toList();

      if (domains.isNotEmpty) {
        rules.add({
          'type': 'field',
          'ruleTag': '$tagPrefix-domains',
          'domain': domains,
          'outboundTag': outboundTag,
        });
      }
      if (geo.geoipCodes.isNotEmpty) {
        rules.add({
          'type': 'field',
          'ruleTag': '$tagPrefix-geoip',
          'ip': geo.geoipCodes.map((c) => 'geoip:$c').toList(),
          'outboundTag': outboundTag,
        });
      }
      if (ips.isNotEmpty) {
        rules.add({
          'type': 'field',
          'ruleTag': '$tagPrefix-ips',
          'ip': ips,
          'outboundTag': outboundTag,
        });
      }
    }

    addGroup(settings.blockedRules, blockTag, 'user-block');
    addGroup(settings.directRules, directTag, 'user-direct');
    addGroup(settings.proxyRules, proxyTag, 'user-proxy');
    return rules;
  }

  /// Тег первого аутбаунда с указанным протоколом — чтобы не дописывать свой,
  /// когда у автора он уже есть.
  static String? _existingOutboundTag(
    CustomXrayConfig custom,
    String protocol,
  ) {
    final outbounds = custom.json['outbounds'];
    if (outbounds is! List) return null;
    for (final item in outbounds) {
      if (item is! Map) continue;
      if (item['protocol']?.toString().toLowerCase() != protocol) continue;
      final tag = item['tag']?.toString().trim() ?? '';
      if (tag.isNotEmpty) return tag;
    }
    return null;
  }

  /// Роутинг конфига пробы: сам сервер и приватные сети — мимо туннеля,
  /// остальное — в основной аутбаунд (иначе авторское правило могло бы увести
  /// пробу напрямую, и «пинг сервера» мерил бы вовсе не сервер).
  static List<Map<String, dynamic>> _customPingRules({
    required String serverAddress,
    required String originalAddress,
    required String proxyTag,
  }) {
    final rules = <Map<String, dynamic>>[];
    final isServerIp =
        serverAddress.isNotEmpty && _isIpLiteral(serverAddress);
    if (isServerIp) {
      rules.add({
        'type': 'field',
        'ip': [serverAddress],
        'outboundTag': _pingDirectTag,
      });
    }
    if (originalAddress.isNotEmpty) {
      if (!_isIpLiteral(originalAddress)) {
        rules.add({
          'type': 'field',
          'domain': ['full:$originalAddress'],
          'outboundTag': _pingDirectTag,
        });
      } else if (!isServerIp) {
        rules.add({
          'type': 'field',
          'ip': [originalAddress],
          'outboundTag': _pingDirectTag,
        });
      }
    }
    rules.add({
      'type': 'field',
      'ip': [
        '0.0.0.0/8', '10.0.0.0/8', '127.0.0.0/8', '172.16.0.0/12',
        '192.168.0.0/16', '::1/128', 'fc00::/7', 'fe80::/10',
      ],
      'outboundTag': _pingDirectTag,
    });
    rules.add({
      'type': 'field',
      'outboundTag': proxyTag,
      'network': 'tcp,udp',
    });
    return rules;
  }

  /// Блок `xhttpSettings.extra` из share-ссылки.
  ///
  /// У xray это не «дополнительные поля»: объект из `extra` замещает собой весь
  /// блок XHTTP, и от внешнего остаются только `host`, `path` и `mode`. Панели
  /// кладут туда всё прочее — паддинг, лимиты, заголовки, xmux. Пока мы этот
  /// параметр выбрасывали, сервер получал клиента с настройками по умолчанию
  /// вместо своих.
  ///
  /// [paddingBytes] — старая плоская форма для ссылок без `extra`; при
  /// конфликте выигрывает то, что автор положил в сам `extra`. Битый json
  /// разбор ссылки не роняет: сервер без паддинга лучше, чем сервер, который
  /// вообще не добавился.
  static Map<String, dynamic>? _xhttpExtra(String raw, String paddingBytes) {
    Map<String, dynamic>? extra;
    final trimmed = raw.trim();
    if (trimmed.isNotEmpty) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          extra = Map<String, dynamic>.from(decoded);
        }
      } on FormatException {
        // не наша забота чинить чужую ссылку — молча игнорируем
      }
    }
    final padding = paddingBytes.trim();
    if (padding.isNotEmpty) {
      extra ??= <String, dynamic>{};
      extra.putIfAbsent('xPaddingBytes', () => padding);
    }
    final download = extra?['downloadSettings'];
    if (download is Map<String, dynamic>) _fillDownloadFingerprint(download);
    return (extra == null || extra.isEmpty) ? null : extra;
  }

  /// Скачивание по `downloadSettings` — отдельное подключение со своим TLS, и
  /// без отпечатка ядро представилось бы в нём Chrome. Пишем тот же
  /// [defaultTlsFingerprint], что и основному.
  static void _fillDownloadFingerprint(Map<String, dynamic> download) {
    final key = switch (download['security']?.toString().toLowerCase()) {
      'tls' => 'tlsSettings',
      'reality' => 'realitySettings',
      _ => null,
    };
    if (key == null) return;
    final settings = download[key] is Map
        ? Map<String, dynamic>.from(download[key] as Map)
        : <String, dynamic>{};
    if ((settings['fingerprint']?.toString().trim() ?? '').isEmpty) {
      settings['fingerprint'] = defaultTlsFingerprint;
    }
    download[key] = settings;
  }

  /// Размер ранних данных — в путь, потому что ядро читает его только оттуда.
  ///
  /// Отдельного поля у ядра нет вовсе: `WebSocketConfig.Build` разбирает путь и
  /// вынимает `ed` из его запроса сам (`infra/conf/transport_method.go`), у
  /// httpupgrade то же. Ссылки же несут его и так, и так — v2rayN кладёт в
  /// путь, стандарт #716 отдельным параметром.
  static String _pathWithEarlyData(String path, String ed) {
    final size = int.tryParse(ed.trim());
    if (size == null || size <= 0) return path;
    if (path.contains('ed=')) return path;
    return path.contains('?') ? '$path&ed=$size' : '$path?ed=$size';
  }

  /// client-side xhttp extras (xmux) and similar stream options.
  /// Мультиплексор на выходной аутбаунд — там, где ядро его поймёт.
  ///
  /// Mux — надстройка над протоколом: клиент дозванивается до служебного адреса
  /// `v1.mux.cool`, а пачку разбирает сервер. На стороне сервера этим занят
  /// общий обработчик (`common/mux/server.go`), одинаковый для всех инбаундов,
  /// поэтому годятся vless, vmess и trojan — trojan в том числе, хотя Happ его
  /// исключает. Shadowsocks же уедет к чужому серверу, который про `mux.cool`
  /// не знает и попробует резолвить этот домен как обычный. Hysteria возит
  /// датаграммы своим способом, ей мультиплексор поверх не нужен.
  ///
  /// XHTTP исключён по другой причине: он мультиплексирует сам (`extra.xmux`),
  /// и второй слой поверх первого только добавит очередь.
  static void _applyMux(Map<String, dynamic> outbound, XrayCoreSettings core) {
    final mux = core.buildMuxMap();
    if (mux == null) return;
    const muxable = {'vless', 'vmess', 'trojan'};
    if (!muxable.contains(outbound['protocol']?.toString())) return;
    final stream = outbound['streamSettings'];
    final network =
        stream is Map<String, dynamic> ? stream['network']?.toString() : null;
    if (network == 'xhttp' || network == 'splithttp') return;

    // Vision пускает в пачку только UDP: сервер обрывает всё mux-соединение,
    // если внутри оказался TCP («it will break the whole Mux connection» —
    // common/mux/server.go, ветка vless.XRV в inbound.go). Настройка тут не
    // спорит с ядром: включённый mux с vision означает XUDP и ничего больше.
    outbound['mux'] = _hasVisionFlow(outbound)
        ? {...mux, 'concurrency': -1}
        : mux;
  }

  static bool _hasVisionFlow(Map<String, dynamic> outbound) {
    final settings = outbound['settings'];
    if (settings is! Map) return false;
    return (settings['flow']?.toString().trim() ?? '')
        .startsWith('xtls-rprx-vision');
  }

  static void _applyXrayStreamExtras(
    Map<String, dynamic> outbound,
    XrayCoreSettings core,
  ) {
    final stream = outbound['streamSettings'];
    if (stream is! Map<String, dynamic>) return;
    final network = stream['network']?.toString() ?? '';
    if (network != 'xhttp' && network != 'splithttp') return;

    final xmux = core.buildXmuxMap();
    if (xmux == null) return;

    final xhttp = Map<String, dynamic>.from(
      (stream['xhttpSettings'] as Map<String, dynamic>?) ?? {},
    );
    final extra = Map<String, dynamic>.from(
      (xhttp['extra'] as Map<String, dynamic>?) ?? {},
    );
    extra['xmux'] = xmux;
    xhttp['extra'] = extra;
    stream['xhttpSettings'] = xhttp;
  }

  // vless
  static Map<String, dynamic> _buildVlessOutbound(
      Uri uri, String Function(String, [String]) getParam, String address, int port, Map<String, dynamic> streamSettings) {
    final uuid = uri.userInfo;
    if (uuid.isEmpty) {
      throw ArgumentError('VLESS requires UUID in userInfo');
    }

    final flow = getParam('flow');
    final encryption = getParam('encryption', 'none').trim().isEmpty
        ? 'none'
        : getParam('encryption', 'none').trim();

    return {
      'tag': 'proxy',
      'protocol': 'vless',
      'settings': {
        'address': address,
        'port': port,
        'id': uuid,
        'encryption': encryption,
        if (flow.isNotEmpty) 'flow': flow,
        'level': 0,
      },
      'streamSettings': _buildStreamSettings(getParam, address, streamSettings),
    };
  }

  // vmess
  static Map<String, dynamic> _buildVmessOutbound(
      Uri uri, Map<String, dynamic>? vmessConfig, String Function(String, [String]) getParam,
      String address, int port, Map<String, dynamic> streamSettings) {
    final uuid = (vmessConfig?['id'] ?? uri.userInfo).toString();
    if (uuid.isEmpty) {
      throw ArgumentError('VMess requires id in payload');
    }

    // У AEAD-ссылки шифр приезжает в `encryption` — так его называет стандарт
    // и так его читает mihomo (`converter.go`, ветка vmess).
    final vmessSecurity = vmessConfig?['security']?.toString() ??
        vmessConfig?['scy']?.toString() ??
        (vmessConfig == null ? getParam('encryption', 'auto') : 'auto');
    final flow = vmessConfig?['flow']?.toString() ?? getParam('flow');

    return {
      'tag': 'proxy',
      'protocol': 'vmess',
      'settings': {
        'address': address,
        'port': port,
        'id': uuid,
        'security': vmessSecurity,
        'level': 0,
        if (flow.isNotEmpty) 'flow': flow,
      },
      'streamSettings': _buildStreamSettings(
        vmessConfig != null ? _vmessStreamParams(vmessConfig) : getParam,
        address,
        streamSettings,
      ),
    };
  }

  /// Параметры транспорта vmess-ссылки в том виде, в каком их спрашивает
  /// [_buildStreamSettings]: у vmess они не в запросе, а полями base64-json, и
  /// имена там свои.
  ///
  /// Поля разведены руками. `type` в json — это заголовок маскировки, сам
  /// транспорт лежит в `net`. `security` там бывает шифром vmess, а не
  /// `tls`/`reality`: совпади имена, ссылка с `"security":"auto"` осталась бы
  /// без TLS вовсе. Имя gRPC-сервиса и seed mKCP v2rayN кладёт в `path`
  /// (VmessFmt.cs) — своих полей у них нет, и потому grpc у vmess не
  /// собирался никогда.
  static String Function(String, [String]) _vmessStreamParams(
      Map<String, dynamic>? cfg) {
    String raw(String key) {
      final value = cfg?[key];
      if (value == null) return '';
      // `extra` у xhttp приезжает вложенным объектом, а дальше его ждёт
      // jsonDecode, — не `toString()` дартовой карты.
      return (value is Map || value is List)
          ? jsonEncode(value)
          : value.toString();
    }

    return (String key, [String def = '']) {
      final value = switch (key) {
        'type' => raw('net'),
        'headerType' => raw('type'),
        'security' => raw('tls').toLowerCase() == 'tls' ? 'tls' : '',
        'serviceName' => raw('path'),
        'seed' => const {'kcp', 'mkcp'}.contains(raw('net').toLowerCase())
            ? raw('path')
            : raw('seed'),
        _ => raw(key),
      };
      return value.isEmpty ? def : value;
    };
  }

  /// userInfo ссылки раскодированным. Пароль со спецсимволами стандарт ссылки
  /// несёт закодированным (`p%40ss`), так его читает и разбор mihomo
  /// (`url.User` в common/convert); без этого в ядро уезжал `p%40ss`. Битое
  /// кодирование оставляем как есть — это тоже бывает паролем.
  static String _decodedUserInfo(Uri uri) {
    try {
      return Uri.decodeComponent(uri.userInfo);
    } catch (_) {
      return uri.userInfo;
    }
  }

  // trojan
  static Map<String, dynamic> _buildTrojanOutbound(
      Uri uri, String Function(String, [String]) getParam, Map<String, dynamic>? vmessConfig,
      String address, int port, Map<String, dynamic> streamSettings) {
    final password = vmessConfig != null
        ? (vmessConfig['id']?.toString() ?? '')
        : _decodedUserInfo(uri);
    if (password.isEmpty) {
      throw ArgumentError('Trojan requires password in userInfo');
    }

    final email = getParam('email');

    // Trojan без TLS не бывает: протокол — это TLS плюс пароль. Ссылки при этом
    // сплошь пишут `security=none` копипастой, поэтому чужое значение здесь не
    // слушаем — кроме REALITY, ради которого поле и читается.
    String stream(String key, [String def = '']) {
      if (key != 'security') return getParam(key, def);
      return getParam('security').trim().toLowerCase() == 'reality'
          ? 'reality'
          : 'tls';
    }

    _buildStreamSettings(
      stream,
      address,
      streamSettings,
      defaultSecurity: 'tls',
      sniFallback: address,
    );

    return {
      'tag': 'proxy',
      'protocol': 'trojan',
      'settings': {
        'address': address,
        'port': port,
        'password': password,
        if (email.isNotEmpty) 'email': email,
        'level': 0,
      },
      'streamSettings': streamSettings,
    };
  }

  // shadowsocks
  static Map<String, dynamic> _buildShadowsocksOutbound(
      Uri uri, String Function(String, [String]) getParam, String address, int port) {
    // sip002: ss://base64(method:password@host:port) или ss://method:password@host:port
    // также бывает ss://base64(method:password)@host:port
    final withoutScheme = uri.toString().replaceFirst('ss://', '').trim();
    final hashIdx = withoutScheme.indexOf('#');
    final beforeHash = hashIdx >= 0 ? withoutScheme.substring(0, hashIdx) : withoutScheme;
    final atIdx = beforeHash.lastIndexOf('@');

    String method;
    String password;

    if (atIdx < 0) {
      throw ArgumentError('Shadowsocks requires userInfo with method:password');
    }

    final userInfo = beforeHash.substring(0, atIdx);

    if (userInfo.contains(':')) {
      // plain text method:password
      final splitIdx = userInfo.indexOf(':');
      method = userInfo.substring(0, splitIdx);
      password = userInfo.substring(splitIdx + 1);
    } else {
      // base64 method:password (sip002)
      final decoded = _decodeBase64UrlCompat(userInfo);
      final splitIdx = decoded.indexOf(':');
      if (splitIdx <= 0 || splitIdx >= decoded.length - 1) {
        throw ArgumentError('Invalid Shadowsocks userInfo format');
      }
      method = decoded.substring(0, splitIdx);
      password = decoded.substring(splitIdx + 1);
    }

    final email = getParam('email');

    // `uot`/`UoTVersion` отсюда убраны: у shadowsocks в xray 26 таких полей нет
    // вовсе (`infra/conf/shadowsocks.go` — адрес, метод, пароль, email,
    // уровень), и ядро их молча выбрасывало. UDP внутри TCP умеет только
    // mihomo, туда такую ссылку и разводит правило выбора ядра.
    return {
      'tag': 'proxy',
      'protocol': 'shadowsocks',
      'settings': {
        'address': address,
        'port': port,
        'method': method,
        'password': password,
        if (email.isNotEmpty) 'email': email,
        'level': 0,
      },
      'streamSettings': {'network': 'tcp'},
    };
  }

  // hysteria / hy2
  static Map<String, dynamic> _buildHysteriaOutbound(
      Uri uri,
      String rawLink,
      String Function(String, [String]) getParam,
      String address,
      int port,
      Map<String, dynamic> streamSettings,
  ) {
    var auth = getParam('auth', getParam('password', '')).trim();
    if (auth.isEmpty && uri.userInfo.isNotEmpty) {
      auth = _decodedUserInfo(uri).trim();
    }
    if (auth.isEmpty) {
      throw ArgumentError('Hysteria requires auth/password in URI (query or userInfo)');
    }

    final udpIdleTimeout = int.tryParse(getParam('udpIdleTimeout', '60')) ?? 60;

    Map<String, dynamic>? buildMasquerade() {
      final type = getParam('masqueradeType', getParam('masqType', ''));
      final dir = getParam('masqueradeDir', getParam('masqDir', ''));
      final url = getParam('masqueradeUrl', getParam('masqUrl', ''));
      final content = getParam('masqueradeContent', getParam('masqContent', ''));
      final statusCode = int.tryParse(getParam('masqueradeStatusCode', getParam('masqStatusCode', '')));

      if (type.isEmpty && dir.isEmpty && url.isEmpty && content.isEmpty && statusCode == null) {
        return null;
      }

      final map = <String, dynamic>{
        if (type.isNotEmpty) 'type': type,
        if (dir.isNotEmpty) 'dir': dir,
        if (url.isNotEmpty) 'url': url,
        if (content.isNotEmpty) 'content': content,
        'statusCode': ?statusCode,
      };
      return map;
    }

    // Из исходной ссылки, а не из [uri]: список портов мог стоять в адресе, и
    // при разборе его оттуда уже вынули.
    final hyParams = HysteriaLinkParams.fromConfig(rawLink);
    final sni = getParam('sni', hyParams.sni.isNotEmpty ? hyParams.sni : address);
    // Схема `hysteria://` одна на обе версии, и без проверки первая собиралась
    // бы как вторая: конфиг не того протокола, сервер молчит, а снаружи это
    // «сервер не работает». Признаки версии — в [HysteriaLinkParams.isV1].
    final version = int.tryParse(getParam('version', '2')) ?? 2;
    if (version != 2 || HysteriaLinkParams.isV1(uri.toString())) {
      throw ArgumentError(
        'Hysteria v1 is not supported. Use a hysteria2:// or hy2:// link.',
      );
    }

    final alpnRaw = getParam('alpn', hyParams.alpn);
    final alpnForTls = alpnRaw.isNotEmpty ? alpnRaw : 'h3';

    // xray 26+ removed standalone "quic"; use the dedicated "hysteria" network
    streamSettings['network'] = 'hysteria';
    streamSettings['security'] = 'tls';
    streamSettings['tlsSettings'] = _tlsClientSettings(
      serverName: sni,
      network: 'hysteria',
      fingerprint: getParam('fp', ''),
      alpnQuery: alpnForTls,
      echConfigList: getParam('ech'),
      pinnedPeerCertSha256: getParam('pinSHA256', hyParams.pinSha256),
    );

    streamSettings['hysteriaSettings'] = <String, dynamic>{
      'version': version,
      'auth': auth,
      'udpIdleTimeout': udpIdleTimeout,
      'masquerade': ?buildMasquerade(),
    };

    // Полоса и перебор портов в xray 26 живут в finalmask.quicParams. Из
    // hysteriaSettings ядро их читает, пишет предупреждение и выбрасывает
    // (HysteriaConfig.Build, infra/conf/transport_method.go) — там заданная
    // скорость и смена портов молча не работали.
    final quicParams = <String, dynamic>{};
    final up = HysteriaLinkParams.formatBandwidth(
      getParam('up', hyParams.up),
    );
    final down = HysteriaLinkParams.formatBandwidth(
      getParam('down', hyParams.down),
    );
    if (up != null) quicParams['brutalUp'] = up;
    if (down != null) quicParams['brutalDown'] = down;
    final mport = getParam('mport', hyParams.mport);
    if (mport.isNotEmpty) {
      quicParams['udpHop'] = <String, dynamic>{
        'ports': mport,
        'interval': ?_hopInterval(
          getParam('hop-interval', hyParams.hopInterval),
        ),
      };
    }

    final finalmask = hyParams.buildFinalmask() ?? <String, dynamic>{};
    if (quicParams.isNotEmpty) finalmask['quicParams'] = quicParams;
    if (finalmask.isNotEmpty) streamSettings['finalmask'] = finalmask;

    return {
      'tag': 'proxy',
      'protocol': 'hysteria',
      'settings': {
        'address': address,
        'port': port,
        'version': version,
      },
      'streamSettings': streamSettings,
    };
  }

  /// Интервал перебора портов в секундах, числом или диапазоном `30-60`.
  ///
  /// Меньше 5 секунд xray не принимает и отказывается от конфига целиком
  /// (infra/conf/transport_internet.go), mihomo такой поднимает до 5 —
  /// поднимаем так же. Нечитаемое значение отбрасываем: оно уронило бы весь
  /// конфиг, а без него ядро берёт свои 30 секунд.
  static String? _hopInterval(String raw) {
    final match = RegExp(r'^\s*(\d+)\s*(?:-\s*(\d+)\s*)?$').firstMatch(raw);
    if (match == null) return null;
    int? atLeast5(String? value) {
      final seconds = int.tryParse(value ?? '');
      if (seconds == null) return null;
      return seconds < 5 ? 5 : seconds;
    }

    final from = atLeast5(match.group(1));
    if (from == null) return null;
    final to = atLeast5(match.group(2)) ?? from;
    return to > from ? '$from-$to' : '$from';
  }

  // stream settings
  /// Транспорт и TLS из ссылки — один сборщик на vless, vmess и trojan.
  ///
  /// Сборок было три, и две из них умели только ws и grpc: сервер VMess или
  /// Trojan на httpupgrade, xhttp или с HTTP-маскировкой собирался без своих
  /// настроек и молча не подключался.
  ///
  /// Различия протоколов остались параметрами, потому что они настоящие.
  /// [defaultSecurity] — для trojan: TLS там подразумевается самим протоколом,
  /// и ссылки сплошь не пишут `security`. [sniFallback] — тоже для него: имя
  /// берётся от адреса, а не от `host`, как и в mihomo-генераторе, иначе смена
  /// ядра меняла бы имя в ClientHello.
  static Map<String, dynamic> _buildStreamSettings(
    String Function(String, [String]) getParam,
    String address,
    Map<String, dynamic> existing, {
    String defaultSecurity = 'none',
    String? sniFallback,
  }) {
    final type = getParam('type', 'tcp');
    final security = getParam('security', defaultSecurity);
    final sni = getParam('sni', sniFallback ?? getParam('host', address));

    final stream = existing;
    stream['network'] = type;
    stream['security'] = security;

    if (security == 'tls') {
      stream['tlsSettings'] = _tlsClientSettings(
        serverName: sni,
        network: type,
        fingerprint: getParam('fp', ''),
        alpnQuery: getParam('alpn'),
        echConfigList: getParam('ech'),
        pinnedPeerCertSha256: getParam('pcs'),
        verifyPeerCertByName: getParam('vcn'),
      );
    } else if (security == 'reality') {
      final rfp = getParam('fp', '').trim();
      stream['realitySettings'] = {
        'show': false,
        'fingerprint': rfp.isNotEmpty ? rfp : defaultTlsFingerprint,
        'serverName': sni,
        'publicKey': getParam('pbk'),
        'shortId': getParam('sid'),
        'spiderX': getParam('spx'),
        // Post-quantum подпись сертификата REALITY (ML-DSA-65). Без ключа
        // соединение всё равно встанет, но без дополнительной проверки — то
        // есть тише, чем просил тот, кто выдал ссылку.
        if (getParam('pqv').trim().isNotEmpty)
          'mldsa65Verify': getParam('pqv').trim(),
      };
    }

    // `fm` — finalmask сервера целиком: так его отдаёт 3X-UI эпохи xray 26
    // (`applyFinalMaskToParams`, inbound-link.ts) для любого транспорта. Маски
    // на обеих сторонах одни и те же, поэтому берём как есть. Одна оговорка
    // вне нашей власти: порядок масок в списке xray между 26.3 и 26.7
    // перевернул (стенд G-12), и две маски сервера на 26.3 наш клиент прочтёт
    // наоборот. Версии сервера ссылка не несёт.
    final finalmask = _finalmaskFromLink(getParam('fm'));
    if (finalmask != null) stream['finalmask'] = finalmask;

    switch (type) {
      case 'ws':
        stream['wsSettings'] = {
          'path': _pathWithEarlyData(getParam('path', '/'), getParam('ed')),
          'headers': {'Host': getParam('host', sni)},
        };
      case 'grpc':
        // `authority` — то имя, под которым запрос уезжает в HTTP/2; без него
        // ядро подставляет адрес узла, и сервер за общим фронтом отвечает 404.
        final authority = getParam('authority');
        stream['grpcSettings'] = {
          'serviceName': getParam('serviceName'),
          'multiMode': getParam('mode') == 'multi',
          if (authority.isNotEmpty) 'authority': authority,
        };
      case 'xhttp': case 'splithttp':
        final host = getParam('host');
        stream['xhttpSettings'] = {
          'path': getParam('path', '/'),
          'host': host.isNotEmpty ? host : sni,
          if (getParam('mode').isNotEmpty) 'mode': getParam('mode'),
          'extra': ?_xhttpExtra(
            getParam('extra'),
            getParam('x_padding_bytes', getParam('xPaddingBytes')),
          ),
        };
      case 'httpupgrade':
        stream['httpupgradeSettings'] = {
          'path': _pathWithEarlyData(getParam('path', '/'), getParam('ed')),
          'host': getParam('host', sni),
        };
      case 'kcp' || 'mkcp':
        final kcp = <String, dynamic>{
          'mtu': ?_intInRange(getParam('mtu'), 21, 65535),
          'tti': ?_intInRange(getParam('tti'), 10, 1000),
        };
        if (kcp.isNotEmpty) stream['kcpSettings'] = kcp;
        if (finalmask == null) {
          final masks = _legacyKcpMasks(
            getParam('headerType'),
            getParam('seed'),
          );
          if (masks != null) stream['finalmask'] = {'udp': masks};
        }
      // `raw` — новое имя `tcp` в ядре; в ссылках встречаются оба, и
      // mihomo-генератор давно считает их одним транспортом.
      case 'tcp' || 'raw':
        if (getParam('headerType') == 'http') {
          // Путь маскировки ядро берёт списком (`AuthenticatorRequest.Path`).
          // Пустым его не пишем: у ядра по умолчанию `/`, а пустой список оно
          // поняло бы как запрос без пути вовсе.
          final path = getParam('path');
          final method = getParam('method');
          stream['tcpSettings'] = {
            'header': {
              'type': 'http',
              'request': {
                if (method.isNotEmpty) 'method': method,
                if (path.isNotEmpty) 'path': [path],
                'headers': {'Host': [getParam('host', address)]},
              },
            },
          };
        }
    }
    return stream;
  }

  /// `fm` ссылки — finalmask сервера целиком. Нечитаемый json не переносим:
  /// ядро отказалось бы от конфига целиком.
  static Map<String, dynamic>? _finalmaskFromLink(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> && decoded.isNotEmpty
          ? decoded
          : null;
    } on FormatException {
      return null;
    }
  }

  /// Маски mKCP по ссылке старого вида — с `headerType` или `seed`.
  ///
  /// xray 26 снял оба поля из kcpSettings (с ними KCPConfig.Build роняет весь
  /// конфиг) и заодно прежнюю обфускацию по умолчанию: без масок он шлёт
  /// голые кадры, и сервер до 26 их не принимает. Прежний провод — маска
  /// mkcp-legacy: пустая — та обфускация, `value` — шифрование на seed,
  /// `header` — маскировка. Заголовок последним, ближе к сети, как клеил его
  /// старый сервер. Каждое сочетание проверено трафиком против xray 25.12.8,
  /// и подходит ровно одно (refactor/PROGRESS.md, G-12).
  ///
  /// Новые панели (3X-UI под xray 26) ни `headerType`, ни `seed` у kcp не
  /// пишут, а маски отдают в `fm`. Ссылка без них — сервер без масок: null.
  static List<Map<String, dynamic>>? _legacyKcpMasks(
    String header,
    String seed,
  ) {
    var h = header.trim().toLowerCase();
    final s = seed.trim();
    if (h.isEmpty && s.isEmpty) return null;
    // У старых ядер этот заголовок звался wechat-video.
    if (h == 'wechat-video') h = 'wechat';
    final withHeader = h.isNotEmpty && h != 'none';
    if (withHeader && !_mkcpHeaders.contains(h)) {
      throw ArgumentError('mKCP header "$header" is not known to the core');
    }
    return [
      {
        'type': 'mkcp-legacy',
        if (s.isNotEmpty) 'settings': {'value': s},
      },
      if (withHeader)
        {
          'type': 'mkcp-legacy',
          'settings': {'header': h},
        },
    ];
  }

  /// Заголовки, которые знает mkcp-legacy (MkcpLegacy.Build,
  /// infra/conf/transport_finalmask.go); с любым другим ядро роняет конфиг.
  static const _mkcpHeaders = {
    'dns',
    'dtls',
    'srtp',
    'utp',
    'wechat',
    'wireguard',
  };

  /// Число из ссылки, если ядро его примет: вне своих границ mtu и tti xray
  /// роняет весь конфиг (KCPConfig.Build).
  static int? _intInRange(String raw, int min, int max) {
    final value = int.tryParse(raw.trim());
    return value != null && value >= min && value <= max ? value : null;
  }

  // обёртка конфига
  //
  // [proxyOutbounds] — аутбаунды сервера: у одиночного он один, у цепочки это
  // выходной узел (тег `proxy`, всегда первым) и остальные звенья.
  // [extraServerAddresses] — адреса промежуточных узлов цепочки: для них тоже
  // нужно правило «мимо туннеля».
  static Map<String, dynamic> _wrapConfig(
      List<Map<String, dynamic>> proxyOutbounds, AppSettings settings, String serverAddress, int serverPort,
      {String? originalServerAddress, List<String> extraServerAddresses = const [], int? pingSocksPort, bool pingHttpInbound = false, bool localInboundsNoAuth = false, bool nativeTunInbound = false}) {

    originalServerAddress ??= serverAddress;
    final isPingMode = pingSocksPort != null;

    // each list is mixed (domains + ip/cidr + geoip:); split per kind.
    final directSplit  = splitDomainsAndIps(_parseRuleList(settings.directRules));
    final proxySplit   = splitDomainsAndIps(_parseRuleList(settings.proxyRules));
    final blockedSplit = splitDomainsAndIps(_parseRuleList(settings.blockedRules));

    final directGeo    = splitGeoipTokens(directSplit.ips);
    final proxyGeo     = splitGeoipTokens(proxySplit.ips);
    final blockedGeo   = splitGeoipTokens(blockedSplit.ips);

    final directDomains  = _normalizeDomains(directSplit.domains);
    final blockedDomains = _normalizeDomains(blockedSplit.domains);
    final proxyDomains   = _normalizeDomains(proxySplit.domains);
    final directIps      = directGeo.plainIps
        .where((e) => !e.trim().toLowerCase().startsWith('geoip:'))
        .toList();
    final proxyIps       = proxyGeo.plainIps
        .where((e) => !e.trim().toLowerCase().startsWith('geoip:'))
        .toList();
    final blockedIps     = blockedGeo.plainIps
        .where((e) => !e.trim().toLowerCase().startsWith('geoip:'))
        .toList();
    final directGeoip    = directGeo.geoipCodes;
    final proxyGeoip     = proxyGeo.geoipCodes;
    final blockedGeoip   = blockedGeo.geoipCodes;

    // Базовые приватные/LAN диапазоны — всегда direct, не считаются
    // «пользовательскими» IP-правилами (иначе стратегию поднимало бы всегда).
    final extraDirectIps = directIps
        .where((ip) => !_basePrivateRanges.contains(ip.trim()))
        .toList();

    final core = settings.xrayCore;

    // Если пользователь задал собственные IP/CIDR-правила (напр. корпоративный
    // 10.130.0.0/16 в Direct), они должны срабатывать и для соединений по
    // домену: браузер через прокси шлёт `CONNECT host:443`, и под `AsIs` xray
    // не резолвит домен → IP-правило игнорируется, трафик уходит в proxy (баг
    // «CIDR direct не работает»). `IPIfNonMatch` резолвит не совпавший с
    // доменными правилами домен и проверяет IP-правила — корп-CIDR начинает
    // работать. Без пользовательских IP-правил остаёмся на `AsIs` (не резолвим
    // проксируемые домены — приватнее и быстрее). Явный выбор ≠ AsIs уважаем.
    final hasUserIpRules =
        extraDirectIps.isNotEmpty || proxyIps.isNotEmpty || blockedIps.isNotEmpty;
    final effectiveDomainStrategy =
        (!isPingMode && hasUserIpRules && core.routingDomainStrategy == 'AsIs')
            ? 'IPIfNonMatch'
            : core.routingDomainStrategy;
    // Адреса самих серверов — в bootstrap-список DNS (см. buildDnsBlock).
    // IP-литералы туда не нужны: резолвить нечего.
    final bootstrapDomains = <String>[
      for (final addr in [originalServerAddress, ...extraServerAddresses])
        if (addr.trim().isNotEmpty && !_isIpLiteral(addr)) 'full:${addr.trim()}',
    ];

    // Перехват DNS имеет смысл только там, где «остальное» уходит в туннель:
    // см. `proxiedDoh` в buildDnsBlock.
    final globalProxy = settings.finalOutbound == AppSettings.finalOutboundProxy;

    final dns = isPingMode
        ? {
            // Тот же DoH, что и в боевом конфиге: пинг дозванивается до того же
            // домена сервера, и резолвить его другим путём — значит мерить не
            // то, что потом будет подключаться. Обычный UDP-53 к 8.8.8.8 у
            // части провайдеров подменяется, и пинг краснел бы на живом
            // сервере. Системный резолвер — последним, как и там.
            'servers': [
              'https+local://1.1.1.1/dns-query',
              'https+local://8.8.8.8/dns-query',
              'localhost',
            ],
            'queryStrategy': 'UseIPv4',
          }
        : core.buildDnsBlock(
            directDomains: directDomains,
            bootstrapDomains: bootstrapDomains,
            proxiedDoh: globalProxy,
          );

    // `ruleTag` — имя правила в логах ядра: xray печатает «Hit route rule:
    // [tag] so taking detour [proxy] for [tcp:host:443]» (уровень логов Info),
    // и по нему дебаг-экран «Соединения» показывает, по какому правилу ушло
    // соединение. В ping-режиме теги не нужны (там log level none).
    final rules = <Map<String, dynamic>>[];
    Map<String, dynamic> rule(
      String tag,
      Map<String, dynamic> fields,
    ) => {
          'type': 'field',
          ...fields,
          if (!isPingMode) 'ruleTag': tag,
        };

    rules.add(rule('block-special', {
      'ip': ['169.254.0.0/16', '224.0.0.0/4', '255.255.255.255/32'],
      'outboundTag': 'block',
    }));

    // «Мимо туннеля» для промежуточных узлов цепочки — той же формы правило,
    // что и для самого сервера выше. Сама цепочка через роутинг не проходит
    // (dialerProxy отдаёт соединение хендлеру напрямую), так что правило
    // защищает пользовательские обращения к этим адресам от закольцовывания.
    void addChainHopDirectRules() {
      for (var i = 0; i < extraServerAddresses.length; i++) {
        final addr = extraServerAddresses[i].trim();
        if (addr.isEmpty) continue;
        rules.add(rule(
          'chain-hop-$i',
          _isIpLiteral(addr)
              ? {'ip': [addr], 'outboundTag': 'direct'}
              : {'domain': ['full:$addr'], 'outboundTag': 'direct'},
        ));
      }
    }

    if (isPingMode) {
      final isServerIp = _isIpLiteral(serverAddress);
      if (isServerIp) {
        rules.add({'type': 'field', 'ip': [serverAddress], 'outboundTag': 'direct'});
      }
      if (!_isIpLiteral(originalServerAddress)) {
        rules.add({'type': 'field', 'domain': ['full:$originalServerAddress'], 'outboundTag': 'direct'});
      } else if (!isServerIp) {
        rules.add({'type': 'field', 'ip': [originalServerAddress], 'outboundTag': 'direct'});
      }
      addChainHopDirectRules();
      rules.add({
        'type': 'field',
        'ip': [
          '0.0.0.0/8', '10.0.0.0/8', '127.0.0.0/8', '172.16.0.0/12',
          '192.168.0.0/16', '::1/128', 'fc00::/7', 'fe80::/10',
        ],
        'outboundTag': 'direct',
      });
    } else {
    if (!isPingMode && settings.lanSharing) {
      rules.add(rule('lan-allow', {
        'inboundTag': ['socks-lan', 'http-lan'],
        'source': [
          '10.0.0.0/8',
          '172.16.0.0/12',
          '192.168.0.0/16',
          '169.254.0.0/16',
          '127.0.0.0/8',
        ],
        'outboundTag': 'proxy',
      }));
      rules.add(rule('lan-deny', {
        'inboundTag': ['socks-lan', 'http-lan'],
        'network': 'tcp,udp',
        'outboundTag': 'block',
      }));
    }
    // DNS устройства отвечает само ядро, а не сервер на том конце туннеля.
    //
    // TUN отдаёт системе 8.8.8.8, и без этого правила каждый запрос уезжал в
    // туннель отдельной сессией — то есть отдельным TCP до сервера. Android
    // шлёт их пачками (в логах по 5–7 одновременно), и на сервере с лимитом
    // новых соединений с одного адреса такая пачка выносит весь лимит: часть
    // соединений проходит, остальные висят с молча дропнутым SYN. Именно так
    // выглядела «Нидерланды не работают, а в FlClash работают» — mihomo с
    // fake-ip на DNS соединений не тратит вовсе.
    //
    // `dns`-аутбаунд отвечает из dns-блока конфига: A/AAAA — локально и
    // бесплатно, остальные типы — `reject` (дефолт ядра, задаём явно, чтобы
    // смена дефолта наверху не поменяла наше поведение молча).
    //
    // после lan-правил, не до: инбаунд LAN-прокси слушает 0.0.0.0, и перехвати
    // мы DNS раньше запрета — получили бы открытый резолвер наружу.
    rules.add(rule('dns-out', {
      'port': '53',
      'network': 'tcp,udp',
      'outboundTag': 'dns-out',
    }));
    if (blockedDomains.isNotEmpty) {
      rules.add(rule('block-domains',
          {'domain': blockedDomains, 'outboundTag': 'block'}));
    }
    if (blockedGeoip.isNotEmpty) {
      // xray has no top-level `geoip` rule field; geoip codes ride the `ip`
      // field as `geoip:xx` tokens. A bare `geoip` key is silently dropped and
      // the core aborts with "this rule has no effective fields".
      rules.add(rule('block-geoip', {
        'ip': blockedGeoip.map((c) => 'geoip:$c').toList(),
        'outboundTag': 'block',
      }));
    }
    if (blockedIps.isNotEmpty) {
      rules.add(rule('block-ips', {'ip': blockedIps, 'outboundTag': 'block'}));
    }
    final isServerIp = _isIpLiteral(serverAddress);
    if (isServerIp) {
      rules.add(rule('server-ip',
          {'ip': [serverAddress], 'outboundTag': 'direct'}));
    }
    if (!_isIpLiteral(originalServerAddress)) {
      rules.add(rule('server-domain', {
        'domain': ['full:$originalServerAddress'],
        'outboundTag': 'direct',
      }));
    } else if (!isServerIp) {
      rules.add(rule('server-address',
          {'ip': [originalServerAddress], 'outboundTag': 'direct'}));
    }
    addChainHopDirectRules();
    if (directDomains.isNotEmpty) {
      rules.add(rule('direct-domains',
          {'domain': directDomains, 'outboundTag': 'direct'}));
    }
    if (directGeoip.isNotEmpty) {
      rules.add(rule('direct-geoip', {
        'ip': directGeoip.map((c) => 'geoip:$c').toList(),
        'outboundTag': 'direct',
      }));
    }
    rules.add(rule('direct-private', {
      'ip': [
        ...extraDirectIps,
        ..._basePrivateRanges,
      ],
      'outboundTag': 'direct',
    }));
    // QUIC в vision-аутбаунд не пролезает — и узнаёт об этом ядро слишком поздно.
    //
    // При `flow=xtls-rprx-vision` xray отвергает UDP/443 (`XTLS rejected UDP/443
    // traffic`), но только после того, как поднял до сервера полноценное
    // TCP+TLS-соединение: отказ живёт в vless-аутбаунде, за диалером. Каждый
    // QUIC-пакет, который приложение шлёт «на всякий случай», стоит нам одного
    // рукопожатия до сервера, выброшенного в мусор. В логе это видно прямо: одна
    // цель (`udp:188.234.73.160:443`) успевает съесть пять рукопожатий за 2.5
    // секунды, потому что приложение ретраит QUIC, а ядро каждый раз честно
    // дозванивается до сервера заново.
    //
    // Блокируем такой трафик правилом, до аутбаунда. Для приложений это ничего
    // не меняет — QUIC и так не работал, они откатываются на TCP через секунду —
    // но убирает шквал коротких TLS-сессий к одному IP:443.
    //
    // Только при глобал-прокси: если «остальное» уходит direct или block, то
    // сюда доезжает и трафик, которому в туннель не надо, и резать его QUIC —
    // не наше дело. Вариант флоу `-udp443` умеет UDP/443 сам, его не трогаем.
    if (settings.finalOutbound == AppSettings.finalOutboundProxy &&
        _visionRejectsQuic(proxyOutbounds)) {
      rules.add(rule('block-quic', {
        'network': 'udp',
        'port': '443',
        'outboundTag': 'block',
      }));
    }
    if (proxyDomains.isNotEmpty) {
      rules.add(rule('proxy-domains',
          {'domain': proxyDomains, 'outboundTag': 'proxy'}));
    }
    if (proxyGeoip.isNotEmpty) {
      rules.add(rule('proxy-geoip', {
        'ip': proxyGeoip.map((c) => 'geoip:$c').toList(),
        'outboundTag': 'proxy',
      }));
    }
    if (proxyIps.isNotEmpty) {
      rules.add(rule('proxy-ips', {'ip': proxyIps, 'outboundTag': 'proxy'}));
    }

    // kill switch здесь не нужен: catch-all ниже и так шлёт всё в proxy,
    // а реальный kill switch (final: block) живёт в sing-box TUN-конфиге
    // (singbox_tun_config.dart).
    } // end full routing (non-ping)

    // Финальное действие (catch-all) для всего, что не попало в правила.
    // В ping-режиме всегда proxy (тестируем сам прокси); иначе — выбор
    // пользователя: proxy (глобал-прокси), direct (обход) или block.
    final finalTag = isPingMode
        ? 'proxy'
        : switch (settings.finalOutbound) {
            AppSettings.finalOutboundDirect => 'direct',
            AppSettings.finalOutboundBlock => 'block',
            _ => 'proxy',
          };
    rules.add(rule('final', {'outboundTag': finalTag, 'network': 'tcp,udp'}));

    // Фрагментация ClientHello. Сам прокси-аутбаунд резать пакеты не умеет —
    // это делает freedom, поэтому наружу дозванивается он, а прокси-аутбаунд
    // ходит к нему через dialerProxy. В ping-режиме включаем на тех же
    // условиях: проба обязана дозваниваться ровно так же, как потом боевое
    // соединение, иначе зелёный пинг ничего не обещает.
    final fragmentOutbound = _applyFragment(proxyOutbounds, core);

    // Шум перед UDP — для тех же аутбаундов, для которых фрагментация не
    // работает, и по тому же правилу «только внешний, не звено цепочки».
    _applyUdpNoise(proxyOutbounds, core);

    final inbounds = _buildInbounds(
      settings,
      pingSocksPort: pingSocksPort,
      pingHttpInbound: pingHttpInbound,
      localInboundsNoAuth: localInboundsNoAuth,
      nativeTunInbound: nativeTunInbound,
    );

    return {
      'log': {'loglevel': isPingMode ? 'none' : core.logLevel},
      'dns': dns,
      'inbounds': inbounds,
      'outbounds': [
        ...proxyOutbounds,
        {'protocol': 'freedom', 'tag': 'direct'},
        {'protocol': 'blackhole', 'tag': 'block'},
        // Не раньше прокси-аутбаунда: первый в списке у xray считается
        // основным, и всё, что не попало в правила, ушло бы в обход туннеля.
        ?fragmentOutbound,
        // Тег из правила `dns-out`; в ping-режиме правила нет, и аутбаунд с
        // несуществующим тегом только раздувал бы конфиг пробы.
        if (!isPingMode)
          {
            'protocol': 'dns',
            'tag': 'dns-out',
            'settings': {'nonIPQuery': 'reject'},
          },
      ],
      'routing': {
        'domainStrategy': isPingMode ? 'AsIs' : effectiveDomainStrategy,
        'rules': rules,
      },
    };
  }

  /// Отвергает ли выходной аутбаунд UDP/443 сам, уже после дозвона до сервера.
  ///
  /// Так ведёт себя `xtls-rprx-vision`; отдельный флоу `xtls-rprx-vision-udp443`
  /// как раз для того и заведён, чтобы UDP/443 пропускать — его исключаем.
  /// Смотрим только на первый аутбаунд: в цепочке это выходной узел, а именно
  /// он решает судьбу пакета.
  static bool _visionRejectsQuic(List<Map<String, dynamic>> proxyOutbounds) {
    if (proxyOutbounds.isEmpty) return false;
    final first = proxyOutbounds.first;
    if (first['protocol'] != 'vless') return false;
    final settings = first['settings'];
    if (settings is! Map) return false;
    final flow = settings['flow']?.toString().trim() ?? '';
    return flow.startsWith('xtls-rprx-vision') && !flow.endsWith('-udp443');
  }

  /// Теги инбаундов, которые ставит [_buildInbounds]. Вынесены, потому что по
  /// ним считается, какие авторские правила готового конфига остались без
  /// инбаунда и уже не сработают (`previewDeadInboundRules`).
  ///
  /// `tun-in` тут вместе с остальными, хотя появляется не всегда: список
  /// перечисляет теги, которые вообще бывают наши, а не те, что есть в этом
  /// конкретном конфиге. Лишний тег даёт разве что не показанное
  /// предупреждение, недостающий — предупреждение о живом правиле.
  static const appInboundTags = [
    'socks-in',
    'http-in',
    'socks-lan',
    'http-lan',
    'tun-in',
  ];

  /// Инбаунды приложения: локальные SOCKS/HTTP (и опционально LAN).
  ///
  /// Общие для сгенерированных и готовых (custom) конфигов: их порты и креды
  /// ждёт нативная часть — на Android в них ходит само приложение, на десктопе
  /// sing-box внутри keqrnel поднимает listener'ы по этому же списку
  /// (см. KeqrnelConfig). Поэтому у готового конфига авторские инбаунды
  /// заменяются на эти, а не дополняются ими.
  static List<Map<String, dynamic>> _buildInbounds(
    AppSettings settings, {
    int? pingSocksPort,
    bool pingHttpInbound = false,
    bool localInboundsNoAuth = false,
    /// Туннель держит само ядро: в конфиг добавляется tun-инбаунд, а
    /// дескриптор ему передаёт нативная часть через переменную окружения.
    bool nativeTunInbound = false,
  }) {
    final core = settings.xrayCore;
    final isPingMode = pingSocksPort != null;
    final socksPort = pingSocksPort ?? settings.localPort;
    final useNoAuthInbound = isPingMode || localInboundsNoAuth;
    return <Map<String, dynamic>>[
      // Ядро само читает пакеты из туннеля. Дескриптор сюда не пишем: ядро берёт
      // его из переменной окружения `XRAY_TUN_FD` (`proxy/tun/tun_android.go`),
      // и знает этот номер только нативная часть, поднявшая интерфейс. Оттуда
      // же приезжает и `mtu`: разойдись он с интерфейсом — пакеты, законные для
      // netstack, отбрасывались бы ядром ОС при записи в tun.
      //
      // Порт ядро у этого инбаунда не спрашивает вовсе (`InboundDetourConfig`
      // пропускает проверку для `tun`), но ключ обязан быть: без него разбор
      // конфига падает на «Listen on AnyIP but no Port(s) set».
      //
      // Снифер тут не роскошь: без него роутинг видит только IP, и все правила
      // по доменам перестают срабатывать разом.
      if (nativeTunInbound && !isPingMode)
        {
          'tag': 'tun-in',
          'port': 0,
          'protocol': 'tun',
          'settings': {'name': _tunInterfaceName, 'mtu': _defaultTunMtu},
          'sniffing': core.buildSniffing(),
        },
      if (isPingMode && pingHttpInbound)
        // Desktop ping listens over HTTP, not SOCKS: the Dart probe uses dart:io
        // HttpClient, whose findProxy supports only 'PROXY host:port' (HTTP CONNECT)
        // and 'DIRECT' — it cannot speak SOCKS at all. A SOCKS inbound here is what
        // made every desktop url/proxy ping fail with "Invalid proxy configuration
        // SOCKS ...". Android keeps the SOCKS inbound below (its Java probe uses
        // Proxy.Type.SOCKS). See EphemeralXrayPing (Dart + Kotlin).
        {
          'tag': 'http-in',
          'port': socksPort,
          'listen': '127.0.0.1',
          'protocol': 'http',
          'settings': {'allowTransparent': false},
        }
      else if (isPingMode)
        {
          'tag': 'socks-in',
          'port': socksPort,
          'listen': '127.0.0.1',
          'protocol': 'socks',
          'settings': {'auth': 'noauth', 'udp': true},
        }
      else ...[
      {
        'tag': 'socks-in',
        'port': socksPort,
        'listen': '127.0.0.1',
        'protocol': 'socks',
        'settings': useNoAuthInbound
            ? {'auth': 'noauth', 'udp': true}
            : {
                'auth': 'password',
                'udp': true,
                'accounts': [
                  {
                    'user': Socks5Credentials().username,
                    'pass': Socks5Credentials().password,
                  }
                ],
              },
        'sniffing': core.buildSniffing(),
      },
      {
        'tag': 'http-in',
        'port': settings.httpPort,
        'listen': '127.0.0.1',
        'protocol': 'http',
        'settings': useNoAuthInbound
            ? {'allowTransparent': false}
            : {
                'allowTransparent': false,
                'accounts': [
                  {
                    'user': Socks5Credentials().username,
                    'pass': Socks5Credentials().password,
                  }
                ],
              },
      },
      if (settings.lanSharing) ...[
        // Опциональный пароль на LAN-инбаунды: обе строки непустые — auth
        // password, иначе noauth (инбаунды слушают 0.0.0.0, source-правило
        // в роутинге пускает только частные диапазоны).
        {
          'tag': 'socks-lan',
          'port': settings.lanSocksPort,
          'listen': '0.0.0.0',
          'protocol': 'socks',
          'settings': _lanAuthEnabled(settings)
              ? {
                  'auth': 'password',
                  'udp': true,
                  'accounts': [
                    {
                      'user': settings.lanUsername.trim(),
                      'pass': settings.lanPassword,
                    }
                  ],
                }
              : {
                  'auth': 'noauth',
                  'udp': true,
                },
          'sniffing': core.buildSniffing(),
        },
        {
          'tag': 'http-lan',
          'port': settings.lanHttpPort,
          'listen': '0.0.0.0',
          'protocol': 'http',
          'settings': _lanAuthEnabled(settings)
              ? {
                  'allowTransparent': false,
                  'accounts': [
                    {
                      'user': settings.lanUsername.trim(),
                      'pass': settings.lanPassword,
                    }
                  ],
                }
              : {'allowTransparent': false},
        },
      ],
      ],
    ];
  }
}
