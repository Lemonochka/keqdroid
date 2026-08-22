import '../tunnel/connection_mode.dart';
import '../tunnel/tunnel_state.dart';

/// Техническая начинка приложения: что за ядра стоят, какие geo-базы, что
/// происходит в текущей сессии и на чём всё это запущено.
///
/// Смысл в том, чтобы на вопрос «а какой у тебя xray?» отвечал сам клиент, а не
/// раскопки в логах: версии ядер читаются из самих бинарей ([GoBuildInfo]),
/// остальное — из настроек и состояния сессии.
class AppInternals {
  const AppInternals({
    required this.cores,
    required this.geoBases,
    required this.session,
    required this.build,
  });

  final List<CoreInfo> cores;
  final List<GeoBaseInfo> geoBases;
  final SessionInfo session;
  final BuildInfo build;
}

/// За что отвечает ядро. Текст подписи живёт в локализации, здесь — только роль.
enum CoreRole {
  /// Единый бинарь: и протоколы, и TUN (keqrnel на десктопе).
  core,

  /// Только протоколы и локальный SOCKS/HTTP (libxray на Android).
  proxy,

  /// Владеет TUN-устройством (tun2socks на Android).
  tun,

  /// AmneziaWG.
  amneziawg,
}

/// Ядро — поставляемый с приложением Go-бинарь.
class CoreInfo {
  const CoreInfo({
    required this.name,
    required this.role,
    this.version,
    this.goVersion,
    this.path,
    this.sizeBytes,
    this.modified,
    this.engines = const {},
    this.missing = false,
  });

  /// Отсутствующий бинарь — не ошибка: wireproxy нужен только для AmneziaWG,
  /// а на Android нет ни keqrnel, ни wireproxy вовсе.
  const CoreInfo.missing({required this.name, required this.role})
      : version = null,
        goVersion = null,
        path = null,
        sizeBytes = null,
        modified = null,
        engines = const {},
        missing = true;

  /// Имя файла ядра: `keqrnel.exe`, `libxray.so`.
  final String name;

  final CoreRole role;

  /// Собственная версия ядра. Null — бинарь собран из рабочего дерева
  /// (`(devel)`), как keqrnel: тогда о нём говорят только [engines].
  final String? version;

  /// Версия тулчейна Go, которым собран бинарь.
  final String? goVersion;

  final String? path;
  final int? sizeBytes;
  final DateTime? modified;

  /// Движки, вкомпилированные внутрь: `xray-core` → `v1.26…`.
  /// У keqrnel это единственный источник версий xray и sing-box.
  final Map<String, String> engines;

  final bool missing;
}

/// Поставляемая база geoip/geosite.
class GeoBaseInfo {
  const GeoBaseInfo({
    required this.name,
    required this.codeCount,
    this.sizeBytes,
    this.modified,
    this.missing = false,
  });

  final String name;

  /// Сколько кодов верхнего уровня реально лежит в базе — то же число, по
  /// которому проверяются правила маршрутизации перед стартом ядра.
  final int codeCount;

  final int? sizeBytes;
  final DateTime? modified;
  final bool missing;
}

/// Что происходит прямо сейчас.
class SessionInfo {
  const SessionInfo({
    required this.status,
    required this.engine,
    required this.socksPort,
    required this.httpPort,
    this.mode,
    this.uptime,
    this.corePids = const {},
    this.elevated,
    this.clashApiPort,
  });

  final VpnStatus status;

  /// Движок сессии: `keqrnel` на десктопе, `libxray` или `libmihomo` на
  /// Android — смотря чем подключились, а не что выбрано в настройках сейчас.
  final String engine;

  /// Null — режим не применим (Android всегда TUN через VpnService).
  final ConnectionMode? mode;

  final int socksPort;
  final int httpPort;
  final Duration? uptime;

  /// Подпись процесса → pid. Пусто — сессии нет.
  final Map<String, int> corePids;

  /// Windows/Linux: запущено ли приложение с правами администратора.
  /// Null — платформа без такого понятия либо выяснить не удалось.
  final bool? elevated;

  final int? clashApiPort;

  bool get isActive =>
      status == VpnStatus.connected || status == VpnStatus.connecting;
}

/// Приложение и устройство.
class BuildInfo {
  const BuildInfo({
    required this.appVersion,
    required this.buildNumber,
    required this.packageName,
    required this.operatingSystem,
    required this.osVersion,
    required this.abi,
    required this.dartVersion,
    required this.releaseMode,
  });

  final String appVersion;
  final String buildNumber;
  final String packageName;
  final String operatingSystem;
  final String osVersion;

  /// Архитектура: `android-arm64`, `windows-x64`.
  final String abi;

  /// Только номер, без длинной строки с датой сборки SDK.
  final String dartVersion;

  final bool releaseMode;
}
