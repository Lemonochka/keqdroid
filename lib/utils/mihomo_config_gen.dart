import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';
import '../models/xray_core_settings.dart';
import '../tunnel/app_routing_mode.dart';
import 'custom_clash_config.dart';
import 'routing_entry.dart';
import 'socks5_credentials.dart';

/// Туннель, которым владеет само ядро: wintun-адаптер на десктопе или готовый
/// fd от VpnService на Android.
///
/// Отсутствие этого объекта (`tun: null`) означает противоположную схему —
/// ядро всего лишь локальный SOCKS-листенер, а пакеты ему приносит кто-то
/// другой (tun2socks под Android, системный прокси на десктопе).
class MihomoTunOptions {
  const MihomoTunOptions({
    this.device,
    required this.stack,
    this.mtu = 0,
    this.autoRoute = true,
    this.strictRoute = false,
    this.fromFileDescriptor = false,
  });

  /// Устройство создано не ядром, а нами, и приезжает готовым дескриптором
  /// (Android: `VpnService.Builder.establish`).
  ///
  /// Самого номера дескриптора здесь нет и быть не может: конфиг собирается до
  /// того, как интерфейс поднят, а поднимает его нативный сервис. Он же
  /// дописывает в готовый конфиг `file-descriptor` и `mtu` — обе величины его
  /// собственные, и хранить их копию на этой стороне значило бы завести второй
  /// источник правды для числа, которое обязано совпадать с `--mtu`,
  /// переданным tun2socks.
  final bool fromFileDescriptor;

  /// Имя интерфейса (десктоп). Задаём сами: без него mihomo берёт `Meta`, а
  /// wintun считает GUID адаптера от имени — то есть один и тот же GUID у
  /// любого mihomo-клиента на машине: соседний клиент через `OpenAdapter`
  /// забирает себе чужой адаптер.
  final String? device;

  /// `gvisor` | `system` | `mixed`. Ядро обязано быть собрано с
  /// `-tags with_gvisor` для первых двух вариантов.
  final String stack;

  /// `0` — не писать вовсе: значение проставит тот, кто создал устройство.
  final int mtu;

  /// Ставит ли ядро маршруты само. На Android — нет: там это дело VpnService,
  /// и попытка ядра прописать маршруты закончится отказом без root.
  final bool autoRoute;

  final bool strictRoute;

  /// Ядро ищет исходящий интерфейс само только там, где само же и
  /// маршрутизирует. На Android его сокеты и так вне туннеля (UID приложения
  /// исключён через `addDisallowedApplication`), и автодетект там лишний.
  bool get autoDetectInterface => autoRoute;
}

/// Конфиг mihomo — и для роли «локальный SOCKS под чужим туннелем», и для роли
/// владельца туннеля. Различает их наличие [MihomoTunOptions].
///
/// Под чужим туннелем (Android с tun2socks, десктопный proxy-режим) домен
/// назначения ядро узнаёт только из снифера: в SOCKS приезжает голый IP, и без
/// него доменные правила не срабатывают вообще. Перехвата DNS в этой схеме нет
/// и быть не может — он живёт в tun-инбаунде. Когда туннель ядра собственный,
/// доступны и `dns-hijack`, и правила по процессам (на десктопе).
///
/// У прокси всегда `udp: true`: под SOCKS это UDP ASSOCIATE, под своим туннелем
/// обычные UDP-сессии, и без флага mihomo молча отбрасывает и то и другое.
///
/// `fake-ip` не включаем даже там, где перехват DNS есть: ядро отдаёт системе
/// подменный адрес, и IP-правила пользователя сравниваются уже не с тем
/// адресом, ради которого их писали. Списки «обход/прокси» обязаны означать
/// одно и то же в обоих генераторах.
///
/// Эмитим JSON, а не YAML: YAML 1.2 — его надмножество, и райтер тащить незачем.
/// Расширение файла всё равно `.yaml`, как ядро и ждёт.
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
    int? httpPort,
    String? resolvedServerIp,
    bool localInboundsNoAuth = false,
    int? apiPort,
    String apiSecret = '',
    MihomoTunOptions? tun,
    AppRoutingMode routingMode = AppRoutingMode.allProxy,
    List<String> managedProcessNames = const [],
    String appProcessName = '',
    bool? windows,
  }) =>
      const JsonEncoder.withIndent('  ').convert(
        build(
          input,
          settings,
          socksPort: socksPort,
          httpPort: httpPort,
          resolvedServerIp: resolvedServerIp,
          localInboundsNoAuth: localInboundsNoAuth,
          apiPort: apiPort,
          apiSecret: apiSecret,
          tun: tun,
          routingMode: routingMode,
          managedProcessNames: managedProcessNames,
          appProcessName: appProcessName,
          windows: windows,
        ),
      );

  /// [apiPort]/[apiSecret] — RESTful API ядра для экрана «Соединения».
  /// Поднимается только когда порт передали: пингу и спидтесту он не нужен.
  ///
  /// [httpPort] — локальный HTTP-инбаунд. Нужен на всех платформах, включая
  /// Android: через него приложение качает обновления и подписки, потому что
  /// `Dart HttpClient` не умеет SOCKS вовсе, а свой пакет
  /// исключён из TUN и прямой запрос уходит мимо туннеля. Null он бывает
  /// только у пинга и спидтеста — им хватает SOCKS.
  ///
  /// [tun] непустой — ядро само владеет туннелем; [managedProcessNames] и
  /// [appProcessName] тогда превращаются в правила `PROCESS-NAME`, но только
  /// там, где ядро способно узнать процесс (десктоп).
  static Map<String, dynamic> build(
    String input,
    AppSettings settings, {
    required int socksPort,
    int? httpPort,
    String? resolvedServerIp,
    bool localInboundsNoAuth = false,
    int? apiPort,
    String apiSecret = '',
    MihomoTunOptions? tun,
    AppRoutingMode routingMode = AppRoutingMode.allProxy,
    List<String> managedProcessNames = const [],
    String appProcessName = '',
    bool? windows,
  }) {
    // Правила по процессам умеет только та сторона, где ядро способно найти
    // владельца соединения: десктопный TUN. На Android их роль исполняет сам
    // VpnService (addAllowed/DisallowedApplication), а поиск владельца из
    // непривилегированного процесса упирается в SELinux — netlink INET_DIAG и
    // `/proc/net/*` чужих uid untrusted_app не отдаются.
    final processRules = tun != null && !tun.fromFileDescriptor;

    // Режим сплита без правил по процессам — это не «сплит не сработал», а
    // «весь трафик ушёл мимо прокси». Финал у `onlySelected` равен `DIRECT`
    // («не выбранные приложения идут напрямую»), и держится этот смысл ровно на
    // правилах `PROCESS-NAME`, которые ставят выбранным приложениям прокси. Там,
    // где ядро процесс-владельца не знает, правил нет — а финал оставался, и
    // ядро честно отправляло в `DIRECT` всё: `[TCP] ... match Match using
    // DIRECT` на каждое соединение при живом «подключено».
    //
    // Так ломался десктопный proxy-режим (туннеля у ядра нет, процесс искать
    // негде) — и ровно так же ломался бы Android, где владельца по соединению
    // не отдаёт система, а по приложениям маршрутизирует VpnService. В обоих
    // случаях верный режим один — «весь трафик», а сплит исполняет тот, кто
    // умеет: VpnService на Android, никто в proxy-режиме (там он и не обещан).
    final effectiveRoutingMode = processRules
        ? routingMode
        : AppRoutingMode.allProxy;

    // fake-ip держится на перехвате DNS, а перехват живёт в tun-блоке: без
    // своего туннеля подменный адрес некому вернуть системе. Поэтому настройка
    // включает его только вместе с туннелем — и молчаливым откатом это не
    // является: в прокси-режиме десктопа запросы системы до ядра не доходят
    // вовсе, подменять там нечего.
    final fakeIp = settings.mihomoFakeIp && tun != null;

    // Готовый конфиг Clash вместо ссылки: прокси, группы и правила авторские,
    // наше дело — инбаунд, снифер, api и свои списки роутинга поверх.
    final clash = CustomClashConfig.tryParse(input);
    if (clash != null) {
      return _buildCustom(
        clash,
        settings,
        socksPort: socksPort,
        httpPort: httpPort,
        resolvedServerIp: resolvedServerIp,
        localInboundsNoAuth: localInboundsNoAuth,
        apiPort: apiPort,
        apiSecret: apiSecret,
        tun: tun,
        routingMode: effectiveRoutingMode,
        managedProcessNames: managedProcessNames,
        appProcessName: appProcessName,
        processRules: processRules,
        fakeIp: fakeIp,
        windows: windows,
      );
    }

    final proxy = buildProxy(input.trim());

    return <String, dynamic>{
      ..._inbound(
        settings,
        socksPort: socksPort,
        httpPort: httpPort,
        localInboundsNoAuth: localInboundsNoAuth,
        apiPort: apiPort,
        apiSecret: apiSecret,
      ),
      'mode': 'rule',
      'log-level': _logLevel(settings.xrayCore.logLevel),
      // Базы geo — те же вшитые v2fly `.dat`, что и у xray: ядро запускается с
      // `-d <dir>` и берёт их оттуда. Автообновление глушим, иначе ядро
      // полезет в сеть за своими копиями ещё до того, как туннель поднялся.
      'geodata-mode': true,
      'geo-auto-update': false,
      // Поиск процесса-владельца соединения стоит денег на каждой сессии
      // (лезет в /proc или в таблицы ОС), поэтому включаем его ровно там, где
      // без него не работают наши же правила.
      'find-process-mode': processRules ? 'strict' : 'off',
      'sniffer': buildSniffer(settings.xrayCore),
      'dns': buildDns(settings, fakeIp: fakeIp),
      if (tun != null) 'tun': buildTun(tun),
      if (settings.lanSharing) ...{
        'listeners': buildLanListeners(settings),
        'sub-rules': {lanRuleSet: buildLanRules()},
      },
      'proxies': [proxy],
      'rules': buildRules(
        settings,
        serverAddress: proxy['server']?.toString() ?? '',
        resolvedServerIp: resolvedServerIp,
        routingMode: effectiveRoutingMode,
        managedProcessNames: processRules ? managedProcessNames : const [],
        appProcessName: processRules ? appProcessName : '',
        tunOwned: tun != null,
        fakeIp: fakeIp,
        windows: windows,
      ),
    };
  }

  // ─────────────────────────────── TUN ───────────────────────────────

  /// tun-инбаунд: ядро само принимает пакеты.
  ///
  /// `dns-hijack` — то, ради чего эта схема и нужна: запрос системы на порт 53
  /// заворачивается в резолвер ядра вместо того, чтобы уехать в туннель
  /// обычным соединением. Аналог правила `dns-out` у xray.
  ///
  /// Адрес интерфейса задать нельзя: mihomo считает его из `dns.fake-ip-range`
  /// (`config.parseTun`: `PrefixFrom(FakeIPRange.Addr(), 30)`) независимо от
  /// того, включён ли fake-ip вообще. Поэтому готовность десктопного туннеля
  /// определяется по имени интерфейса, а не по адресу, как у sing-box.
  static Map<String, dynamic> buildTun(MihomoTunOptions tun) =>
      <String, dynamic>{
        'enable': true,
        if (tun.device != null && tun.device!.isNotEmpty) 'device': tun.device,
        'stack': tun.stack,
        if (tun.mtu > 0) 'mtu': tun.mtu,
        'auto-route': tun.autoRoute,
        'auto-detect-interface': tun.autoDetectInterface,
        if (tun.strictRoute) 'strict-route': true,
        'dns-hijack': const ['any:53'],
      };

  /// Конфиг сессии из готового clash-конфига.
  ///
  /// Наши списки роутинга едут в прокси-цель самого конфига ([primaryTarget] —
  /// первая группа, а не узел: пользователь переключает узлы внутри неё, и
  /// правило обязано ехать за его выбором), и встают после авторских правил, но
  /// перед их `MATCH`. Своего `MATCH` не добавляем: «остальное» в таком сервере
  /// решает автор — за этим его и берут.
  static Map<String, dynamic> _buildCustom(
    CustomClashConfig clash,
    AppSettings settings, {
    required int socksPort,
    int? httpPort,
    String? resolvedServerIp,
    bool localInboundsNoAuth = false,
    int? apiPort,
    String apiSecret = '',
    MihomoTunOptions? tun,
    AppRoutingMode routingMode = AppRoutingMode.allProxy,
    List<String> managedProcessNames = const [],
    String appProcessName = '',
    bool processRules = false,
    bool fakeIp = false,
    bool? windows,
  }) {
    return clash.buildSessionConfig(
      inbound: _inbound(
        settings,
        socksPort: socksPort,
        httpPort: httpPort,
        localInboundsNoAuth: localInboundsNoAuth,
        apiPort: apiPort,
        apiSecret: apiSecret,
      ),
      sniffer: buildSniffer(settings.xrayCore),
      logLevel: _logLevel(settings.xrayCore.logLevel),
      // Свой DNS (а с ним и fake-ip) уезжает сюда только когда у автора его нет
      // вовсе — см. `buildSessionConfig`. Автор конфига решил про DNS сам, и
      // настройка приложения его выбор не отменяет.
      dns: buildDns(settings, fakeIp: fakeIp),
      // Правила по процессам идут перед авторскими: «этот процесс мимо
      // туннеля» — решение пользователя о своей машине, и заготовка провайдера
      // его не отменяет. Ровно так же лежит `lan-deny`.
      prependRules: [
        if (processRules)
          ...buildProcessRules(
            routingMode: routingMode,
            managedProcessNames: managedProcessNames,
            appProcessName: appProcessName,
            proxyTarget: clash.primaryTarget,
            windows: windows,
          ),
        ...buildServerDirectRules(
          serverAddress: clash.address,
          resolvedServerIp: resolvedServerIp,
        ),
        if (tun != null) 'IP-CIDR,$tunInterfaceRange,DIRECT,no-resolve',
      ],
      appendRules: buildUserRules(
        settings,
        proxyTarget: clash.primaryTarget,
        fakeIp: fakeIp,
      ),
      extra: {
        if (processRules) 'find-process-mode': 'strict',
        if (tun != null) 'tun': buildTun(tun),
        if (settings.lanSharing) ...{
          'listeners': buildLanListeners(settings),
          'sub-rules': {lanRuleSet: buildLanRules(target: clash.primaryTarget)},
        },
      },
    );
  }

  /// Общая часть обоих путей: наши инбаунды, их креды и RESTful API.
  static Map<String, dynamic> _inbound(
    AppSettings settings, {
    required int socksPort,
    int? httpPort,
    required bool localInboundsNoAuth,
    int? apiPort,
    String apiSecret = '',
  }) {
    final creds = Socks5Credentials();
    return <String, dynamic>{
      'socks-port': socksPort,
      // `port` у mihomo — это HTTP-прокси. На десктопе он обязателен: через
      // него ходит апдейтер (SOCKS `HttpClient` не умеет вовсе) и на него
      // указывает системный прокси Windows/GNOME.
      'port': ?httpPort,
      // Слушаем только петлю: наружу инбаунд не смотрит, в него ходят
      // исключительно свои — tun2socks, апдейтер, системный прокси.
      'bind-address': '127.0.0.1',
      'allow-lan': false,
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
    };
  }

  // ───────────────────────────── sniffer ─────────────────────────────

  /// Восстановление домена из уже установленного соединения — аналог `sniffing`
  /// на инбаунде xray.
  ///
  /// Без него доменные правила не работают вовсе: tun2socks отдаёт в SOCKS
  /// чистый `IP:port`, сравнивать `DOMAIN-SUFFIX` и `GEOSITE` не с чем, и всё
  /// проваливается в `MATCH`. Со стороны выглядит как «списки не действуют, хотя
  /// у xray с теми же настройками действуют».
  ///
  /// `parse-pure-ip` обязателен: по умолчанию ядро нюхает только соединения, у
  /// которых имя хоста уже есть, а у нас его нет никогда.
  /// `override-destination` — зеркало `sniffingRouteOnly` у xray, значения
  /// инвертированы: они описывают одно и то же с разных сторон.
  ///
  /// Порты только строками, включая одиночные: у ядра это список строк, и число
  /// `80` роняет конфиг целиком с «cannot unmarshal !!int into string».
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
  /// Всё держится на разнице между пустым `users` и отсутствующим ключом:
  /// пустой список означает инбаунд без пароля, а отсутствующий ключ подставляет
  /// глобальный `authentication`, где лежат наши случайные креды для tun2socks.
  /// Забыть ключ — значит поднять раздачу, в которую никто не войдёт.
  ///
  /// `port` строкой: у mihomo это строка с диапазонами, и хотя листенеры
  /// пережили бы и число, писать сразу в целевом типе честнее.
  ///
  /// `rule` привязывает инбаунд к отдельному набору правил [buildLanRules] —
  /// ядро подставляет его вместо основного списка.
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
  /// только когда заполнены оба поля.
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
  /// [target] — куда уходит трафик из LAN-инбаундов: у ссылки это наш узел, у
  /// готового конфига — его группа.
  static List<String> buildLanRules({String target = proxyName}) => [
        for (final range in _lanSourceRanges) 'SRC-IP-CIDR,$range,$target',
        'MATCH,REJECT',
      ];

  // ──────────────────────────────── замер ────────────────────────────────

  /// Минимальный конфиг для короткоживущего ядра замера — аналог
  /// `generatePingConfig` у xray, и отличаться от него он должен только ядром.
  ///
  /// Боевой конфиг для замера не годится, и дело не в аккуратности: geo-базы
  /// ядро разбирает полсекунды (в логе это `Initial configuration complete,
  /// total time: 543ms`), а замер живёт секунды — полсекунды уехали бы прямо в
  /// измеренную задержку. Снифер и поиск процесса-владельца стоят на каждом
  /// соединении и здесь не нужны никому: соединение ровно одно, и оно уже
  /// известно куда идёт.
  ///
  /// [httpInbound] выбирает транспорт пробы, как и у xray: HTTP на десктопе
  /// (`HttpClient` из dart:io не умеет SOCKS вовсе), SOCKS на Android, где
  /// пробу делает Java через `Proxy.Type.SOCKS`. У mihomo это `port` против
  /// `socks-port`.
  ///
  /// Готовый конфиг Clash сюда не приходит: у него свои прокси и группы, и
  /// какой из них мерить — вопрос без ответа. Такой сервер остаётся с прежним
  /// поведением, то есть без url-замера.
  static String generatePingConfig(
    String input,
    AppSettings settings, {
    required int socksPort,
    bool httpInbound = false,
  }) {
    final proxy = buildProxy(input.trim());
    return jsonEncode(<String, dynamic>{
      if (httpInbound) 'port': socksPort else 'socks-port': socksPort,
      'bind-address': '127.0.0.1',
      'allow-lan': false,
      // Замер xray-стороны жёстко ходит по IPv4 (`queryStrategy: UseIPv4` в
      // ping-режиме), и здесь то же самое: два ядра обязаны мерить одинаково,
      // иначе разница в цифрах окажется разницей семейства адресов.
      'ipv6': false,
      'mode': 'rule',
      // Логи замера никому не показываются, а ядро на `info` пишет строку на
      // каждое соединение — в короткоживущем процессе это чистые расходы.
      'log-level': 'silent',
      'find-process-mode': 'off',
      // Ядро иначе полезет в сеть за своими копиями geo-баз — на замере это
      // лишний трафик и лишняя задержка старта.
      'geo-auto-update': false,
      'dns': _pingDns(),
      'proxies': [proxy],
      // Единственное правило: всё в прокси. Своё же соединение до сервера ядро
      // правилами не гоняет, так что закольцевать здесь нечего.
      'rules': ['MATCH,$proxyName'],
    });
  }

  /// DNS замера: тот же список, что у xray в ping-режиме.
  ///
  /// Фиксированный, а не пользовательский, и это не забывчивость — так же
  /// устроен замер у xray. Обычный UDP-53 у части провайдеров подменяется, и
  /// живой сервер краснел бы из-за резолва, а не из-за себя. `#DIRECT` —
  /// «мимо правил»: в туннель, которого ещё нет, DNS уходить не должен.
  static Map<String, dynamic> _pingDns() => <String, dynamic>{
        'enable': true,
        'ipv6': false,
        'enhanced-mode': 'normal',
        'default-nameserver': const ['https://1.1.1.1/dns-query'],
        'nameserver': const [
          'https://1.1.1.1/dns-query#DIRECT',
          'https://8.8.8.8/dns-query#DIRECT',
          'system',
        ],
      };

  // ─────────────────────────────── DNS ───────────────────────────────

  /// Резолвер самого ядра — аналог `dns`-блока xray.
  ///
  /// Без `enable` mihomo резолвит средствами Go, а на Android им резолвить
  /// нечем: `/etc/resolv.conf` там нет, и Go-резолвер уходит на 127.0.0.1:53,
  /// где никто не отвечает. Домен сервера из ссылки превращается в «no such
  /// host» ещё до первого пакета.
  ///
  /// DNS устройства этот блок не перехватывает — перехват живёт в tun-инбаунде
  /// (см. [buildTun]). [fakeIp] осмыслен только вместе с ним: без перехвата
  /// подменный адрес некому вернуть системе, и он же приедет обратно в правила
  /// неизвестным IP, поэтому включает его [build], а не настройка сама по себе.
  static Map<String, dynamic> buildDns(
    AppSettings settings, {
    bool fakeIp = false,
  }) {
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
      'enhanced-mode': fakeIp ? 'fake-ip' : 'normal',
      if (fakeIp) ...{
        // Диапазон подменных адресов. Тот же, что у ядра по умолчанию, и это
        // не косметика: из него же ядро берёт адрес собственного
        // tun-интерфейса (см. [buildTun]), а его мы отдельным правилом пускаем
        // мимо туннеля.
        'fake-ip-range': fakeIpRange,
        // Кому подменный адрес нельзя давать ни при каких условиях.
        //
        // Локальные зоны — потому что к ним ходят по настоящему адресу в своей
        // сети, а не через туннель. Проверки связности — потому что система
        // считает сеть сломанной, когда её пробник получает адрес, по которому
        // никто не отвечает: на Android это «интернета нет» в шторке при живом
        // туннеле.
        'fake-ip-filter': fakeIpFilter,
      },
      'default-nameserver': bootstrapNameservers(core),
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
  /// Схемы у ядер разные, а поле в настройках одно, поэтому переводим.
  /// `localhost` становится `system`. `h2c://` и `fakedns` mihomo не знает, и
  /// их выбрасываем: неизвестная схема роняет разбор конфига целиком, а с ним
  /// и подключение.
  ///
  /// Суффикс `+local` («мимо роутинга» у xray) превращается в `#DIRECT`.
  /// Раньше он просто снимался — считалось, что прямой резолв у mihomo и так
  /// по умолчанию. Это перестало быть правдой вместе с `respect-rules`
  /// (см. [buildDns]): ядро подставляет `RULES` каждому серверу, у которого во
  /// фрагменте пусто, и весь список уезжает в туннель. Явное имя прокси
  /// фрагмент перебивает, а `DIRECT` у mihomo существует всегда.
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

  /// Bootstrap-резолвер: по нему ядро разрешает ИМЕНА самих DoH-серверов.
  ///
  /// Ходит по нему mihomo всегда напрямую — мимо туннеля и мимо правил
  /// (`parseNameServer` с `respectRules = false` в config.go ядра), — поэтому
  /// содержимое списка видит провайдер. Пара чужих резолверов, вписанная сюда
  /// намертво, означала вот что: человек выбрал Quad9, а имя его же
  /// DoH-сервера уходило спрашивать у Google с Cloudflare, открытым текстом и
  /// в обход туннеля.
  ///
  /// Берём его собственные серверы, но только те, у которых адрес — IP: им
  /// резолв не нужен, а значит только они здесь и работают (ядро это прямо
  /// требует — «default nameserver should be pure IP»). Запись переносится
  /// целиком, вместе со схемой: `https://9.9.9.9/dns-query` прячет запрос в
  /// TLS, а голый `9.9.9.9` отдал бы его провайдеру открытым.
  ///
  /// Список, где ни одного IP нет (все серверы заданы именами), остаётся на
  /// прежней паре: подставить туда нечего, а менять ей транспорт — отдельный
  /// риск в сети, где DoH к этим адресам могут и не пустить.
  static List<String> bootstrapNameservers(XrayCoreSettings core) {
    final out = [
      for (final server in dnsServers(core))
        if (_hasIpAddress(server)) server,
    ];
    return out.isEmpty ? _bootstrapFallback : out;
  }

  static const _bootstrapFallback = ['1.1.1.1', '8.8.8.8'];

  /// Адрес записи — IP, а не имя.
  static bool _hasIpAddress(String server) {
    var host = server;
    // Ни фрагмент (`#DIRECT`), ни путь (`/dns-query`) к адресу не относятся.
    final hash = host.indexOf('#');
    if (hash >= 0) host = host.substring(0, hash);
    final scheme = host.indexOf('://');
    if (scheme >= 0) host = host.substring(scheme + 3);
    final slash = host.indexOf('/');
    if (slash >= 0) host = host.substring(0, slash);
    if (host.startsWith('[')) {
      final close = host.indexOf(']');
      if (close < 0) return false;
      host = host.substring(1, close);
    } else if (':'.allMatches(host).length == 1) {
      // Одно двоеточие — это порт. У голого IPv6 их больше, и там отрезать
      // нечего.
      host = host.substring(0, host.indexOf(':'));
    }
    return InternetAddress.tryParse(host) != null;
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
    final local = scheme.group(2) != null;
    return '$name://${v.substring(scheme.end)}${local ? '#DIRECT' : ''}';
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

  /// Переносит `vcn`/`pcs` из ссылки в поля mihomo — то же, что делает
  /// xray-генератор (`config_gen.dart`, `_tlsClientSettings`).
  ///
  /// `name-cert-verify` описан у ядра как «меняет только цель проверки DNSName
  /// в сертификате, не трогая SNI» — дословный аналог `verifyPeerCertByName`.
  /// Без него сертификат сверяется с маскировочным `sni` (панели ставят туда
  /// чужой домен) и рукопожатие падает.
  ///
  /// Оба поля переносим, только когда значение одно. У xray и то и другое —
  /// список через запятую, у mihomo обе настройки принимают одну строку, а
  /// какое из нескольких значений относится к листу цепочки, из ссылки не
  /// видно. Взятый наугад чужой отпечаток закрыл бы соединение совсем, поэтому
  /// при нескольких значениях не пиним вовсе: имя проверяется правильное,
  /// цепочка — по системным корням.
  static void _applyCertPinning(Map<String, dynamic> out, Uri uri) {
    List<String> values(String key) => _param(uri, key)
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final names = values('vcn');
    if (names.length == 1) out['name-cert-verify'] = names.first;
    final pins = values('pcs');
    if (pins.length == 1) out['fingerprint'] = pins.first;
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
    // Только для обычного TLS: у REALITY своя проверка подлинности сервера,
    // сертификат там подставной и пинить его нечем.
    if (security == 'tls') _applyCertPinning(out, uri);
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
    final network = _param(uri, 'type', 'tcp');
    final alpn = _alpn(_param(uri, 'alpn'));
    if (alpn != null) out['alpn'] = _alpnForTrojan(network, alpn);
    _applyCertPinning(out, uri);

    _applyTransport(out, uri, network: network, host: sni);
    return out;
  }

  /// Тот же случай, что у xray: ws поверх TLS не переживает выбор h2 по ALPN,
  /// апгрейд соединения идёт только по HTTP/1.1.
  ///
  /// Чиним только trojan, потому что в mihomo только он и читает alpn на
  /// ws-пути (`adapter/outbound/trojan.go`): у vless и vmess ws-ветка
  /// подставляет `http/1.1` сама и alpn из конфига там не смотрит вовсе. Тянуть
  /// правку туда — менять конфиг там, где ядро на него не смотрит.
  ///
  /// Пара целиком, как и в xray: одиночный `h2` — осознанный выбор.
  static List<String> _alpnForTrojan(String network, List<String> alpn) =>
      network == 'ws' &&
              alpn.length == 2 &&
              alpn[0] == 'h2' &&
              alpn[1] == 'http/1.1'
          ? const ['http/1.1']
          : alpn;

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

  /// Правила mihomo: `тип,значение,цель[,no-resolve]`.
  ///
  /// Порядок повторяет xray-генератор, иначе одно и то же правило вело бы себя
  /// по-разному в зависимости от ядра: блок, сам сервер, обход, приватные сети,
  /// прокси, финал.
  ///
  /// `no-resolve` на пользовательских IP-правилах — зеркало
  /// `routingDomainStrategy` у xray. Обычно назначение и так приходит голым IP,
  /// резолвить нечего, и запрет экономит запрос. Но со снятым
  /// `sniffingRouteOnly` ядро подменяет назначение вынюханным доменом, и тогда
  /// `IP-CIDR` с `no-resolve` промахивается мимо собственного адреса — тот самый
  /// баг «корпоративный CIDR в обходе не работает». Поэтому резолв разрешаем,
  /// но только когда пользовательские IP-правила вообще есть.
  static List<String> buildRules(
    AppSettings settings, {
    required String serverAddress,
    String? resolvedServerIp,
    String proxyTarget = proxyName,
    AppRoutingMode routingMode = AppRoutingMode.allProxy,
    List<String> managedProcessNames = const [],
    String appProcessName = '',
    bool tunOwned = false,
    bool fakeIp = false,
    bool? windows,
  }) {
    final rules = <String>[
      ...buildProcessRules(
        routingMode: routingMode,
        managedProcessNames: managedProcessNames,
        appProcessName: appProcessName,
        proxyTarget: proxyTarget,
        windows: windows,
      ),
      ...buildUserRules(settings, blockedOnly: true, fakeIp: fakeIp),
      ...buildServerDirectRules(
        serverAddress: serverAddress,
        resolvedServerIp: resolvedServerIp,
      ),
      // Адрес собственного tun-интерфейса. Ядро считает его из
      // `dns.fake-ip-range` (см. [buildTun]), и без явного правила обращение к
      // нему ушло бы в туннель — то есть само в себя.
      if (tunOwned) 'IP-CIDR,$tunInterfaceRange,DIRECT,no-resolve',
      ...buildUserRules(
        settings,
        proxyTarget: proxyTarget,
        blockedOnly: false,
        skipBlocked: true,
        fakeIp: fakeIp,
      ),
    ];

    // При пер-аппном сплите финал несёт смысл «остальные приложения идут
    // мимо/через туннель», и выбор пользователя в «финальном действии» его не
    // отменяет: он про трафик, а не про приложения.
    var finalTarget = switch (routingMode) {
      AppRoutingMode.onlySelected => 'DIRECT',
      AppRoutingMode.allExceptSelected => proxyTarget,
      AppRoutingMode.allProxy => _finalTarget(settings.finalOutbound, proxyTarget),
    };

    // Kill switch осмыслен только при глобал-прокси: гоним весь IP-трафик в
    // прокси, а финалом ставим отказ — тогда падение прокси не превращается в
    // утечку мимо туннеля. Для «обхода» и «блокировки» финал и так не proxy.
    if (settings.killSwitch &&
        routingMode == AppRoutingMode.allProxy &&
        finalTarget == proxyTarget) {
      rules
        ..add('IP-CIDR,0.0.0.0/1,$proxyTarget')
        ..add('IP-CIDR,128.0.0.0/1,$proxyTarget');
      finalTarget = 'REJECT';
    }

    return [...rules, 'MATCH,$finalTarget'];
  }

  /// Подсеть tun-интерфейса ядра: `dns.fake-ip-range` по умолчанию
  /// `198.18.0.1/16`, а адрес интерфейса mihomo берёт из неё же с маской /30.
  static const tunInterfaceRange = '198.18.0.0/30';

  /// Диапазон подменных адресов. Совпадает с умолчанием ядра намеренно: тот же
  /// диапазон определяет адрес tun-интерфейса, и разъехаться им нельзя.
  static const fakeIpRange = '198.18.0.1/16';

  /// Домены, которым подменный адрес не выдаётся никогда.
  ///
  /// Первые — локальные зоны: к ним ходят по настоящему адресу в своей сети.
  /// Остальные — проверки связности Android, Windows и Apple: получив адрес, по
  /// которому никто не отвечает, система решает, что сети нет, и рисует
  /// «интернета нет» поверх работающего туннеля.
  static const fakeIpFilter = <String>[
    '*.lan',
    '*.local',
    '*.localdomain',
    '*.home.arpa',
    'localhost',
    'connectivitycheck.gstatic.com',
    '*.msftconnecttest.com',
    '*.msftncsi.com',
    'captive.apple.com',
    'time.*.com',
    '*.ntp.org',
  ];

  /// Правила по процессам — только для схемы, где туннель принадлежит ядру и
  /// оно способно узнать владельца соединения (десктоп).
  ///
  /// Порядок важен: собственный процесс приложения и чужие VPN-клиенты идут
  /// раньше пользовательского сплита, иначе выбранный «весь трафик кроме…»
  /// режим утащил бы в туннель и наши пинг-сокеты.
  ///
  /// Имя сравнивается без учёта регистра (`strings.EqualFold` в
  /// `rules/common/process.go`), поэтому вариантов регистра, как у sing-box с
  /// его map-lookup'ом, тут не нужно.
  static List<String> buildProcessRules({
    required AppRoutingMode routingMode,
    required List<String> managedProcessNames,
    required String appProcessName,
    String proxyTarget = proxyName,
    bool? windows,
  }) {
    final app = appProcessName.trim();
    if (app.isEmpty && managedProcessNames.isEmpty) return const [];

    // Целевая ОС параметром, а не из `Platform`: три имени ниже несут `.exe`
    // только на Windows, и снятая там фикстура иначе падала бы на linux-раннере,
    // ничего не сообщая о самом генераторе. Ср. [SingBoxTunConfigGen.generate].
    final exe = (windows ?? Platform.isWindows) ? '.exe' : '';

    final rules = <String>[
      // Наши собственные сокеты (tcp-пинг, спидтест, апдейтер) — мимо туннеля,
      // иначе пинг мерил бы локальный конец туннеля вместо сервера.
      if (app.isNotEmpty) 'PROCESS-NAME,$app,DIRECT',
      // Чужие VPN-клиенты: их собственный транспорт обязан идти мимо нашего
      // туннеля, иначе получается туннель в туннеле и оба перестают работать.
      // Только в режиме «весь трафик»: при пер-аппном сплите пользователь
      // назвал приложения сам, и дописывать к его списку свои нельзя.
      if (routingMode == AppRoutingMode.allProxy) ...[
        'PROCESS-NAME,tailscaled$exe,DIRECT',
        'PROCESS-NAME,wireguard$exe,DIRECT',
        'PROCESS-NAME,openvpn$exe,DIRECT',
      ],
    ];

    for (final process in managedProcessNames) {
      final name = process.trim();
      if (name.isEmpty) continue;
      switch (routingMode) {
        case AppRoutingMode.onlySelected:
          rules.add('PROCESS-NAME,$name,$proxyTarget');
        case AppRoutingMode.allExceptSelected:
          rules.add('PROCESS-NAME,$name,DIRECT');
        case AppRoutingMode.allProxy:
          break;
      }
    }
    return rules;
  }

  /// Сам сервер — мимо туннеля, иначе обращение к его адресу закольцуется.
  ///
  /// `no-resolve` здесь безусловен, и снимать его нельзя ни при каких
  /// настройках: резолв ради правила, которое защищает от круга, — это тот же
  /// круг, только на шаг раньше.
  static List<String> buildServerDirectRules({
    required String serverAddress,
    String? resolvedServerIp,
  }) {
    final rules = <String>[];
    if (serverAddress.isNotEmpty && !looksLikeIpOrCidr(serverAddress)) {
      rules.add('DOMAIN,$serverAddress,DIRECT');
    }
    for (final ip in [serverAddress, resolvedServerIp ?? '']) {
      if (ip.isNotEmpty && looksLikeIpOrCidr(ip)) {
        rules.add('IP-CIDR,${_cidr(ip)},DIRECT,no-resolve');
      }
    }
    return rules;
  }

  /// Списки роутинга из настроек: блок, обход (плюс приватные диапазоны) и
  /// прокси. [proxyTarget] — куда слать «в прокси»: у ссылки это наш
  /// единственный узел, у готового конфига — его группа.
  ///
  /// [blockedOnly]/[skipBlocked] разделяют список надвое: у ссылки блокировки
  /// решают раньше правила про сам сервер, и порядок этот менять нельзя.
  static List<String> buildUserRules(
    AppSettings settings, {
    String proxyTarget = proxyName,
    bool blockedOnly = false,
    bool skipBlocked = false,
    bool fakeIp = false,
  }) {
    final rules = <String>[];

    final hasUserIpRules = [
      settings.blockedRules,
      settings.directRules,
      settings.proxyRules,
    ].any((raw) => splitGeoipTokens(
          splitDomainsAndIps(_parseList(raw)).ips,
        ).plainIps.isNotEmpty);
    // С fake-ip назначение и вовсе перестаёт быть адресом: ядро выдало системе
    // подменный, а перед выбором правила стирает его (`preHandleMetadata`
    // чистит `DstIP` для fake-адресов) и восстанавливает домен. Правило с
    // `no-resolve` тогда сравнивать не с чем — оно промахивается всегда, и
    // «корпоративный CIDR в обходе не работает» возвращается в полном объёме.
    final resolveForIpRules =
        (fakeIp || !settings.xrayCore.sniffingRouteOnly) && hasUserIpRules;
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

    if (!skipBlocked) addGroup(settings.blockedRules, 'REJECT');
    if (blockedOnly) return rules;

    addGroup(settings.directRules, 'DIRECT');
    // Приватные диапазоны xray под `AsIs` тоже по домену не проверяет, так что
    // резолв им не положен независимо от настроек снифинга.
    for (final range in _privateRanges) {
      rules.add('IP-CIDR,$range,DIRECT,no-resolve');
    }

    addGroup(settings.proxyRules, proxyTarget);
    return rules;
  }

  static String _finalTarget(String finalOutbound, String proxyTarget) =>
      switch (finalOutbound) {
        AppSettings.finalOutboundDirect => 'DIRECT',
        AppSettings.finalOutboundBlock => 'REJECT',
        _ => proxyTarget,
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
