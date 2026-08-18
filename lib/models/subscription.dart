import 'package:uuid/uuid.dart';

/// Чем клиент представляется панели при загрузке ОДНОЙ подписки.
///
/// Панели с привязкой по HWID считают устройства по заголовкам запроса
/// (`x-hwid`, `x-device-os`, `x-device-model`, `x-ver-os`) и по User-Agent.
/// Здесь эти значения задаются на подписку, а не на приложение: у разных
/// провайдеров разные требования, и общий на всех HWID означал бы, что ради
/// одной подписки придётся ломать привязку остальных.
///
/// Пустое поле = «как у приложения»: подставится настоящее значение устройства.
class SubscriptionFetchIdentity {
  /// Подмена включена. Отдельно от заполненности полей: выключить её, не
  /// потеряв набранные значения, — обычное дело при отладке привязки.
  final bool enabled;

  final String? hwid;
  final String? userAgent;
  final String? deviceModel;
  final String? deviceOs;
  final String? osVersion;

  const SubscriptionFetchIdentity({
    this.enabled = false,
    this.hwid,
    this.userAgent,
    this.deviceModel,
    this.deviceOs,
    this.osVersion,
  });

  static const empty = SubscriptionFetchIdentity();

  factory SubscriptionFetchIdentity.fromJson(Map<String, dynamic>? json) {
    if (json == null) return empty;
    return SubscriptionFetchIdentity(
      enabled: json['enabled'] as bool? ?? false,
      hwid: _trimOrNull(json['hwid'] as String?),
      userAgent: _trimOrNull(json['userAgent'] as String?),
      deviceModel: _trimOrNull(json['deviceModel'] as String?),
      deviceOs: _trimOrNull(json['deviceOs'] as String?),
      osVersion: _trimOrNull(json['osVersion'] as String?),
    );
  }

  static String? _trimOrNull(String? v) {
    final t = v?.trim();
    return t == null || t.isEmpty ? null : t;
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        if (hwid != null) 'hwid': hwid,
        if (userAgent != null) 'userAgent': userAgent,
        if (deviceModel != null) 'deviceModel': deviceModel,
        if (deviceOs != null) 'deviceOs': deviceOs,
        if (osVersion != null) 'osVersion': osVersion,
      };

  /// Значения, которые реально уходят в запрос. Выключенная подмена не даёт
  /// ничего, даже если поля заполнены.
  String? get activeHwid => enabled ? hwid : null;
  String? get activeUserAgent => enabled ? userAgent : null;
  String? get activeDeviceOs => enabled ? deviceOs : null;
  String? get activeDeviceModel => enabled ? deviceModel : null;
  String? get activeOsVersion => enabled ? osVersion : null;

  bool get hasCustomFields =>
      hwid != null ||
      userAgent != null ||
      deviceModel != null ||
      deviceOs != null ||
      osVersion != null;

  /// Подмена включена, но ни одно поле не задано — запрос уйдёт обычным.
  bool get isActive => enabled && hasCustomFields;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubscriptionFetchIdentity &&
          enabled == other.enabled &&
          hwid == other.hwid &&
          userAgent == other.userAgent &&
          deviceModel == other.deviceModel &&
          deviceOs == other.deviceOs &&
          osVersion == other.osVersion;

  @override
  int get hashCode =>
      Object.hash(enabled, hwid, userAgent, deviceModel, deviceOs, osVersion);
}

class Subscription {
  final String id;
  final String name;
  final String url;
  final DateTime? lastUpdatedAt;
  final int? usedBytes;
  final int? totalBytes;
  final DateTime? expiresAt;
  final bool autoUpdate;
  final int serverCount;
  final int updateIntervalHours; // свой интервал авто-обновления
  final String? userAgent; // User-Agent, под которым панель отдала payload

  /// Имя сервиса, как его называет сама панель (заголовок `profile-title`).
  ///
  /// Храним отдельно от [name] даже когда оно же и подставлено: если
  /// пользовательница дала подписке своё имя, карточка всё равно может
  /// показать, чей это сервис на самом деле.
  final String? providerTitle;

  /// Объявление провайдера (`announce`) — техработы, смена адреса и подобное.
  final String? announce;

  /// Ссылки на поддержку (`support-url`) и на страницу подписки
  /// (`profile-web-page-url`).
  final String? supportUrl;
  final String? webPageUrl;

  /// Имя подставлено автоматически, а не введено руками.
  ///
  /// Отличать это обязательно: авто-имя можно молча заменить на название от
  /// провайдера, а введённое пользовательницей — нельзя ни при каких условиях.
  final bool nameIsAuto;

  /// Чем клиент представляется этой панели: HWID, User-Agent, device-заголовки.
  final SubscriptionFetchIdentity fetchIdentity;

  const Subscription({
    required this.id,
    required this.name,
    required this.url,
    this.lastUpdatedAt,
    this.usedBytes,
    this.totalBytes,
    this.expiresAt,
    this.autoUpdate = true,
    this.serverCount = 0,
    this.updateIntervalHours = 12,
    this.userAgent,
    this.providerTitle,
    this.announce,
    this.supportUrl,
    this.webPageUrl,
    this.nameIsAuto = false,
    this.fetchIdentity = SubscriptionFetchIdentity.empty,
  });

  factory Subscription.create({
    required String name,
    required String url,
    bool nameIsAuto = false,
    SubscriptionFetchIdentity fetchIdentity = SubscriptionFetchIdentity.empty,
  }) =>
      Subscription(
        id: const Uuid().v4(),
        name: name,
        url: url,
        nameIsAuto: nameIsAuto,
        fetchIdentity: fetchIdentity,
      );

  factory Subscription.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String;
    final url = json['url'] as String;
    return Subscription(
    id: json['id'] as String,
    name: name,
    url: url,
    lastUpdatedAt: json['lastUpdatedAt'] != null
        ? DateTime.tryParse(json['lastUpdatedAt'] as String)
        : null,
    usedBytes: json['usedBytes'] as int?,
    totalBytes: json['totalBytes'] as int?,
    expiresAt: json['expiresAt'] != null
        ? DateTime.tryParse(json['expiresAt'] as String)
        : null,
    autoUpdate: json['autoUpdate'] as bool? ?? true,
    serverCount: json['serverCount'] as int? ?? 0,
    updateIntervalHours: json['updateIntervalHours'] as int? ?? 12,
    userAgent: json['userAgent'] as String?,
    providerTitle: json['providerTitle'] as String?,
    announce: json['announce'] as String?,
    supportUrl: json['supportUrl'] as String?,
    webPageUrl: json['webPageUrl'] as String?,
    // Миграция подписок, заведённых до появления флага: при создании пустое
    // имя заполнялось хостом из URL, поэтому совпадение с хостом и означает
    // «имя автоматическое». Иначе оно введено руками и трогать его нельзя.
    nameIsAuto:
        json['nameIsAuto'] as bool? ?? (name == Uri.tryParse(url)?.host),
    fetchIdentity: json['fetchIdentity'] is Map
        ? SubscriptionFetchIdentity.fromJson(
            (json['fetchIdentity'] as Map).cast<String, dynamic>(),
          )
        : SubscriptionFetchIdentity.empty,
  );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    if (lastUpdatedAt != null)
      'lastUpdatedAt': lastUpdatedAt!.toIso8601String(),
    if (usedBytes != null) 'usedBytes': usedBytes,
    if (totalBytes != null) 'totalBytes': totalBytes,
    if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
    'autoUpdate': autoUpdate,
    'serverCount': serverCount,
    'updateIntervalHours': updateIntervalHours,
    if (userAgent != null) 'userAgent': userAgent,
    if (providerTitle != null) 'providerTitle': providerTitle,
    if (announce != null) 'announce': announce,
    if (supportUrl != null) 'supportUrl': supportUrl,
    if (webPageUrl != null) 'webPageUrl': webPageUrl,
    'nameIsAuto': nameIsAuto,
    if (fetchIdentity.enabled || fetchIdentity.hasCustomFields)
      'fetchIdentity': fetchIdentity.toJson(),
  };

  Subscription copyWith({
    String? id,
    String? name,
    String? url,
    DateTime? lastUpdatedAt,
    int? usedBytes,
    int? totalBytes,
    DateTime? expiresAt,
    bool? autoUpdate,
    int? serverCount,
    int? updateIntervalHours,
    String? userAgent,
    String? providerTitle,
    String? announce,
    String? supportUrl,
    String? webPageUrl,
    bool? nameIsAuto,
    SubscriptionFetchIdentity? fetchIdentity,
  }) =>
      Subscription(
        id: id ?? this.id,
        name: name ?? this.name,
        url: url ?? this.url,
        lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
        usedBytes: usedBytes ?? this.usedBytes,
        totalBytes: totalBytes ?? this.totalBytes,
        expiresAt: expiresAt ?? this.expiresAt,
        autoUpdate: autoUpdate ?? this.autoUpdate,
        serverCount: serverCount ?? this.serverCount,
        updateIntervalHours: updateIntervalHours ?? this.updateIntervalHours,
        userAgent: userAgent ?? this.userAgent,
        providerTitle: providerTitle ?? this.providerTitle,
        announce: announce ?? this.announce,
        supportUrl: supportUrl ?? this.supportUrl,
        webPageUrl: webPageUrl ?? this.webPageUrl,
        nameIsAuto: nameIsAuto ?? this.nameIsAuto,
        fetchIdentity: fetchIdentity ?? this.fetchIdentity,
      );

  /// Записывает косметику из заголовков ответа панели.
  ///
  /// Отдельно от [copyWith] именно потому, что здесь важно уметь ОБНУЛЯТЬ:
  /// `copyWith` трактует null как «не трогать», и снятое провайдером
  /// объявление висело бы в карточке вечно. Тут же значения задаются ровно
  /// такими, какими пришли в последнем успешном ответе.
  ///
  /// [name] заменяется на название сервиса только если стоит автоматическое:
  /// имя, введённое пользовательницей, не перетирается никогда.
  Subscription withProfileHeaders({
    required String? title,
    required String? announce,
    required String? supportUrl,
    required String? webPageUrl,
    int? updateIntervalHours,
  }) {
    final cleanTitle = title?.trim();
    final adoptTitle =
        nameIsAuto && cleanTitle != null && cleanTitle.isNotEmpty;
    return Subscription(
      id: id,
      name: adoptTitle ? cleanTitle : name,
      url: url,
      lastUpdatedAt: lastUpdatedAt,
      usedBytes: usedBytes,
      totalBytes: totalBytes,
      expiresAt: expiresAt,
      autoUpdate: autoUpdate,
      serverCount: serverCount,
      updateIntervalHours: updateIntervalHours ?? this.updateIntervalHours,
      userAgent: userAgent,
      providerTitle: cleanTitle?.isEmpty ?? true ? null : cleanTitle,
      announce: announce?.trim().isEmpty ?? true ? null : announce!.trim(),
      supportUrl: supportUrl,
      webPageUrl: webPageUrl,
      nameIsAuto: nameIsAuto,
      fetchIdentity: fetchIdentity,
    );
  }

  /// Название сервиса, если оно отличается от того, что стоит в заголовке
  /// карточки. Пусто, когда показывать нечего или это одно и то же.
  String? get providerSubtitle {
    final title = providerTitle?.trim();
    if (title == null || title.isEmpty || title == name) return null;
    return title;
  }

  // total=0 от провайдера = безлимит
  bool get isUnlimited => totalBytes != null && totalBytes! == 0;

  double? get usagePercent {
    if (isUnlimited) return null;           // безлимит — прогресс-бар не нужен
    if (totalBytes == null || totalBytes! <= 0) return null;
    if (usedBytes == null) return null;
    return (usedBytes! / totalBytes!).clamp(0.0, 1.0);
  }

  /// Потрачено — отдельно от лимита, чтобы карточка могла набрать это крупно.
  ///
  /// Склеенная строка `641.7 / ∞ GiB` не даёт сделать главное: показатель,
  /// ради которого на карточку и смотрят, обязан отличаться размером, а не
  /// стоять тем же кеглем, что и всё остальное.
  String? get usedDisplay {
    if (usedBytes == null && totalBytes == null) return null;
    const gib = 1024 * 1024 * 1024;
    return '${((usedBytes ?? 0) / gib).toStringAsFixed(1)} GiB';
  }

  /// Лимит рядом с [usedDisplay]: `∞` или, например, `10 GiB`.
  String? get limitDisplay {
    if (usedBytes == null && totalBytes == null) return null;
    if (isUnlimited || totalBytes == null) return '∞';
    const gib = 1024 * 1024 * 1024;
    return '${(totalBytes! / gib).toStringAsFixed(0)} GiB';
  }

  String get usageLabel {
    // лимит вообще не пришёл — ∞ не рисуем
    if (usedBytes == null && totalBytes == null) return '—';
    // провайдер считает в гибибайтах (1024³), делим так же, чтобы цифры сошлись
    const gib = 1024 * 1024 * 1024;
    // total=0 → безлимит, показываем сколько потрачено вместо голого "∞"
    if (isUnlimited) {
      final usedGib = ((usedBytes ?? 0) / gib).toStringAsFixed(1);
      return '$usedGib / ∞ GiB';
    }
    if (usedBytes == null) return '0 / ∞ GiB';
    final usedGib = (usedBytes! / gib).toStringAsFixed(1);
    final totalStr = (totalBytes != null && !isUnlimited)
        ? '${(totalBytes! / gib).toStringAsFixed(0)} GiB'
        : '∞';
    return '$usedGib / $totalStr';
  }

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());
}