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
  });

  factory Subscription.create({required String name, required String url}) =>
      Subscription(
        id: const Uuid().v4(),
        name: name,
        url: url,
      );

  factory Subscription.fromJson(Map<String, dynamic> json) => Subscription(
    id: json['id'] as String,
    name: json['name'] as String,
    url: json['url'] as String,
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
  );

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
      );

  // total=0 от провайдера = безлимит
  bool get isUnlimited => totalBytes != null && totalBytes! == 0;

  double? get usagePercent {
    if (isUnlimited) return null;           // безлимит — прогресс-бар не нужен
    if (totalBytes == null || totalBytes! <= 0) return null;
    if (usedBytes == null) return null;
    return (usedBytes! / totalBytes!).clamp(0.0, 1.0);
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