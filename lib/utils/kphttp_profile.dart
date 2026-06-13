import 'dart:convert';

/// Client export profile for KpHTTP / KpCore (matches rust-kp `ClientExportProfile`).
class KphttpProfile {
  final String remark;
  final String server;
  final int port;
  final String transport;
  final KphttpCrypto crypto;
  final KphttpTls tls;
  final KphttpUplink uplink;
  final KphttpObfuscation obfuscation;
  final KphttpHeaders headers;
  final KphttpCore core;

  const KphttpProfile({
    required this.remark,
    required this.server,
    required this.port,
    required this.transport,
    required this.crypto,
    required this.tls,
    required this.uplink,
    required this.obfuscation,
    required this.headers,
    required this.core,
  });

  /// Splits pasted text into individual configs.
  /// Multi-line KpHTTP JSON must stay one block (not one line per config).
  static List<String> splitPastedConfigs(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];
    if (trimmed.startsWith('{') && isKphttpConfig(trimmed)) {
      return [trimmed];
    }
    return trimmed
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  static bool isKphttpConfig(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return false;
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('kphttp://')) return true;
    if (trimmed.startsWith('{')) {
      try {
        final json = jsonDecode(trimmed);
        if (json is Map<String, dynamic>) {
          final protocol = json['protocol']?.toString().toLowerCase() ?? '';
          return protocol == 'kphttp';
        }
      } catch (_) {}
    }
    return false;
  }

  static KphttpProfile parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('KpHTTP config is empty');
    }

    Map<String, dynamic> json;
    if (trimmed.toLowerCase().startsWith('kphttp://')) {
      json = _decodeKphttpUri(trimmed);
    } else if (trimmed.startsWith('{')) {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) {
        throw ArgumentError('Invalid KpHTTP JSON profile');
      }
      json = decoded;
    } else {
      throw ArgumentError('Unsupported KpHTTP format');
    }

    final protocol = json['protocol']?.toString().toLowerCase() ?? 'kphttp';
    if (protocol != 'kphttp') {
      throw ArgumentError('Expected protocol kphttp, got $protocol');
    }

    final server = json['server']?.toString().trim() ?? '';
    final port = _asInt(json['port']) ?? 443;
    if (server.isEmpty) {
      throw ArgumentError('KpHTTP profile: server is required');
    }

    final cryptoRaw = json['crypto'];
    if (cryptoRaw is! Map) {
      throw ArgumentError('KpHTTP profile: crypto block is required');
    }
    final psk = cryptoRaw['psk']?.toString() ?? '';
    if (psk.length < 8) {
      throw ArgumentError('KpHTTP profile: crypto.psk must be at least 8 characters');
    }

    final coreRaw = json['core'];
    if (coreRaw is! Map) {
      throw ArgumentError('KpHTTP profile: core block with uuid is required');
    }
    final uuid = coreRaw['uuid']?.toString().trim() ?? '';
    if (uuid.isEmpty) {
      throw ArgumentError('KpHTTP profile: core.uuid is required');
    }

    final tlsRaw = json['tls'];
    final tlsMap = tlsRaw is Map ? tlsRaw : const <String, dynamic>{};

    return KphttpProfile(
      remark: json['remark']?.toString().trim() ?? '',
      server: server,
      port: port,
      transport: _normalizeTransport(json['transport']?.toString()),
      crypto: KphttpCrypto(
        psk: psk,
        uriWindowSecs: _asInt(cryptoRaw['uri_window_secs']) ?? 30,
        pathPrefix: cryptoRaw['path_prefix']?.toString() ?? '/assets/v1/',
      ),
      tls: KphttpTls(
        enabled: tlsMap['enabled'] as bool? ?? true,
        sni: tlsMap['sni']?.toString() ?? server,
        serverName: tlsMap['server_name']?.toString(),
        insecure: tlsMap['insecure'] as bool? ?? false,
      ),
      uplink: KphttpUplink.fromJson(
        json['uplink'] is Map ? Map<String, dynamic>.from(json['uplink'] as Map) : null,
      ),
      obfuscation: KphttpObfuscation.fromJson(
        json['obfuscation'] is Map
            ? Map<String, dynamic>.from(json['obfuscation'] as Map)
            : null,
      ),
      headers: KphttpHeaders.fromJson(
        json['headers'] is Map
            ? Map<String, dynamic>.from(json['headers'] as Map)
            : null,
      ),
      core: KphttpCore(uuid: uuid),
    );
  }

  /// Normalizes config to `kphttp://` + base64url(JSON) + optional `#remark`.
  String toStorageUri() {
    final payload = <String, dynamic>{
      'protocol': 'kphttp',
      'version': 1,
      'remark': remark,
      'server': server,
      'port': port,
      'transport': transport,
      'crypto': {
        'psk': crypto.psk,
        'uri_window_secs': crypto.uriWindowSecs,
        'path_prefix': crypto.pathPrefix,
      },
      'tls': {
        'enabled': tls.enabled,
        'sni': tls.sni,
        if (tls.serverName != null && tls.serverName!.isNotEmpty)
          'server_name': tls.serverName,
        'insecure': tls.insecure,
      },
      'uplink': uplink.toJson(),
      'obfuscation': obfuscation.toJson(),
      'headers': headers.toJson(),
      'core': {'uuid': core.uuid},
    };
    final encoded = base64Url.encode(utf8.encode(jsonEncode(payload)));
    final fragment = remark.isNotEmpty ? '#${Uri.encodeComponent(remark)}' : '';
    return 'kphttp://$encoded$fragment';
  }

  static Map<String, dynamic> _decodeKphttpUri(String raw) {
    final lower = raw.toLowerCase();
    if (!lower.startsWith('kphttp://')) {
      throw ArgumentError('Not a kphttp URI');
    }
    final withoutScheme = raw.substring('kphttp://'.length);
    final hashIdx = withoutScheme.indexOf('#');
    final payload = (hashIdx >= 0 ? withoutScheme.substring(0, hashIdx) : withoutScheme).trim();
    if (payload.isEmpty) {
      throw ArgumentError('KpHTTP URI payload is empty');
    }
    final decoded = utf8.decode(base64Url.decode(base64Url.normalize(payload)));
    final json = jsonDecode(decoded);
    if (json is! Map<String, dynamic>) {
      throw ArgumentError('Invalid KpHTTP URI payload');
    }
    if (hashIdx >= 0 && (json['remark']?.toString().isEmpty ?? true)) {
      json['remark'] = Uri.decodeComponent(withoutScheme.substring(hashIdx + 1));
    }
    return json;
  }

  static int? _asInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  static String _normalizeTransport(String? raw) {
    final t = (raw ?? 'h2').trim().toLowerCase();
    if (t == 'h3') return 'h3';
    return 'h2';
  }
}

class KphttpCrypto {
  final String psk;
  final int uriWindowSecs;
  final String pathPrefix;

  const KphttpCrypto({
    required this.psk,
    required this.uriWindowSecs,
    required this.pathPrefix,
  });
}

class KphttpTls {
  final bool enabled;
  final String sni;
  final String? serverName;
  final bool insecure;

  const KphttpTls({
    required this.enabled,
    required this.sni,
    this.serverName,
    required this.insecure,
  });
}

class KphttpUplink {
  final String mode;
  final int batchIntervalMs;
  final int maxBufferBytes;

  const KphttpUplink({
    this.mode = 'packet-up',
    this.batchIntervalMs = 20,
    this.maxBufferBytes = 262144,
  });

  factory KphttpUplink.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const KphttpUplink();
    final modeRaw = json['mode']?.toString().trim().toLowerCase() ?? 'packet-up';
    return KphttpUplink(
      mode: modeRaw == 'stream-up' ? 'stream-up' : 'packet-up',
      batchIntervalMs: KphttpProfile._asInt(json['batch_interval_ms']) ?? 20,
      maxBufferBytes: KphttpProfile._asInt(json['max_buffer_bytes']) ?? 262144,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'batch_interval_ms': batchIntervalMs,
        'max_buffer_bytes': maxBufferBytes,
      };
}

class KphttpObfuscation {
  final int paddingGrid;
  final int randomPaddingMin;
  final int randomPaddingMax;
  final bool dummyPosts;
  final int dummyJitterMinMs;
  final int dummyJitterMaxMs;

  const KphttpObfuscation({
    this.paddingGrid = 128,
    this.randomPaddingMin = 0,
    this.randomPaddingMax = 64,
    this.dummyPosts = true,
    this.dummyJitterMinMs = 2000,
    this.dummyJitterMaxMs = 8000,
  });

  factory KphttpObfuscation.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const KphttpObfuscation();
    return KphttpObfuscation(
      paddingGrid: KphttpProfile._asInt(json['padding_grid']) ?? 128,
      randomPaddingMin: KphttpProfile._asInt(json['random_padding_min']) ?? 0,
      randomPaddingMax: KphttpProfile._asInt(json['random_padding_max']) ?? 64,
      dummyPosts: json['dummy_posts'] as bool? ?? true,
      dummyJitterMinMs: KphttpProfile._asInt(json['dummy_jitter_min_ms']) ?? 2000,
      dummyJitterMaxMs: KphttpProfile._asInt(json['dummy_jitter_max_ms']) ?? 8000,
    );
  }

  Map<String, dynamic> toJson() => {
        'padding_grid': paddingGrid,
        'random_padding_min': randomPaddingMin,
        'random_padding_max': randomPaddingMax,
        'dummy_posts': dummyPosts,
        'dummy_jitter_min_ms': dummyJitterMinMs,
        'dummy_jitter_max_ms': dummyJitterMaxMs,
      };
}

class KphttpHeaders {
  final String? host;
  final String? userAgent;
  final String? accept;
  final String? acceptLanguage;
  final String? acceptEncoding;
  final String? secFetchMode;
  final String? secFetchSite;
  final Map<String, String> extra;

  const KphttpHeaders({
    this.host,
    this.userAgent,
    this.accept,
    this.acceptLanguage,
    this.acceptEncoding,
    this.secFetchMode,
    this.secFetchSite,
    this.extra = const {},
  });

  factory KphttpHeaders.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const KphttpHeaders();
    final extraRaw = json['extra'];
    final extra = <String, String>{};
    if (extraRaw is Map) {
      for (final entry in extraRaw.entries) {
        extra[entry.key.toString()] = entry.value.toString();
      }
    }
    return KphttpHeaders(
      host: json['host']?.toString(),
      userAgent: json['user_agent']?.toString(),
      accept: json['accept']?.toString(),
      acceptLanguage: json['accept_language']?.toString(),
      acceptEncoding: json['accept_encoding']?.toString(),
      secFetchMode: json['sec_fetch_mode']?.toString(),
      secFetchSite: json['sec_fetch_site']?.toString(),
      extra: extra,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      if (host != null && host!.isNotEmpty) 'host': host,
      if (userAgent != null && userAgent!.isNotEmpty) 'user_agent': userAgent,
      if (accept != null && accept!.isNotEmpty) 'accept': accept,
      if (acceptLanguage != null && acceptLanguage!.isNotEmpty)
        'accept_language': acceptLanguage,
      if (acceptEncoding != null && acceptEncoding!.isNotEmpty)
        'accept_encoding': acceptEncoding,
      if (secFetchMode != null && secFetchMode!.isNotEmpty)
        'sec_fetch_mode': secFetchMode,
      if (secFetchSite != null && secFetchSite!.isNotEmpty)
        'sec_fetch_site': secFetchSite,
      if (extra.isNotEmpty) 'extra': extra,
    };
    return map;
  }
}

class KphttpCore {
  final String uuid;

  const KphttpCore({required this.uuid});
}
