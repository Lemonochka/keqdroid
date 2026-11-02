import 'package:uuid/uuid.dart';

import 'subscription_card_layout.dart';
import 'subscription_card_theme.dart';


class SubscriptionFetchIdentity {
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
  final int updateIntervalHours;
  final String? userAgent;

  final String? providerTitle;

  final String? announce;

  final String? supportUrl;
  final String? webPageUrl;

  final bool nameIsAuto;

  final SubscriptionFetchIdentity fetchIdentity;

  final String cardThemeId;

  final bool cardThemeInServers;

  final Set<SubscriptionCardElement> hiddenCardElements;

  final CardVeil cardVeil;

  final bool autoSelectVisible;

  final bool autoSelect;

  // запасной адрес от провайдера: читается, когда основной не отвечает, сам адрес подписки не меняет
  final String? fallbackUrl;

  // провайдер просит напоминать за 3 дня до конца
  final bool remindExpiry;

  // группа шаблона mihomo и выбранный в ней пункт, сам шаблон в StorageService.getClashTemplate
  final Map<String, String> groupChoices;

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
    this.cardThemeId = '',
    this.cardThemeInServers = true,
    this.hiddenCardElements = const {},
    this.cardVeil = CardVeil.medium,
    this.autoSelectVisible = false,
    this.autoSelect = false,
    this.fallbackUrl,
    this.remindExpiry = false,
    this.groupChoices = const {},
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
        autoSelectVisible: true,
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
    // старые подписки без флага: имя по умолчанию было хостом из URL
    nameIsAuto:
        json['nameIsAuto'] as bool? ?? (name == Uri.tryParse(url)?.host),
    cardThemeId: json['cardThemeId'] as String? ?? '',
    cardThemeInServers: json['cardThemeInServers'] as bool? ?? true,
    hiddenCardElements:
        SubscriptionCardElement.setFromJson(json['cardHidden']),
    cardVeil: CardVeil.byName(json['cardVeil'] as String?),
    autoSelectVisible: json['autoSelectVisible'] as bool? ?? false,
    autoSelect: json['autoSelect'] as bool? ?? false,
    fallbackUrl: json['fallbackUrl'] as String?,
    remindExpiry: json['remindExpiry'] as bool? ?? false,
    groupChoices: json['groupChoices'] is Map
        ? {
            for (final MapEntry(:key, :value)
                in (json['groupChoices'] as Map).entries)
              key.toString(): value.toString(),
          }
        : const {},
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
    if (cardThemeId.isNotEmpty) 'cardThemeId': cardThemeId,
    if (!cardThemeInServers) 'cardThemeInServers': false,
    if (hiddenCardElements.isNotEmpty)
      'cardHidden': [for (final e in hiddenCardElements) e.name],
    if (cardVeil != CardVeil.medium) 'cardVeil': cardVeil.name,
    if (autoSelectVisible) 'autoSelectVisible': true,
    if (autoSelect) 'autoSelect': true,
    if (fallbackUrl != null) 'fallbackUrl': fallbackUrl,
    if (remindExpiry) 'remindExpiry': true,
    if (groupChoices.isNotEmpty) 'groupChoices': groupChoices,
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
    String? cardThemeId,
    bool? cardThemeInServers,
    Set<SubscriptionCardElement>? hiddenCardElements,
    CardVeil? cardVeil,
    bool? autoSelectVisible,
    bool? autoSelect,
    SubscriptionFetchIdentity? fetchIdentity,
    String? fallbackUrl,
    bool? remindExpiry,
    Map<String, String>? groupChoices,
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
        cardThemeId: cardThemeId ?? this.cardThemeId,
        cardThemeInServers: cardThemeInServers ?? this.cardThemeInServers,
        hiddenCardElements: hiddenCardElements ?? this.hiddenCardElements,
        cardVeil: cardVeil ?? this.cardVeil,
        autoSelectVisible: autoSelectVisible ?? this.autoSelectVisible,
        autoSelect: autoSelect ?? this.autoSelect,
        fetchIdentity: fetchIdentity ?? this.fetchIdentity,
        fallbackUrl: fallbackUrl ?? this.fallbackUrl,
        remindExpiry: remindExpiry ?? this.remindExpiry,
        groupChoices: groupChoices ?? this.groupChoices,
      );

  // новое поле модели добавлять и сюда, иначе оно слетает при каждом обновлении подписки
  // copyWith не годится: для него null значит не трогать, а снятое объявление надо стирать
  Subscription withProfileHeaders({
    required String? title,
    required String? announce,
    required String? supportUrl,
    required String? webPageUrl,
    int? updateIntervalHours,
    String? fallbackUrl,
    bool remindExpiry = false,
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
      cardThemeId: cardThemeId,
      cardThemeInServers: cardThemeInServers,
      hiddenCardElements: hiddenCardElements,
      cardVeil: cardVeil,
      autoSelectVisible: autoSelectVisible,
      autoSelect: autoSelect,
      // запасной адрес приходит не в каждом ответе: со старым ничего не теряется, а отказ основного без него глухой
      fallbackUrl: fallbackUrl ?? this.fallbackUrl,
      remindExpiry: remindExpiry,
      groupChoices: groupChoices,
    );
  }

  String? get providerSubtitle {
    final title = providerTitle?.trim();
    if (title == null || title.isEmpty || title == name) return null;
    return title;
  }

  bool get isUnlimited => totalBytes != null && totalBytes! == 0;

  double? get usagePercent {
    if (isUnlimited) return null;
    if (totalBytes == null || totalBytes! <= 0) return null;
    if (usedBytes == null) return null;
    return (usedBytes! / totalBytes!).clamp(0.0, 1.0);
  }

  String? get usedDisplay {
    if (usedBytes == null && totalBytes == null) return null;
    const gib = 1024 * 1024 * 1024;
    return '${((usedBytes ?? 0) / gib).toStringAsFixed(1)} GiB';
  }

  String? get limitDisplay {
    if (usedBytes == null && totalBytes == null) return null;
    if (isUnlimited || totalBytes == null) return '∞';
    const gib = 1024 * 1024 * 1024;
    return '${(totalBytes! / gib).toStringAsFixed(0)} GiB';
  }

  String get usageLabel {
    if (usedBytes == null && totalBytes == null) return '—';
    const gib = 1024 * 1024 * 1024;
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

  bool showsCard(SubscriptionCardElement element) =>
      !hiddenCardElements.contains(element);

  SubscriptionCardPreset get cardPreset =>
      SubscriptionCardPreset.of(hiddenCardElements);
}
