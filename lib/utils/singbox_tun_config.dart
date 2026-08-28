import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';
import '../models/tun_settings.dart';
import '../tunnel/app_routing_mode.dart';
import 'process_name_utils.dart';
import 'routing_entry.dart';

/// Адрес TUN-интерфейса (тот же, что у sing-box по умолчанию). Вынесен из
/// генератора: по нему бэкенды понимают, что адаптер уже поднят.
const kTunInterfaceAddress = '172.19.0.1';

/// Подсеть TUN-интерфейса — /30, как требует system-стек sing-box (ему нужен
/// «следующий» адрес в префиксе).
const kTunInterfacePrefix = '$kTunInterfaceAddress/30';

/// IPv6-подсеть TUN-интерфейса — умолчание sing-box (`/126` по той же причине,
/// что и `/30` у IPv4). Заводится только когда у машины есть глобальный IPv6:
/// см. [TunSettings.blockIpv6Leak].
const kTunInterfaceIpv6Prefix = 'fdfe:dcba:9876::1/126';

/// Локальные IPv6-диапазоны, которые обязаны ходить мимо туннеля и НЕ попадать
/// под запрет: link-local (соседи, SLAAC), ULA (адреса своей сети), multicast
/// (mDNS/SSDP — обнаружение принтеров и колонок) и петля.
const kLocalIpv6Cidrs = ['::1/128', 'fe80::/10', 'fc00::/7', 'ff00::/8'];

/// Имя TUN-интерфейса. Задаём САМИ на всех платформах: без него sing-box берёт
/// «tun0», а wintun считает GUID адаптера как MD5("wintun" + имя) — один и тот
/// же у любого sing-box-клиента на машине.
const kTunInterfaceName = 'tun-keqdis';

/// Поднялся ли TUN, судя по выводу ядра.
///
/// Признак — строка САМОГО sing-box, и только она. Прежняя проверка («в логе
/// есть "started" и где-нибудь есть "tun"») срабатывала на баннере встроенного
/// xray: ядро запускает аутбаунды раньше инбаундов (`Box.preStart` → outbound,
/// затем `Box.start` → inbound), поэтому «Xray N.N.N started» появляется ДО
/// того, как создан адаптер, прописаны маршруты и DNS. Приложение показывало
/// «Подключено» и заводило таймер сессии, пока трафик ещё шёл старым путём —
/// отсюда «работает только через 20 секунд после включения».
///
/// Однозначных строк три: `started at <имя>` от tun-инбаунда (маршруты уже
/// добавлены), `sing-box started` по окончании старта всего ядра и
/// `keqrnel started` — её печатает уже наша обёртка, последней.
/// Годится ли строка как значение `ip_cidr`: голый адрес или адрес с маской.
///
/// Домен сюда попадает штатным путём — резолв адреса сервера при неудаче
/// откатывается на исходную строку, — а `ip_cidr` его не принимает и роняет
/// разбор ВСЕГО конфига.
bool _isRoutableIpTarget(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return false;
  final slash = value.lastIndexOf('/');
  if (slash < 0) return InternetAddress.tryParse(value) != null;
  final address = InternetAddress.tryParse(value.substring(0, slash));
  if (address == null) return false;
  final bits = int.tryParse(value.substring(slash + 1));
  if (bits == null) return false;
  final max = address.type == InternetAddressType.IPv6 ? 128 : 32;
  return bits >= 0 && bits <= max;
}

bool singboxTunReady(String rawLog) {
  final text = rawLog.toLowerCase();
  return text.contains('sing-box started') ||
      text.contains('keqrnel started') ||
      text.contains('started at ');
}

/// Стеки, которых нет в ядре, собранном без `-tags with_gvisor`.
///
/// `NewGVisor`/`NewMixed` там заменены заглушкой и возвращают «gVisor is not
/// included in this build», то есть ядро падает на СТАРТЕ — конфиг разобран,
/// адаптер не создан, пользователь видит «keqrnel TUN did not start (exit code
/// 1)». Наши поставляемые бинари собраны с тегом (`go version -m` →
/// `-tags=with_gvisor`), но чужая сборка `go build ./...` — нет.
const _gvisorStacks = {TunSettings.stackGvisor, TunSettings.stackMixed};

/// Понижает стек TUN-инбаунда до `system`, если ядро собрано без gVisor.
///
/// Умолчание у нас `gvisor`, и с ядром без тега оно означало бы «TUN не
/// работает вообще, у всех, всегда». Обрезанный конфиг лучше упавшего: system
/// доступен в любой сборке.
///
/// [gvisorAvailable] — `null`, когда выяснить не удалось (бинарь не Go, блок
/// настроек сборки не прочитался). Тогда конфиг не трогаем: «неизвестно» — не
/// повод переписывать выбор пользователя.
({String config, String? downgradedFrom}) applyTunStackFallback(
  String singboxConfig, {
  required bool? gvisorAvailable,
}) {
  if (gvisorAvailable != false) {
    return (config: singboxConfig, downgradedFrom: null);
  }
  final Map<String, dynamic> box;
  try {
    box = jsonDecode(singboxConfig) as Map<String, dynamic>;
  } catch (_) {
    return (config: singboxConfig, downgradedFrom: null);
  }
  final inbounds = box['inbounds'];
  if (inbounds is! List) return (config: singboxConfig, downgradedFrom: null);

  String? downgradedFrom;
  for (final raw in inbounds) {
    if (raw is! Map) continue;
    if (raw['type'] != 'tun') continue;
    final stack = raw['stack']?.toString();
    if (stack == null || !_gvisorStacks.contains(stack)) continue;
    raw['stack'] = TunSettings.stackSystem;
    // endpoint_independent_nat живёт только на gvisor/mixed: на system
    // sing-box его игнорирует, но в конфиге он оставался бы ложью.
    raw.remove('endpoint_independent_nat');
    downgradedFrom = stack;
  }
  if (downgradedFrom == null) {
    return (config: singboxConfig, downgradedFrom: null);
  }
  return (
    config: const JsonEncoder.withIndent('  ').convert(box),
    downgradedFrom: downgradedFrom,
  );
}

/// sing-box tun-конфиг: весь трафик tun → socks5 (auth) → локальный xray.
/// xray поднимает upstream (vless, vmess, hysteria, …), sing-box только
/// перехватывает пакеты и не парсит subscription-протоколы.
class SingBoxTunConfigGen {
  static String generate({
    required int localSocksPort,
    required String socksUsername,
    required String socksPassword,
    required String serverIpToExclude,
    required AppSettings settings,
    List<String> managedProcessNames = const [],
    AppRoutingMode routingMode = AppRoutingMode.allProxy,
    /// AmneziaWG: wireproxy SOCKS5 без auth — не шлём username/password в outbound.
    bool localSocksNoAuth = false,
    /// this app's own exe (e.g. keqdroid.exe). routed direct so our tcp/url ping
    /// sockets measure latency from the local pc, not through the active server.
    String appProcessName = '',
    /// Целевая ОС. По умолчанию текущая — в бою иначе не бывает. Параметром она
    /// стала ради golden-тестов: три места ниже читают `Platform.isWindows`, и
    /// снятая на Windows фикстура падала на linux-раннере, ничего не сообщая о
    /// генераторе. Ср. [TunSettings.strictRouteEnabled], где платформа уже входит
    /// аргументом.
    bool? windows,
    /// Есть ли у машины глобальный IPv6 (см. `utils/host_ipv6.dart`). Только
    /// вместе с [TunSettings.blockIpv6Leak] это включает захват IPv6: адрес на
    /// интерфейсе там, где IPv6 в системе выключен, — это не «лишняя строка в
    /// конфиге», а упавший на старте sing-box.
    bool hostHasIpv6 = false,
  }) {
    final isWindows = windows ?? Platform.isWindows;
    // Разделители — и запятая, и перевод строки: UI обещает «по одному в
    // строке или через запятую», сплит только по ',' склеивал построчные
    // записи в один несрабатывающий токен.
    List<String> parseList(String s) => s
        .split(RegExp(r'[\r\n,]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    Map<String, dynamic> buildProxyDnsServer() {
      // Кастомный DNS уважаем только когда он включён в настройках xray-ядра.
      final customDns = !settings.xrayCore.dnsUseCustom
          ? const <String>[]
          : settings.xrayCore.dnsServers
              .split(RegExp(r'[\n,]+'))
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();

      // Дефолт — DNS-over-HTTPS через туннель. Многие VPS-хостеры/серверы режут
      // исходящий порт 53 (анти-abuse), из-за чего и UDP-, и TCP-DNS через
      // прокси умирали с "read response: EOF" — браузер получал "server not
      // found" при живом туннеле. DoH на 443 неотличим от обычного HTTPS.
      Map<String, dynamic> defaultDoh() => {
            'tag': 'proxy-dns',
            'type': 'https',
            'server': '1.1.1.1',
            'detour': 'proxy',
          };

      if (customDns.isEmpty) return defaultDoh();

      // Поле DNS хранит адреса в xray-синтаксисе (https+local://, tls://,
      // quic://, tcp://, голый ip[:port]). sing-box же ждёт типизированный
      // объект сервера, а НЕ сырую xray-строку: если скормить её как есть,
      // keqrnel падал на разборе конфига (exit code 2 — «ошибка подключения»).
      // Берём ПЕРВЫЙ переводимый адрес, а не просто первый: непереводимая
      // строка в начале списка (localhost, fakedns) иначе отправляла в дефолт
      // весь список, включая нормальный DoH следующей строкой.
      for (final address in customDns) {
        final server = _singBoxDnsServerFromXray(address);
        if (server != null) return server;
      }
      return defaultDoh();
    }

    ({
      List<String> domain,
      List<String> domainSuffix,
      List<String> domainRegex,
    }) classifyDomains(List<String> domains) {
      final exact = <String>[];
      final suffix = <String>[];
      final regex = <String>[];

      for (final raw in domains) {
        final cleaned = raw.trim().toLowerCase();
        if (cleaned.isEmpty) continue;

        if (cleaned.startsWith('full:')) {
          final v = cleaned.substring('full:'.length).trim();
          if (v.isNotEmpty) exact.add(v);
          continue;
        }
        if (cleaned.startsWith('regexp:')) {
          final v = cleaned.substring('regexp:'.length).trim();
          if (v.isNotEmpty) regex.add(v);
          continue;
        }
        if (cleaned.startsWith('domain:')) {
          final v = cleaned.substring('domain:'.length).trim();
          if (v.isNotEmpty) suffix.add(v.startsWith('.') ? v.substring(1) : v);
          continue;
        }
        if (cleaned.startsWith('geosite:')) {
          // sing-box (1.11+) не умеет читать v2fly .dat вообще, а прежний
          // перевод `geosite:telegram` → `domain_suffix: telegram` давал
          // мёртвое правило: суффиксу «telegram» не соответствует ни
          // telegram.org, ни t.me — так geosite молча не работал в TUN.
          // Такие токены оставляем встроенному xray (см. needsXrayForGeo).
          continue;
        }
        if (cleaned.startsWith('.')) {
          final v = cleaned.substring(1).trim();
          if (v.isNotEmpty) suffix.add(v);
          continue;
        }
        if (!cleaned.contains('.')) {
          suffix.add(cleaned);
          continue;
        }
        suffix.add(cleaned);
      }

      return (domain: exact, domainSuffix: suffix, domainRegex: regex);
    }

    void addDomainRule({
      required List<Map<String, dynamic>> targetRules,
      required List<String> sourceDomains,
      required String outbound,
    }) {
      final parts = classifyDomains(sourceDomains);
      if (parts.domain.isEmpty &&
          parts.domainSuffix.isEmpty &&
          parts.domainRegex.isEmpty) {
        return;
      }
      targetRules.add({
        if (parts.domain.isNotEmpty) 'domain': parts.domain,
        if (parts.domainSuffix.isNotEmpty) 'domain_suffix': parts.domainSuffix,
        if (parts.domainRegex.isNotEmpty) 'domain_regex': parts.domainRegex,
        'outbound': outbound,
      });
    }

    // each list is mixed (domains + ip/cidr + geoip:); split per kind.
    final directSplit = splitDomainsAndIps(parseList(settings.directRules));
    final proxySplit = splitDomainsAndIps(parseList(settings.proxyRules));
    final blockedSplit = splitDomainsAndIps(parseList(settings.blockedRules));

    final directDomains = directSplit.domains;
    final blockedDomains = blockedSplit.domains;
    final proxyDomains = proxySplit.domains;

    bool isIPv4OrCidr(String value) {
      final v = value.trim();
      final ipV4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
      final cidrV4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}/\d{1,2}$');
      return ipV4.hasMatch(v) || cidrV4.hasMatch(v);
    }

    bool isIPv6OrCidr(String value) {
      final v = value.trim();
      final ipV6 = RegExp(r'^[0-9a-fA-F:]+$');
      final cidrV6 = RegExp(r'^[0-9a-fA-F:]+/\d{1,3}$');
      return ipV6.hasMatch(v) || cidrV6.hasMatch(v);
    }

    // sing-box has no built-in geoip db here, so keep only literal ip/cidr and
    // leave every geoip: code (including geoip:private) to the embedded xray.
    // `ip_cidr` accepts nothing but a prefix or a bare address — sing-box's
    // NewIPCIDRItem rejects anything else and the core then exits on config
    // load, so a stray `geoip:private` used to kill the whole connection.
    List<String> ipsForSingBox(List<String> ips) => ips
        .where((entry) => isIPv4OrCidr(entry) || isIPv6OrCidr(entry))
        .map((e) => e.trim())
        .toList();

    final directIpsForSingBox = ipsForSingBox(directSplit.ips);
    final proxyIpsForSingBox = ipsForSingBox(proxySplit.ips);
    final blockedIpsForSingBox = ipsForSingBox(blockedSplit.ips);

    // geo-токен, который умеет вычислить только xray (у sing-box нет .dat).
    bool isGeoToken(String value) {
      final v = value.trim().toLowerCase();
      return v.startsWith('geosite:') || v.startsWith('geoip:');
    }

    // Есть ли geo-правила, которые ДОЛЖНЫ отправить трафик в прокси/блок.
    // Их применяет встроенный xray — но только если соединение вообще доехало
    // до аутбаунда `proxy`; см. финальное действие ниже.
    final needsXrayForGeo = [
      ...proxySplit.domains,
      ...proxySplit.ips,
      ...blockedSplit.domains,
      ...blockedSplit.ips,
    ].any(isGeoToken);

    const tunInboundTag = 'tun-in';

    // Забирать ли IPv6 в туннель. Без адреса на интерфейсе ядро не берёт
    // IPv6-маршруты, и на дуалстеке весь IPv6 идёт мимо туннеля (см.
    // [TunSettings.blockIpv6Leak]); с адресом на машине, где IPv6 выключен,
    // sing-box падает при настройке адаптера. Отсюда И настройка, И проверка
    // машины.
    final captureIpv6 = settings.tun.blockIpv6Leak && hostHasIpv6;

    final rules = <Map<String, dynamic>>[
      {
        'inbound': [tunInboundTag],
        'action': 'sniff',
      },
      {'protocol': 'dns', 'action': 'hijack-dns'},
      // Тот же перехват, но ПО ПОРТУ, а не по определению снифера.
      //
      // Правило выше срабатывает только если снифер опознал пакет как DNS.
      // Не опознал — запрос проваливается ниже и попадает под правило
      // «подсеть самого TUN → direct», а адрес системного резолвера лежит
      // ровно в ней: sing-tun ставит системе СЛЕДУЮЩИЙ адрес после адреса
      // интерфейса (172.19.0.1 → 172.19.0.2). Тогда ядро честно пытается
      // открыть сокет к 172.19.0.2:53 наружу, попадает в никуда, и резолва
      // нет вовсе — снаружи это «подключился, а интернета нет».
      //
      // У mihomo то же самое сделано сразу по порту (`dns-hijack: any:53`),
      // и у xray-пути тоже (`dns-out` по `port: 53`).
      {'port': 53, 'action': 'hijack-dns'},
      // icmp can't go over socks; route it locally
      {'protocol': 'icmp', 'outbound': 'direct'},
      {'ip_cidr': ['172.19.0.0/30'], 'outbound': 'direct'},
    ];

    // bypass tun for the cores and this app itself so they go direct:
    //  - xray.exe / ephemeral ping xray: only dials the server, avoids double-tunnel
    //  - sing-box.exe: don't route its own direct egress back into itself
    //  - <app>.exe: our dart tcp-ping sockets, so latency reflects the local pc
    // placed before split-tunnel rules so it wins regardless of routing mode.
    // Windows process names carry `.exe`; on Linux they are the bare binary
    // basename (sing-box's find_process matches the comm name). Keep Windows
    // output byte-identical by only appending the suffix there.
    final exe = isWindows ? '.exe' : '';
    final bypassProcessNames = <String>{
      // ИМЕНА РЕАЛЬНЫХ БИНАРЕЙ, а не движков внутри них.
      //
      // `xray` и `sing-box` отдельными процессами на десктопе не существуют
      // с тех пор, как оба переехали внутрь keqrnel: правило по ним не
      // совпадало ни разу. Держало схему только правило по IP сервера ниже —
      // а оно исчезает, стоит резолву адреса не удаться. Без обоих правил
      // соединение ядра к серверу забирает auto_route, отдаёт его обратно в
      // `proxy`, то есть в само ядро, и получается круг: туннель поднят,
      // ошибок нет, трафика нет.
      'keqrnel$exe',
      // mihomo в TUN-режиме владеет адаптером сам, и этот конфиг ему не нужен;
      // но он же исполняет сервер в proxy-режиме под нашим TUN.
      'mihomo$exe',
      'xray$exe',
      'sing-box$exe',
      // wireproxy (AmneziaWG): его WG-UDP к серверу должен идти мимо туннеля
      'wireproxy$exe',
      // Через варианты, а не .toLowerCase(): sing-box сравнивает process_name
      // map-lookup'ом, без приведения регистра. Заниженное имя не совпадёт с
      // реальным (переименованный портативный `KEQDIS.exe`), правило молча
      // промахнётся — и tcp-пинг начнёт мерить локальный конец туннеля вместо
      // сервера. Пользовательские правила сплит-туннеля так и делают.
      ...processNameMatchVariants(appProcessName.trim()),
    }.toList();
    rules.add({
      'process_name': bypassProcessNames,
      'outbound': 'direct',
    });

    if (routingMode == AppRoutingMode.allProxy) {
      rules.add({
        'process_name': [
          'tailscaled$exe',
          'wireguard$exe',
          'openvpn$exe',
          if (isWindows) 'openvpn-gui.exe',
        ],
        'outbound': 'direct',
      });
    }

    if (managedProcessNames.isNotEmpty) {
      switch (routingMode) {
        case AppRoutingMode.onlySelected:
          for (final process in managedProcessNames) {
            final variants = processNameMatchVariants(process);
            if (variants.isEmpty) continue;
            rules.add({
              'process_name': variants,
              'outbound': 'proxy',
            });
          }
        case AppRoutingMode.allExceptSelected:
          for (final process in managedProcessNames) {
            final variants = processNameMatchVariants(process);
            if (variants.isEmpty) continue;
            rules.add({
              'process_name': variants,
              'outbound': 'direct',
            });
          }
        case AppRoutingMode.allProxy:
          break;
      }
    }

    if (blockedDomains.isNotEmpty) {
      addDomainRule(
        targetRules: rules,
        sourceDomains: blockedDomains,
        outbound: 'block',
      );
    }
    if (blockedIpsForSingBox.isNotEmpty) {
      rules.add({'ip_cidr': blockedIpsForSingBox, 'outbound': 'block'});
    }

    // Адрес сервера мимо туннеля — иначе коннект ядра к нему заходит в круг.
    //
    // Только настоящий адрес: сюда приезжает результат резолва, а он при
    // неудаче откатывается на исходную строку сервера, то есть на ДОМЕН
    // (`vpn.example.com`). Домен в `ip_cidr` — это `vpn.example.com/32`,
    // невалидный префикс: sing-box не разбирает такой конфиг вовсе и выходит,
    // то есть туннель не поднимается совсем. Пропустить правило хуже, чем
    // уронить ядро, только на первый взгляд: круг ловит правило по имени
    // процесса выше, а упавшее ядро не ловит ничего.
    if (_isRoutableIpTarget(serverIpToExclude)) {
      // Маска по семейству адреса: `/32` на IPv6-адресе — это не «сам сервер»,
      // а треть интернета (`2a03:…::1/32` → `2a03::/32`), пущенная мимо
      // туннеля. `ip_cidr` у sing-box принимает и голый адрес, но у нас он
      // приезжает уже с маской у половины вызовов, так что считаем её сами.
      final cidrs = serverIpToExclude.contains('/')
          ? [serverIpToExclude]
          : ['$serverIpToExclude/${serverIpToExclude.contains(':') ? 128 : 32}'];
      rules.add({'ip_cidr': cidrs, 'outbound': 'direct'});
    }

    if (directDomains.isNotEmpty) {
      addDomainRule(
        targetRules: rules,
        sourceDomains: directDomains,
        outbound: 'direct',
      );
    }

    if (directIpsForSingBox.isNotEmpty) {
      rules.add({'ip_cidr': directIpsForSingBox, 'outbound': 'direct'});
    }

    rules.add({
      'ip_cidr': [
        '10.0.0.0/8',
        '172.16.0.0/12',
        '192.168.0.0/16',
        '127.0.0.0/8',
        // Локальный IPv6 — только когда мы его вообще забираем: иначе это
        // мёртвые строки в конфиге у всех.
        if (captureIpv6) ...kLocalIpv6Cidrs,
      ],
      'outbound': 'direct',
    });

    if (proxyDomains.isNotEmpty) {
      addDomainRule(
        targetRules: rules,
        sourceDomains: proxyDomains,
        outbound: 'proxy',
      );
    }
    if (proxyIpsForSingBox.isNotEmpty) {
      rules.add({'ip_cidr': proxyIpsForSingBox, 'outbound': 'proxy'});
    }

    // Выход IPv6 наружу закрыт — но ПОСЛЕ пользовательских правил: явное
    // IPv6-правило пользователя остаётся сильнее умолчания.
    //
    // Смысл именно в закрытии, а не в проксировании: наш DNS отдаёт только
    // A-записи, значит IPv6-адрес у приложения появляется лишь помимо нас
    // (свой DoH браузера, литерал в коде). Закрытый выход возвращает такое
    // соединение на IPv4 мгновенно — Happy Eyeballs делает это за миллисекунды,
    // — тогда как отправленное в прокси оно висело бы до таймаута на сервере
    // без IPv6. Локальный IPv6 сюда не попадает: он ушёл в `direct` выше.
    if (captureIpv6) {
      rules.add({'ip_cidr': ['::/0'], 'outbound': 'block'});
    }

    // Финальное действие (catch-all). При per-app сплите режим сам диктует финал
    // (onlySelected → direct: не выбранные приложения идут напрямую). В обычном
    // режиме allProxy финал выбирает пользователь: proxy (глобал-прокси),
    // direct (обход) или block.
    final finalOutbound = switch (settings.finalOutbound) {
      AppSettings.finalOutboundDirect => 'direct',
      AppSettings.finalOutboundBlock => 'block',
      _ => 'proxy',
    };
    var routeFinal = switch (routingMode) {
      AppRoutingMode.onlySelected => 'direct',
      AppRoutingMode.allExceptSelected => 'proxy',
      AppRoutingMode.allProxy => finalOutbound,
    };

    // Kill switch имеет смысл только когда финал — proxy (глобал-прокси): гоним
    // весь IP-трафик в proxy, а финал делаем block, чтобы при падении прокси не
    // было утечки. Для direct (обход) и block это не нужно.
    if (settings.killSwitch &&
        routingMode == AppRoutingMode.allProxy &&
        routeFinal == 'proxy') {
      rules.add({
        'ip_cidr': ['0.0.0.0/1', '128.0.0.0/1'],
        'outbound': 'proxy',
      });
      routeFinal = 'block';
    }

    // Финал ≠ proxy + geo-правила: не совпавшее с правилами sing-box уходило
    // мимо xray, и `geosite:telegram → proxy` при финале «обход» не работал
    // вообще (жалоба «геосайты не учитываются / не грузит ниче»). Отдаём остаток
    // встроенному xray: он вычислит geo-правила, а его собственный catch-all —
    // тот же finalOutbound, так что для не-geo трафика решение не меняется.
    // Только в режиме allProxy: при пер-аппном сплите финал несёт смысл
    // «невыбранные приложения идут напрямую», и его подменять нельзя.
    if (needsXrayForGeo &&
        routingMode == AppRoutingMode.allProxy &&
        routeFinal != 'proxy') {
      routeFinal = 'proxy';
    }

    final proxyOutbound = <String, dynamic>{
      'type': 'socks',
      'tag': 'proxy',
      'server': '127.0.0.1',
      'server_port': localSocksPort,
      'version': '5',
      if (!localSocksNoAuth) ...{
        'username': socksUsername,
        'password': socksPassword,
      },
    };

    // Direct-домены резолвим системным резолвером (local-dns): он знает
    // корпоративные/LAN-зоны сплит-DNS, которых у публичного DoH нет — иначе
    // домен из Direct-списка получает NXDOMAIN, хотя маршрут для него direct.
    // hijack-dns при этом перехватывает ВСЕ запросы (анти-leak, см. dns.final),
    // поэтому выбор резолвера возможен только здесь, через dns.rules.
    final directDnsParts = classifyDomains(directDomains);
    final dnsRules = <Map<String, dynamic>>[
      if (directDnsParts.domain.isNotEmpty ||
          directDnsParts.domainSuffix.isNotEmpty ||
          directDnsParts.domainRegex.isNotEmpty)
        {
          if (directDnsParts.domain.isNotEmpty)
            'domain': directDnsParts.domain,
          if (directDnsParts.domainSuffix.isNotEmpty)
            'domain_suffix': directDnsParts.domainSuffix,
          if (directDnsParts.domainRegex.isNotEmpty)
            'domain_regex': directDnsParts.domainRegex,
          'server': 'local-dns',
        },
    ];

    final tun = settings.tun;
    final tunInbound = <String, dynamic>{
      'type': 'tun',
      'tag': tunInboundTag,
      'mtu': tun.mtu,
      // Второй адрес — это и есть «забрать IPv6 в туннель»: sing-box ставит
      // IPv6-маршруты только на интерфейс, у которого IPv6-адрес есть.
      'address': [kTunInterfacePrefix, if (captureIpv6) kTunInterfaceIpv6Prefix],
      // без auto_route трафик в TUN не попадает; off — только для ручных маршрутов
      'auto_route': tun.autoRoute,
      // auto: on везде, кроме Windows — там strict_route breaks routing when
      // another vpn (e.g. tailscale) is active.
      'strict_route': tun.strictRouteEnabled(windows: isWindows),
      'stack': tun.stack,
      // full-cone NAT считает только gvisor-netstack (в mixed он держит UDP)
      if (tun.endpointIndependentNat && tun.stack != TunSettings.stackSystem)
        'endpoint_independent_nat': true,
      if (tun.udpTimeoutSec != TunSettings.defaultUdpTimeoutSec)
        'udp_timeout': '${tun.udpTimeoutSec}s',
    };
    // Собственное имя интерфейса ОБЯЗАТЕЛЬНО и на Windows. Без него sing-box
    // берёт `CalculateInterfaceName("")` → «tun0», а wintun-адаптер получает
    // GUID = MD5("wintun" + имя) — то есть ровно тот же GUID, что у любого
    // другого sing-box-клиента на этой машине (Happ, Nekoray, sing-box CLI).
    // Дальше по коду sing-tun: CreateAdapter падает с ErrExist и делается
    // OpenAdapter(имя) — мы молча забираем ЧУЖОЙ адаптер и настраиваем на нём
    // свои адреса и маршруты. Отсюда и «TUN запустился, ошибок нет, трафика
    // нет», и падения через раз на машинах, где стоит второй такой клиент.
    tunInbound['interface_name'] = kTunInterfaceName;

    final map = <String, dynamic>{
      'log': {
        'level': 'info',
        'timestamp': true,
      },
      'dns': {
        'servers': [
          {'tag': 'local-dns', 'type': 'local'},
          buildProxyDnsServer(),
        ],
        if (dnsRules.isNotEmpty) 'rules': dnsRules,
        'strategy': 'ipv4_only',
        // Клиентский DNS идёт через туннель (proxy-dns), а не через системный
        // резолвер: иначе на машинах с Tailscale его перехватывает MagicDNS
        // (100.100.100.100) и резолв ломается, плюс это утечка DNS мимо VPN.
        // Исключение — direct-домены, их dns.rules выше шлют в local-dns.
        'final': 'proxy-dns',
      },
      'inbounds': [tunInbound],
      'outbounds': [
        proxyOutbound,
        {'type': 'direct', 'tag': 'direct'},
        {'type': 'block', 'tag': 'block'},
      ],
      'route': {
        'auto_detect_interface': true,
        'find_process': true,
        'default_domain_resolver': 'proxy-dns',
        'rules': rules,
        'final': routeFinal,
      },
    };

    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Переводит один DNS-адрес из xray-синтаксиса в объект sing-box dns-сервера
  /// (формат 1.12+: `{type, server, server_port?, path?}`). Возвращает null,
  /// когда адрес нельзя гонять как сетевой upstream через прокси
  /// (localhost/fakedns/dhcp) — вызывающий тогда берёт дефолтный DoH.
  ///
  /// UDP через SOCKS хрупок (см. коммент выше про TCP:53), поэтому и «голый»
  /// адрес, и udp://-схему форсируем в TCP. Все серверы идут `detour: proxy`.
  static Map<String, dynamic>? _singBoxDnsServerFromXray(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();

    // Служебные xray-резолверы без сетевого upstream — их через прокси не гонишь.
    if (lower == 'localhost' || lower == 'fakedns' || lower.startsWith('dhcp')) {
      return null;
    }

    Map<String, dynamic> server(String type, String host, int? port,
            {String? path}) =>
        {
          'tag': 'proxy-dns',
          'type': type,
          'server': host,
          'server_port': ?port,
          if (path != null && path.isNotEmpty && path != '/') 'path': path,
          'detour': 'proxy',
        };

    // Схема вида `scheme://`. У xray scheme может нести суффикс (`https+local`,
    // `tcp+local`, …) — базой считаем часть до '+'.
    final schemeMatch = RegExp(r'^([a-z][a-z0-9.+-]*)://').firstMatch(lower);
    if (schemeMatch != null) {
      final base = schemeMatch.group(1)!.split('+').first;
      final uri = Uri.tryParse(trimmed);
      if (uri == null || uri.host.isEmpty) return null;
      final port = uri.hasPort ? uri.port : null;
      switch (base) {
        case 'https':
        case 'h2c':
          return server('https', uri.host, port, path: uri.path);
        case 'tls':
        case 'dot':
          return server('tls', uri.host, port);
        case 'quic':
        case 'doq':
          // `type: quic` в ядре НЕ зарегистрирован (реестр транспортов у
          // keqrnel — udp/tcp/tls/https/hosts/fakeip/local), и конфиг с ним не
          // разбирается вовсе: «unknown transport type: quic» → ядро не
          // стартует → TUN не поднимается. Берём DoT к тому же хосту: у всех,
          // кто отдаёт DoQ, он есть, и шифрование сохраняется. Порт не
          // переносим — у DoQ он свой (784/853), у DoT дефолтный 853.
          return server('tls', uri.host, null);
        case 'tcp':
          return server('tcp', uri.host, port);
        case 'udp':
        case 'dns':
          return server('tcp', uri.host, port); // UDP over SOCKS ненадёжен → TCP
        default:
          return null;
      }
    }

    // Без схемы: голый ip / host / host:port / [ipv6]:port → TCP:53 через прокси.
    String host = trimmed;
    int? port;
    final bracketed = RegExp(r'^\[([0-9a-fA-F:]+)\]:(\d+)$').firstMatch(trimmed);
    if (bracketed != null) {
      host = bracketed.group(1)!;
      port = int.parse(bracketed.group(2)!);
    } else if (RegExp(r'^[^:]+:\d+$').hasMatch(trimmed)) {
      // Ровно один ':' с числовым портом — иначе это голый IPv6, не host:port.
      final idx = trimmed.lastIndexOf(':');
      host = trimmed.substring(0, idx).trim();
      port = int.parse(trimmed.substring(idx + 1));
    }
    if (host.isEmpty) return null;
    return server('tcp', host, port);
  }
}
