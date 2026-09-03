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

/// builds client outbound json for xray 26.x. a few quirks: no empty fingerprint
/// (core rejects ""), never emit allowInsecure at all, echConfigList is a
/// string not an array, and hysteria2 uses network "hysteria" not "quic".
class ConfigGeneratorV2 {
  static String generateConfig(
    String input,
    AppSettings settings, {
    String? resolvedServerIp,
    /// windows system proxy can't pass socks5 creds — use noauth on localhost.
    bool localInboundsNoAuth = false,
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
  /// Слушать на нём некому и не должно: запрос приходит в tun2socks и обязан
  /// попасть в перехват, а не наружу.
  static const String _androidTunDns = '172.19.0.2';

  /// Пароль на LAN-инбаунды включается только полной парой логин+пароль:
  /// половинчатый ввод даёт noauth, а не пустой логин/пароль в accounts.
  static bool _lanAuthEnabled(AppSettings settings) =>
      settings.lanUsername.trim().isNotEmpty && settings.lanPassword.isNotEmpty;

  static List<String>? _splitAlpn(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final list = raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return list.isEmpty ? null : list;
  }

  /// tls client profile — keep fields compatible with infra/conf json tags.
  ///
  /// Отсутствующий `fingerprint` подставлять НЕ надо: `tls.GetFingerprint("")`
  /// в ядре возвращает `utls.HelloChrome_Auto`, то есть пустое поле — это уже
  /// Chrome-рукопожатие, а не Go-шный crypto/tls. Дописывать сюда `chrome`
  /// значит писать в конфиг то, что ядро и так делает.
  ///
  /// `allowInsecure` не эмитим НИКОГДА, даже когда ссылка просит (`insecure=1`,
  /// `skip-cert-verify=1`). Ядро это поле снесло намертво:
  ///
  /// ```go
  /// if c.AllowInsecure {
  ///   return nil, errors.PrintRemovedFeatureError(`"allowInsecure"`, ...)
  /// }
  /// ```
  ///
  /// (`infra/conf/transport_security.go`; в 26.3.27 отказ был по дате
  /// «после 2026-06-01», в 26.7.28 стал безусловным). Разбор падает целиком —
  /// то есть ОДИН сервер с `insecure=1` в подписке лишал связи все остальные,
  /// и наружу это выглядело как «SOCKS port not ready» без намёка на причину.
  ///
  /// Замен, предлагаемых ядром, тут не подставить: `pinnedPeerCertSha256` хочет
  /// отпечаток сертификата (его в ссылке нет), а `verifyPeerCertByName` сверяет
  /// цепочку с системными корнями по другому имени — самоподписанному серверу
  /// это не поможет. Поэтому просто проверяем сертификат как обычно: сервер с
  /// нормальным сертификатом (а `insecure=1` в панелях сплошь и рядом просто
  /// мусор копипасты) работает, а остальные хотя бы не тянут за собой всю
  /// подписку.
  static Map<String, dynamic> _tlsClientSettings({
    required String serverName,
    String fingerprint = '',
    String? alpnQuery,
    String? echConfigList,
    String? pinnedPeerCertSha256,
  }) {
    final tls = <String, dynamic>{
      'serverName': serverName,
    };
    final fp = fingerprint.trim();
    if (fp.isNotEmpty) tls['fingerprint'] = fp;
    final alpn = _splitAlpn(alpnQuery);
    if (alpn != null) tls['alpn'] = alpn;
    final ech = echConfigList?.trim() ?? '';
    if (ech.isNotEmpty) tls['echConfigList'] = ech;
    final pin = pinnedPeerCertSha256?.trim() ?? '';
    if (pin.isNotEmpty) tls['pinnedPeerCertSha256'] = pin;
    return tls;
  }

  static String _decodeBase64UrlCompat(String input) {
    var normalized = input.trim().replaceAll('-', '+').replaceAll('_', '/');
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    return utf8.decode(base64.decode(normalized));
  }

  static Map<String, dynamic> _parseVmessPayload(String input) {
    final payload = input.substring('vmess://'.length).trim();
    if (payload.isEmpty) {
      throw ArgumentError('VMess payload is empty');
    }
    final decoded = _decodeBase64UrlCompat(payload);
    final parsed = jsonDecode(decoded);
    if (parsed is! Map<String, dynamic>) {
      throw ArgumentError('Invalid VMess payload format');
    }
    return parsed;
  }

  static Map<String, dynamic> _buildXrayConfig(
    String input,
    AppSettings settings, {
    String? resolvedServerIp,
    int? pingSocksPort,
    bool pingHttpInbound = false,
    bool localInboundsNoAuth = false,
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
        geoIndex: geoIndex,
      );
    }

    final link = _buildLinkOutbound(trimmed, settings);

    return _wrapConfig(
      [link.outbound],
      settings,
      resolvedServerIp ?? link.address,
      link.port,
      originalServerAddress: link.address,
      pingSocksPort: pingSocksPort,
      pingHttpInbound: pingHttpInbound,
      localInboundsNoAuth: localInboundsNoAuth,
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
        uri = Uri.parse('vmess://proxy');
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
    final address = isVmess ? (vmessConfig?['add']?.toString() ?? '') : uri.host;
    final port = isVmess
        ? int.tryParse(vmessConfig?['port']?.toString() ?? '') ?? 0
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
      outbound = _buildVmessOutbound(vmessConfig, getParam, address, port, streamSettings);
    } else if (isHysteria) {
      outbound = _buildHysteriaOutbound(uri, getParam, address, port, streamSettings);
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
  /// не отвечает: `/etc/resolv.conf` там нет, и в логах ядра бесконечное
  /// «dial tcp: lookup <сервер>: operation was canceled» — трафик стоит, хотя
  /// сервер жив и раз в пару минут случайно пробивается. `domainStrategy`
  /// переводит этот резолв на dns-блок конфига (у нас DoH), то есть на тот же
  /// путь, которым ходят остальные домены. В mihomo ту же дыру закрывает
  /// отдельная настройка `proxy-server-nameserver`.
  ///
  /// Семейство адресов берём от queryStrategy: просить A+AAAA, когда DNS
  /// настроен отдавать только A, значит ждать впустую вторую половину ответа.
  ///
  /// Адрес-IP не трогаем: резолвить там нечего, а лишняя строка в конфиге —
  /// лишний повод сломать то, что и так работает.
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
  /// Наружу из процесса уходит только соединение до ВХОДНОГО узла — поэтому
  /// [resolvedServerIp] относится к нему, и обход туннеля строится по нему же.
  static Map<String, dynamic> _buildChainConfig(
    ProxyChainConfig chain,
    AppSettings settings, {
    String? resolvedServerIp,
    int? pingSocksPort,
    bool pingHttpInbound = false,
    bool localInboundsNoAuth = false,
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

    // Перебор портов hysteria (`mport`) работает только на самом внешнем узле:
    // получив от dialerProxy готовый поток, ядро отвечает «udphop requires
    // being at the outermost level» и коннект падает целиком. Роняем перебор,
    // а не соединение — базовый порт из ссылки остаётся рабочим.
    final hysteria = stream['hysteriaSettings'];
    if (hysteria is Map) hysteria.remove('udphop');

    outbound['streamSettings'] = stream;
  }

  /// Тег freedom-аутбаунда, который режет ClientHello.
  static const String _fragmentTag = 'fragment';

  /// Включает фрагментацию и возвращает аутбаунд, который её исполняет
  /// (`null` — выключена или применять её не к чему).
  ///
  /// Подцепляется к САМОМУ ВНЕШНЕМУ аутбаунду — тому, который реально
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
      // UDP-транспорт резать нечем: ClientHello там нет вовсе, а dialerProxy
      // поверх hysteria ядро встречает «udphop requires being at the outermost
      // level» и роняет соединение целиком (та же грабля, что и в цепочках).
      if (_isDatagramOutbound(outbound)) return null;

      final newStream = Map<String, dynamic>.from(
        stream ?? const <String, dynamic>{},
      );
      final newSockopt = Map<String, dynamic>.from(
        sockopt ?? const <String, dynamic>{},
      );
      newSockopt['dialerProxy'] = _fragmentTag;
      // `domainStrategy` отсюда НЕ убираем, в отличие от цепочки: там адрес
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
  /// Что меняем и почему:
  ///  - инбаунды — на свои (см. [_buildInbounds]);
  ///  - `log.loglevel` — из настроек: на уровне ниже `info` ядро не печатает
  ///    решения роутинга, и экран «Соединения» остаётся без правил;
  ///  - при включённом LAN-шаринге первыми идут правила «в наши LAN-инбаунды
  ///    только с частных адресов»: у автора правил для этих тегов нет, а
  ///    инбаунд слушает 0.0.0.0;
  ///  - `geoip:`/`geosite:`-коды, которых нет в поставляемых базах, вычищаем —
  ///    один такой код роняет разбор всего конфига.
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
    GeoAssetIndex? geoIndex,
  }) {
    final inbounds = _buildInbounds(
      settings,
      pingSocksPort: pingSocksPort,
      pingHttpInbound: pingHttpInbound,
      localInboundsNoAuth: localInboundsNoAuth,
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

    // Пользовательские списки роутинга — ПОСЛЕ авторских правил.
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
    // Перехват DNS у автора висит на ЕГО инбаунде: `dokodemo-door` с тегом
    // `dns-in` и правило `inboundTag: [dns-in] -> dns-out`. Инбаунды мы
    // заменяем своими (см. [_buildInbounds]), и вместе с `dns-in` умирает
    // правило: сработать ему теперь не на чем. Дальше запрос к 8.8.8.8:53
    // (этот адрес TUN отдаёт системе) не ловит ни одно авторское правило и
    // падает в наш `final`. С финалом «блок» это выглядит как «в кастомном
    // конфиге не работает вообще ничего, даже то, что сам он ведёт напрямую»:
    // без резолва нет и соединений, по которым авторские правила могли бы
    // сработать.
    //
    // ПОСЛЕ авторских правил: если автор DNS всё-таки разложил сам (`port: 53`
    // или catch-all), решает он — принцип готового конфига не меняем.
    //
    // `inboundTag` тут обязателен. Без него правило поймает и запросы САМОГО
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

    // fakedns — единственный случай, когда перехват DNS всё ЛОМАЕТ, а не чинит.
    // Ядро отдало бы приложению адрес из фейкового пула, а достать из такого
    // адреса домен обратно умеет только снифер с `fakedns` в `destOverride` —
    // у нас его нет (`XrayCoreSettings.buildSniffing`). Тогда не сработало бы
    // НИ ОДНО доменное правило автора. Конфиг с fakedns оставляем как был:
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

    // Тот же перехват, но по СЛУЖЕБНОМУ адресу TUN — и он обязан стоять ПЕРЕД
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
    // а общий перехват по порту 53 остаётся ПОСЛЕ авторских правил.
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
    // ядро отправляет ЧЕРЕЗ РОУТИНГ (для того и существует форма `+local`).
    // С финалом «блок» ядро блокирует собственный резолвер: молчит не только
    // перехваченный выше DNS устройства, но и `domainStrategy: IPIfNonMatch`
    // (в готовых конфигах он стоит почти всегда), то есть авторские
    // ip-правила по доменам разваливаются следом.
    //
    // Ловим такие запросы ПЕРЕД `final` и уводим напрямую — ровно так же
    // ходит DoH сгенерированных конфигов. Правило добавляем, только если
    // резолверу действительно нужен роутинг: у `https+local`/`localhost`
    // запросы идут мимо него, и «блок» остаётся буквальным.
    //
    // Когда перехвата нет (fakedns), это же правило спасает DNS САМОГО
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
      // LAN-правила остаются ПЕРЕД авторскими, и это не вкусовщина: инбаунд
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
  /// зависимости от типа сервера. Приватные диапазоны сюда НЕ добавляем: у
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
  /// У xray это НЕ «дополнительные поля»: в `SplitHTTPConfig.Build` объект из
  /// `extra` ЗАМЕЩАЕТ собой весь блок XHTTP, и от внешнего остаются только
  /// `host`, `path` и `mode`. Панели (xray 25+) кладут туда всё остальное —
  /// `xPaddingBytes`, `scMaxEachPostBytes`, `noGRPCHeader`, `headers`, `xmux`,
  /// `downloadSettings`. Пока мы этот параметр выбрасывали, сервер получал
  /// клиента с дефолтными настройками XHTTP вместо своих.
  ///
  /// [paddingBytes] — старая плоская форма (`x_padding_bytes=92-1412`) для
  /// ссылок без `extra`; при конфликте выигрывает то, что author положил в
  /// сам `extra`.
  ///
  /// Битый json не роняет разбор ссылки: сервер без padding-настроек всё же
  /// лучше, чем сервер, который вообще не добавился.
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
    return (extra == null || extra.isEmpty) ? null : extra;
  }

  /// client-side xhttp extras (xmux) and similar stream options.
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
      'streamSettings': _buildStreamSettings(uri, getParam, address, streamSettings),
    };
  }

  // vmess
  static Map<String, dynamic> _buildVmessOutbound(
      Map<String, dynamic>? vmessConfig, String Function(String, [String]) getParam,
      String address, int port, Map<String, dynamic> streamSettings) {
    final uuid = vmessConfig?['id']?.toString() ?? '';
    if (uuid.isEmpty) {
      throw ArgumentError('VMess requires id in payload');
    }

    final vmessSecurity = vmessConfig?['security']?.toString() ?? vmessConfig?['scy']?.toString() ?? 'auto';
    final flow = vmessConfig?['flow']?.toString() ?? '';

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
      'streamSettings': _buildVmessStreamSettings(vmessConfig, streamSettings),
    };
  }

  static Map<String, dynamic> _buildVmessStreamSettings(
      Map<String, dynamic>? vmessConfig, Map<String, dynamic> streamSettings) {
    final network = vmessConfig?['net']?.toString() ?? 'tcp';
    final security = vmessConfig?['tls']?.toString() ?? 'none';
    final sni = vmessConfig?['sni']?.toString() ?? vmessConfig?['host']?.toString() ?? '';

    if (security == 'tls') {
      streamSettings['security'] = 'tls';
      final fp = vmessConfig?['fp']?.toString() ?? '';
      final alpn = vmessConfig?['alpn']?.toString();
      final ech = vmessConfig?['ech']?.toString();
      streamSettings['tlsSettings'] = _tlsClientSettings(
        serverName: sni.isNotEmpty ? sni : (vmessConfig?['add']?.toString() ?? ''),
        fingerprint: fp,
        alpnQuery: alpn,
        echConfigList: ech,
      );
    }

    if (network == 'ws') {
      streamSettings['wsSettings'] = {
        'path': vmessConfig?['path']?.toString() ?? '/',
        'headers': {'Host': vmessConfig?['host']?.toString() ?? sni},
      };
    } else if (network == 'grpc') {
      streamSettings['grpcSettings'] = {
        'serviceName': vmessConfig?['serviceName']?.toString() ?? '',
      };
    }

    return streamSettings;
  }

  // trojan
  static Map<String, dynamic> _buildTrojanOutbound(
      Uri uri, String Function(String, [String]) getParam, Map<String, dynamic>? vmessConfig,
      String address, int port, Map<String, dynamic> streamSettings) {
    final password = vmessConfig != null
        ? (vmessConfig['id']?.toString() ?? '')
        : uri.userInfo;
    if (password.isEmpty) {
      throw ArgumentError('Trojan requires password in userInfo');
    }

    final email = getParam('email');

    final type = getParam('type', 'tcp');
    final sni = getParam('sni', address);
    final fingerprint = getParam('fp', '');

    streamSettings['network'] = type;
    streamSettings['security'] = 'tls';
    streamSettings['tlsSettings'] = _tlsClientSettings(
      serverName: sni,
      fingerprint: fingerprint,
      alpnQuery: getParam('alpn'),
      echConfigList: getParam('ech'),
    );

    if (type == 'ws') {
      streamSettings['wsSettings'] = {
        'path': getParam('path', '/'),
        'headers': {'Host': getParam('host', sni)},
      };
    } else if (type == 'grpc') {
      streamSettings['grpcSettings'] = {
        'serviceName': getParam('serviceName'),
      };
    }

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
    final uot = getParam('uot');
    final uotVersion = getParam('UoTVersion');

    return {
      'tag': 'proxy',
      'protocol': 'shadowsocks',
      'settings': {
        'address': address,
        'port': port,
        'method': method,
        'password': password,
        if (email.isNotEmpty) 'email': email,
        if (uot.isNotEmpty) 'uot': uot.toLowerCase() == 'true',
        if (uotVersion.isNotEmpty) 'UoTVersion': int.tryParse(uotVersion) ?? 0,
        'level': 0,
      },
      'streamSettings': {'network': 'tcp'},
    };
  }

  // hysteria / hy2
  static Map<String, dynamic> _buildHysteriaOutbound(
      Uri uri,
      String Function(String, [String]) getParam,
      String address,
      int port,
      Map<String, dynamic> streamSettings,
  ) {
    var auth = getParam('auth', getParam('password', '')).trim();
    if (auth.isEmpty && uri.userInfo.isNotEmpty) {
      auth = Uri.decodeComponent(uri.userInfo).trim();
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

    final hyParams = HysteriaLinkParams.fromConfig(uri.toString());
    final sni = getParam('sni', hyParams.sni.isNotEmpty ? hyParams.sni : address);
    final version = int.tryParse(getParam('version', '2')) ?? 2;
    if (version != 2) {
      throw ArgumentError(
        'Hysteria v1 is not supported by Xray 26+. Use hysteria2:// or hy2:// links.',
      );
    }

    final alpnRaw = getParam('alpn', hyParams.alpn);
    final alpnForTls = alpnRaw.isNotEmpty ? alpnRaw : 'h3';

    // xray 26+ removed standalone "quic"; use the dedicated "hysteria" network
    streamSettings['network'] = 'hysteria';
    streamSettings['security'] = 'tls';
    streamSettings['tlsSettings'] = _tlsClientSettings(
      serverName: sni,
      fingerprint: getParam('fp', ''),
      alpnQuery: alpnForTls,
      echConfigList: getParam('ech'),
      pinnedPeerCertSha256: getParam('pinSHA256', hyParams.pinSha256),
    );

    final hysteriaSettings = <String, dynamic>{
      'version': version,
      'auth': auth,
      'udpIdleTimeout': udpIdleTimeout,
      'masquerade': ?buildMasquerade(),
    };

    final up = HysteriaLinkParams.formatBandwidth(
      getParam('up', hyParams.up),
    );
    final down = HysteriaLinkParams.formatBandwidth(
      getParam('down', hyParams.down),
    );
    if (up != null) hysteriaSettings['up'] = up;
    if (down != null) hysteriaSettings['down'] = down;

    final mport = getParam('mport', hyParams.mport);
    if (mport.isNotEmpty) {
      final hop = <String, dynamic>{'ports': mport};
      final interval = getParam('hop-interval', hyParams.hopInterval);
      if (interval.isNotEmpty) hop['interval'] = interval;
      hysteriaSettings['udphop'] = hop;
    }

    streamSettings['hysteriaSettings'] = hysteriaSettings;

    final finalmask = hyParams.buildFinalmask();
    if (finalmask != null) {
      streamSettings['finalmask'] = finalmask;
    }

    return {
      'tag': 'proxy',
      'protocol': 'hysteria',
      'settings': {
        'address': address,
        'port': port,
        'version': hysteriaSettings['version'],
      },
      'streamSettings': streamSettings,
    };
  }

  // stream settings
  static Map<String, dynamic> _buildStreamSettings(
      Uri uri, String Function(String, [String]) getParam, String address, Map<String, dynamic> existing) {
    final type = getParam('type', 'tcp');
    final security = getParam('security', 'none');
    final sni = getParam('sni', getParam('host', address));

    final stream = existing;
    stream['network'] = type;
    stream['security'] = security;

    if (security == 'tls') {
      stream['tlsSettings'] = _tlsClientSettings(
        serverName: sni,
        fingerprint: getParam('fp', ''),
        alpnQuery: getParam('alpn'),
        echConfigList: getParam('ech'),
      );
    } else if (security == 'reality') {
      final rfp = getParam('fp', '').trim();
      stream['realitySettings'] = {
        'show': false,
        // reality needs a known utls fingerprint; empty is invalid on xray 26+.
        'fingerprint': rfp.isNotEmpty ? rfp : 'chrome',
        'serverName': sni,
        'publicKey': getParam('pbk'),
        'shortId': getParam('sid'),
        'spiderX': getParam('spx'),
      };
    }

    switch (type) {
      case 'ws':
        stream['wsSettings'] = {'path': getParam('path', '/'), 'headers': {'Host': getParam('host', sni)}};
      case 'grpc':
        stream['grpcSettings'] = {'serviceName': getParam('serviceName'), 'multiMode': getParam('mode') == 'multi'};
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
        stream['httpupgradeSettings'] = {'path': getParam('path', '/'), 'host': getParam('host', sni)};
      case 'tcp':
        if (getParam('headerType') == 'http') {
          stream['tcpSettings'] = {'header': {'type': 'http', 'request': {'headers': {'Host': [getParam('host', address)]}}}};
        }
    }
    return stream;
  }

  // обёртка конфига
  //
  // [proxyOutbounds] — аутбаунды сервера: у одиночного он один, у цепочки это
  // выходной узел (тег `proxy`, всегда первым) и остальные звенья.
  // [extraServerAddresses] — адреса промежуточных узлов цепочки: для них тоже
  // нужно правило «мимо туннеля».
  static Map<String, dynamic> _wrapConfig(
      List<Map<String, dynamic>> proxyOutbounds, AppSettings settings, String serverAddress, int serverPort,
      {String? originalServerAddress, List<String> extraServerAddresses = const [], int? pingSocksPort, bool pingHttpInbound = false, bool localInboundsNoAuth = false}) {

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
    // ДОМЕНУ: браузер через прокси шлёт `CONNECT host:443`, и под `AsIs` xray
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
    // и по нему дебаг-экран «Соединения» показывает, ПО КАКОМУ правилу ушло
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
    // TUN отдаёт системе 8.8.8.8, и без этого правила КАЖДЫЙ запрос уезжал в
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
    // ПОСЛЕ lan-правил, не до: инбаунд LAN-прокси слушает 0.0.0.0, и перехвати
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
    // traffic`), но ТОЛЬКО после того, как поднял до сервера полноценное
    // TCP+TLS-соединение: отказ живёт в vless-аутбаунде, за диалером. Каждый
    // QUIC-пакет, который приложение шлёт «на всякий случай», стоит нам одного
    // рукопожатия до сервера, выброшенного в мусор. В логе это видно прямо: одна
    // цель (`udp:188.234.73.160:443`) успевает съесть пять рукопожатий за 2.5
    // секунды, потому что приложение ретраит QUIC, а ядро каждый раз честно
    // дозванивается до сервера заново.
    //
    // Блокируем такой трафик правилом, до аутбаунда. Для приложений это ничего
    // не меняет — QUIC и так не работал, они откатываются на TCP через секунду —
    // но убирает шквал коротких TLS-сессий к одному IP:443. Так же поступают
    // v2rayNG и Happ.
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

    final inbounds = _buildInbounds(
      settings,
      pingSocksPort: pingSocksPort,
      pingHttpInbound: pingHttpInbound,
      localInboundsNoAuth: localInboundsNoAuth,
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
  static const appInboundTags = ['socks-in', 'http-in', 'socks-lan', 'http-lan'];

  /// Инбаунды приложения: локальные SOCKS/HTTP (и опционально LAN).
  ///
  /// Общие для сгенерированных и готовых (custom) конфигов: их порты и креды
  /// ждёт нативная часть — на Android в них ходит tun2socks, на десктопе
  /// sing-box внутри keqrnel поднимает listener'ы по этому же списку
  /// (см. KeqrnelConfig). Поэтому у готового конфига авторские инбаунды
  /// заменяются на эти, а не дополняются ими.
  static List<Map<String, dynamic>> _buildInbounds(
    AppSettings settings, {
    int? pingSocksPort,
    bool pingHttpInbound = false,
    bool localInboundsNoAuth = false,
  }) {
    final core = settings.xrayCore;
    final isPingMode = pingSocksPort != null;
    final socksPort = pingSocksPort ?? settings.localPort;
    final useNoAuthInbound = isPingMode || localInboundsNoAuth;
    return <Map<String, dynamic>>[
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
