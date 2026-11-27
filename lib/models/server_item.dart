import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../utils/awg_profile.dart';
import '../utils/custom_clash_config.dart';
import '../utils/custom_xray_config.dart';
import '../utils/mieru_uri.dart';
import '../utils/proxy_chain.dart';
import '../utils/same_server_key.dart';
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
  final bool autoSkip;
  final int? pingMs;
  final DateTime? lastTestedAt;
  final String? lastPingType;
  final List<PingSample> pingSamples;
  // null: ещё не проверяли; проверка идёт в замере, только когда IPv6 пускают через VPN
  final bool? ipv6Exit;
  final DateTime? ipv6CheckedAt;
  // узел не обслуживал имена, адрес ищет наше ядро; действует сутки (NamesFallback)
  final DateTime? namesFallbackAt;

  String? _cachedDerivedName;
  ServerFlag? _cachedFlag;
  bool _flagParsed = false;
  String? _cachedAddress;
  int? _cachedPort;
  bool _vmessMetaParsed = false;
  bool _structuredMetaParsed = false;
  bool _cachedHasProviderRules = false;
  bool _cachedHasProviderDns = false;
  ProxyChainConfig? _cachedChain;
  bool _chainParsed = false;
  String? _cachedSameServerKey;
  String? _cachedProtocol;

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
    this.autoSkip = false,
    this.pingMs,
    this.lastTestedAt,
    this.lastPingType,
    this.pingSamples = const [],
    this.ipv6Exit,
    this.ipv6CheckedAt,
    this.namesFallbackAt,
  }) : addedAt = addedAt ?? DateTime.now();

  factory ServerItem.fromRaw(
    String config, {
    String? subscriptionId,
    String? subscriptionName,
  }) => ServerItem(
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
    autoSkip: json['autoSkip'] as bool? ?? false,
    pingMs: json['pingMs'] as int?,
    lastTestedAt: json['lastTestedAt'] != null
        ? DateTime.parse(json['lastTestedAt'] as String)
        : null,
    lastPingType: json['lastPingType'] as String?,
    pingSamples: [
      for (final raw in (json['pingSamples'] as List?) ?? const [])
        ?PingSample.fromJson(raw),
    ],
    ipv6Exit: json['ipv6Exit'] as bool?,
    ipv6CheckedAt: json['ipv6CheckedAt'] is String
        ? DateTime.tryParse(json['ipv6CheckedAt'] as String)
        : null,
    namesFallbackAt: json['namesFallbackAt'] is String
        ? DateTime.tryParse(json['namesFallbackAt'] as String)
        : null,
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
    if (autoSkip) 'autoSkip': true,
    if (pingMs != null) 'pingMs': pingMs,
    if (lastTestedAt != null) 'lastTestedAt': lastTestedAt!.toIso8601String(),
    if (lastPingType != null) 'lastPingType': lastPingType,
    if (pingSamples.isNotEmpty)
      'pingSamples': [for (final s in pingSamples) s.toJson()],
    if (ipv6Exit != null) 'ipv6Exit': ipv6Exit,
    if (ipv6CheckedAt != null)
      'ipv6CheckedAt': ipv6CheckedAt!.toIso8601String(),
    if (namesFallbackAt != null)
      'namesFallbackAt': namesFallbackAt!.toIso8601String(),
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
    bool? autoSkip,
    Object? pingMs = _sentinel,
    Object? lastTestedAt = _sentinel,
    Object? lastPingType = _sentinel,
    List<PingSample>? pingSamples,
    Object? ipv6Exit = _sentinel,
    Object? ipv6CheckedAt = _sentinel,
    Object? namesFallbackAt = _sentinel,
  }) {
    final nextConfig = config ?? this.config;
    final nextCustomName = customName == _sentinel
        ? this.customName
        : customName as String?;
    final copy = ServerItem(
      id: id ?? this.id,
      config: nextConfig,
      type: type ?? this.type,
      subscriptionId: subscriptionId ?? this.subscriptionId,
      subscriptionName: subscriptionName ?? this.subscriptionName,
      addedAt: addedAt ?? this.addedAt,
      customName: nextCustomName,
      pinnedAt: pinnedAt == _sentinel ? this.pinnedAt : pinnedAt as DateTime?,
      configOverridden: configOverridden ?? this.configOverridden,
      autoSkip: autoSkip ?? this.autoSkip,
      pingMs: pingMs == _sentinel ? this.pingMs : pingMs as int?,
      lastTestedAt: lastTestedAt == _sentinel
          ? this.lastTestedAt
          : lastTestedAt as DateTime?,
      lastPingType: lastPingType == _sentinel
          ? this.lastPingType
          : lastPingType as String?,
      pingSamples: pingSamples ?? this.pingSamples,
      ipv6Exit: ipv6Exit == _sentinel ? this.ipv6Exit : ipv6Exit as bool?,
      ipv6CheckedAt: ipv6CheckedAt == _sentinel
          ? this.ipv6CheckedAt
          : ipv6CheckedAt as DateTime?,
      namesFallbackAt: namesFallbackAt == _sentinel
          ? this.namesFallbackAt
          : namesFallbackAt as DateTime?,
    );
    if (nextConfig == this.config) {
      copy
        .._cachedDerivedName = _cachedDerivedName
        .._cachedAddress = _cachedAddress
        .._cachedPort = _cachedPort
        .._vmessMetaParsed = _vmessMetaParsed
        .._structuredMetaParsed = _structuredMetaParsed
        .._cachedHasProviderRules = _cachedHasProviderRules
        .._cachedHasProviderDns = _cachedHasProviderDns
        .._cachedChain = _cachedChain
        .._chainParsed = _chainParsed
        .._cachedSameServerKey = _cachedSameServerKey
        .._cachedProtocol = _cachedProtocol;
      if (nextCustomName == this.customName) {
        copy
          .._cachedFlag = _cachedFlag
          .._flagParsed = _flagParsed;
      }
    }
    return copy;
  }

  bool get isPinned => pinnedAt != null;

  String get sameServerKey => _cachedSameServerKey ??= sameServerKeyOf(config);

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
      if (protocol == 'custom' || protocol == 'clash') {
        _ensureStructuredMeta();
        return _cachedDerivedName ??= protocol == 'clash'
            ? 'Clash config'
            : 'Custom config';
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
        _ensureVmessMeta();
        if (_cachedDerivedName != null) return _cachedDerivedName!;
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
        _cachedFlag =
            ServerNameUtils.extractFlag(customName ?? '') ??
            ServerNameUtils.extractFlag(chainConfig!.exit.name);
      } else {
        _cachedFlag =
            ServerNameUtils.extractFlag(displayName) ??
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
  void _ensureVmessMeta() {
    if (_vmessMetaParsed) return;
    _vmessMetaParsed = true;
    try {
      final payload = config
          .substring('vmess://'.length)
          .replaceAll(RegExp(r'\s+'), '')
          .replaceAll('-', '+')
          .replaceAll('_', '/');
      final decoded = utf8.decode(base64.decode(base64.normalize(payload)));
      final json = jsonDecode(decoded);
      if (json is Map<String, dynamic>) {
        final ps = (json['ps'] ?? '').toString().trim();
        if (ps.isNotEmpty) _cachedDerivedName = _sanitizeUtf16(ps);
        _cachedAddress = (json['add'] ?? '').toString().trim();
        _cachedPort = int.tryParse((json['port'] ?? '').toString()) ?? 0;
      }
    } catch (_) {}
  }

  // готовый JSON/YAML в Map весит под 250 КБ на сервер, поэтому оставляем только поля строки списка
  void _ensureStructuredMeta() {
    if (_structuredMetaParsed) return;
    _structuredMetaParsed = true;
    if (CustomClashConfig.looksLikeClash(config)) {
      final clash = CustomClashConfig.tryParse(config);
      if (clash != null) {
        final remarks = clash.remarks;
        _cachedProtocol = 'clash';
        _cachedDerivedName = _sanitizeUtf16(
          remarks.isNotEmpty
              ? remarks
              : (clash.address.isNotEmpty ? clash.address : 'Clash config'),
        );
        _cachedAddress = clash.address;
        _cachedPort = clash.port;
        _cachedHasProviderRules = clash.hasProviderRules;
        _cachedHasProviderDns = clash.hasProviderDns;
        return;
      }
    }
    if (CustomXrayConfig.looksLikeJson(config)) {
      final custom = CustomXrayConfig.tryParse(config);
      if (custom != null) {
        final remarks = custom.remarks;
        _cachedProtocol = 'custom';
        _cachedDerivedName = _sanitizeUtf16(
          remarks.isNotEmpty
              ? remarks
              : (custom.address.isNotEmpty ? custom.address : 'Custom config'),
        );
        _cachedAddress = custom.address;
        _cachedPort = custom.port;
        _cachedHasProviderRules = custom.hasProviderRules;
        _cachedHasProviderDns = custom.hasProviderDns;
        return;
      }
    }
    _cachedProtocol ??= 'unknown';
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
      if (protocol == 'custom' || protocol == 'clash') {
        _ensureStructuredMeta();
        return _cachedAddress ?? '';
      }
      if (protocol == 'awg') {
        return AwgProfile.parse(config).endpointHost;
      }
      if (protocol == 'vmess') {
        _ensureVmessMeta();
        return _cachedAddress ?? '';
      }
      if (protocol == 'ssr') return SsrLink.tryParse(config)?.host ?? '';
      if (protocol == 'mieru') return MieruLink.tryParse(config)?.host ?? '';
      if (protocol == 'socks') return SocksLink.tryParse(config)?.host ?? '';
      return Uri.parse(
        config.replaceFirst(RegExp(r'^[a-z]+://'), 'https://'),
      ).host;
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
      if (protocol == 'custom' || protocol == 'clash') {
        _ensureStructuredMeta();
        return _cachedPort ?? 0;
      }
      if (protocol == 'awg') {
        return AwgProfile.parse(config).endpointPort;
      }
      if (protocol == 'vmess') {
        _ensureVmessMeta();
        return _cachedPort ?? 0;
      }
      if (protocol == 'mieru') return MieruLink.tryParse(config)?.port ?? 0;
      if (protocol == 'ssr') return SsrLink.tryParse(config)?.port ?? 0;
      if (protocol == 'socks') return SocksLink.tryParse(config)?.port ?? 0;
      return Uri.parse(
        config.replaceFirst(RegExp(r'^[a-z]+://'), 'https://'),
      ).port;
    } catch (_) {
      return 0;
    }
  }

  bool get hasProviderRules {
    if (protocol != 'custom' && protocol != 'clash') return false;
    _ensureStructuredMeta();
    return _cachedHasProviderRules;
  }

  bool get hasProviderDns {
    if (protocol != 'custom' && protocol != 'clash') return false;
    _ensureStructuredMeta();
    return _cachedHasProviderDns;
  }

  CustomXrayConfig? get customConfig {
    if (_cachedProtocol != null && _cachedProtocol != 'custom') return null;
    if (!CustomXrayConfig.looksLikeJson(config)) return null;
    return CustomXrayConfig.tryParse(config);
  }

  CustomClashConfig? get clashConfig {
    if (_cachedProtocol != null && _cachedProtocol != 'clash') return null;
    if (!CustomClashConfig.looksLikeClash(config)) return null;
    return CustomClashConfig.tryParse(config);
  }

  ProxyChainConfig? get chainConfig {
    if (_chainParsed) return _cachedChain;
    _chainParsed = true;
    if (ProxyChainConfig.looksLikeChain(config)) {
      _cachedChain = ProxyChainConfig.tryParse(config);
    }
    return _cachedChain;
  }

  static ServerItem _hopItem(String hopConfig) =>
      ServerItem(id: '', config: hopConfig, type: ServerItemType.manual);

  List<ServerItem> get chainHopItems {
    final chain = chainConfig;
    if (chain == null) return const [];
    return [
      for (final hop in chain.hops)
        _hopItem(
          hop.config,
        ).copyWith(customName: hop.name.isEmpty ? null : hop.name),
    ];
  }

  String get protocol => _cachedProtocol ??= _protocolOf();

  String _protocolOf() {
    final headLen = config.length < 16 ? config.length : 16;
    final lower = config.substring(0, headLen).toLowerCase();
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
    _ensureStructuredMeta();
    return _cachedProtocol ?? 'unknown';
  }

  // одиночные суррогаты от провайдеров роняют движок текста Flutter
  static String _sanitizeUtf16(String input) {
    bool hasSurrogate = false;
    for (var i = 0; i < input.length; i++) {
      final c = input.codeUnitAt(i);
      if (c >= 0xD800 && c <= 0xDFFF) {
        hasSurrogate = true;
        break;
      }
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
