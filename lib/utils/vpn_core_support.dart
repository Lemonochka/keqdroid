import 'dart:convert';
import 'dart:io';

import '../tunnel/vpn_backend.dart';
import 'awg_profile.dart';
import 'custom_clash_config.dart';
import 'custom_xray_config.dart';
import 'proxy_chain.dart';

/// В каком виде записан сервер. От формата зависит, какое ядро вообще способно
/// его исполнить, — а не только то, как его показать в списке.
enum ServerFormat {
  /// Обычная ссылка (`vless://`, `vmess://`, `trojan://`, `ss://`, `hy2://`…).
  /// Обычно её умеют оба ядра, но не всякую: что именно ссылка несёт, решает
  /// [backendsForLink].
  link,

  /// Готовый конфиг xray из подписки: аутбаунды, роутинг и dns авторские и
  /// описаны в терминах xray. Переводить их в другое ядро нечем.
  xrayJson,

  /// Готовый конфиг Clash/mihomo: `proxies`, `proxy-groups`, `rules`.
  clashYaml,

  /// Цепочка серверов: узлы связаны `dialerProxy` xray.
  chain,

  /// Профиль AmneziaWG (`[Interface]`/`[Peer]`).
  amneziaWg,

  /// Ни на что не похоже — сервер в списке видно, подключиться нельзя.
  unknown,
}

/// Почему выбранное пользователем ядро не исполняет конкретный сервер.
///
/// Выбор ядра — настройка, а исполняет сервер всегда то ядро, которое понимает
/// его формат. Раньше несовпадение молча откатывалось на xray: в настройках
/// стоял mihomo, в сессии шёл libxray, и понять почему было неоткуда (жалоба
/// «включил михомо — пишет, что активное ядро xray»). Причина считается здесь
/// один раз и используется и на пути подключения, и в панели «О приложении».
enum VpnCoreSkip {
  /// Готовый xray-конфиг: только xray.
  customConfig,

  /// Цепочка: только xray.
  chain,

  /// AmneziaWG: только своё ядро.
  amneziaWg,

  /// Готовый clash-конфиг: только mihomo.
  clashConfig,

  /// Ссылку берёт только xray: транспорт, которого у mihomo нет в этом
  /// протоколе.
  linkXrayOnly,

  /// Ссылку берёт только mihomo: xray такого не умеет вовсе.
  linkMihomoOnly,

  /// Ядра нет на этой платформе. Сейчас недостижимо — mihomo поставляется всюду
  /// (см. [mihomoShipsHere]), — но причина остаётся: молчаливый откат на другое
  /// ядро запрещён, и новая платформа без него обязана сказать об этом вслух.
  platform,
}

/// Поставляется ли mihomo на этой платформе.
///
/// Сейчас — на всех трёх, что умеет приложение: `libmihomo.so` в APK,
/// `mihomo.exe`/`mihomo` рядом с десктопным бинарём. Функция осталась ради
/// одного места правды: раньше «только Android» было записано в трёх файлах
/// подряд, и снятие ограничения означало найти их все.
bool get mihomoShipsHere =>
    Platform.isAndroid || Platform.isWindows || Platform.isLinux;

/// Формат сервера по его конфигу. Порядок проверок — от дешёвых и однозначных
/// к разбору.
ServerFormat detectServerFormat(String config) {
  final trimmed = config.trim();
  if (trimmed.isEmpty) return ServerFormat.unknown;
  if (ProxyChainConfig.looksLikeChain(trimmed)) return ServerFormat.chain;
  if (AwgProfile.isAwgConfig(trimmed)) return ServerFormat.amneziaWg;
  if (_linkScheme.hasMatch(trimmed)) return ServerFormat.link;
  // Clash — раньше xray: json-конфиг Clash тоже начинается с `{`, но у него
  // `proxies`, а не `outbounds`, и разбор xray-парсером его не возьмёт.
  if (CustomClashConfig.looksLikeClash(trimmed) &&
      CustomClashConfig.tryParse(trimmed) != null) {
    return ServerFormat.clashYaml;
  }
  if (CustomXrayConfig.looksLikeJson(trimmed) &&
      CustomXrayConfig.tryParse(trimmed) != null) {
    return ServerFormat.xrayJson;
  }
  return ServerFormat.unknown;
}

final _linkScheme = RegExp(
  r'^(vless|vmess|trojan|ss|ssr|hysteria|hysteria2|hy2|tuic|anytls|mierus)://',
  caseSensitive: false,
);

/// Ядра, способные исполнить этот формат, независимо от платформы.
///
/// Про ссылку тут сказано только «обычно оба»; какую именно ссылку кто берёт —
/// [backendsForLink].
Set<VpnBackend> backendsForFormat(ServerFormat format) => switch (format) {
      ServerFormat.link => const {VpnBackend.xray, VpnBackend.mihomo},
      ServerFormat.xrayJson || ServerFormat.chain => const {VpnBackend.xray},
      ServerFormat.clashYaml => const {VpnBackend.mihomo},
      ServerFormat.amneziaWg => const {VpnBackend.awg},
      ServerFormat.unknown => const {VpnBackend.xray},
    };

const _bothCores = {VpnBackend.xray, VpnBackend.mihomo};

/// Схемы, которые исполняет только mihomo: у xray таких аутбаундов нет.
const _mihomoOnlySchemes = {'tuic', 'anytls', 'ssr', 'mierus'};

/// Какие ядра берут именно эту ссылку.
///
/// «Ссылку умеют оба» было неправдой и до этой проверки. Оба ядра молча
/// пропускают незнакомый ключ, поэтому конфиг собирается, ядро поднимается,
/// подключение якобы есть — а трафик идёт не тем транспортом, каким просил
/// сервер, и тот не отвечает. Так mihomo с `network: xhttp` у VMess уходит в
/// свою ветку `default` и говорит с сервером голым TCP поверх TLS
/// (`adapter/outbound/vmess.go`), а xray на транспорте h2 роняет весь конфиг:
/// он его снёс, и `TransportProtocol.Build` отвечает отказом.
///
/// Разбирается только то, от чего зависит ответ: схема, транспорт, плагин
/// shadowsocks и маски finalmask. Ссылка, которую не удалось прочесть, — «оба»: решать про неё
/// не нам, дальше её всё равно развернёт генератор со своим сообщением.
Set<VpnBackend> backendsForLink(String link) {
  final trimmed = link.trim();
  final scheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*)://')
      .firstMatch(trimmed)
      ?.group(1)
      ?.toLowerCase();
  if (scheme == null) return _bothCores;

  // Протоколы, которых у xray нет вовсе: своего аутбаунда под них в ядре не
  // заведено, и никакой транспорт этого не меняет.
  if (_mihomoOnlySchemes.contains(scheme)) return const {VpnBackend.mihomo};

  if (scheme == 'vmess') return _vmessBackends(trimmed);

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return _bothCores;
  String param(String key) =>
      (uri.queryParameters[key] ?? '').trim().toLowerCase();

  // Плагины shadowsocks (`obfs-local`, `v2ray-plugin`) есть только у mihomo:
  // у xray в shadowsocks нет даже поля под них (`infra/conf/shadowsocks.go` —
  // только method и password), и сервер с плагином ждёт обёртки, которой не
  // будет.
  if (scheme == 'ss' && param('plugin').isNotEmpty) {
    return const {VpnBackend.mihomo};
  }

  // UDP внутри TCP — тоже только mihomo (`udp-over-tcp` у `ShadowSocksOption`);
  // у xray в shadowsocks такого поля нет.
  if (scheme == 'ss' &&
      (param('uot') == '1' ||
          param('uot') == 'true' ||
          param('udp-over-tcp') == 'true' ||
          param('udp-over-tcp') == '1')) {
    return const {VpnBackend.mihomo};
  }

  // Маски finalmask (`fm`, так их отдаёт 3X-UI) есть только у xray: у mihomo
  // их нет вовсе, и без них сервер получает пакеты не той формы.
  if ((scheme == 'vless' || scheme == 'trojan') && param('fm').isNotEmpty) {
    return const {VpnBackend.xray};
  }

  return _transportBackends(scheme, param('type'), param('headerType'));
}

/// vmess прячет транспорт в base64-json, а не в запросе.
Set<VpnBackend> _vmessBackends(String link) {
  try {
    var payload = link.substring('vmess://'.length).trim();
    payload = payload.replaceAll('-', '+').replaceAll('_', '/');
    final decoded = jsonDecode(utf8.decode(base64.decode(
      base64.normalize(payload),
    )));
    if (decoded is! Map) return _bothCores;
    if ((decoded['fm']?.toString() ?? '').trim().isNotEmpty) {
      return const {VpnBackend.xray};
    }
    return _transportBackends(
      'vmess',
      decoded['net']?.toString().trim().toLowerCase() ?? '',
      // `type` в json vmess — это заголовок маскировки, а не транспорт.
      decoded['type']?.toString().trim().toLowerCase() ?? '',
    );
  } catch (_) {
    return _bothCores;
  }
}

/// Кто берёт этот транспорт у этого протокола.
///
/// Сверено по `adapter/outbound/*.go` mihomo 1.19.30 и `infra/conf` xray
/// 26.7.28: у ядра либо есть поле под настройки транспорта, либо нет, и
/// «нет» означает молчаливый откат на голый TCP.
Set<VpnBackend> _transportBackends(
  String scheme,
  String type,
  String headerType,
) {
  // Маскировка под HTTP поверх tcp: `http-opts` есть у VLESS и VMess, у
  // `TrojanOption` их нет вовсе.
  if (scheme == 'trojan' &&
      headerType == 'http' &&
      (type.isEmpty || type == 'tcp' || type == 'raw')) {
    return const {VpnBackend.xray};
  }
  return switch ((scheme, type)) {
      // xray 26 снёс транспорт HTTP/2 целиком: `TransportProtocol.Build`
      // отвечает отказом и роняет весь конфиг, снаружи это «SOCKS port not
      // ready». У mihomo он остался — `h2-opts` есть и у VLESS, и у VMess.
      // Trojan сюда не попадает: у `TrojanOption` полей h2 нет, и такую ссылку
      // не берёт вообще никто — решать это отдельно, молча слать её к mihomo
      // было бы хуже, чем оставить как есть.
      ('vless' || 'vmess', 'http' || 'h2') => const {VpnBackend.mihomo},
      // mKCP: у `VlessOption` и `TrojanOption` нет `mkcp-opts` вовсе, у
      // `VmessOption` есть, но наш генератор его не собирает.
      (_, 'kcp' || 'mkcp') => const {VpnBackend.xray},
      // xhttp у mihomo заведён только для VLESS.
      ('vmess' || 'trojan', 'xhttp' || 'splithttp') => const {VpnBackend.xray},
      _ => _bothCores,
    };
}

/// Итог выбора: чем сервер поедет и почему это не то, что просил пользователь.
typedef VpnBackendChoice = ({
  VpnBackend backend,
  ServerFormat format,
  VpnCoreSkip? skip,
});

/// Какое ядро исполнит сервер.
///
/// [preference] — `AppSettings.vpnCore`: `auto`, `xray` или `mihomo`. Выбор
/// значим ровно для одного формата — обычной ссылки; всё остальное умеет
/// ровно одно ядро, и просить у него другое бессмысленно. [skip] непустой,
/// когда пользователь просил ядро, которое этот сервер не берёт: причину видно
/// в логе и в панели, молчаливого отката больше нет.
///
/// [mihomoAvailable] — поставляется ли mihomo на этой платформе.
VpnBackendChoice resolveVpnBackend({
  required String config,
  required String preference,
  required bool mihomoAvailable,
}) {
  final format = detectServerFormat(config);
  final capable = format == ServerFormat.link
      ? backendsForLink(config)
      : backendsForFormat(format);

  // Формат, который умеет ровно одно ядро: выбор пользователя тут ничего не
  // решает — либо это ядро, либо сервер не поедет вовсе.
  if (capable.length == 1) {
    final only = capable.single;
    if (only == VpnBackend.mihomo && !mihomoAvailable) {
      return (backend: only, format: format, skip: VpnCoreSkip.platform);
    }
    final skip = switch (preference) {
      'mihomo' when only != VpnBackend.mihomo => _skipFor(format, only),
      'xray' when only != VpnBackend.xray => _skipFor(format, only),
      _ => null,
    };
    return (backend: only, format: format, skip: skip);
  }

  // Ссылку берут оба. `auto` — xray: он исполняет любой формат, и на нём
  // отлажен путь по умолчанию.
  final wantsMihomo = preference == 'mihomo';
  if (wantsMihomo && !mihomoAvailable) {
    return (
      backend: VpnBackend.xray,
      format: format,
      skip: VpnCoreSkip.platform,
    );
  }
  return (
    backend: wantsMihomo ? VpnBackend.mihomo : VpnBackend.xray,
    format: format,
    skip: null,
  );
}

VpnCoreSkip _skipFor(ServerFormat format, VpnBackend only) => switch (format) {
      ServerFormat.link => only == VpnBackend.xray
          ? VpnCoreSkip.linkXrayOnly
          : VpnCoreSkip.linkMihomoOnly,
      ServerFormat.xrayJson => VpnCoreSkip.customConfig,
      ServerFormat.chain => VpnCoreSkip.chain,
      ServerFormat.clashYaml => VpnCoreSkip.clashConfig,
      ServerFormat.amneziaWg => VpnCoreSkip.amneziaWg,
      _ => VpnCoreSkip.customConfig,
    };

/// Строка для лога (не для UI — тот берёт локализованный текст).
String vpnCoreSkipLogReason(VpnCoreSkip skip) => switch (skip) {
      VpnCoreSkip.customConfig => 'the server is a ready-made Xray JSON config',
      VpnCoreSkip.chain => 'the server is a proxy chain',
      VpnCoreSkip.amneziaWg => 'the server is an AmneziaWG profile',
      VpnCoreSkip.clashConfig => 'the server is a ready-made Clash config',
      VpnCoreSkip.linkXrayOnly => 'mihomo has no such transport for this '
          'protocol',
      VpnCoreSkip.linkMihomoOnly => 'Xray 26 does not support this link',
      VpnCoreSkip.platform => 'that core does not ship on this platform',
    };
