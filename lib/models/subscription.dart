import 'package:uuid/uuid.dart';

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
  });

  factory Subscription.create({
    required String name,
    required String url,
    bool nameIsAuto = false,
  }) =>
      Subscription(
        id: const Uuid().v4(),
        name: name,
        url: url,
        nameIsAuto: nameIsAuto,
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