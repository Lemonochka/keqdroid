import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../utils/awg_profile.dart';
import '../utils/custom_xray_config.dart';
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
  /// Пользовательское имя: перекрывает имя из конфига, переживает обновление
  /// подписки (переносится в copyWith при stable-match). null/пусто — имя
  /// берётся из конфига как раньше.
  final String? customName;
  /// Момент закрепления: закреплённые серверы всегда наверху группы (порядок —
  /// по времени пина), независимо от режима сортировки. null — не закреплён.
  final DateTime? pinnedAt;
  /// Конфиг подписочного сервера отредактирован вручную: при обновлении
  /// подписки stable-match сохраняет пользовательский конфиг, а не затирает
  /// его серверным. Для manual-серверов не используется.
  final bool configOverridden;
  final int? pingMs;
  final DateTime? lastTestedAt;
  /// `'tcp'` | `'url'` — метод последнего пинга, нужен для цвета в UI
  final String? lastPingType;

  // кэш чтобы не парсить uri каждый раз
  String? _cachedDerivedName;
  String? _cachedCountryCode;
  String? _cachedAddress;
  int? _cachedPort;
  Map<String, dynamic>? _cachedVmessPayload;
  bool _vmessPayloadParsed = false;
  CustomXrayConfig? _cachedCustom;
  bool _customParsed = false;

  ServerItem({
    required this.id,
    required this.config,
    required this.type,
    this.subscriptionId,
    this.subscriptionName,
    DateTime? addedAt,
    this.customName,
    this.pinnedAt,
    this.configOverridden = false,
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
    customName: json['customName'] as String?,
    pinnedAt: json['pinnedAt'] != null
        ? DateTime.tryParse(json['pinnedAt'] as String)
        : null,
    configOverridden: json['configOverridden'] as bool? ?? false,
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
    if (customName != null) 'customName': customName,
    if (pinnedAt != null) 'pinnedAt': pinnedAt!.toIso8601String(),
    if (configOverridden) 'configOverridden': configOverridden,
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
    Object? customName = _sentinel,
    Object? pinnedAt = _sentinel,
    bool? configOverridden,
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
        customName:
            customName == _sentinel ? this.customName : customName as String?,
        pinnedAt:
            pinnedAt == _sentinel ? this.pinnedAt : pinnedAt as DateTime?,
        configOverridden: configOverridden ?? this.configOverridden,
        pingMs: pingMs == _sentinel ? this.pingMs : pingMs as int?,
        lastTestedAt: lastTestedAt == _sentinel
            ? this.lastTestedAt
            : lastTestedAt as DateTime?,
        lastPingType: lastPingType == _sentinel
            ? this.lastPingType
            : lastPingType as String?,
      );

  bool get isPinned => pinnedAt != null;

  /// Имя для отображения: пользовательское [customName], если задано,
  /// иначе — имя из конфига ([derivedName]).
  String get displayName {
    final custom = customName?.trim();
    if (custom != null && custom.isNotEmpty) return _sanitizeUtf16(custom);
    return derivedName;
  }

  /// Читаемое название сервера из фрагмента URI (без учёта переименования).
  ///
  /// санитизируем после decodeComponent: некоторые провайдеры суют битые
  /// surrogate-эмодзи, на которых flutter падает "string is not well-formed UTF-16".
  String get derivedName {
    if (_cachedDerivedName != null) return _cachedDerivedName!;
    try {
      if (protocol == 'custom') {
        final custom = customConfig!;
        final remarks = custom.remarks;
        return _cachedDerivedName = _sanitizeUtf16(
          remarks.isNotEmpty
              ? remarks
              : (custom.address.isNotEmpty ? custom.address : 'Custom config'),
        );
      }
      if (protocol == 'awg') {
        final profile = AwgProfile.parse(config);
        final remark = profile.remark;
        _cachedDerivedName = _sanitizeUtf16(
          (remark != null && remark.isNotEmpty) ? remark : profile.endpointHost,
        );
        return _cachedDerivedName!;
      }
      if (protocol == 'vmess') {
        final ps = (_vmessPayload()?['ps'] ?? '').toString().trim();
        if (ps.isNotEmpty) {
          return _cachedDerivedName = _sanitizeUtf16(ps);
        }
      }
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
      _cachedDerivedName = _sanitizeUtf16(raw.isEmpty ? 'Unknown Server' : raw);
    } catch (_) {
      _cachedDerivedName = 'Unknown Server';
    }
    return _cachedDerivedName!;
  }


  /// Имя сервера без флаг-эмодзи и кода страны в начале.
  String get cleanName => ServerNameUtils.cleanDisplayName(displayName);

  /// ISO alpha-2 код страны. Сначала из отображаемого имени; если пользователь
  /// переименовал сервер без страновых меток — фолбэк на имя из конфига,
  /// чтобы флаг не пропадал после переименования.
  String? get countryCode {
    _cachedCountryCode ??= ServerNameUtils.extractCountryCode(displayName) ??
        ServerNameUtils.extractCountryCode(derivedName);
    return _cachedCountryCode;
  }

  /// vmess://BASE64(JSON) — реальные host/port лежат внутри payload, а не в
  /// authority URI. Декодируем из СЫРОЙ строки конфига: Uri.parse лоуэркейсит
  /// host, а base64 регистрозависим — через Uri address превращался бы в
  /// обрезанный base64-блоб, а port — в 443 (дефолт https).
  Map<String, dynamic>? _vmessPayload() {
    if (_vmessPayloadParsed) return _cachedVmessPayload;
    _vmessPayloadParsed = true;
    try {
      final payload = config
          .substring('vmess://'.length)
          .replaceAll(RegExp(r'\s+'), '')
          .replaceAll('-', '+')
          .replaceAll('_', '/');
      final decoded = utf8.decode(base64.decode(base64.normalize(payload)));
      final json = jsonDecode(decoded);
      if (json is Map<String, dynamic>) _cachedVmessPayload = json;
    } catch (_) {
      // битый payload — address/port уйдут в пустые значения
    }
    return _cachedVmessPayload;
  }

  String get address {
    final cached = _cachedAddress;
    if (cached != null) return cached;
    return _cachedAddress = _computeAddress();
  }

  String _computeAddress() {
    try {
      if (protocol == 'custom') {
        return customConfig!.address;
      }
      if (protocol == 'awg') {
        return AwgProfile.parse(config).endpointHost;
      }
      if (protocol == 'vmess') {
        return (_vmessPayload()?['add'] ?? '').toString().trim();
      }
      return Uri.parse(config.replaceFirst(RegExp(r'^[a-z]+://'), 'https://')).host;
    } catch (_) {
      return '';
    }
  }

  int get port {
    final cached = _cachedPort;
    if (cached != null) return cached;
    return _cachedPort = _computePort();
  }

  int _computePort() {
    try {
      if (protocol == 'custom') {
        return customConfig!.port;
      }
      if (protocol == 'awg') {
        return AwgProfile.parse(config).endpointPort;
      }
      if (protocol == 'vmess') {
        return int.tryParse((_vmessPayload()?['port'] ?? '').toString()) ?? 0;
      }
      return Uri.parse(config.replaceFirst(RegExp(r'^[a-z]+://'), 'https://')).port;
    } catch (_) {
      return 0;
    }
  }

  /// Готовый xray-конфиг вместо ссылки (сервер «CUSTOM»): роутинг и dns в нём
  /// авторские. null — конфиг не такой. Разбор кэшируется: [protocol] дёргают
  /// на каждую перерисовку плитки.
  CustomXrayConfig? get customConfig {
    if (_customParsed) return _cachedCustom;
    _customParsed = true;
    if (CustomXrayConfig.looksLikeJson(config)) {
      _cachedCustom = CustomXrayConfig.tryParse(config);
    }
    return _cachedCustom;
  }

  /// Протокол ('vless', 'vmess', 'trojan', 'ss', 'ssr', 'hysteria', 'hy2',
  /// 'awg', 'custom', 'unknown')
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
    if (AwgProfile.isAwgConfig(config)) return 'awg';
    if (customConfig != null) return 'custom';
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