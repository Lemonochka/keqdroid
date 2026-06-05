import 'package:uuid/uuid.dart';

import 'server_name_utils.dart';

enum ServerItemType { manual, subscription }

class ServerItem {
  // sentinel чтобы в copyWith можно было явно передать null
  static const _sentinel = Object();

  final String id;
  final String config;           // raw vless:// vmess:// etc.
  final ServerItemType type;
  final String? subscriptionId;
  final String? subscriptionName;
  final DateTime addedAt;
  final bool isFavorite;
  final int? pingMs;
  final DateTime? lastTestedAt;
  /// `'tcp'` | `'url'` — метод последнего пинга, нужен для цвета в UI
  final String? lastPingType;

  // кэш чтобы не парсить uri каждый раз
  String? _cachedDisplayName;
  String? _cachedCountryCode;

  ServerItem({
    required this.id,
    required this.config,
    required this.type,
    this.subscriptionId,
    this.subscriptionName,
    DateTime? addedAt,
    this.isFavorite = false,
    this.pingMs,
    this.lastTestedAt,
    this.lastPingType,
  }) : addedAt = addedAt ?? DateTime.now();

  /// из raw-строки конфига
  factory ServerItem.fromRaw(
      String config, {
        String? subscriptionId,
        String? subscriptionName,
      }) =>
      ServerItem(
        id: const Uuid().v4(),
        config: config,
        type: subscriptionId != null
            ? ServerItemType.subscription
            : ServerItemType.manual,
        subscriptionId: subscriptionId,
        subscriptionName: subscriptionName,
      );

  factory ServerItem.fromJson(Map<String, dynamic> json) => ServerItem(
    id: json['id'] as String,
    config: json['config'] as String,
    type: ServerItemType.values.firstWhere(
          (e) => e.name == json['type'],
      orElse: () => ServerItemType.manual,
    ),
    subscriptionId: json['subscriptionId'] as String?,
    subscriptionName: json['subscriptionName'] as String?,
    addedAt: json['addedAt'] != null
        ? DateTime.parse(json['addedAt'] as String)
        : DateTime.now(),
    isFavorite: json['isFavorite'] as bool? ?? false,
    pingMs: json['pingMs'] as int?,
    lastTestedAt: json['lastTestedAt'] != null
        ? DateTime.parse(json['lastTestedAt'] as String)
        : null,
    lastPingType: json['lastPingType'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'config': config,
    'type': type.name,
    if (subscriptionId != null) 'subscriptionId': subscriptionId,
    if (subscriptionName != null) 'subscriptionName': subscriptionName,
    'addedAt': addedAt.toIso8601String(),
    'isFavorite': isFavorite,
    if (pingMs != null) 'pingMs': pingMs,
    if (lastTestedAt != null) 'lastTestedAt': lastTestedAt!.toIso8601String(),
    if (lastPingType != null) 'lastPingType': lastPingType,
  };

  ServerItem copyWith({
    String? id,
    String? config,
    ServerItemType? type,
    String? subscriptionId,
    String? subscriptionName,
    DateTime? addedAt,
    bool? isFavorite,
    Object? pingMs = _sentinel,
    Object? lastTestedAt = _sentinel,
    Object? lastPingType = _sentinel,
  }) =>
      ServerItem(
        id: id ?? this.id,
        config: config ?? this.config,
        type: type ?? this.type,
        subscriptionId: subscriptionId ?? this.subscriptionId,
        subscriptionName: subscriptionName ?? this.subscriptionName,
        addedAt: addedAt ?? this.addedAt,
        isFavorite: isFavorite ?? this.isFavorite,
        pingMs: pingMs == _sentinel ? this.pingMs : pingMs as int?,
        lastTestedAt: lastTestedAt == _sentinel
            ? this.lastTestedAt
            : lastTestedAt as DateTime?,
        lastPingType: lastPingType == _sentinel
            ? this.lastPingType
            : lastPingType as String?,
      );

  /// Читаемое название сервера из фрагмента URI.
  ///
  /// санитизируем после decodeComponent: некоторые провайдеры суют битые
  /// surrogate-эмодзи, на которых flutter падает "string is not well-formed UTF-16".
  String get displayName {
    if (_cachedDisplayName != null) return _cachedDisplayName!;
    try {
      final uri = Uri.parse(config);
      String raw;
      if (uri.fragment.isNotEmpty) {
        // decodeComponent может кинуть на битом percent-encoding
        try {
          raw = Uri.decodeComponent(uri.fragment);
        } catch (_) {
          // fallback: просто выкидываем percent-encoding
          raw = uri.fragment.replaceAll(RegExp(r'%[0-9A-Fa-f]{2}'), '');
        }
      } else {
        raw = uri.host;
      }
      _cachedDisplayName = _sanitizeUtf16(raw.isEmpty ? 'Unknown Server' : raw);
    } catch (_) {
      _cachedDisplayName = 'Unknown Server';
    }
    return _cachedDisplayName!;
  }


  /// Имя сервера без флаг-эмодзи и кода страны в начале.
  /// Используется для отображения в UI.
  String get cleanName => ServerNameUtils.cleanDisplayName(displayName);

  /// ISO alpha-2 код страны, определённый из displayName.
  String? get countryCode {
    _cachedCountryCode ??= ServerNameUtils.extractCountryCode(displayName);
    return _cachedCountryCode;
  }

  /// Адрес сервера
  String get address {
    try {
      return Uri.parse(config.replaceFirst(RegExp(r'^[a-z]+://'), 'https://')).host;
    } catch (_) {
      return '';
    }
  }

  /// Порт сервера
  int get port {
    try {
      return Uri.parse(config.replaceFirst(RegExp(r'^[a-z]+://'), 'https://')).port;
    } catch (_) {
      return 0;
    }
  }

  /// Протокол ('vless', 'vmess', 'trojan', 'ss', 'ssr', 'hysteria', 'hy2', 'awg', 'unknown')
  String get protocol {
    final lower = config.toLowerCase();
    if (lower.startsWith('vless://')) return 'vless';
    if (lower.startsWith('vmess://')) return 'vmess';
    if (lower.startsWith('trojan://')) return 'trojan';
    if (lower.startsWith('ss://')) return 'ss';
    if (lower.startsWith('ssr://')) return 'ssr';
    if (lower.startsWith('hy2://')) return 'hy2';
    if (lower.startsWith('hysteria2://')) return 'hysteria2';
    if (lower.startsWith('hysteria://')) return 'hysteria';
    return 'unknown';
  }

  // выкидываем одиночные surrogate'ы (на них падает flutter text engine),
  // валидные пары оставляем как есть
  static String _sanitizeUtf16(String input) {
    // быстрый путь: суррогатов нет — отдаём как есть
    bool hasSurrogate = false;
    for (var i = 0; i < input.length; i++) {
      final c = input.codeUnitAt(i);
      if (c >= 0xD800 && c <= 0xDFFF) { hasSurrogate = true; break; }
    }
    if (!hasSurrogate) return input;

    final buffer = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final code = input.codeUnitAt(i);

      if (code >= 0xD800 && code <= 0xDBFF) {
        // high surrogate — должен идти в паре с low
        if (i + 1 < input.length) {
          final next = input.codeUnitAt(i + 1);
          if (next >= 0xDC00 && next <= 0xDFFF) {
            buffer.writeCharCode(code);
            buffer.writeCharCode(next);
            i++;
            continue;
          }
        }
        continue;
      }

      // одиночный low surrogate
      if (code >= 0xDC00 && code <= 0xDFFF) continue;

      buffer.writeCharCode(code);
    }
    return buffer.toString();
  }

  @override
  String toString() => 'ServerItem($displayName, $protocol, $address:$port)';
}