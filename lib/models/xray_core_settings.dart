import 'dart:convert';
import 'dart:io';

/// клиентские опции xray (dns, routing, xhttp/xmux, sniffing)
class XrayCoreSettings {
  final String logLevel;
  final String routingDomainStrategy;

  final bool dnsUseCustom;
  /// One DNS server address per line (e.g. `https+local://1.1.1.1/dns-query`).
  final String dnsServers;
  final String dnsQueryStrategy;
  final bool dnsDisableCache;
  /// When true, first resolver uses [directDomains] with skipFallback (legacy behavior).
  final bool dnsSplitDirectDomains;

  /// Mux.Cool — несколько соединений внутри одного (`mux` у аутбаунда).
  ///
  /// Придуман ради экономии рукопожатий, а не ради скорости: документация ядра
  /// прямо предупреждает, что на видео, загрузках и замерах скорости
  /// мультиплексор делает хуже. Поэтому выключен по умолчанию — как и в ядре.
  final bool muxEnabled;

  /// Сколько TCP-потоков вести в одном соединении. `-1` — не мультиплексировать
  /// TCP вовсе (остаётся только XUDP), `0` ядро само считает за 8, потолок 128.
  final int muxConcurrency;

  /// То же для UDP — XUDP, отдельная пачка. Ради него всё и затевалось: без
  /// него каждая UDP-сессия открывает своё соединение до сервера, и пачка
  /// DNS-запросов с Android упирается в лимит новых соединений (см. правило
  /// `dns-out`). `0` — UDP едет в общей TCP-пачке, `-1` — не трогать UDP вовсе.
  final int muxXudpConcurrency;

  /// Что делать с UDP/443, то есть с QUIC: `reject`, `allow` или `skip`.
  /// Умолчание ядра — `reject`: браузер через секунду откатится на TCP.
  final String muxXudpProxyUDP443;

  final bool xmuxEnabled;
  final String xmuxMaxConcurrency;
  final String xmuxMaxConnections;
  final String xmuxCMaxReuseTimes;
  final String xmuxHMaxRequestTimes;
  final String xmuxHMaxReusableSecs;
  final int xmuxHKeepAlivePeriod;

  /// Фрагментация TLS ClientHello (`fragment` у freedom-аутбаунда xray).
  ///
  /// Режет первый пакет соединения на куски, чтобы DPI не увидел SNI целиком.
  /// Работает только на xray-пути: у mihomo такой опции нет вовсе
  /// (MetaCubeX/mihomo#1046 висит открытым), у sing-box своя `tls_fragment`,
  /// и наш десктопный TUN-конфиг её не использует — там дозванивается xray
  /// внутри keqrnel, то есть эта же настройка.
  final bool fragmentEnabled;

  /// `tlshello` (только ClientHello) или `1-3` (первые N записей потока).
  final String fragmentPackets;

  /// Размер куска в байтах: число или диапазон `100-200`.
  final String fragmentLength;

  /// Пауза между кусками в миллисекундах: число или диапазон `10-20`.
  /// `0` с `tlshello` — разрезать ClientHello, но отправить одним пакетом.
  final String fragmentInterval;

  /// Шум перед UDP-трафиком (`streamSettings.finalmask.udp`, тип `noise`).
  ///
  /// Фрагментация ClientHello сюда не годится по устройству: у hysteria и mkcp
  /// никакого ClientHello в потоке нет, и `_applyFragment` для них честно
  /// ничего не делает. Шум работает иначе — перед первым настоящим пакетом на
  /// адрес ядро отправляет туда мусор, и профиль соединения перестаёт быть
  /// узнаваемым с первого пакета.
  final bool noiseEnabled;

  /// Чем шуметь: [noiseRandom] — случайный мусор, остальное — свой пакет из
  /// [noisePacket] в этой кодировке.
  final String noiseKind;

  /// Пакет-заготовка. Пуст при [noiseRandom].
  final String noisePacket;

  /// Длина случайного пакета в байтах: число или диапазон `50-100`.
  /// Работает только при [noiseRandom]: ядро отвергает конфиг, где заданы и
  /// `packet`, и `rand` разом.
  final String noiseRandLength;

  /// Диапазон значений случайных байтов, 0–255. Пусто — весь диапазон.
  final String noiseRandBytes;

  /// Пауза после шумового пакета в миллисекундах: число или диапазон.
  final String noiseDelay;

  /// Через сколько секунд шум повторить для того же адреса. Пусто или 0 —
  /// один раз за жизнь соединения.
  final String noiseReset;

  final bool sniffingEnabled;

  /// `true` — снифер только подсказывает роутингу домен, соединение уходит на
  /// тот адрес, который подставило приложение. `false` (умолчание, как у
  /// v2rayNG/Happ) — адресом назначения становится сам домен.
  ///
  /// Разница видна ровно там, где IP от приложения «неправильный». Домен для
  /// прямого маршрута приложение резолвит своим DNS, и если этот DNS ушёл через
  /// туннель (готовый конфиг провайдера без перехвата DNS, DoH внутри браузера,
  /// кеш до подключения), в ответе будет узел CDN, ближний к выходу туннеля.
  /// С `routeOnly` мы к нему и дозваниваемся — напрямую, из России, в обход
  /// туннеля: «ру-сайты не грузятся, пока не выключишь снифинг». Подмена
  /// адреса заставляет резолвить домен заново и на месте: прямой маршрут
  /// получает локальный IP, проксируемый — резолв на стороне сервера.
  final bool sniffingRouteOnly;

  /// Дозваниваться до адресов домена одновременно, а не по очереди.
  ///
  /// Домен сервера обычно резолвится в несколько адресов, и по очереди это
  /// значит «мёртвый адрес стоит целого таймаута»: у заблокированного IP
  /// соединение висит, пока ядро не сдастся и не возьмёт следующий. С гонкой
  /// выживает тот, кто ответил первым.
  ///
  /// У ядер это разные ручки. mihomo включает гонку глобально
  /// (`tcp-concurrent`), xray — на конкретном аутбаунде
  /// (`sockopt.happyEyeballs`), причём за `dialerProxy` ядро её игнорирует:
  /// дозвон там делает не этот аутбаунд, а предыдущее звено. Поэтому в
  /// цепочке гонки не будет, а с фрагментацией будет — там настоящий дозвон
  /// делает freedom-аутбаунд, ему настройка и достаётся. В десктопном TUN
  /// дозвон исполняет sing-box, и он гоняет адреса параллельно всегда, без
  /// нашего участия.
  final bool concurrentDial;

  /// Свои адреса для доменов — то же, что файл hosts, только внутри ядра.
  ///
  /// Строка на запись: `домен адрес`. Порядок слов свободный (адрес слева
  /// тоже понимаем — так выглядит системный hosts), разделителем годится
  /// пробел, двоеточие или знак равенства. Адресов можно несколько через
  /// запятую, а вместо адреса — другой домен: ядро тогда резолвит его.
  /// Маска `*.example.com` значит «домен и его поддомены».
  final String dnsHosts;

  /// Резолвер для отдельных доменов: «кого спрашивать про вот эти имена».
  ///
  /// Строка на запись: маска домена, затем один или несколько адресов
  /// резолвера в том же синтаксисе, что и в поле «свои DNS-серверы».
  /// Домашний суффикс — на роутер, рабочий — на корпоративный DNS, остальное
  /// идёт обычным путём. Откат на общий список ядро при этом не делает: в
  /// этом и смысл — адрес выбран явно.
  final String dnsPolicy;



  const XrayCoreSettings({
    this.logLevel = 'warning',
    this.routingDomainStrategy = 'AsIs',
    this.dnsUseCustom = false,
    this.dnsServers = 'https+local://1.1.1.1/dns-query\nhttps+local://8.8.8.8/dns-query',
    this.dnsQueryStrategy = 'UseIPv4',
    this.dnsDisableCache = false,
    this.dnsSplitDirectDomains = true,
    this.muxEnabled = false,
    this.muxConcurrency = defaultMuxConcurrency,
    this.muxXudpConcurrency = defaultMuxXudpConcurrency,
    this.muxXudpProxyUDP443 = muxUdp443Reject,
    this.xmuxEnabled = false,
    this.xmuxMaxConcurrency = '',
    this.xmuxMaxConnections = '',
    this.xmuxCMaxReuseTimes = '',
    this.xmuxHMaxRequestTimes = '',
    this.xmuxHMaxReusableSecs = '',
    this.xmuxHKeepAlivePeriod = 0,
    this.fragmentEnabled = false,
    this.fragmentPackets = fragmentPacketsTlsHello,
    this.fragmentLength = defaultFragmentLength,
    this.fragmentInterval = defaultFragmentInterval,
    this.noiseEnabled = false,
    this.noiseKind = noiseRandom,
    this.noisePacket = '',
    this.noiseRandLength = defaultNoiseRandLength,
    this.noiseRandBytes = '',
    this.noiseDelay = '',
    this.noiseReset = '',
    this.sniffingEnabled = true,
    this.sniffingRouteOnly = false,
    this.concurrentDial = false,
    this.dnsHosts = '',
    this.dnsPolicy = '',
  });

  static const logLevels = ['none', 'error', 'warning', 'info', 'debug'];

  /// Режет только TLS ClientHello — то, ради чего фрагментация и нужна.
  static const fragmentPacketsTlsHello = 'tlshello';

  /// Режет первые записи TCP-потока независимо от того, TLS там или нет.
  static const fragmentPacketsFirstPackets = '1-3';

  /// Оба значения, которые документирует xray. Свободного ввода тут нет
  /// намеренно: `packets` вне этого списка ядро не понимает, а ошибка вылезет
  /// не в настройках, а на подключении — «SOCKS port not ready» без причины.
  static const fragmentPacketModes = [
    fragmentPacketsTlsHello,
    fragmentPacketsFirstPackets,
  ];

  static const defaultFragmentLength = '100-200';
  static const defaultFragmentInterval = '10-20';

  /// QUIC режем: браузер через секунду сам откатится на TCP. Так же считает и
  /// ядро — пустое поле оно превращает именно в это.
  static const muxUdp443Reject = 'reject';

  /// QUIC пускаем внутрь мультиплексора.
  static const muxUdp443Allow = 'allow';

  /// QUIC мимо мультиплексора, своим ходом протокола.
  static const muxUdp443Skip = 'skip';

  /// Три значения, которые ядро понимает. Четвёртое роняет разбор всего
  /// конфига — та же цена ошибки, что у `fragmentPacketModes`.
  static const muxUdp443Modes = [
    muxUdp443Reject,
    muxUdp443Allow,
    muxUdp443Skip,
  ];

  /// Случайный мусор вместо своего пакета: у ядра это `rand` вместо `packet`.
  /// Двух сразу оно не принимает и роняет конфиг целиком, поэтому выбор здесь
  /// один на оба поля, а не два независимых.
  static const noiseRandom = 'rand';

  /// Свой пакет: текстом как есть, шестнадцатеричный, base64. Имена — те же,
  /// что ядро ждёт в поле `type` (`PraseByteSlice` в `transport_finalmask.go`).
  static const noiseStr = 'str';
  static const noiseHex = 'hex';
  static const noiseBase64 = 'base64';

  static const noiseKinds = [noiseRandom, noiseStr, noiseHex, noiseBase64];

  /// Длина мусорного пакета по умолчанию. Своего умолчания у ядра тут нет:
  /// пустой `rand` означает нулевую длину, то есть шума не будет вовсе.
  static const defaultNoiseRandLength = '50-100';

  /// Столько же кладёт ядро, когда `concurrency` не задан.
  static const defaultMuxConcurrency = 8;

  /// Своего умолчания у ядра тут нет: пустое поле означает «UDP едет в общей
  /// TCP-пачке», то есть XUDP выключен. 16 — рабочее число, с которым XUDP и
  /// живёт у клиентов; ядро принимает от 1 до 1024.
  static const defaultMuxXudpConcurrency = 16;
  static const dnsQueryStrategies = [
    'UseIPv4',
    'UseIPv6',
    'UseIP',
    'PreferIPv4',
    'PreferIPv6',
  ];
  static const routingDomainStrategies = ['AsIs', 'IPIfNonMatch', 'IPOnDemand'];

  Map<String, dynamic> toJson() => {
        'logLevel': logLevel,
        'routingDomainStrategy': routingDomainStrategy,
        'dnsUseCustom': dnsUseCustom,
        'dnsServers': dnsServers,
        'dnsQueryStrategy': dnsQueryStrategy,
        'dnsDisableCache': dnsDisableCache,
        'dnsSplitDirectDomains': dnsSplitDirectDomains,
        'muxEnabled': muxEnabled,
        'muxConcurrency': muxConcurrency,
        'muxXudpConcurrency': muxXudpConcurrency,
        'muxXudpProxyUDP443': muxXudpProxyUDP443,
        'xmuxEnabled': xmuxEnabled,
        'xmuxMaxConcurrency': xmuxMaxConcurrency,
        'xmuxMaxConnections': xmuxMaxConnections,
        'xmuxCMaxReuseTimes': xmuxCMaxReuseTimes,
        'xmuxHMaxRequestTimes': xmuxHMaxRequestTimes,
        'xmuxHMaxReusableSecs': xmuxHMaxReusableSecs,
        'xmuxHKeepAlivePeriod': xmuxHKeepAlivePeriod,
        'fragmentEnabled': fragmentEnabled,
        'fragmentPackets': fragmentPackets,
        'fragmentLength': fragmentLength,
        'fragmentInterval': fragmentInterval,
        'noiseEnabled': noiseEnabled,
        'noiseKind': noiseKind,
        'noisePacket': noisePacket,
        'noiseRandLength': noiseRandLength,
        'noiseRandBytes': noiseRandBytes,
        'noiseDelay': noiseDelay,
        'noiseReset': noiseReset,
        'sniffingEnabled': sniffingEnabled,
        'sniffingRouteOnly': sniffingRouteOnly,
        'concurrentDial': concurrentDial,
        'dnsHosts': dnsHosts,
        'dnsPolicy': dnsPolicy,
      };

  factory XrayCoreSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const XrayCoreSettings();
    String str(String k, String def) => (json[k] as String?)?.trim().isNotEmpty == true
        ? (json[k] as String).trim()
        : def;
    bool b(String k, bool def) => json[k] as bool? ?? def;
    int i(String k, int def) {
      final v = (json[k] as num?)?.toInt() ?? def;
      return v < 0 ? 0 : v;
    }
    // Отрицательное значение у mux осмысленно («не мультиплексировать»),
    // поэтому свой читатель: общий `i` срезает минус в ноль.
    int signed(String k, int def, int min, int max) {
      final v = (json[k] as num?)?.toInt() ?? def;
      return v < min ? min : (v > max ? max : v);
    }
    final log = str('logLevel', 'warning');
    final domain = str('routingDomainStrategy', 'AsIs');
    final query = str('dnsQueryStrategy', 'UseIPv4');
    final packets = str('fragmentPackets', fragmentPacketsTlsHello);
    final udp443 = str('muxXudpProxyUDP443', muxUdp443Reject);
    final noiseKind = str('noiseKind', noiseRandom);
    return XrayCoreSettings(
      logLevel: logLevels.contains(log) ? log : 'warning',
      routingDomainStrategy:
          routingDomainStrategies.contains(domain) ? domain : 'AsIs',
      dnsUseCustom: b('dnsUseCustom', false),
      dnsServers: json['dnsServers'] as String? ??
          'https+local://1.1.1.1/dns-query\nhttps+local://8.8.8.8/dns-query',
      dnsQueryStrategy: dnsQueryStrategies.contains(query) ? query : 'UseIPv4',
      dnsDisableCache: b('dnsDisableCache', false),
      dnsSplitDirectDomains: b('dnsSplitDirectDomains', true),
      muxEnabled: b('muxEnabled', false),
      muxConcurrency: signed('muxConcurrency', defaultMuxConcurrency, -1, 128),
      muxXudpConcurrency:
          signed('muxXudpConcurrency', defaultMuxXudpConcurrency, -1, 1024),
      muxXudpProxyUDP443: muxUdp443Modes.contains(udp443)
          ? udp443
          : muxUdp443Reject,
      xmuxEnabled: b('xmuxEnabled', false),
      xmuxMaxConcurrency: json['xmuxMaxConcurrency'] as String? ?? '',
      xmuxMaxConnections: json['xmuxMaxConnections'] as String? ?? '',
      xmuxCMaxReuseTimes: json['xmuxCMaxReuseTimes'] as String? ?? '',
      xmuxHMaxRequestTimes: json['xmuxHMaxRequestTimes'] as String? ?? '',
      xmuxHMaxReusableSecs: json['xmuxHMaxReusableSecs'] as String? ?? '',
      xmuxHKeepAlivePeriod: i('xmuxHKeepAlivePeriod', 0),
      fragmentEnabled: b('fragmentEnabled', false),
      // Неизвестный режим — не повод отдать ядру мусор: откатываемся на
      // tlshello, как если бы фрагментацию только что включили.
      fragmentPackets: fragmentPacketModes.contains(packets)
          ? packets
          : fragmentPacketsTlsHello,
      fragmentLength: str('fragmentLength', defaultFragmentLength),
      fragmentInterval: str('fragmentInterval', defaultFragmentInterval),
      noiseEnabled: b('noiseEnabled', false),
      // Незнакомый вид шума — назад к случайному мусору: свой пакет без
      // понятной кодировки ядру отдавать нечем.
      noiseKind: noiseKinds.contains(noiseKind) ? noiseKind : noiseRandom,
      noisePacket: json['noisePacket'] as String? ?? '',
      noiseRandLength: str('noiseRandLength', defaultNoiseRandLength),
      noiseRandBytes: json['noiseRandBytes'] as String? ?? '',
      noiseDelay: json['noiseDelay'] as String? ?? '',
      noiseReset: json['noiseReset'] as String? ?? '',
      sniffingEnabled: b('sniffingEnabled', true),
      sniffingRouteOnly: b('sniffingRouteOnly', false),
      concurrentDial: b('concurrentDial', false),
      dnsHosts: json['dnsHosts'] as String? ?? '',
      dnsPolicy: json['dnsPolicy'] as String? ?? '',
    );
  }

  XrayCoreSettings copyWith({
    String? logLevel,
    String? routingDomainStrategy,
    bool? dnsUseCustom,
    String? dnsServers,
    String? dnsQueryStrategy,
    bool? dnsDisableCache,
    bool? dnsSplitDirectDomains,
    bool? muxEnabled,
    int? muxConcurrency,
    int? muxXudpConcurrency,
    String? muxXudpProxyUDP443,
    bool? xmuxEnabled,
    String? xmuxMaxConcurrency,
    String? xmuxMaxConnections,
    String? xmuxCMaxReuseTimes,
    String? xmuxHMaxRequestTimes,
    String? xmuxHMaxReusableSecs,
    int? xmuxHKeepAlivePeriod,
    bool? fragmentEnabled,
    String? fragmentPackets,
    String? fragmentLength,
    String? fragmentInterval,
    bool? noiseEnabled,
    String? noiseKind,
    String? noisePacket,
    String? noiseRandLength,
    String? noiseRandBytes,
    String? noiseDelay,
    String? noiseReset,
    bool? sniffingEnabled,
    bool? sniffingRouteOnly,
    bool? concurrentDial,
    String? dnsHosts,
    String? dnsPolicy,
  }) =>
      XrayCoreSettings(
        logLevel: logLevel ?? this.logLevel,
        routingDomainStrategy:
            routingDomainStrategy ?? this.routingDomainStrategy,
        dnsUseCustom: dnsUseCustom ?? this.dnsUseCustom,
        dnsServers: dnsServers ?? this.dnsServers,
        dnsQueryStrategy: dnsQueryStrategy ?? this.dnsQueryStrategy,
        dnsDisableCache: dnsDisableCache ?? this.dnsDisableCache,
        dnsSplitDirectDomains:
            dnsSplitDirectDomains ?? this.dnsSplitDirectDomains,
        muxEnabled: muxEnabled ?? this.muxEnabled,
        muxConcurrency: muxConcurrency ?? this.muxConcurrency,
        muxXudpConcurrency: muxXudpConcurrency ?? this.muxXudpConcurrency,
        muxXudpProxyUDP443: muxXudpProxyUDP443 ?? this.muxXudpProxyUDP443,
        xmuxEnabled: xmuxEnabled ?? this.xmuxEnabled,
        xmuxMaxConcurrency: xmuxMaxConcurrency ?? this.xmuxMaxConcurrency,
        xmuxMaxConnections: xmuxMaxConnections ?? this.xmuxMaxConnections,
        xmuxCMaxReuseTimes: xmuxCMaxReuseTimes ?? this.xmuxCMaxReuseTimes,
        xmuxHMaxRequestTimes:
            xmuxHMaxRequestTimes ?? this.xmuxHMaxRequestTimes,
        xmuxHMaxReusableSecs:
            xmuxHMaxReusableSecs ?? this.xmuxHMaxReusableSecs,
        xmuxHKeepAlivePeriod:
            xmuxHKeepAlivePeriod ?? this.xmuxHKeepAlivePeriod,
        fragmentEnabled: fragmentEnabled ?? this.fragmentEnabled,
        fragmentPackets: fragmentPackets ?? this.fragmentPackets,
        fragmentLength: fragmentLength ?? this.fragmentLength,
        fragmentInterval: fragmentInterval ?? this.fragmentInterval,
        noiseEnabled: noiseEnabled ?? this.noiseEnabled,
        noiseKind: noiseKind ?? this.noiseKind,
        noisePacket: noisePacket ?? this.noisePacket,
        noiseRandLength: noiseRandLength ?? this.noiseRandLength,
        noiseRandBytes: noiseRandBytes ?? this.noiseRandBytes,
        noiseDelay: noiseDelay ?? this.noiseDelay,
        noiseReset: noiseReset ?? this.noiseReset,
        sniffingEnabled: sniffingEnabled ?? this.sniffingEnabled,
        sniffingRouteOnly: sniffingRouteOnly ?? this.sniffingRouteOnly,
        concurrentDial: concurrentDial ?? this.concurrentDial,
        dnsHosts: dnsHosts ?? this.dnsHosts,
        dnsPolicy: dnsPolicy ?? this.dnsPolicy,
      );

  /// Разбор поля [dnsHosts]: «маска домена → чем её подменить».
  ///
  /// Ключ остаётся в синтаксисе приложения (`example.com`, `*.example.com`),
  /// переводит его каждый генератор сам: у ядер маски пишутся по-разному.
  /// [dropped] — строки, в которых нет пары «домен и адрес» или значение не
  /// годится ни в адрес, ни в имя. Их вызывающий пишет в лог: молча съеденная
  /// строка выглядит как «настройка не работает».
  static ({Map<String, List<String>> entries, List<String> dropped})
      parseDnsHosts(String raw) {
    final entries = <String, List<String>>{};
    final dropped = <String>[];
    for (final line in raw.split(RegExp(r'[\n;]+'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final parts = trimmed
          .split(RegExp(r'[\s:=]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (parts.length < 2) {
        dropped.add(trimmed);
        continue;
      }
      // Системный hosts пишется наоборот — «адрес домен», и человек, который
      // его знает, напишет так же. Определяем по тому, что слева: адрес там
      // может быть только в этой раскладке.
      final reversed = _isIpAddress(parts.first) && !_isIpAddress(parts[1]);
      final key = reversed ? parts[1] : parts.first;
      final rest = reversed
          ? [parts.first, ...parts.skip(2)]
          : parts.skip(1).toList();
      final values = <String>[];
      for (final chunk in rest) {
        values.addAll(
          chunk.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty),
        );
      }
      final domainKey = key.toLowerCase();
      if (values.isEmpty || !_isHostMask(domainKey)) {
        dropped.add(trimmed);
        continue;
      }
      // Либо адреса, либо один чужой домен: ядра берут «список IP» или
      // «имя, которое резолвить вместо этого», но не смесь.
      final allIps = values.every(_isIpAddress);
      final alias = values.length == 1 && _isHostMask(values.single);
      if (!allIps && !alias) {
        dropped.add(trimmed);
        continue;
      }
      entries[domainKey] = values;
    }
    return (entries: entries, dropped: dropped);
  }

  /// Разбор поля [dnsPolicy]: «маска домена → чем его резолвить».
  ///
  /// Ключ остаётся в синтаксисе приложения, адреса — в синтаксисе поля «свои
  /// DNS-серверы» и проверяются тем же [xrayDnsEntry]: адрес, который ядро не
  /// поднимет, тут так же бесполезен, как и в общем списке. Строки без пары
  /// или с негодными адресами уезжают в [dropped] — вызывающий пишет их в лог.
  static ({Map<String, List<String>> entries, List<String> dropped})
      parseDnsPolicy(String raw) {
    final entries = <String, List<String>>{};
    final dropped = <String>[];
    for (final line in raw.split(RegExp(r'[\n;]+'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      // По пробелу и знаку равенства, но НЕ по двоеточию: оно живёт внутри
      // адресов (`https://`, `:53`). Двоеточие после домена — привычная
      // запись, поэтому просто срезаем его с ключа.
      final parts = trimmed
          .split(RegExp(r'[\s=]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (parts.length < 2) {
        dropped.add(trimmed);
        continue;
      }
      var key = parts.first.toLowerCase();
      if (key.endsWith(':')) key = key.substring(0, key.length - 1);
      final servers = <String>[];
      for (final chunk in parts.skip(1)) {
        for (final value in chunk.split(',')) {
          final address = value.trim();
          if (address.isEmpty) continue;
          if (xrayDnsEntry(address) == null) continue;
          servers.add(address);
        }
      }
      if (!_isHostMask(key) || servers.isEmpty) {
        dropped.add(trimmed);
        continue;
      }
      entries[key] = servers;
    }
    return (entries: entries, dropped: dropped);
  }

  static bool _isIpAddress(String value) {
    final bare = value.startsWith('[') && value.endsWith(']')
        ? value.substring(1, value.length - 1)
        : value;
    return InternetAddress.tryParse(bare) != null;
  }

  /// Домен или маска `*.домен`: всё, что годится в ключ hosts.
  static bool _isHostMask(String value) {
    final bare = value.startsWith('*.') ? value.substring(2) : value;
    if (bare.isEmpty || bare.contains('/') || bare.contains(' ')) return false;
    return RegExp(r'^[a-z0-9_-]+(\.[a-z0-9_-]+)*$', caseSensitive: false)
        .hasMatch(bare);
  }

  static List<String> _parseServerLines(String raw) => raw
      .split(RegExp(r'[\n,;]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  /// Один DNS-адрес в виде, который xray действительно исполнит, или null —
  /// такой адрес ядро не поднимет, и его лучше выбросить.
  ///
  /// Поле `address` — не строка подключения: если в ней не узнаётся IP, xray
  /// считает её доменом и разбирает как URL. Отсюда три ловушки, и каждая
  /// оставляет пользователя без DNS. `[2606:4700:4700::1111]:53` как URL не
  /// разбирается вовсе, и ядро не стартует — порт у xray живёт отдельным полем,
  /// поэтому host и порт делим сами. `tls://`, `sdns://`, `dhcp://` ошибки не
  /// дают, но молча становятся доменом обычного UDP-резолвера, который никогда
  /// не отвечает, — такие выбрасываем. `quic://` приводим к `quic+local`:
  /// удалённого режима у DoQ в xray нет.
  static ({String address, int? port})? xrayDnsEntry(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();
    if (lower == 'localhost' || lower == 'fakedns') {
      return (address: lower, port: null);
    }

    final schemeMatch = RegExp(r'^([a-z][a-z0-9.+-]*)://').firstMatch(lower);
    if (schemeMatch != null) {
      final scheme = schemeMatch.group(1)!;
      final rest = trimmed.substring(schemeMatch.end);
      switch (scheme) {
        case 'https':
        case 'https+local':
        case 'h2c':
        case 'h2c+local':
        case 'tcp':
        case 'tcp+local':
        case 'quic+local':
          return (address: trimmed, port: null);
        case 'quic':
        case 'doq':
        case 'doq+local':
          return (address: 'quic+local://$rest', port: null);
        // Голый UDP: схему xray не знает, но она и не нужна — это его дефолт.
        case 'udp':
        case 'udp+local':
        case 'dns':
          return _hostPort(rest);
        default:
          return null;
      }
    }

    return _hostPort(trimmed);
  }

  /// `host` / `host:port` / `[v6]:port` / голый IPv6 → адрес и порт отдельно.
  static ({String address, int? port})? _hostPort(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final bracketed = RegExp(r'^\[([0-9a-fA-F:.]+)\](?::(\d+))?$').firstMatch(trimmed);
    if (bracketed != null) {
      final port = int.tryParse(bracketed.group(2) ?? '');
      return (address: bracketed.group(1)!, port: port);
    }
    // Ровно одно двоеточие с числовым портом — иначе это голый IPv6.
    final hostPort = RegExp(r'^([^:]+):(\d+)$').firstMatch(trimmed);
    if (hostPort != null) {
      return (address: hostPort.group(1)!, port: int.tryParse(hostPort.group(2)!));
    }
    return (address: trimmed, port: null);
  }

  /// DNS-адреса пользователя, приведённые под xray. Второй список — то, что
  /// выброшено: вызывающий пишет его в лог, чтобы «мой DNS не применился» имело
  /// объяснение.
  static ({List<Map<String, dynamic>> servers, List<String> dropped})
      xrayDnsServers(String raw) {
    final servers = <Map<String, dynamic>>[];
    final dropped = <String>[];
    for (final line in _parseServerLines(raw)) {
      final entry = xrayDnsEntry(line);
      if (entry == null) {
        dropped.add(line);
        continue;
      }
      servers.add({
        'address': entry.address,
        if (entry.port != null) 'port': entry.port,
      });
    }
    return (servers: servers, dropped: dropped);
  }

  /// Собирает блок `dns`.
  ///
  /// [bootstrapDomains] — адреса самих серверов (свой узел и звенья цепочки).
  /// Резолвить их через туннель нельзя: адрес нужен, чтобы до сервера
  /// дозвониться, и запрос через прокси замкнул бы круг. Поэтому у них своя
  /// запись со схемой `+local` — тот же DoH, но мимо роутинга.
  ///
  /// Системный резолвер стоит вторым, а не первым: открытый UDP-53 у части
  /// провайдеров подменяется, причём ответ приходит с подставленным адресом
  /// источника и в `dig` подмена не видна. Коннект от этого не ломался, но
  /// провайдеру уходил список узлов, к которым подключается пользователь.
  ///
  /// Перебор обрывает `finalQuery`, а не `skipFallback`: второй значит другое —
  /// «не брать этот сервер для чужих доменов» — и свалиться с записи на общий
  /// DoH не мешает, а тот при глобал-прокси ведёт в ещё не поднятый туннель.
  ///
  /// [proxiedDoh] — гнать ли DoH внутрь туннеля. Включаем при глобал-прокси:
  /// все запросы схлопываются в одно постоянное соединение до 1.1.1.1 вместо
  /// отдельного TCP на каждый. В режимах «остальное direct/block» оставляем
  /// прямой — там `final` увёл бы запрос мимо прокси или вовсе в blackhole.
  /// Маска домена из полей приложения в правило xray.
  ///
  /// Голый домен в списке `domains` у сервера ядро понимает как ПОДСТРОКУ
  /// (ParseDomainRules с Domain_Substr), то есть `example.com` поймал бы и
  /// `notexample.community`. Поэтому пишем явно: точное имя — `full:`, маска —
  /// `domain:` (домен и поддомены).
  static String xrayDomainRule(String mask) => mask.startsWith('*.')
      ? 'domain:${mask.substring(2)}'
      : 'full:$mask';

  /// Свои адреса для доменов в синтаксисе xray.
  ///
  /// Голый ключ ядро разбирает как ПОЛНОЕ совпадение (ParseDomainRule с
  /// Domain_Full), поэтому маска `*.example.com` переводится в `domain:`, а не
  /// остаётся звёздочкой: звёздочку ядро сочло бы частью имени.
  Map<String, dynamic> buildHostsMap() {
    final parsed = parseDnsHosts(dnsHosts).entries;
    return {
      for (final entry in parsed.entries)
        (entry.key.startsWith('*.')
                ? 'domain:${entry.key.substring(2)}'
                : entry.key):
            entry.value.length == 1 ? entry.value.single : entry.value,
    };
  }

  Map<String, dynamic> buildDnsBlock({
    required List<String> directDomains,
    List<String> bootstrapDomains = const [],
    bool proxiedDoh = false,
  }) {
    final servers = <Map<String, dynamic>>[];

    final dohScheme = proxiedDoh ? 'https' : 'https+local';

    // Пустой список после чистки (пользователь вписал только то, чего ядро не
    // исполняет) — не повод остаться без резолвера: уходим в ветку дефолта.
    final custom = dnsUseCustom
        ? xrayDnsServers(dnsServers).servers
        : const <Map<String, dynamic>>[];

    if (bootstrapDomains.isNotEmpty) {
      for (final server in _bootstrapResolvers(custom)) {
        servers.add({
          ...server,
          'domains': bootstrapDomains,
          'skipFallback': true,
        });
      }
      servers.add({
        'address': 'localhost',
        'domains': bootstrapDomains,
        'skipFallback': true,
        'finalQuery': true,
      });
    }

    // Резолвер для отдельных доменов — раньше общего списка: ядро идёт по
    // серверам сверху вниз, и «этот домен спрашивать только тут» работает,
    // только пока запись не перехватил кто-то выше. `skipFallback` держит
    // обещание до конца: отказ выбранного резолвера не уводит запрос в общий
    // список, иначе выбор был бы не выбором, а подсказкой.
    for (final policy in parseDnsPolicy(dnsPolicy).entries.entries) {
      final domains = [xrayDomainRule(policy.key)];
      for (final address in policy.value) {
        final entry = xrayDnsEntry(address);
        if (entry == null) continue;
        servers.add({
          'address': entry.address,
          if (entry.port != null) 'port': entry.port,
          'domains': domains,
          'skipFallback': true,
        });
      }
    }

    if (custom.isNotEmpty) {
      // `length > 1`, а не `isNotEmpty`: первая строка уходит под
      // Direct-домены со `skipFallback`, то есть общего резолва не касается.
      // Когда сервер в списке один, такой раскладке не остаётся резолвера
      // вообще — всё, чего нет в Direct-списке, не резолвится ничем, и это
      // выглядит как «прописал свой DNS, и интернет пропал». С одним сервером
      // сплит и не нужен: он и так отвечает на всё, включая Direct-домены.
      if (dnsSplitDirectDomains && directDomains.isNotEmpty && custom.length > 1) {
        servers.add({
          ...custom.first,
          'domains': directDomains,
          'skipFallback': true,
        });
        servers.addAll(custom.skip(1));
      } else {
        servers.addAll(custom);
      }
      // Единственному своему резолверу — вторая попытка тем же адресом.
      //
      // Резолверы ядро опрашивает по очереди, и когда он один, очередь
      // кончается на первой же неудаче: `record not found`, домен не
      // резолвится, приложение пробует само секунды через три. Неудача при
      // этом штатная и частая — DoH-соединение простаивает, дальний конец его
      // закрывает, и следующий запрос уезжает в мёртвое (`unexpected EOF`).
      // Само по себе ядро такой запрос не повторяет: DoH ходит методом POST, а
      // его Go на оборвавшемся соединении переотправлять не берётся.
      //
      // Вторая строка тем же адресом — это второй клиент ядра со своим пулом
      // соединений (одинаковые записи оно не схлопывает). На `EOF` у первого
      // очередь доходит до него, он дозванивается заново и отвечает. Ни
      // резолвер, ни путь до него не меняются — то есть ни приватность, ни
      // выбор пользователя это не трогает.
      //
      // Только когда сервер один: с двумя и больше проваливаться уже есть
      // куда. И только здесь, ПОСЛЕ развилки про сплит: попади дубль в неё,
      // первая строка ушла бы под Direct-домены со `skipFallback`, и для них
      // всё вернулось бы ровно к тому же тупику.
      if (custom.length == 1) servers.add(custom.single);
    } else {
      if (dnsSplitDirectDomains && directDomains.isNotEmpty) {
        servers.add({
          // 'localhost' — системный резолвер xray. Direct-домены включают
          // корпоративные/LAN-зоны сплит-DNS, которых публичный DoH не знает:
          // с ним домен из Direct-списка получал NXDOMAIN при direct-маршруте.
          'address': 'localhost',
          'domains': directDomains,
          'skipFallback': true,
        });
      }
      servers.add({'address': '$dohScheme://1.1.1.1/dns-query'});
      servers.add({'address': '$dohScheme://8.8.8.8/dns-query'});
      // Последним — системный резолвер, на случай сети, где DoH к 1.1.1.1 и
      // 8.8.8.8 просто не пускают. Через него теперь резолвится и адрес самого
      // сервера (streamSettings.sockopt.domainStrategy), так что «DoH не
      // прошёл» означало бы «подключения нет вообще». Спрашивается он только
      // когда оба DoH промолчали.
      servers.add({'address': 'localhost'});
    }

    if (servers.isEmpty) {
      servers.add({'address': 'https+local://1.1.1.1/dns-query'});
    }

    final hosts = buildHostsMap();
    return {
      // Раньше серверов: ядро смотрит hosts до опроса резолверов, и порядок
      // ключей тут только для читающего человека.
      if (hosts.isNotEmpty) 'hosts': hosts,
      'servers': [for (final server in servers) _withDnsLimits(server)],
      'queryStrategy': dnsQueryStrategy,
      if (dnsDisableCache) 'disableCache': true,
    };
  }

  /// Чем искать адрес самого сервера, в порядке опроса. Системный резолвер
  /// идёт после них и добавляется вызывающим.
  ///
  /// Не больше двух записей: каждый молчащий резолвер стоит [_dnsTimeoutMs], а
  /// этот список лежит на критическом пути к подключению. В сети, где DoH
  /// режут, цена платится не один раз при старте, а перед каждым коннектом с
  /// истёкшим TTL — поэтому по умолчанию тут один адрес, а не пара, как в
  /// общем списке.
  static List<Map<String, dynamic>> _bootstrapResolvers(
    List<Map<String, dynamic>> custom,
  ) {
    if (custom.isEmpty) {
      return [
        {'address': 'https+local://1.1.1.1/dns-query'},
      ];
    }
    final out = <Map<String, dynamic>>[];
    for (final server in custom) {
      final address = server['address'];
      if (address is! String) continue;
      final local = _forceLocalScheme(address);
      if (local == null) continue;
      out.add({...server, 'address': local});
      if (out.length == 2) break;
    }
    return out;
  }

  /// `https://` → `https+local://`: тот же резолвер, но запрос идёт напрямую, а
  /// не через outbound-цепочку.
  ///
  /// null — адрес, которым адрес сервера искать нельзя: `localhost` вызывающий
  /// добавляет сам последним, а `fakedns` вернул бы на него поддельный IP из
  /// fake-диапазона, и подключение ушло бы в никуда.
  static String? _forceLocalScheme(String address) {
    final lower = address.toLowerCase();
    if (lower == 'localhost' || lower == 'fakedns') return null;
    final scheme = RegExp(r'^([a-z][a-z0-9.+-]*)://').firstMatch(lower);
    // Голый хост — это UDP-резолвер, он и так опрашивается напрямую.
    if (scheme == null) return address;
    final name = scheme.group(1)!;
    if (name.endsWith('+local')) return address;
    return '$name+local://${address.substring(scheme.end)}';
  }

  /// Сколько ждать один резолвер и что делать, когда он молчит.
  ///
  /// Это лечение «интернет отвалился секунд на двадцать и вернулся сам».
  /// Резолверы xray опрашивает по очереди, таймаут у него по умолчанию 4 секунды
  /// на каждый, а в списке их до четырёх — один потерянный пакет к первому DoH
  /// стоит дюжины секунд ожидания. Всё это время новые соединения стоят: с
  /// `IPIfNonMatch` резолв нужен каждому до выбора маршрута. Отсюда и жалоба на
  /// «произвольную хуйню без периодичности» — зависит от того, когда истёк TTL и
  /// повезло ли пакету.
  ///
  /// [_dnsTimeoutMs] режет цену одного молчащего резолвера, `serveStale` — саму
  /// паузу: пока ядро идёт за свежим ответом, оно отдаёт просроченный из кэша.
  /// Оба поля на каждом сервере, потому что у xray они per-server.
  static Map<String, dynamic> _withDnsLimits(Map<String, dynamic> server) => {
        ...server,
        if (!server.containsKey('timeoutMs')) 'timeoutMs': _dnsTimeoutMs,
        if (!server.containsKey('serveStale')) 'serveStale': true,
      };

  /// 2.5 с: DoH через туннель укладывается в сотни миллисекунд даже на
  /// мобильной сети, а вчетверо больший дефолт ядра существует ради совсем
  /// плохих каналов — ценой той самой двадцатисекундной паузы.
  static const _dnsTimeoutMs = 2500;

  /// Один элемент для `finalmask.udp`, или `null` — шум выключен.
  ///
  /// Ключ у ядра пишется строчными (`finalmask`), хотя всё вокруг camelCase —
  /// в Go-структуре он `FinalMask`, а в json-теге строчный. Ошибка здесь не
  /// заметна ничем: неизвестный ключ xray молча выбрасывает, конфиг поднимается,
  /// а шума нет.
  ///
  /// `rand` и `packet` вместе ядро отвергает («len(item.Packet) > 0 &&
  /// item.Rand.To > 0»), поэтому [noiseKind] и выбирает одно из двух.
  Map<String, dynamic>? buildNoiseItem() {
    if (!noiseEnabled) return null;
    final item = <String, dynamic>{};
    if (noiseKind == noiseRandom) {
      item['rand'] = _parseRangeValue(
        _rangeOrFallback(noiseRandLength, defaultNoiseRandLength),
      );
      final bytes = noiseRandBytes.trim();
      if (RegExp(r'^\d+(-\d+)?$').hasMatch(bytes)) {
        item['randRange'] = _parseRangeValue(bytes);
      }
    } else {
      // Пустой пакет — это ни шум, ни ошибка: ядро отправит ноль байт. Молчать
      // тут хуже, чем откатиться на мусор, ради которого настройку и включали.
      final packet = noisePacket.trim();
      if (packet.isEmpty) {
        item['rand'] = _parseRangeValue(defaultNoiseRandLength);
      } else {
        item['type'] = noiseKind;
        item['packet'] = packet;
      }
    }
    final delay = noiseDelay.trim();
    if (RegExp(r'^\d+(-\d+)?$').hasMatch(delay)) {
      item['delay'] = _parseRangeValue(delay);
    }
    return {
      'type': 'noise',
      'settings': {
        if (RegExp(r'^\d+(-\d+)?$').hasMatch(noiseReset.trim()))
          'reset': _parseRangeValue(noiseReset.trim()),
        'noise': [item],
      },
    };
  }

  static String _rangeOrFallback(String raw, String fallback) {
    final v = raw.trim();
    return RegExp(r'^\d+(-\d+)?$').hasMatch(v) ? v : fallback;
  }

  /// `mux` для аутбаунда, или `null` — тогда ключа в конфиге нет вовсе.
  ///
  /// Значения подрезаны по границам ядра (`docs/config/outbound.md`), а режим
  /// UDP/443 — по списку: незнакомая строка там роняет разбор всего конфига,
  /// а не отключает мультиплексор.
  Map<String, dynamic>? buildMuxMap() {
    if (!muxEnabled) return null;
    return {
      'enabled': true,
      'concurrency': muxConcurrency.clamp(-1, 128),
      'xudpConcurrency': muxXudpConcurrency.clamp(-1, 1024),
      'xudpProxyUDP443': muxUdp443Modes.contains(muxXudpProxyUDP443)
          ? muxXudpProxyUDP443
          : muxUdp443Reject,
    };
  }

  /// XMUX block for XHTTP `extra` (client-only).
  Map<String, dynamic>? buildXmuxMap() {
    if (!xmuxEnabled) return null;
    final map = <String, dynamic>{};
    void range(String key, String raw) {
      final v = raw.trim();
      if (v.isNotEmpty) map[key] = _parseRangeValue(v);
    }

    range('maxConcurrency', xmuxMaxConcurrency);
    range('maxConnections', xmuxMaxConnections);
    range('cMaxReuseTimes', xmuxCMaxReuseTimes);
    range('hMaxRequestTimes', xmuxHMaxRequestTimes);
    range('hMaxReusableSecs', xmuxHMaxReusableSecs);
    if (xmuxHKeepAlivePeriod > 0) {
      map['hKeepAlivePeriod'] = xmuxHKeepAlivePeriod;
    }
    return map.isEmpty ? <String, dynamic>{} : map;
  }

  static Object _parseRangeValue(String v) {
    if (RegExp(r'^\d+$').hasMatch(v)) return int.parse(v);
    return v;
  }

  /// `settings.fragment` для freedom-аутбаунда, или `null` — фрагментация
  /// выключена и аутбаунд заводить не нужно.
  ///
  /// `length` и `interval` ядру нужны оба: freedom с одним лишь `packets`
  /// не поднимается, поэтому пустое или кривое поле подменяется дефолтом, а
  /// не выбрасывается. Цена ошибки тут несимметричная — пустая строка в
  /// настройках стоила бы не «фрагментация без длины», а неработающего
  /// подключения с невнятной ошибкой порта.
  Map<String, dynamic>? buildFragmentMap() {
    if (!fragmentEnabled) return null;
    final packets = fragmentPackets.trim();
    return {
      'packets': fragmentPacketModes.contains(packets)
          ? packets
          : fragmentPacketsTlsHello,
      'length': _fragmentRange(fragmentLength, defaultFragmentLength),
      'interval': _fragmentRange(fragmentInterval, defaultFragmentInterval),
    };
  }

  /// Число или диапазон `N-M`; всё остальное — [fallback]. Пустой верхней
  /// границы (`100-`) ядро не прощает, поэтому регексп строгий с обеих сторон.
  static Object _fragmentRange(String raw, String fallback) {
    final v = raw.trim();
    return _parseRangeValue(
      RegExp(r'^\d+(-\d+)?$').hasMatch(v) ? v : fallback,
    );
  }

  Map<String, dynamic> buildSniffing() => {
        'enabled': sniffingEnabled,
        'destOverride': ['http', 'tls', 'quic'],
        'routeOnly': sniffingRouteOnly,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is XrayCoreSettings &&
          runtimeType == other.runtimeType &&
          logLevel == other.logLevel &&
          routingDomainStrategy == other.routingDomainStrategy &&
          dnsUseCustom == other.dnsUseCustom &&
          dnsServers == other.dnsServers &&
          dnsQueryStrategy == other.dnsQueryStrategy &&
          dnsDisableCache == other.dnsDisableCache &&
          dnsSplitDirectDomains == other.dnsSplitDirectDomains &&
          muxEnabled == other.muxEnabled &&
          muxConcurrency == other.muxConcurrency &&
          muxXudpConcurrency == other.muxXudpConcurrency &&
          muxXudpProxyUDP443 == other.muxXudpProxyUDP443 &&
          xmuxEnabled == other.xmuxEnabled &&
          xmuxMaxConcurrency == other.xmuxMaxConcurrency &&
          xmuxMaxConnections == other.xmuxMaxConnections &&
          xmuxCMaxReuseTimes == other.xmuxCMaxReuseTimes &&
          xmuxHMaxRequestTimes == other.xmuxHMaxRequestTimes &&
          xmuxHMaxReusableSecs == other.xmuxHMaxReusableSecs &&
          xmuxHKeepAlivePeriod == other.xmuxHKeepAlivePeriod &&
          fragmentEnabled == other.fragmentEnabled &&
          fragmentPackets == other.fragmentPackets &&
          fragmentLength == other.fragmentLength &&
          fragmentInterval == other.fragmentInterval &&
          noiseEnabled == other.noiseEnabled &&
          noiseKind == other.noiseKind &&
          noisePacket == other.noisePacket &&
          noiseRandLength == other.noiseRandLength &&
          noiseRandBytes == other.noiseRandBytes &&
          noiseDelay == other.noiseDelay &&
          noiseReset == other.noiseReset &&
          sniffingEnabled == other.sniffingEnabled &&
          sniffingRouteOnly == other.sniffingRouteOnly &&
          concurrentDial == other.concurrentDial &&
          dnsHosts == other.dnsHosts &&
          dnsPolicy == other.dnsPolicy;

  @override
  // hashAll, а не hash: у последнего потолок в двадцать аргументов, а полей
  // здесь больше.
  int get hashCode => Object.hashAll([
        logLevel,
        routingDomainStrategy,
        dnsUseCustom,
        dnsServers,
        dnsQueryStrategy,
        dnsDisableCache,
        dnsSplitDirectDomains,
        muxEnabled,
        muxConcurrency,
        muxXudpConcurrency,
        muxXudpProxyUDP443,
        xmuxEnabled,
        xmuxMaxConcurrency,
        xmuxMaxConnections,
        xmuxCMaxReuseTimes,
        xmuxHMaxRequestTimes,
        xmuxHMaxReusableSecs,
        xmuxHKeepAlivePeriod,
        fragmentEnabled,
        fragmentPackets,
        fragmentLength,
        fragmentInterval,
        noiseEnabled,
        noiseKind,
        noisePacket,
        noiseRandLength,
        noiseRandBytes,
        noiseDelay,
        noiseReset,
        sniffingEnabled,
        sniffingRouteOnly,
        concurrentDial,
        dnsHosts,
        dnsPolicy,
      ]);

  String toJsonString() => jsonEncode(toJson());

  factory XrayCoreSettings.fromJsonString(String s) =>
      XrayCoreSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
