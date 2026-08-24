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
  /// Единственный формат, который умеют оба ядра: генераторы переводят его и в
  /// конфиг xray, и в конфиг mihomo.
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

/// Почему выбранное пользователем ядро НЕ исполняет конкретный сервер.
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
  r'^(vless|vmess|trojan|ss|ssr|hysteria|hysteria2|hy2)://',
  caseSensitive: false,
);

/// Ядра, способные исполнить этот формат, независимо от платформы.
Set<VpnBackend> backendsForFormat(ServerFormat format) => switch (format) {
      ServerFormat.link => const {VpnBackend.xray, VpnBackend.mihomo},
      ServerFormat.xrayJson || ServerFormat.chain => const {VpnBackend.xray},
      ServerFormat.clashYaml => const {VpnBackend.mihomo},
      ServerFormat.amneziaWg => const {VpnBackend.awg},
      ServerFormat.unknown => const {VpnBackend.xray},
    };

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
  final capable = backendsForFormat(format);

  // Формат, который умеет ровно одно ядро: выбор пользователя тут ничего не
  // решает — либо это ядро, либо сервер не поедет вовсе.
  if (capable.length == 1) {
    final only = capable.single;
    if (only == VpnBackend.mihomo && !mihomoAvailable) {
      return (backend: only, format: format, skip: VpnCoreSkip.platform);
    }
    final skip = switch (preference) {
      'mihomo' when only != VpnBackend.mihomo => _skipFor(format),
      'xray' when only != VpnBackend.xray => _skipFor(format),
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

VpnCoreSkip _skipFor(ServerFormat format) => switch (format) {
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
      VpnCoreSkip.platform => 'that core does not ship on this platform',
    };
