import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../utils/awg_profile.dart';
import '../utils/custom_clash_config.dart';
import '../utils/custom_xray_config.dart';
import '../utils/mieru_uri.dart';
import '../utils/proxy_chain.dart';
import '../utils/socks_uri.dart';
import '../utils/ssr_uri.dart';
import 'ping_sample.dart';
import 'server_flag.dart';
import 'server_name_utils.dart';

enum ServerItemType { manual, subscription }

class ServerItem {
  static const _sentinel = Object();

  final String id;
  final String config;
  final ServerItemType type;
  final String? subscriptionId;
  final String? subscriptionName;
  final DateTime addedAt;
  final String? customName;
  final DateTime? pinnedAt;
  final bool configOverridden;
  final int? pingMs;
  final DateTime? lastTestedAt;
  final String? lastPingType;
  final List<PingSample> pingSamples;

  String? _cachedDerivedName;
  ServerFlag? _cachedFlag;
  bool _flagParsed = false;
  String? _cachedAddress;
  int? _cachedPort;
  Map<String, dynamic>? _cachedVmessPayload;
  bool _vmessPayloadParsed = false;
  CustomXrayConfig? _cachedCustom;
  bool _customParsed = false;
  CustomClashConfig? _cachedClash;
  bool _clashParsed = false;
  ProxyChainConfig? _cachedChain;
  bool _chainParsed = false;

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
    this.pingSamples = const [],
  }) : addedAt = addedAt ?? DateTime.now();

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
    pingSamples: [
      for (final raw in (json['pingSamples'] as List?) ?? const [])
        ?PingSample.fromJson(raw),
    ],
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
    if (pingSamples.isNotEmpty)
      'pingSamples': [for (final s in pingSamples) s.toJson()],
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
    List<PingSample>? pingSamples,
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
        pingSamples: pingSamples ?? this.pingSamples,
      );

  bool get isPinned => pinnedAt != null;

  String get displayName {
    final custom = customName?.trim();
    if (custom != null && custom.isNotEmpty) return _sanitizeUtf16(custom);
    return derivedName;
  }

  String get derivedName {
    if (_cachedDerivedName != null) return _cachedDerivedName!;
    try {
      if (protocol == 'chain') {
        final chain = chainConfig!;
        final title = chain.name.trim();
        return _cachedDerivedName = _sanitizeUtf16(
          title.isNotEmpty ? title : _chainRouteLabel(chain),
        );
      }
      if (protocol == 'custom') {
        final custom = customConfig!;
        final remarks = custom.remarks;
        return _cachedDerivedName = _sanitizeUtf16(
          remarks.isNotEmpty
              ? remarks
              : (custom.address.isNotEmpty ? custom.address : 'Custom config'),
        );
      }
      if (protocol == 'clash') {
        final clash = clashConfig!;
        final remarks = clash.remarks;
        return _cachedDerivedName = _sanitizeUtf16(
          remarks.isNotEmpty
              ? remarks
              : (clash.address.isNotEmpty ? clash.address : 'Clash config'),
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
        try {
          raw = Uri.decodeComponent(uri.fragment);
        } catch (_) {
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


  static String _chainRouteLabel(ProxyChainConfig chain) {
    final parts = [
      for (final hop in chain.hops)
        ServerNameUtils.cleanDisplayName(hop.name).trim(),
    ].where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return 'Chain';
    return parts.join(' → ');
  }

  String get cleanName => ServerNameUtils.cleanDisplayName(displayName);

  ServerFlag? get flag {
    if (!_flagParsed) {
      _flagParsed = true;
      if (protocol == 'chain') {
        // автоимя цепочки начинается с флага входа, а в кружке нужна страна выхода
        _cachedFlag = ServerNameUtils.extractFlag(customName ?? '') ??
            ServerNameUtils.extractFlag(chainConfig!.exit.name);
      } else {
        _cachedFlag = ServerNameUtils.extractFlag(displayName) ??
            ServerNameUtils.extractFlag(derivedName);
      }
    }
    return _cachedFlag;
  }

  List<ServerFlag?> get chainFlags {
    final chain = chainConfig;
    if (chain == null) return const [];
    return [
      for (final hop in chain.hops) ServerNameUtils.extractFlag(hop.name),
    ];
  }

  String? get countryCode => switch (flag) {
        FlagArt(:final countryCode) => countryCode,
        _ => null,
      };

  // из сырой строки: Uri.parse приводит host к нижнему регистру, а base64 к нему чувствителен
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
    } catch (_) {}
    return _cachedVmessPayload;
  }

  String get address {
    final cached = _cachedAddress;
    if (cached != null) return cached;
    return _cachedAddress = _computeAddress();
  }

  String _computeAddress() {
    try {
      if (protocol == 'chain') {
        return _hopItem(chainConfig!.entry.config).address;
      }
      if (protocol == 'custom') {
        return customConfig!.address;
      }
      if (protocol == 'clash') {
        return clashConfig!.address;
      }
      if (protocol == 'awg') {
        return AwgProfile.parse(config).endpointHost;
      }
      if (protocol == 'vmess') {
        return (_vmessPayload()?['add'] ?? '').toString().trim();
      }
      if (protocol == 'ssr') return SsrLink.tryParse(config)?.host ?? '';
      if (protocol == 'mieru') return MieruLink.tryParse(config)?.host ?? '';
      if (protocol == 'socks') return SocksLink.tryParse(config)?.host ?? '';
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
      if (protocol == 'chain') {
        return _hopItem(chainConfig!.entry.config).port;
      }
      if (protocol == 'custom') {
        return customConfig!.port;
      }
      if (protocol == 'clash') {
        return clashConfig!.port;
      }
      if (protocol == 'awg') {
        return AwgProfile.parse(config).endpointPort;
      }
      if (protocol == 'vmess') {
        return int.tryParse((_vmessPayload()?['port'] ?? '').toString()) ?? 0;
      }
      if (protocol == 'mieru') return MieruLink.tryParse(config)?.port ?? 0;
      if (protocol == 'ssr') return SsrLink.tryParse(config)?.port ?? 0;
      if (protocol == 'socks') return SocksLink.tryParse(config)?.port ?? 0;
      return Uri.parse(config.replaceFirst(RegExp(r'^[a-z]+://'), 'https://')).port;
    } catch (_) {
      return 0;
    }
  }

  CustomXrayConfig? get customConfig {
    if (_customParsed) return _cachedCustom;
    _customParsed = true;
    if (CustomXrayConfig.looksLikeJson(config)) {
      _cachedCustom = CustomXrayConfig.tryParse(config);
    }
    return _cachedCustom;
  }

  CustomClashConfig? get clashConfig {
    if (_clashParsed) return _cachedClash;
    _clashParsed = true;
    if (CustomClashConfig.looksLikeClash(config)) {
      _cachedClash = CustomClashConfig.tryParse(config);
    }
    return _cachedClash;
  }

  ProxyChainConfig? get chainConfig {
    if (_chainParsed) return _cachedChain;
    _chainParsed = true;
    if (ProxyChainConfig.looksLikeChain(config)) {
      _cachedChain = ProxyChainConfig.tryParse(config);
    }
    return _cachedChain;
  }

  static ServerItem _hopItem(String hopConfig) => ServerItem(
        id: '',
        config: hopConfig,
        type: ServerItemType.manual,
      );

  List<ServerItem> get chainHopItems {
    final chain = chainConfig;
    if (chain == null) return const [];
    return [
      for (final hop in chain.hops)
        _hopItem(hop.config).copyWith(
          customName: hop.name.isEmpty ? null : hop.name,
        ),
    ];
  }

  String get protocol {
    final lower = config.toLowerCase();
    if (lower.startsWith('${ProxyChainConfig.scheme}://')) {
      // битая цепочка остаётся unknown, иначе chainConfig! ниже упадёт на null
      return chainConfig != null ? 'chain' : 'unknown';
    }
    if (lower.startsWith('vless://')) return 'vless';
    if (lower.startsWith('vmess://')) return 'vmess';
    if (lower.startsWith('trojan://')) return 'trojan';
    if (lower.startsWith('ss://')) return 'ss';
    if (lower.startsWith('ssr://')) return 'ssr';
    if (lower.startsWith('hy2://')) return 'hy2';
    if (lower.startsWith('hysteria2://')) return 'hysteria2';
    if (lower.startsWith('hysteria://')) return 'hysteria';
    if (lower.startsWith('tuic://')) return 'tuic';
    if (lower.startsWith('anytls://')) return 'anytls';
    if (lower.startsWith('mierus://')) return 'mieru';
    if (SocksLink.isSocks(config)) return 'socks';
    if (AwgProfile.isAwgConfig(config)) return 'awg';
    // clash проверять раньше xray: json-конфиг clash тоже начинается с {
    if (clashConfig != null) return 'clash';
    if (customConfig != null) return 'custom';
    return 'unknown';
  }

  // одиночные суррогаты от провайдеров роняют движок текста Flutter
  static String _sanitizeUtf16(String input) {
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

      if (code >= 0xDC00 && code <= 0xDFFF) continue;

      buffer.writeCharCode(code);
    }
    return buffer.toString();
  }

  @override
  String toString() => 'ServerItem($displayName, $protocol, $address:$port)';
}
