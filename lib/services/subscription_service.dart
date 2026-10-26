import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

import '../utils/local_vpn_proxy.dart';
import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../core/app_logger.dart';
import '../models/server_item.dart';
import '../models/subscription.dart';
import '../services/storage_service.dart';
import '../utils/custom_clash_config.dart';
import '../utils/custom_xray_config.dart';
import '../utils/hysteria_uri.dart';
import '../utils/identity_presets.dart';
import '../utils/mieru_uri.dart';
import '../utils/singbox_outbounds.dart';
import '../utils/ssr_uri.dart';
import '../utils/vmess_json_link.dart';
import '../core/exceptions.dart';

class SubscriptionProfileHeaders {
  final String? title;
  final String? announce;
  final String? supportUrl;
  final String? webPageUrl;
  final int? updateIntervalHours;

  const SubscriptionProfileHeaders({
    this.title,
    this.announce,
    this.supportUrl,
    this.webPageUrl,
    this.updateIntervalHours,
  });

  static const empty = SubscriptionProfileHeaders();

  bool get isEmpty =>
      title == null &&
      announce == null &&
      supportUrl == null &&
      webPageUrl == null &&
      updateIntervalHours == null;
}

class SubscriptionFetchResult {
  final List<String> configs;
  final int? usedBytes;
  final int? totalBytes;
  final DateTime? expiresAt;

  final String? usedUserAgent;

  final SubscriptionProfileHeaders profile;

  const SubscriptionFetchResult({
    required this.configs,
    required this.usedBytes,
    required this.totalBytes,
    required this.expiresAt,
    required this.usedUserAgent,
    required this.profile,
  });
}

class UpdateResult {
  final bool success;
  final int serverCount;
  final String? error;
  final Subscription subscription;

  const UpdateResult({
    required this.success,
    this.serverCount = 0,
    this.error,
    required this.subscription,
  });
}

class SubscriptionService {
  final StorageService _storage;
  final Dio _dio;

  final LocalProxyPortResolver? _localProxyPort;
  String? _cachedHwid;
  String? _cachedDeviceModel;
  static const MethodChannel _platform = MethodChannel('keqdis_vpn_channel');

  static const browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static const clientUserAgents = ClientUaPresets.rotation;

  static String _appUserAgentCache = 'keqdroid';
  static bool _appUserAgentResolved = false;
  static Future<String> appUserAgent() async {
    if (!_appUserAgentResolved) {
      try {
        final info = await PackageInfo.fromPlatform();
        if (info.version.isNotEmpty) {
          _appUserAgentCache = 'keqdroid/${info.version}';
        }
      } on Object {
        // нет платформы, остаётся голый keqdroid
      }
      _appUserAgentResolved = true;
    }
    return _appUserAgentCache;
  }

  SubscriptionService(
    this._storage, {
    Dio? dio,
    LocalProxyPortResolver? localProxyPort,
  })  : _localProxyPort = localProxyPort,
        _dio = dio ?? _buildDio(localProxyPort: localProxyPort);

  // при включённом VPN только через локальный инбаунд: пакет приложения исключён из TUN
  static Dio _buildDio({LocalProxyPortResolver? localProxyPort}) {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'User-Agent': browserUserAgent,
        'Accept': '*/*',
        'Accept-Language': 'en-US,en;q=0.9',
      },
    ));

    if (localProxyPort != null) {
      configureDioForLocalVpnProxy(dio, localProxyPort);
    }

    return dio;
  }

  static const _blockedHostnames = {
    'metadata.google.internal',
    '169.254.169.254',           // AWS/GCP/Azure IMDS
    'fd00:ec2::254',             // AWS IMDSv2 IPv6
  };

  static bool isSafeUrl(String url) {
    try {
      if (url.length > 2048) return false;
      final uri = Uri.parse(url);
      // только https: в payload пароли и ключи серверов, по http их читает любой посредник
      if (!uri.hasScheme || uri.scheme != 'https') {
        return false;
      }
      if (uri.host.isEmpty) return false;
      final host = uri.host.toLowerCase();

      if (host == 'localhost' ||
          host.startsWith('127.') ||
          host == '0.0.0.0' ||
          host == '::1' ||
          _blockedHostnames.contains(host)) {
        return false;
      }

      if (_isDisallowedIpHost(host)) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  // числовые записи вроде 2130706433 и 0x7f000001 тоже бывают частным адресом
  static bool _isDisallowedIpHost(String host) {
    if (RegExp(r'^0x[0-9a-f]+$').hasMatch(host)) return true;
    if (RegExp(r'^\d+$').hasMatch(host)) return true;

    final addr = InternetAddress.tryParse(host);
    if (addr == null) return false;
    if (addr.isLoopback || addr.isLinkLocal || addr.isMulticast) return true;

    final b = addr.rawAddress;
    if (addr.type == InternetAddressType.IPv4) {
      if (b[0] == 0) return true; // 0.0.0.0/8
      if (b[0] == 10) return true; // 10/8
      if (b[0] == 127) return true; // 127/8
      if (b[0] == 169 && b[1] == 254) return true; // 169.254/16
      if (b[0] == 172 && b[1] >= 16 && b[1] <= 31) return true; // 172.16/12
      if (b[0] == 192 && b[1] == 168) return true; // 192.168/16
      if (b[0] == 100 && b[1] >= 64 && b[1] <= 127) return true; // CGNAT 100.64/10
    } else if (addr.type == InternetAddressType.IPv6) {
      if ((b[0] & 0xfe) == 0xfc) return true; // fc00::/7 ULA
    }
    return false;
  }

  // ключ без query: REALITY-провайдеры ротируют sid/spx/pbk, а сервер тот же
  static String _stableKey(String rawConfig) {
    try {
      if (CustomXrayConfig.looksLikeJson(rawConfig)) {
        final custom = CustomXrayConfig.tryParse(rawConfig);
        if (custom != null) {
          final endpoint = custom.endpoint;
          return 'custom:${custom.remarks.toLowerCase()}'
              '@${endpoint.address.toLowerCase()}:${endpoint.port}';
        }
      }

      // Uri.parse не берёт порт вида host:20000-20050, ключ уходил бы в фолбэк и менялся вместе с именем
      final uri = Uri.parse(_parsableUri(rawConfig));
      final host = uri.host.toLowerCase();
      final port = uri.port.toString();

      // у SSR имя внутри base64, ключ по сырой ссылке менялся бы при переименовании
      if (rawConfig.toLowerCase().startsWith('ssr://')) {
        final ssr = SsrLink.tryParse(rawConfig);
        if (ssr != null) {
          return 'ssr:${ssr.password.toLowerCase()}@'
              '${ssr.host.toLowerCase()}:${ssr.port}';
        }
      }

      // из сырой строки: uri.host портит регистр base64, и ключ уходил бы в фолбэк вместе с именем
      if (rawConfig.startsWith('vmess://')) {
        try {
          final payload = rawConfig.substring('vmess://'.length);
          final decoded = _tryDecodeBase64Flexible(payload);
          // не декодировалось: формат AEAD (#716), uuid там же, где у vless
          if (decoded == null) {
            return 'vmess:${uri.userInfo.toLowerCase()}@$host:$port';
          }
          final json = jsonDecode(decoded) as Map<String, dynamic>;
          final id = (json['id'] as String? ?? '').toLowerCase();
          final add = (json['add'] as String? ?? '').toLowerCase();
          final portJ = json['port']?.toString() ?? port;
          return 'vmess:$id@$add:$portJ';
        } catch (_) {
          return 'vmess:@$host:$port';
        }
      }

      final schemeLower = uri.scheme.toLowerCase();
      if (schemeLower == 'hysteria' || schemeLower == 'hysteria2' || schemeLower == 'hy2') {
        final qp = uri.queryParameters;
        var auth = (qp['auth'] ?? qp['password'] ?? '').toLowerCase();
        if (auth.isEmpty && uri.userInfo.isNotEmpty) {
          auth = Uri.decodeComponent(uri.userInfo).toLowerCase();
        }
        return '$schemeLower:$auth@$host:$port';
      }

      final userInfo = uri.userInfo.toLowerCase();
      return '${uri.scheme}:$userInfo@$host:$port';
    } catch (_) {
      final noFragment = rawConfig.split('#').first;
      return noFragment.substring(0, noFragment.length.clamp(0, 80));
    }
  }

  Future<SubscriptionFetchResult>
  fetchRaw(
    String url, {
    CancelToken? cancelToken,
    String? userAgent,
    SubscriptionFetchIdentity identity = SubscriptionFetchIdentity.empty,
  }) async {
    if (!isSafeUrl(url)) {
      if (Uri.tryParse(url)?.scheme.toLowerCase() == 'http') {
        throw SubscriptionFetchException('Insecure http URL', url: url);
      }
      throw SubscriptionFetchException('Forbidden URL', url: url);
    }

    // настройку читаем на каждый запрос: поле с дефолтом расходится с тумблером в фоновых изолятах
    final shareHwid = (await _storage.getSettings()).shareDeviceHwid;
    // выключенный тумблер HWID главнее подмены
    final hwid =
        shareHwid ? await _getOrCreateHwid(override: identity.activeHwid) : null;
    final hwidHeaders = hwid != null
        ? await _buildRemnawaveHeaders(
            hwid,
            overrideOs: identity.activeDeviceOs,
            overrideModel: identity.activeDeviceModel,
            overrideOsVersion: identity.activeOsVersion,
          )
        : const <String, String>{};
    // закреплённый UA не перебираем, иначе подмена схлопнется в наш. кириллица в заголовке роняет dart:io
    final pinnedUserAgent = _asciiHeaderValueOrNull(identity.activeUserAgent);

    try {
      final result = await _fetchWithRetry(
        url,
        cancelToken: cancelToken,
        attempt: 0,
        hwid: hwid,
        hwidHeaders: hwidHeaders,
        savedUserAgent: userAgent,
        pinnedUserAgent: pinnedUserAgent,
      );

      return SubscriptionFetchResult(
        configs: result.configs,
        usedBytes: result.usedBytes,
        totalBytes: result.totalBytes,
        expiresAt: result.expiresAt,
        usedUserAgent: result.usedUserAgent,
        profile: result.profile,
      );
    } on Object catch (e, st) {
      AppLogger.instance.warn(
        'Subscription fetch failed, checking HWID query fallback',
        error: e,
        stackTrace: st,
      );
      if (hwid != null && _shouldRetryWithHwidQuery(e)) {
        final urlWithHwid = _appendHwidQuery(url, hwid);
        if (urlWithHwid != url) {
          return _fetchWithRetry(
            urlWithHwid,
            cancelToken: cancelToken,
            attempt: 0,
            hwid: hwid,
            hwidHeaders: hwidHeaders,
            savedUserAgent: userAgent,
            pinnedUserAgent: pinnedUserAgent,
          );
        }
      }
      rethrow;
    }
  }

  Future<SubscriptionFetchResult>
  _fetchWithRetry(
    String url, {
    CancelToken? cancelToken,
    required int attempt,
    required String? hwid,
    required Map<String, String> hwidHeaders,
    String? savedUserAgent,
    String? pinnedUserAgent,
  }) async {
    String? usedUserAgent;
    var profile = SubscriptionProfileHeaders.empty;
    final initialUa = pinnedUserAgent ??
        ((savedUserAgent != null && savedUserAgent.isNotEmpty)
            ? savedUserAgent
            : await appUserAgent());
    try {
      Response<String> response = await _dio.get<String>(
        url,
        cancelToken: cancelToken,
        options: _hwidOptions({'User-Agent': initialUa, ...hwidHeaders}),
      );
      _throwIfRemnawaveHwidHeadersIndicateError(response.headers, url: url);

      if (response.statusCode != 200) {
        throw SubscriptionFetchException('HTTP ${response.statusCode}', url: url);
      }

      final body = response.data ?? '';
      if (body.length > 10 * 1024 * 1024) {
        throw SubscriptionFetchException('Response too large (>10MB)', url: url);
      }
      final contentType = response.headers.value('content-type')?.toLowerCase() ?? '';

      int? usedBytes, totalBytes;
      DateTime? expiresAt;

      final headerMetaInitial = _parseUserInfoHeader(response.headers);
      profile = _parseProfileHeaders(response.headers);
      usedBytes = headerMetaInitial.usedBytes;
      totalBytes = headerMetaInitial.totalBytes;
      expiresAt = headerMetaInitial.expiresAt;

      var looksLikeHtml = contentType.contains('text/html') ||
          body.trimLeft().startsWith('<!doctype html') ||
          body.trimLeft().startsWith('<html');
      var effectiveBody = body;

      if (looksLikeHtml) {
        final uaResponse = await _retryWithSubscriptionUserAgents(
          url,
          cancelToken: cancelToken,
          hwidHeaders: hwidHeaders,
          skipUserAgents: {initialUa},
          pinnedUserAgent: pinnedUserAgent,
        );
        if (uaResponse != null) {
          response = uaResponse;
          effectiveBody = uaResponse.data ?? '';
          final uaType = (uaResponse.headers.value('content-type') ?? '').toLowerCase();
          looksLikeHtml = uaType.contains('text/html') ||
              effectiveBody.trimLeft().startsWith('<!doctype html') ||
              effectiveBody.trimLeft().startsWith('<html');
          usedUserAgent = uaResponse.requestOptions.headers['User-Agent'] as String?;
          if (usedBytes == null || totalBytes == null || expiresAt == null) {
            final headerMetaUa = _parseUserInfoHeader(uaResponse.headers);
            profile = _parseProfileHeaders(uaResponse.headers);
            usedBytes ??= headerMetaUa.usedBytes;
            totalBytes ??= headerMetaUa.totalBytes;
            expiresAt ??= headerMetaUa.expiresAt;
          }
        }
      } else {
        usedUserAgent = initialUa;
      }

      List<String> configs;
      if (looksLikeHtml) {
        configs = _extractConfigsFromHtml(effectiveBody) ?? const [];
        if (configs.isEmpty) {
          configs = await _crawlHtmlForSubscriptionConfigs(
            html: effectiveBody,
            pageUrl: url,
            cancelToken: cancelToken,
          );
        }
        if (configs.isEmpty) {
          throw SubscriptionFetchException(
            'Server returned an HTML page and no subscription payload was found in it. '
            'Use a direct subscription URL (base64/plain URI list).',
            url: url,
          );
        }
      } else {
        configs = await _parseBodyOffThread(effectiveBody);
      }
      final summary = _skippedNodesSummary(
        CustomClashConfig.looksLikeClash(effectiveBody)
            ? unsupportedClashNodes(effectiveBody)
            : SingboxOutbounds.translate(effectiveBody).skipped,
      );
      if (summary != null) {
        AppLogger.instance.warn(
          'Subscription: skipped nodes this client cannot run: $summary',
        );
      }

      if (usedBytes == null || totalBytes == null || expiresAt == null) {
        final meta = _extractMetaFromBody(effectiveBody);
        usedBytes ??= meta.usedBytes;
        totalBytes ??= meta.totalBytes;
        expiresAt ??= meta.expiresAt;
      }

      return SubscriptionFetchResult(
        configs: configs,
        usedBytes: usedBytes,
        totalBytes: totalBytes,
        expiresAt: expiresAt,
        usedUserAgent: usedUserAgent,
        profile: profile,
      );
    } on DioException catch (e) {
      // бывает не-200 (502), а в теле уже валидный payload
      final parsedFromError = await _tryParseFromErrorResponse(e);
      if (parsedFromError != null) {
        return parsedFromError;
      }

      // dio кидает на не-2xx раньше UA-перебора, а часть панелей браузерному UA отдаёт html и 502
      if ((e.response?.statusCode ?? 0) >= 400) {
        final parsedWithClientUa = await _tryParseWithClientUserAgents(
          url,
          cancelToken: cancelToken,
          hwidHeaders: hwidHeaders,
          skipUserAgents: {initialUa},
          pinnedUserAgent: pinnedUserAgent,
        );
        if (parsedWithClientUa != null) {
          return parsedWithClientUa;
        }
      }

      // только если сервер ответил: молчащий хост другой клиент не оживит, а каждый кандидат ждёт 15 с
      if (e.response != null) {
        try {
          final parsedViaHttpClient = await _tryFetchWithHttpClientFallback(
            url,
            hwid: hwid,
            hwidHeaders: hwidHeaders,
            pinnedUserAgent: pinnedUserAgent,
          );
          if (parsedViaHttpClient != null) {
            return parsedViaHttpClient;
          }
        } on FormatException catch (fe) {
          throw SubscriptionFetchException(
            fe.message,
            url: url,
            cause: fe,
          );
        }
      }

      // сбой сокета или TLS посреди обмена dio отдаёт как unknown, он разовый
      final isRetryable = e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError ||
          (e.type == DioExceptionType.unknown && e.error is IOException);

      if (isRetryable && attempt == 0) {
        await Future.delayed(const Duration(seconds: 2));
        return _fetchWithRetry(
          url,
          cancelToken: cancelToken,
          attempt: 1,
          hwid: hwid,
          hwidHeaders: hwidHeaders,
          savedUserAgent: savedUserAgent,
          pinnedUserAgent: pinnedUserAgent,
        );
      }

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw RequestTimeoutException('Request timed out', cause: e);
      }
      throw SubscriptionFetchException(
        e.message ?? 'Network error',
        url: url,
        cause: e,
      );
    }
  }

  Future<SubscriptionFetchResult?>
  _tryParseFromErrorResponse(DioException e) async {
    final response = e.response;
    if (response == null) {
      return null;
    }

    final status = response.statusCode ?? 0;
    if (status < 400) {
      return null;
    }

    final raw = response.data;
    final body = raw is String ? raw : (raw?.toString() ?? '');
    if (body.trim().isEmpty) {
      return null;
    }

    try {
      final configs = _parseBody(body);
      if (configs.isEmpty) {
        return null;
      }
      final headerMeta = _parseUserInfoHeader(response.headers);
      return SubscriptionFetchResult(
        configs: configs,
        usedBytes: headerMeta.usedBytes,
        totalBytes: headerMeta.totalBytes,
        expiresAt: headerMeta.expiresAt,
        usedUserAgent: null,
        profile: _parseProfileHeaders(response.headers),
      );
    } on Object {
      return null;
    }
  }

  Future<SubscriptionFetchResult?>
  _tryParseWithClientUserAgents(
    String url, {
    CancelToken? cancelToken,
    required Map<String, String> hwidHeaders,
    Set<String> skipUserAgents = const {},
    String? pinnedUserAgent,
  }) async {
    final response = await _retryWithSubscriptionUserAgents(
      url,
      cancelToken: cancelToken,
      hwidHeaders: hwidHeaders,
      skipUserAgents: skipUserAgents,
      pinnedUserAgent: pinnedUserAgent,
    );
    if (response == null) {
      return null;
    }
    _throwIfRemnawaveHwidHeadersIndicateError(response.headers, url: url);

    final body = response.data ?? '';
    if (body.length > 10 * 1024 * 1024) {
      throw SubscriptionFetchException('Response too large (>10MB)', url: url);
    }

    List<String> configs;
    try {
      configs = await _parseBodyOffThread(body);
    } on FormatException {
      return null;
    }
    if (configs.isEmpty) {
      return null;
    }

    final headerMeta = _parseUserInfoHeader(response.headers);
    final bodyMeta = _extractMetaFromBody(body);
    return SubscriptionFetchResult(
      configs: configs,
      usedBytes: headerMeta.usedBytes ?? bodyMeta.usedBytes,
      totalBytes: headerMeta.totalBytes ?? bodyMeta.totalBytes,
      expiresAt: headerMeta.expiresAt ?? bodyMeta.expiresAt,
      usedUserAgent: response.requestOptions.headers['User-Agent'] as String?,
      profile: _parseProfileHeaders(response.headers),
    );
  }

  Future<SubscriptionFetchResult?>
  _tryFetchWithHttpClientFallback(
    String url, {
    required String? hwid,
    Map<String, String>? hwidHeaders,
    String? pinnedUserAgent,
  }) async {
    final effectiveHwidHeaders = hwidHeaders ??
        (hwid == null
            ? const <String, String>{}
            : await _buildRemnawaveHeaders(hwid));
    final candidates = _fallbackUrlCandidates(url, hwid);
    FormatException? lastFormatError;
    for (final candidate in candidates) {
      HttpClient? client;
      try {
        client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 15);
        // свой клиент мимо dio, прокси ему отдельно, иначе уйдёт напрямую мимо туннеля
        final resolveProxy = _localProxyPort;
        if (resolveProxy != null) {
          configureHttpClientForLocalVpnProxy(client, resolveProxy);
        }
        final uri = Uri.parse(candidate);
        final req = await client.getUrl(uri);
        req.headers.set(
          HttpHeaders.userAgentHeader,
          pinnedUserAgent ?? browserUserAgent,
        );
        req.headers.set(HttpHeaders.acceptHeader, '*/*');
        req.headers.set(HttpHeaders.acceptLanguageHeader, 'en-US,en;q=0.9');
        req.headers.set('Cache-Control', 'no-cache');
        req.headers.set('Pragma', 'no-cache');
        req.headers.set('Upgrade-Insecure-Requests', '1');
        effectiveHwidHeaders.forEach(req.headers.set);
        req.followRedirects = true;
        req.maxRedirects = 8;

        final resp = await req.close().timeout(const Duration(seconds: 30));
        final responseHeaders = <String, List<String>>{};
        resp.headers.forEach((k, v) {
          responseHeaders[k] = v;
        });
        final dioLikeHeaders = Headers.fromMap(responseHeaders);
        _throwIfRemnawaveHwidHeadersIndicateError(
          dioLikeHeaders,
          url: candidate,
        );
        final bytes = await resp.fold<List<int>>(<int>[], (acc, chunk) {
          acc.addAll(chunk);
          return acc;
        });
        final body = _decodeHttpBody(bytes, dioLikeHeaders);
        if (body.trim().isEmpty) continue;
        final contentType =
            (resp.headers.contentType?.mimeType ?? dioLikeHeaders.value('content-type') ?? '')
                .toLowerCase();
        final looksLikeHtml = contentType.contains('text/html') ||
            body.trimLeft().startsWith('<!doctype html') ||
            body.trimLeft().startsWith('<html');
        // без содержимого: в теле ключи серверов, а лог пересылают при жалобах
        AppLogger.instance.debug(
          'HttpClient fallback candidate response: $candidate '
          '(status=${resp.statusCode}, type=$contentType, len=${body.length}, html=$looksLikeHtml)',
        );

        final hwidError = _detectHwidGateMessage(body);
        if (hwidError != null) {
          lastFormatError = FormatException(hwidError);
          continue;
        }

        List<String> configs;
        if (looksLikeHtml) {
          configs = _extractConfigsFromHtml(body) ?? const [];
          if (configs.isEmpty) {
            configs = await _crawlHtmlForSubscriptionConfigs(
              html: body,
              pageUrl: candidate,
            );
          }
        } else {
          try {
            configs = await _parseBodyOffThread(body);
          } on FormatException {
            configs = _extractConfigsFromHtml(body) ?? const [];
            if (configs.isEmpty) rethrow;
          }
        }
        if (configs.isEmpty) continue;
        final headerMeta = _parseUserInfoHeader(dioLikeHeaders);
        final bodyMeta = _extractMetaFromBody(body);
        return SubscriptionFetchResult(
          configs: configs,
          usedBytes: headerMeta.usedBytes ?? bodyMeta.usedBytes,
          totalBytes: headerMeta.totalBytes ?? bodyMeta.totalBytes,
          expiresAt: headerMeta.expiresAt ?? bodyMeta.expiresAt,
          usedUserAgent: null,
          profile: _parseProfileHeaders(dioLikeHeaders),
        );
      } on Object catch (e, st) {
        if (e is FormatException) {
          lastFormatError = e;
          continue;
        }
        AppLogger.instance.debug(
          'HttpClient fallback candidate failed: $candidate',
          error: e,
          stackTrace: st,
        );
      } finally {
        client?.close(force: true);
      }
    }
    if (lastFormatError != null) {
      throw lastFormatError;
    }
    return null;
  }

  static String _decodeHttpBody(List<int> bytes, Headers headers) {
    if (bytes.isEmpty) return '';
    final encoding = (headers.value('content-encoding') ?? '').toLowerCase();
    var data = bytes;
    try {
      if (encoding.contains('gzip')) {
        data = gzip.decode(data);
      } else if (encoding.contains('deflate')) {
        data = zlib.decode(data);
      } else if (data.length >= 2 && data[0] == 0x1f && data[1] == 0x8b) {
        data = gzip.decode(data);
      }
    } on Object {
      // оставляем payload как есть
    }
    try {
      return utf8.decode(data, allowMalformed: true);
    } on Object {
      return latin1.decode(data, allowInvalid: true);
    }
  }

  List<String> _fallbackUrlCandidates(String url, String? hwid) {
    final out = <String>{url};
    final uri = Uri.tryParse(url);
    if (uri == null) return out.toList();

    if (!uri.path.endsWith('/')) {
      out.add(uri.replace(path: '${uri.path}/').toString());
    } else {
      final p = uri.path.substring(0, uri.path.length - 1);
      out.add(uri.replace(path: p.isEmpty ? '/' : p).toString());
    }

    // http-вариант не пробуем: в URL токен, а в заголовках hwid.
    // query-вариант только для одного проблемного домена
    final host = uri.host.toLowerCase();
    if (hwid != null && host.contains('warriorofblacksun.run')) {
      out.add(_appendHwidQuery(url, hwid));
    }
    return out.toList();
  }

  bool _shouldRetryWithHwidQuery(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('service links') ||
        msg.contains('hwid') ||
        msg.contains('enable/bind');
  }

  String _appendHwidQuery(String url, String hwid) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final qp = Map<String, String>.from(uri.queryParameters);
    qp.putIfAbsent('hwid', () => hwid);
    qp.putIfAbsent('device_id', () => hwid);
    qp.putIfAbsent('deviceId', () => hwid);
    return uri.replace(queryParameters: qp).toString();
  }

  String? _detectHwidGateMessage(String body) {
    // только конкретные фразы: голое hwid ловило html заглушек
    final lower = body.toLowerCase();
    if (lower.contains('turn on hwid') ||
        lower.contains('enable hwid') ||
        lower.contains('bind hwid') ||
        lower.contains('hwid required') ||
        lower.contains('hwid is required')) {
      return 'Provider requires HWID binding for this client. '
          'Enable/bind HWID in provider panel and try updating subscription again.';
    }
    return null;
  }

  Options _hwidOptions(Map<String, String> headers) => Options(headers: headers);

  // подставной HWID не кэшируем и не сохраняем, иначе он станет HWID устройства для всех подписок
  Future<String> _getOrCreateHwid({String? override}) async {
    final custom = override?.trim().toLowerCase();
    if (custom != null && custom.isNotEmpty) return custom;

    if (_cachedHwid != null && _cachedHwid!.isNotEmpty) return _cachedHwid!;

    String? androidId;
    try {
      androidId = (await _platform.invokeMethod<String>('getAndroidId'))
          ?.trim()
          .toLowerCase();
    } on Object {
      androidId = null;
    }
    
    final fromStorage = (_storage.getHwid() ?? '').trim().toLowerCase();
    
    if (androidId != null && androidId.isNotEmpty) {
      if (fromStorage != androidId) {
        await _storage.setHwid(androidId);
      }
      _cachedHwid = androidId;
      return androidId;
    }

    if (fromStorage.isNotEmpty) {
      _cachedHwid = fromStorage;
      return fromStorage;
    }

    final created = const Uuid().v4().replaceAll('-', '');
    await _storage.setHwid(created);
    _cachedHwid = created;
    return created;
  }

  Future<Map<String, String>> _buildRemnawaveHeaders(
    String hwid, {
    String? overrideOs,
    String? overrideModel,
    String? overrideOsVersion,
  }) async {
    final os = _trimmedOrNull(overrideOs) ??
        (Platform.isAndroid
            ? 'Android'
            : Platform.isIOS
                ? 'iOS'
                : Platform.isWindows
                    ? 'Windows'
                    : Platform.isMacOS
                        ? 'macOS'
                        : Platform.isLinux
                            ? 'Linux'
                            : Platform.operatingSystem);
    final model = _trimmedOrNull(overrideModel) ?? await _getDeviceModel();
    final osVersion =
        _trimmedOrNull(overrideOsVersion) ?? Platform.operatingSystemVersion;
    // только ASCII: на русской Windows версия ОС кириллицей, и dart:io роняет запрос до сети
    final osAscii = _asciiHeaderValue(os, fallback: Platform.operatingSystem);
    final verAscii = _asciiHeaderValue(osVersion, fallback: 'unknown');
    final modelAscii = _asciiHeaderValue(model, fallback: 'Unknown Device');
    return {
      'x-hwid': hwid,
      'X-HWID': hwid,
      'hwid': hwid,
      'x-device-os': osAscii,
      'X-Device-Os': osAscii,
      'x-ver-os': verAscii,
      'X-Ver-Os': verAscii,
      'x-device-model': modelAscii,
      'X-Device-Model': modelAscii,
    };
  }

  static String _asciiHeaderValue(String value, {required String fallback}) {
    final cleaned = value
        .replaceAll(RegExp(r'[^\x20-\x7E]'), '')
        .replaceAll('""', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return RegExp(r'[A-Za-z0-9]').hasMatch(cleaned) ? cleaned : fallback;
  }

  static String? _asciiHeaderValueOrNull(String? value) {
    final trimmed = _trimmedOrNull(value);
    if (trimmed == null) return null;
    final cleaned = _asciiHeaderValue(trimmed, fallback: '');
    return cleaned.isEmpty ? null : cleaned;
  }

  static String? _trimmedOrNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  Future<String> _getDeviceModel() async {
    if (_cachedDeviceModel != null && _cachedDeviceModel!.isNotEmpty) {
      return _cachedDeviceModel!;
    }
    if (Platform.isWindows) {
      final host = Platform.localHostname.trim();
      _cachedDeviceModel = host.isNotEmpty ? host : 'Windows PC';
      return _cachedDeviceModel!;
    }
    try {
      final model = await _platform.invokeMethod<String>('getDeviceModel');
      if (model != null && model.trim().isNotEmpty) {
        _cachedDeviceModel = model.trim();
        return _cachedDeviceModel!;
      }
    } on Object {
      // ниже запасное имя
    }
    _cachedDeviceModel = Platform.isAndroid ? 'Android Device' : 'Unknown Device';
    return _cachedDeviceModel!;
  }

  void _throwIfRemnawaveHwidHeadersIndicateError(Headers headers, {required String url}) {
    final active = headers.value('x-hwid-active')?.toLowerCase() == 'true';
    if (!active) {
      return;
    }
    if (headers.value('x-hwid-not-supported')?.toLowerCase() == 'true') {
      throw SubscriptionFetchException(
        'Remnawave requires HWID, but server marked this client as not supported.',
        url: url,
      );
    }
    final maxReached = headers.value('x-hwid-max-devices-reached')?.toLowerCase() == 'true' ||
        headers.value('x-hwid-limit')?.toLowerCase() == 'true';
    if (maxReached) {
      throw SubscriptionFetchException(
        'Remnawave device limit reached for this subscription. Remove old device in panel or raise limit.',
        url: url,
      );
    }
  }

  @visibleForTesting
  static SubscriptionProfileHeaders parseProfileHeadersForTest(Headers headers) =>
      _parseProfileHeaders(headers);

  static SubscriptionProfileHeaders _parseProfileHeaders(Headers headers) {
    String? pick(List<String> names) {
      for (final n in names) {
        final v = headers.value(n)?.trim();
        if (v != null && v.isNotEmpty) return v;
      }
      return null;
    }

    final interval = int.tryParse(
      pick(['profile-update-interval', 'update-interval']) ?? '',
    );

    return SubscriptionProfileHeaders(
      title: _decodeHeaderText(pick(['profile-title', 'profile_title'])),
      announce: _decodeHeaderText(pick(['announce', 'profile-announce'])),
      supportUrl: _sanitizeUrl(pick(['support-url', 'profile-support-url'])),
      webPageUrl: _sanitizeUrl(pick(['profile-web-page-url', 'profile-webpage-url'])),
      updateIntervalHours: (interval != null && interval > 0) ? interval : null,
    );
  }

  // голый base64 только если раскодировался в осмысленный текст: Announce тоже валидный base64
  static String? _decodeHeaderText(String? raw) {
    if (raw == null || raw.isEmpty) return null;

    String? tryDecode(String s) {
      var normalized = s.replaceAll(RegExp(r'\s'), '').replaceAll('-', '+').replaceAll('_', '/');
      if (normalized.isEmpty) return null;
      final pad = normalized.length % 4;
      if (pad != 0) normalized = normalized.padRight(normalized.length + (4 - pad), '=');
      try {
        final bytes = base64.decode(normalized);
        if (bytes.isEmpty) return null;
        final text = utf8.decode(bytes, allowMalformed: false).trim();
        if (text.isEmpty) return null;
        if (text.runes.any((r) => r < 0x20 && r != 0x0A && r != 0x09)) return null;
        return text;
      } catch (_) {
        return null;
      }
    }

    const prefix = 'base64:';
    if (raw.toLowerCase().startsWith(prefix)) {
      return tryDecode(raw.substring(prefix.length)) ?? raw.substring(prefix.length);
    }
    if (raw.length >= 8 && RegExp(r'^[A-Za-z0-9+/_=-]+$').hasMatch(raw)) {
      final decoded = tryDecode(raw);
      if (decoded != null) return decoded;
    }
    return raw;
  }

  // только http(s): ссылка приходит с чужого сервера и открывается в браузере
  static String? _sanitizeUrl(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri.toString();
  }

  static ({int? usedBytes, int? totalBytes, DateTime? expiresAt}) _parseUserInfoHeader(
    Headers headers,
  ) {
    final userInfo = headers.value('x-subscription-userinfo') ??
        headers.value('subscription-userinfo') ??
        headers.value('userinfo') ??
        headers.value('x-userinfo');
    if (userInfo == null || userInfo.isEmpty) {
      return (usedBytes: null, totalBytes: null, expiresAt: null);
    }

    int? upload, download, totalBytes;
    DateTime? expiresAt;
    final parts = userInfo.split(';');
    for (final part in parts) {
      final eqIdx = part.indexOf('=');
      if (eqIdx == -1) continue;
      final k = part.substring(0, eqIdx).trim().toLowerCase();
      final v = int.tryParse(part.substring(eqIdx + 1).trim());
      if (v == null) continue;
      switch (k) {
        case 'upload':
          upload = v;
        case 'download':
          download = v;
        case 'total':
          totalBytes = v;
        case 'expire':
          if (v > 0) {
            final dt = DateTime.fromMillisecondsSinceEpoch(v * 1000);
            if (dt.isAfter(DateTime(2000))) expiresAt = dt;
          }
      }
    }
    final usedBytes = (upload != null || download != null) ? (upload ?? 0) + (download ?? 0) : null;
    return (usedBytes: usedBytes, totalBytes: totalBytes, expiresAt: expiresAt);
  }

  Future<Response<String>?> _retryWithSubscriptionUserAgents(
    String url, {
    CancelToken? cancelToken,
    required Map<String, String> hwidHeaders,
    Set<String> skipUserAgents = const {},
    String? pinnedUserAgent,
  }) async {
    if (pinnedUserAgent != null) return null;
    final userAgents = <String>[
      await appUserAgent(),
      ...clientUserAgents,
      browserUserAgent,
    ];

    for (final ua in userAgents) {
      if (skipUserAgents.contains(ua)) continue;
      try {
        final resp = await _dio.get<String>(
          url,
          cancelToken: cancelToken,
          options: Options(
            headers: {
              'User-Agent': ua,
              'Accept': 'text/plain,*/*',
              ...hwidHeaders,
            },
          ),
        );
        if (resp.statusCode != 200) continue;
        final body = (resp.data ?? '').trimLeft();
        final type = (resp.headers.value('content-type') ?? '').toLowerCase();
        final isHtml = type.contains('text/html') ||
            body.startsWith('<!doctype html') ||
            body.startsWith('<html');
        if (!isHtml) return resp;
      } on Object {
        // следующий UA
      }
    }
    return null;
  }

  @visibleForTesting
  static List<String> parseBodyForTest(String content) => _parseBody(content);

  @visibleForTesting
  static String stableKeyForTest(String rawConfig) => _stableKey(rawConfig);

  static Future<List<String>> _parseBodyOffThread(String content) =>
      compute(_parseBody, content);

  static List<String> _parseBody(String content) {
    final original = content.trim();
    final candidates = _collectTextVariants(original);

    for (final candidate in candidates) {
      final extractedLinks = <String>{
        ..._extractUriLinks(candidate),
        ..._extractUriLinks(_htmlUnescape(candidate)),
        ..._extractUriLinks(_jsUnescape(_htmlUnescape(candidate))),
      }
          .where((c) => !_isMetadataConfig(c))
          .toList();
      final customConfigs = _extractCustomConfigs(candidate);
      if (extractedLinks.isNotEmpty || customConfigs.isNotEmpty) {
        return [...customConfigs, ...extractedLinks];
      }

      final singbox = SingboxOutbounds.translate(candidate)
          .links
          .where((c) => !_isMetadataConfig(c))
          .toList();
      if (singbox.isNotEmpty) return singbox;

      final structured = _extractConfigsFromStructuredContent(candidate);
      if (structured.isNotEmpty) return structured;

      final clashConfigs = _extractClashConfigs(candidate);
      if (clashConfigs.isNotEmpty) return clashConfigs;

      final lines = LineSplitter.split(candidate)
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      final hasOnlyMetadataLinks =
          lines.isNotEmpty &&
              lines.every((l) => !_isValidConfig(l) || _isMetadataConfig(l));
      final hasHwidGateMarkers = lines.any(_isHwidGateConfig);
      final providerGateMessage = _detectProviderGateMessage(lines);

      final configs = LineSplitter.split(candidate)
          .map((l) => l.trim())
          .where(_isValidConfig)
          .where((c) => !_isMetadataConfig(c))
          .toList();
      if (configs.isNotEmpty) return configs;
      if (hasOnlyMetadataLinks && providerGateMessage != null) {
        throw FormatException(providerGateMessage);
      }
      if (hasOnlyMetadataLinks && hasHwidGateMarkers) {
        throw const FormatException(
          'Subscription contains only service links. Provider asks to enable/bind HWID for this client.',
        );
      }
    }

    for (final candidate in candidates) {
      final unsupported = _detectUnsupportedFormat(candidate);
      if (unsupported != null) {
        throw FormatException(unsupported);
      }
    }
    throw const FormatException(
      'No supported proxy links found. Expected URI lines like vless://, vmess://, trojan://, ss://, ssr://, hysteria://, hysteria2://, hy2://, tuic://, anytls:// or mierus://',
    );
  }

  static List<String> _extractCustomConfigs(String content) {
    final whole = CustomXrayConfig.extractConfigs(content);
    if (whole.isNotEmpty) {
      return whole.where(_isUsableCustomConfig).toList();
    }

    final out = <String>[];
    for (final raw in LineSplitter.split(content)) {
      final line = raw.trim();
      if (line.isEmpty || _isValidConfig(line)) continue;
      if (CustomXrayConfig.looksLikeJson(line)) {
        out.addAll(CustomXrayConfig.extractConfigs(line));
        continue;
      }
      if (line.length < 40 || !_base64Line.hasMatch(line)) continue;
      final decoded = _tryDecodeBase64Flexible(line);
      if (decoded == null) continue;
      out.addAll(CustomXrayConfig.extractConfigs(decoded));
    }
    return out.where(_isUsableCustomConfig).toList();
  }

  static List<String> _extractClashConfigs(String content) {
    final whole = CustomClashConfig.extractConfigs(content);
    return whole.where(_isUsableClashConfig).toList();
  }

  // профиль на proxy-providers без адресов, узлы ядро скачает само
  static bool _isUsableClashConfig(String config) {
    final clash = CustomClashConfig.tryParse(config);
    if (clash == null) return false;
    return clash.address.isNotEmpty || clash.usesProviders;
  }

  // без адреса сервера это болванка панели (истёкшая подписка, непривязанный HWID)
  static bool _isUsableCustomConfig(String config) {
    if (_isMetadataConfig(config)) return false;
    final custom = CustomXrayConfig.tryParse(config);
    return custom != null && custom.address.isNotEmpty;
  }

  static final _base64Line = RegExp(r'^[A-Za-z0-9+/_=-]+$');

  static List<String> _collectTextVariants(String input) {
    // в релизе даже итеративный обход base64 и regex съедал стек, отсюда лимиты
    const maxVariants = 12;
    const maxQueueSize = 50;

    final queue = <String>[input];
    final seen = <String>{};
    final out = <String>[];

    int iterations = 0;
    const maxIterations = 200;

    while (queue.isNotEmpty && out.length < maxVariants && iterations < maxIterations) {
      iterations++;
      
      if (queue.length > maxQueueSize) {
        queue.clear();
        break;
      }

      final current = queue.removeAt(0).trim();
      if (current.isEmpty || current.length > 1024 * 1024 || !seen.add(current)) continue;
      out.add(current);

      final html = _htmlUnescape(current);
      final js = _jsUnescape(html);
      final decoded = _tryDecodeBase64Flexible(current);
      final decodedCompact = _tryDecodeBase64Flexible(current.replaceAll(RegExp(r'\s+'), ''));
      final uriDecoded = _tryUriDecode(current);

      final nextCandidates = [html, js, decoded, decodedCompact, uriDecoded]
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty && !seen.contains(s.trim()))
          .take(4)
          .toList();

      queue.addAll(nextCandidates);
    }

    return out;
  }

  static String? _tryUriDecode(String input) {
    try {
      final decoded = Uri.decodeFull(input);
      return decoded == input ? null : decoded;
    } on Object {
      return null;
    }
  }

  static String? _tryDecodeBase64Flexible(String input) {
    final compact = input.replaceAll(RegExp(r'\s+'), '').replaceAll('-', '+').replaceAll('_', '/');
    if (compact.isEmpty) return null;

    final padded = switch (compact.length % 4) {
      2 => '$compact==',
      3 => '$compact=',
      _ => compact,
    };
    try {
      return const Utf8Decoder().convert(base64.decode(base64.normalize(padded)));
    } on Object {
      return null;
    }
  }

  static String? _detectUnsupportedFormat(String content) {
    final text = content.trimLeft();
    final lower = text.toLowerCase();

    if (lower.startsWith('proxies:') ||
        lower.contains('\nproxies:') ||
        lower.startsWith('mixed-port:') ||
        lower.startsWith('proxy-providers:') ||
        lower.contains('\nproxy-providers:')) {
      final problem = CustomClashConfig.describeProblem(text);
      if (problem != null) return 'Clash subscription: $problem';
      return 'Clash subscription returned a config without a server address. '
          'This is usually a provider stub: check subscription status and '
          'HWID binding in the provider panel.';
    }

    if (SingboxOutbounds.looksLike(text)) {
      return SingboxOutbounds.describeProblem(text) ??
          SingboxOutbounds.noServers;
    }

    if (text.startsWith('{') || text.startsWith('[')) {
      try {
        final parsed = jsonDecode(text);
        if (parsed is Map<String, dynamic>) {
          final keys = parsed.keys.map((k) => k.toLowerCase()).toSet();
          if (keys.contains('outbounds') || keys.contains('inbounds') || keys.contains('proxies')) {
            if (CustomXrayConfig.tryParse(text) != null) {
              return 'Subscription returned an Xray config without a server address. '
                  'This is usually a provider stub: check subscription status and '
                  'HWID binding in the provider panel.';
            }
            return 'Unsupported subscription format: JSON config '
                '(only Xray, sing-box and Clash configs are supported)';
          }
        } else if (parsed is List && parsed.isNotEmpty) {
          return 'Unsupported subscription format: JSON array config';
        }
      } on Object {
        // не json, ниже общий текст ошибки
      }
    }
    return null;
  }

  static List<String> _extractConfigsFromStructuredContent(String content) {
    final found = <String>{};

    final trimmed = content.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        final parsed = jsonDecode(content);
        _walkStructured(parsed, found);
      } on Object {
        // не json
      }
    }

    for (final proxy in _extractYamlLikeProxies(content)) {
      final uri = _proxyMapToUri(proxy);
      if (uri != null && !_isMetadataConfig(uri)) {
        found.add(uri);
      }
    }

    return found.toList();
  }

  // итеративно: рекурсия переполняла стек на глубоких json
  static void _walkStructured(Object? node, Set<String> found) {
    const maxTotalNodes = 5000;
    const maxQueueSize = 200;
    const maxDepth = 8;

    final queue = <(Object?, int, bool)>[];
    final seen = <Object>{};

    if (node != null) {
      queue.add((node, 0, false));
    }

    int iterations = 0;
    const maxIterations = 1000;

    while (queue.isNotEmpty && found.length < maxTotalNodes && iterations < maxIterations) {
      iterations++;

      if (queue.length > maxQueueSize) {
        queue.removeRange(0, (queue.length - maxQueueSize ~/ 2).clamp(1, queue.length));
      }

      final (current, depth, isDirect) = queue.removeAt(0);

      if (current == null || depth > maxDepth) continue;

      if (current is String) {
        if (isDirect) {
          for (final uri in _extractUriLinks(current)) {
            if (!_isMetadataConfig(uri)) found.add(uri);
          }
        } else {
          if (depth <= 2) {
            for (final v in _collectTextVariants(current)) {
              for (final uri in _extractUriLinks(v)) {
                if (!_isMetadataConfig(uri)) found.add(uri);
              }
            }
          }
        }
        continue;
      }

      if (current is List) {
        final itemsToProcess = current.take(100);
        for (final item in itemsToProcess) {
          if (seen.add(item)) {
            queue.add((item, depth + 1, false));
          }
        }
        continue;
      }

      if (current is Map) {
        final map = <String, dynamic>{};
        current.forEach((k, v) {
          map[k.toString()] = v;
        });

        final uri = _proxyMapToUri(map);
        if (uri != null && !_isMetadataConfig(uri)) {
          found.add(uri);
        }

        var entriesAdded = 0;
        for (final entry in map.entries.take(50)) {
          final value = entry.value;
          if (value is String) {
            final isLikelyConfig = value.startsWith('vless://') ||
                value.startsWith('vmess://') ||
                value.startsWith('ss://') ||
                value.startsWith('trojan://') ||
                value.startsWith('http://') ||
                value.startsWith('https://');
            if (seen.add(value)) {
              queue.add((value, depth + 1, isLikelyConfig));
              entriesAdded++;
              if (entriesAdded >= 20) break;
            }
          } else if (seen.add(value)) {
            queue.add((value, depth + 1, false));
            entriesAdded++;
            if (entriesAdded >= 20) break;
          }
        }
      }
    }
  }

  // узлы неизвестного типа молча пропадали, и подписка на 20 серверов приезжала как 12
  @visibleForTesting
  static Map<String, int> unsupportedClashNodes(String content) {
    final counts = <String, int>{};
    for (final proxy in _extractYamlLikeProxies(content)) {
      if (_proxyMapToUri(proxy) != null) continue;
      final type = (proxy['type'] ?? proxy['protocol'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final key = type.isEmpty ? 'unknown' : type;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  static String? _skippedNodesSummary(Map<String, int> counts) {
    if (counts.isEmpty) return null;
    final parts = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return parts.map((e) => '${e.value} of type ${e.key}').join(', ');
  }

  static List<Map<String, dynamic>> _extractYamlLikeProxies(String content) {
    final parsed = CustomClashConfig.tryParse(content);
    if (parsed != null && parsed.proxies.isNotEmpty) return parsed.proxies;
    return _scanYamlLikeProxies(content);
  }

  static List<Map<String, dynamic>> _scanYamlLikeProxies(String content) {
    final lines = LineSplitter.split(content).toList();
    final proxies = <Map<String, dynamic>>[];
    Map<String, dynamic>? current;
    var inProxiesSection = false;

    for (final raw in lines) {
      final line = raw.replaceAll('\t', '  ');
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      if (trimmed.toLowerCase() == 'proxies:') {
        inProxiesSection = true;
        current = null;
        continue;
      }
      if (!inProxiesSection) continue;
      if (!line.startsWith(' ') && !trimmed.startsWith('- ')) {
        if (current != null && current.isNotEmpty) proxies.add(current);
        current = null;
        inProxiesSection = false;
        continue;
      }
      if (trimmed.startsWith('- ')) {
        if (current != null && current.isNotEmpty) proxies.add(current);
        current = <String, dynamic>{};
        final rest = trimmed.substring(2).trim();
        if (rest.contains(':')) {
          final idx = rest.indexOf(':');
          current[_cleanKey(rest.substring(0, idx))] = _cleanYamlValue(rest.substring(idx + 1));
        }
        continue;
      }
      if (current == null || !trimmed.contains(':')) continue;
      final idx = trimmed.indexOf(':');
      final key = _cleanKey(trimmed.substring(0, idx));
      final val = _cleanYamlValue(trimmed.substring(idx + 1));
      current[key] = val;
    }
    if (current != null && current.isNotEmpty) proxies.add(current);
    return proxies;
  }

  static String _cleanKey(String input) => input.trim().toLowerCase();

  static String _cleanYamlValue(String input) {
    final v = input.trim();
    if (v.length >= 2 &&
        ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'")))) {
      return v.substring(1, v.length - 1).trim();
    }
    return v;
  }

  // без вложенных карт ссылка теряет ключ REALITY и имя grpc-сервиса, собирается и молча не подключается
  static Map<String, String> _flattenClashProxy(Map<String, dynamic> raw) {
    final map = <String, String>{};
    String text(Object? v) {
      if (v == null) return '';
      if (v is List) return v.map((e) => e?.toString().trim() ?? '').join(',');
      return v.toString().trim();
    }

    void put(String key, Object? value) {
      final v = text(value);
      if (v.isNotEmpty && (map[key] ?? '').isEmpty) map[key] = v;
    }

    raw.forEach((k, v) {
      if (v is Map || v is List) {
        if (v is List) put(k.toLowerCase(), v);
        return;
      }
      put(k.toLowerCase(), v);
    });

    Map<String, dynamic>? nested(String key) {
      final value = raw[key];
      return value is Map ? value.cast<String, dynamic>() : null;
    }

    final ws = nested('ws-opts');
    if (ws != null) {
      put('path', ws['path']);
      put('ed', ws['max-early-data']);
      put('eh', ws['early-data-header-name']);
      final headers = ws['headers'];
      if (headers is Map) {
        for (final entry in headers.entries) {
          if (entry.key.toString().toLowerCase() == 'host') {
            put('host', entry.value);
          }
        }
      }
    }
    final http = nested('http-opts') ?? nested('h2-opts');
    if (http != null) {
      put('method', http['method']);
      final path = http['path'];
      put('path', path is List && path.isNotEmpty ? path.first : path);
      // у h2-opts host полем, у http-opts только заголовком (HTTPOptions в adapter/outbound/vmess.go)
      var host = http['host'] ?? http['Host'];
      final headers = http['headers'];
      if (host == null && headers is Map) {
        for (final entry in headers.entries) {
          if (entry.key.toString().toLowerCase() == 'host') host = entry.value;
        }
      }
      put('host', host is List && host.isNotEmpty ? host.first : host);
    }
    final grpc = nested('grpc-opts');
    if (grpc != null) put('servicename', grpc['grpc-service-name']);
    final reality = nested('reality-opts');
    if (reality != null) {
      put('pbk', reality['public-key']);
      put('sid', reality['short-id']);
      // spx не пишем: у Clash такого поля нет, раньше сюда уезжал флаг support-x25519mlkem768
    }
    final xhttp = nested('xhttp-opts');
    if (xhttp != null) {
      put('path', xhttp['path']);
      put('host', xhttp['host']);
      put('mode', xhttp['mode']);
    }
    final ech = nested('ech-opts');
    if (ech != null) put('ech', ech['config']);
    final plugin = nested('plugin-opts');
    if (plugin != null) {
      final name = text(raw['plugin']);
      if (name.isNotEmpty) {
        final parts = <String>[
          name == 'obfs' ? 'obfs-local' : name,
          if (name == 'obfs') ...[
            if (text(plugin['mode']).isNotEmpty) 'obfs=${text(plugin['mode'])}',
            if (text(plugin['host']).isNotEmpty)
              'obfs-host=${text(plugin['host'])}',
          ] else ...[
            if (plugin['tls'] == true) 'tls',
            if (text(plugin['mode']).isNotEmpty) 'mode=${text(plugin['mode'])}',
            if (text(plugin['host']).isNotEmpty) 'host=${text(plugin['host'])}',
            if (text(plugin['path']).isNotEmpty) 'path=${text(plugin['path'])}',
          ],
        ];
        // не put: в plugin уже лежит имя, а нужна вся строка
        if (parts.length > 1) map['plugin'] = parts.join(';');
      }
    }

    put('fp', raw['client-fingerprint']);
    put('sni', raw['servername']);
    return map;
  }

  static String? _proxyMapToUri(Map<String, dynamic> raw) {
    final map = _flattenClashProxy(raw);

    String pick(List<String> keys) {
      for (final k in keys) {
        final v = map[k];
        if (v != null && v.isNotEmpty) return v;
      }
      return '';
    }

    final type = pick(['type', 'protocol']).toLowerCase();
    final host = pick(['server', 'address', 'add', 'host']);
    final port = int.tryParse(pick(['port', 'server_port'])) ?? 0;
    final name = pick(['name', 'ps', 'remark', 'remarks']);
    final fragment = name.isNotEmpty ? '#${Uri.encodeComponent(name)}' : '';

    if (type == 'vmess' || (type.isEmpty && map.containsKey('uuid') && map.containsKey('cipher'))) {
      final id = pick(['uuid', 'id']);
      if (host.isEmpty || port <= 0 || id.isEmpty) return null;
      final query = {
        ..._clashTransportQuery(pick),
        ..._clashSecurityQuery(pick),
      };
      if (query['security'] == 'reality') return null;
      // security у vmess бывает шифром (auto, aes-128-gcm), поэтому TLS сперва по tls
      query['security'] = _normalizeTlsValue(pick(['tls', 'security']));
      final header = pick(['header', 'header_type']);
      if (header.isNotEmpty && header != 'none') {
        query.putIfAbsent('headerType', () => header);
      }
      return vmessJsonLink(
        name: name,
        host: host,
        port: port,
        uuid: id,
        alterId: int.tryParse(pick(['alterid', 'alter_id', 'aid'])) ?? 0,
        cipher: pick(['cipher', 'scy']),
        query: query,
      );
    }

    if (type == 'vless') {
      final id = pick(['uuid', 'id']);
      if (host.isEmpty || port <= 0 || id.isEmpty) return null;
      final query = <String, String>{
        ..._clashTransportQuery(pick),
        ..._clashSecurityQuery(pick),
      };
      final uri = Uri(
        scheme: 'vless',
        userInfo: id,
        host: host,
        port: port,
        queryParameters: query.isEmpty ? null : query,
        fragment: name,
      );
      return uri.toString();
    }

    if (type == 'trojan') {
      final password = pick(['password', 'passwd', 'pass']);
      if (host.isEmpty || port <= 0 || password.isEmpty) return null;
      final query = <String, String>{
        ..._clashTransportQuery(pick),
        ..._clashSecurityQuery(pick, defaultSecurity: 'tls'),
      };
      final uri = Uri(
        scheme: 'trojan',
        userInfo: password,
        host: host,
        port: port,
        queryParameters: query.isEmpty ? null : query,
        fragment: name,
      );
      return uri.toString();
    }

    if (type == 'ss' || type == 'shadowsocks') {
      final cipher = pick(['cipher', 'method']);
      final password = pick(['password', 'passwd', 'pass']);
      if (host.isEmpty || port <= 0 || cipher.isEmpty || password.isEmpty) return null;
      final userInfo = base64Url.encode(utf8.encode('$cipher:$password')).replaceAll('=', '');
      final query = <String, String>{
        if (pick(['plugin']).isNotEmpty) 'plugin': pick(['plugin']),
        if (pick(['udp-over-tcp']).toLowerCase() == 'true') 'uot': '1',
        if (pick(['udp-over-tcp-version']).isNotEmpty)
          'udp-over-tcp-version': pick(['udp-over-tcp-version']),
      };
      final tail = query.isEmpty
          ? ''
          : '?${Uri(queryParameters: query).query}';
      return 'ss://$userInfo@$host:$port$tail$fragment';
    }

    if (type == 'ssr' || type == 'shadowsocksr') {
      final cipher = pick(['cipher', 'method']);
      final password = pick(['password', 'passwd', 'pass']);
      final obfs = pick(['obfs']);
      final ssrProtocol = pick(['protocol']);
      if (host.isEmpty ||
          port <= 0 ||
          cipher.isEmpty ||
          password.isEmpty ||
          obfs.isEmpty ||
          ssrProtocol.isEmpty) {
        return null;
      }
      return SsrLink(
        host: host,
        port: port,
        protocol: ssrProtocol,
        method: cipher,
        obfs: obfs,
        password: password,
        obfsParam: pick(['obfs-param', 'obfsparam']),
        protocolParam: pick(['protocol-param', 'protoparam']),
        remarks: name,
      ).encode();
    }

    if (type == 'tuic') {
      final uuid = pick(['uuid']);
      final token = pick(['token']);
      final password = pick(['password']);
      final userInfo = uuid.isNotEmpty
          ? '${Uri.encodeComponent(uuid)}:${Uri.encodeComponent(password)}'
          : Uri.encodeComponent(token);
      if (host.isEmpty || port <= 0 || (uuid.isEmpty && token.isEmpty)) {
        return null;
      }
      final query = <String, String>{
        if (pick(['sni', 'servername']).isNotEmpty)
          'sni': pick(['sni', 'servername']),
        if (pick(['alpn']).isNotEmpty) 'alpn': pick(['alpn']),
        if (pick(['congestion-controller']).isNotEmpty)
          'congestion_control': pick(['congestion-controller']),
        if (pick(['udp-relay-mode']).isNotEmpty)
          'udp_relay_mode': pick(['udp-relay-mode']),
        if (pick(['disable-sni']).toLowerCase() == 'true') 'disable_sni': '1',
      };
      return Uri(
        scheme: 'tuic',
        userInfo: userInfo,
        host: host,
        port: port,
        queryParameters: query.isEmpty ? null : query,
        fragment: name.isEmpty ? null : name,
      ).toString();
    }

    if (type == 'anytls') {
      final password = pick(['password', 'passwd', 'pass']);
      if (host.isEmpty || port <= 0 || password.isEmpty) return null;
      final query = <String, String>{
        if (pick(['sni', 'servername']).isNotEmpty)
          'sni': pick(['sni', 'servername']),
        if (pick(['alpn']).isNotEmpty) 'alpn': pick(['alpn']),
        if (pick(['client-fingerprint']).isNotEmpty)
          'fp': pick(['client-fingerprint']),
        // у anytls пин сертификата зовётся hpkp
        if (pick(['fingerprint']).isNotEmpty) 'hpkp': pick(['fingerprint']),
      };
      return Uri(
        scheme: 'anytls',
        userInfo: password,
        host: host,
        port: port,
        queryParameters: query.isEmpty ? null : query,
        fragment: name.isEmpty ? null : name,
      ).toString();
    }

    if (type == 'mieru') {
      final username = pick(['username']);
      final password = pick(['password', 'passwd', 'pass']);
      final transport = pick(['transport']);
      final portRange = pick(['port-range']);
      if (host.isEmpty ||
          username.isEmpty ||
          transport.isEmpty ||
          (port <= 0 && portRange.isEmpty)) {
        return null;
      }
      final query = <String, String>{
        'port': portRange.isNotEmpty ? portRange : '$port',
        'protocol': transport,
        if (pick(['multiplexing']).isNotEmpty)
          'multiplexing': pick(['multiplexing']),
        if (pick(['handshake-mode']).isNotEmpty)
          'handshake-mode': pick(['handshake-mode']),
        if (pick(['traffic-pattern']).isNotEmpty)
          'traffic-pattern': pick(['traffic-pattern']),
      };
      return Uri(
        scheme: 'mierus',
        userInfo: '${Uri.encodeComponent(username)}:'
            '${Uri.encodeComponent(password)}',
        host: host,
        queryParameters: query,
        fragment: name.isEmpty ? null : name,
      ).toString();
    }

    // hysteria у Clash всегда первая версия, у второй свой тип
    if (type == 'hysteria') return null;
    if (type == 'hysteria2' || type == 'hy2') {
      final auth = pick(['auth', 'password', 'psk', 'auth_str', 'auth-str']);
      if (host.isEmpty || port <= 0 || auth.isEmpty) return null;
      const scheme = 'hy2';
      // hysteria-аутбаунд xray 26+ принимает только version 2
      final query = <String, String>{'auth': auth, 'version': '2'};
      final sni = pick(['sni', 'servername', 'server_name']);
      if (sni.isNotEmpty) query['sni'] = sni;
      final insecure = pick(['insecure', 'skip-cert-verify', 'allow_insecure']).toLowerCase();
      if (insecure == '1' || insecure == 'true') query['insecure'] = '1';
      final obfs = pick(['obfs']);
      if (obfs.isNotEmpty) query['obfs'] = obfs;
      final obfsPass = pick(['obfs-password', 'obfs_password', 'obfspassword']);
      if (obfsPass.isNotEmpty) query['obfs-password'] = obfsPass;
      final alpn = pick(['alpn']);
      if (alpn.isNotEmpty) query['alpn'] = alpn;
      final up = pick(['up', 'upmbps']);
      if (up.isNotEmpty) query['up'] = up;
      final down = pick(['down', 'downmbps']);
      if (down.isNotEmpty) query['down'] = down;
      final pin = pick(['pinSHA256', 'pinsha256', 'fingerprint']);
      if (pin.isNotEmpty) query['pinSHA256'] = pin;
      final ports = pick(['ports']);
      if (ports.isNotEmpty) query['mport'] = ports;
      final hop = pick(['hop-interval']);
      if (hop.isNotEmpty) query['hop-interval'] = hop;
      final uri = Uri(
        scheme: scheme,
        host: host,
        port: port,
        queryParameters: query,
        fragment: name.isNotEmpty ? name : null,
      );
      return uri.toString();
    }

    return null;
  }

  // type у Clash это протокол узла, в транспорт он не годится
  static Map<String, String> _clashTransportQuery(
    String Function(List<String>) pick,
  ) {
    final query = <String, String>{};
    final network = pick(['network', 'net']);
    if (network.isNotEmpty) query['type'] = network;
    final path = pick(['path']);
    if (path.isNotEmpty) query['path'] = path;
    final wsHost = pick(['host']);
    if (wsHost.isNotEmpty) query['host'] = wsHost;
    final serviceName = pick(['servicename', 'grpc-service-name']);
    if (serviceName.isNotEmpty) query['serviceName'] = serviceName;
    final mode = pick(['mode']);
    if (mode.isNotEmpty) query['mode'] = mode;
    // network: http у Clash это маскировка поверх tcp, в ссылке tcp и headerType=http
    if (network.toLowerCase() == 'http') {
      query['type'] = 'tcp';
      query['headerType'] = 'http';
      final method = pick(['method']);
      if (method.isNotEmpty) query['method'] = method;
    }
    final ed = pick(['ed', 'max-early-data']);
    if (ed.isNotEmpty) query['ed'] = ed;
    final eh = pick(['eh', 'early-data-header-name']);
    if (eh.isNotEmpty) query['eh'] = eh;
    return query;
  }

  static Map<String, String> _clashSecurityQuery(
    String Function(List<String>) pick, {
    String defaultSecurity = '',
  }) {
    final query = <String, String>{};
    final pbk = pick(['pbk', 'public-key']);
    final security = pick(['security', 'tls']);
    final normalized =
        security.isNotEmpty ? _normalizeTlsValue(security) : defaultSecurity;
    if (pbk.isNotEmpty) {
      query['security'] = 'reality';
      query['pbk'] = pbk;
      final sid = pick(['sid', 'short-id']);
      if (sid.isNotEmpty) query['sid'] = sid;
    } else if (normalized.isNotEmpty) {
      query['security'] = normalized;
    }
    final sni = pick(['sni', 'servername']);
    if (sni.isNotEmpty) query['sni'] = sni;
    final fp = pick(['fp', 'client-fingerprint']);
    if (fp.isNotEmpty) query['fp'] = fp;
    final flow = pick(['flow']);
    if (flow.isNotEmpty) query['flow'] = flow;
    final alpn = pick(['alpn']);
    if (alpn.isNotEmpty) query['alpn'] = alpn;
    // fingerprint у Clash это пин сертификата, отпечаток uTLS лежит в client-fingerprint
    final pin = pick(['fingerprint']);
    if (pin.isNotEmpty) query['pcs'] = pin;
    final verify = pick(['name-cert-verify']);
    if (verify.isNotEmpty) query['vcn'] = verify;
    final ech = pick(['ech']);
    if (ech.isNotEmpty) query['ech'] = ech;
    return query;
  }

  static String _normalizeTlsValue(String raw) {
    final v = raw.toLowerCase();
    if (v == '1' || v == 'true' || v == 'tls') return 'tls';
    if (v == 'reality') return 'reality';
    return 'none';
  }

  static List<String>? _extractConfigsFromHtml(String html) {
    final candidates = <String>[];

    final blockMatches = RegExp(
      r'<(?:pre|code|textarea)[^>]*>([\s\S]*?)</(?:pre|code|textarea)>',
      caseSensitive: false,
    ).allMatches(html);
    for (final m in blockMatches) {
      final v = m.group(1);
      if (v != null && v.trim().isNotEmpty) candidates.add(v);
    }

    final scriptMatches = RegExp(
      r'<script[^>]*>([\s\S]*?)</script>',
      caseSensitive: false,
    ).allMatches(html);
    for (final m in scriptMatches) {
      final v = m.group(1);
      if (v != null && v.trim().isNotEmpty) candidates.add(v);
    }

    final jsMatches = RegExp(
      r'''(?:payload|subscription|subdata|content|data)\s*[:=]\s*["']([\s\S]*?)["']''',
      caseSensitive: false,
    ).allMatches(html);
    for (final m in jsMatches) {
      final v = m.group(1);
      if (v != null && v.trim().isNotEmpty) candidates.add(v);
    }

    final base64Like = RegExp(
      r'[A-Za-z0-9+/_=\r\n-]{300,}',
      caseSensitive: false,
    ).allMatches(html);
    for (final m in base64Like) {
      final v = m.group(0);
      if (v != null && v.trim().isNotEmpty) candidates.add(v);
    }

    candidates.add(html);

    for (final raw in candidates) {
      final variants = <String>{
        raw,
        _htmlUnescape(raw),
        _jsUnescape(_htmlUnescape(raw)),
      };
      for (final variant in variants) {
        final cleaned = variant.replaceAll(RegExp(r'<[^>]+>'), ' ').trim();
        if (cleaned.isEmpty) continue;

        final directLinks = _extractUriLinks(cleaned);
        if (directLinks.isNotEmpty) return directLinks;

        // без рекурсивного _parseBody: в релизе он давал stack overflow
        final configs = _parseBodyNoRecursion(cleaned);
        if (configs.isNotEmpty) return configs;
      }
    }
    return null;
  }

  static List<String> _parseBodyNoRecursion(String content) {
    final original = content.trim();

    final custom = _extractCustomConfigs(original);
    if (custom.isNotEmpty) return custom;

    final singleDecoded = _tryDecodeBase64Flexible(original);
    if (singleDecoded != null && singleDecoded.trim().isNotEmpty) {
      final configs = _extractUrisDirectly(singleDecoded);
      if (configs.isNotEmpty) return configs;
      final customDecoded = _extractCustomConfigs(singleDecoded);
      if (customDecoded.isNotEmpty) return customDecoded;
    }

    if (singleDecoded != null) {
      final doubleDecoded = _tryDecodeBase64Flexible(singleDecoded);
      if (doubleDecoded != null && doubleDecoded.trim().isNotEmpty) {
        final configs = _extractUrisDirectly(doubleDecoded);
        if (configs.isNotEmpty) return configs;
      }
    }

    final directConfigs = _extractUrisDirectly(original);
    if (directConfigs.isNotEmpty) return directConfigs;

    return const [];
  }

  static List<String> _extractUrisDirectly(String text) {
    final lines = LineSplitter.split(text)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && _isValidConfig(l) && !_isMetadataConfig(l))
        .toList();
    return lines;
  }

  static List<String> _extractSubscriptionUrlsFromHtml(
    String html, {
    required String baseUrl,
  }) {
    final base = Uri.tryParse(baseUrl);
    if (base == null) return const [];

    final found = <String>{};
    final patterns = <RegExp>[
      RegExp(r'''(?:href|src|data-url)\s*=\s*["']([^"']+)["']''', caseSensitive: false),
      RegExp(r'''(?:fetch|axios\.get|open)\s*\(\s*["']([^"']+)["']''', caseSensitive: false),
      RegExp(r'''(?:window\.)?location(?:\.href)?\s*=\s*["']([^"']+)["']''', caseSensitive: false),
    ];

    for (final re in patterns) {
      for (final m in re.allMatches(html)) {
        final raw = (m.group(1) ?? '').trim();
        if (raw.isEmpty) continue;
        final unescaped = _htmlUnescape(raw).replaceAll(r'\/', '/');
        final resolved = base.resolve(unescaped).toString();
        final lower = resolved.toLowerCase();
        if (lower.endsWith('.js') ||
            lower.endsWith('.css') ||
            lower.endsWith('.png') ||
            lower.endsWith('.jpg') ||
            lower.endsWith('.svg') ||
            lower.contains('/login') ||
            lower.contains('/register')) {
          continue;
        }
        if (lower.contains('/sub') ||
            lower.contains('token=') ||
            lower.contains('subscription') ||
            lower.contains('/api/')) {
          found.add(resolved);
        }
      }
    }

    return found.take(8).toList();
  }

  Future<List<String>> _crawlHtmlForSubscriptionConfigs({
    required String html,
    required String pageUrl,
    CancelToken? cancelToken,
  }) async {
    final visited = <String>{pageUrl};
    var frontier = _extractSubscriptionUrlsFromHtml(html, baseUrl: pageUrl);
    const maxDepth = 2;
    const maxRequests = 12;
    var reqCount = 0;

    for (var depth = 0; depth < maxDepth && frontier.isNotEmpty; depth++) {
      final next = <String>[];
      for (final u in frontier) {
        if (reqCount >= maxRequests) break;
        if (!visited.add(u)) continue;
        if (!isSafeUrl(u)) continue;
        reqCount++;
        try {
          final resp = await _dio.get<String>(u, cancelToken: cancelToken);
          if (resp.statusCode != 200) continue;
          final body = (resp.data ?? '').trim();
          if (body.isEmpty) continue;

          final ctype = (resp.headers.value('content-type') ?? '').toLowerCase();
          final looksHtml = ctype.contains('text/html') ||
              body.startsWith('<!doctype html') ||
              body.startsWith('<html');
          if (!looksHtml) {
            try {
              final parsed = await _parseBodyOffThread(body);
              if (parsed.isNotEmpty) return parsed;
            } on Object {
              final extracted = _extractConfigsFromHtml(body);
              if (extracted != null && extracted.isNotEmpty) return extracted;
            }
          } else {
            final extracted = _extractConfigsFromHtml(body);
            if (extracted != null && extracted.isNotEmpty) return extracted;
            next.addAll(_extractSubscriptionUrlsFromHtml(body, baseUrl: u));
          }
        } on Object {
          // неудачный фолбэк-запрос не страшен
        }
      }
      frontier = next;
    }
    return const [];
  }

  static String _htmlUnescape(String input) {
    var s = input
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");

    s = s.replaceAllMapped(RegExp(r'&#(x?[0-9A-Fa-f]+);'), (m) {
      final token = m.group(1)!;
      final code = token.startsWith('x') || token.startsWith('X')
          ? int.tryParse(token.substring(1), radix: 16)
          : int.tryParse(token);
      if (code == null) return m.group(0)!;
      return String.fromCharCode(code);
    });
    return s;
  }

  static String _jsUnescape(String input) {
    var s = input
        .replaceAll(r'\/', '/')
        .replaceAll(r'\"', '"')
        .replaceAll(r"\'", "'")
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t');

    s = s.replaceAllMapped(RegExp(r'\\u([0-9A-Fa-f]{4})'), (m) {
      final code = int.tryParse(m.group(1)!, radix: 16);
      return code == null ? m.group(0)! : String.fromCharCode(code);
    });
    return s;
  }

  static List<String> _extractUriLinks(String text) {
    // пробел внутри ссылки допустим (имя сервера во fragment), режем по переводам строк.
    // lookbehind по символам схемы: иначе wss://host из html матчился как ss://host
    final matches = RegExp(
      r'''(?<![A-Za-z0-9+.\-])(?:vless|vmess|trojan|ss|ssr|hysteria2?|hy2|tuic|anytls|mierus)://(?:(?!(?:vless|vmess|trojan|ssr|ss|hysteria2?|hy2|tuic|anytls|mierus)://)[^\r\n<>"'])+''',
      caseSensitive: false,
    ).allMatches(text);
    final links = <String>[];
    for (final m in matches) {
      final raw = (m.group(0) ?? '').trim();
      if (raw.isEmpty) continue;
      final normalized = raw
          .replaceAll('&amp;', '&')
          .replaceAll('&#38;', '&')
          .replaceAll('\\/', '/');
      if (_isValidConfig(normalized)) {
        links.addAll(MieruLink.expand(normalized));
      }
    }
    return links.toSet().toList();
  }

  static String _parsableUri(String raw) {
    final lower = raw.trimLeft().toLowerCase();
    if (!lower.startsWith('hysteria2://') &&
        !lower.startsWith('hy2://') &&
        !lower.startsWith('hysteria://')) {
      return raw;
    }
    return HysteriaLinkParams.splitPorts(raw).$1;
  }

  static bool _isValidConfig(String s) {
    final lower = s.toLowerCase();
    // hysteria v1 не собирает ни одно ядро, а под общей схемой она выглядит рабочей
    if (HysteriaLinkParams.isV1(s)) return false;
    return lower.startsWith('vless://') ||
        lower.startsWith('vmess://') ||
        lower.startsWith('trojan://') ||
        lower.startsWith('ss://') ||
        lower.startsWith('ssr://') ||
        lower.startsWith('hysteria://') ||
        lower.startsWith('hysteria2://') ||
        lower.startsWith('hy2://') ||
        lower.startsWith('tuic://') ||
        lower.startsWith('anytls://') ||
        lower.startsWith('mierus://');
  }

  static bool _isMetadataConfig(String raw) {
    try {
      final uri = Uri.parse(raw);
      final host = uri.host.toLowerCase();
      if ((host == '0.0.0.0' || host == '::' || host == '::1') && uri.port <= 1) {
        return true;
      }
    } on Object {
      // не разобралось, смотрим по имени
    }

    final name = _extractConfigName(raw);
    if (name == null || name.isEmpty) return false;
    final n = name.toLowerCase();

    const markers = <String>[
      'пользователь',
      'осталось дней',
      'серверов доступно',
      'оплата',
      'трафик',
      'до:',
      'remaining',
      'days left',
      'expire',
      'expires',
      'traffic',
      'user:',
    ];
    for (final m in markers) {
      if (n.contains(m)) return true;
    }
    return false;
  }

  static bool _isHwidGateConfig(String raw) {
    final name = _extractConfigName(raw)?.toLowerCase() ?? '';
    if (name.isEmpty) return false;
    return name.contains('hwid') ||
        name.contains('turn on hwid') ||
        name.contains('enable hwid') ||
        name.contains('bind hwid');
  }

  static String? _detectProviderGateMessage(List<String> lines) {
    final names = <String>[];
    var hasNullRouteEndpoint = false;
    for (final line in lines) {
      if (!_isValidConfig(line)) continue;
      try {
        final uri = Uri.parse(line);
        final host = uri.host.toLowerCase();
        if ((host == '0.0.0.0' || host == '::' || host == '::1') && uri.port <= 1) {
          hasNullRouteEndpoint = true;
        }
      } on Object {
        // не разобралось
      }
      final name = (_extractConfigName(line) ?? '').toLowerCase();
      if (name.isNotEmpty) names.add(name);
    }
    if (names.isEmpty) return null;
    final joined = names.join(' | ');

    final trafficMarkers = <String>[
      'traffic limit reached',
      'quota exceeded',
      'out of traffic',
      'no traffic left',
      'лимит трафика',
      'трафик исчерпан',
      'закончился трафик',
      'достигнут лимит трафика',
      'трафик закончился',
    ];
    for (final marker in trafficMarkers) {
      if (joined.contains(marker)) {
        return 'Provider reports traffic limit reached for this subscription. '
            'Renew your plan or wait until quota resets.';
      }
    }

    final expiredMarkers = <String>[
      'subscription expired',
      'expired',
      'account expired',
      'истек',
      'истёк',
      'подписка истекла',
      'подписка истек',
    ];
    for (final marker in expiredMarkers) {
      if (joined.contains(marker)) {
        return 'Provider reports this subscription has expired.';
      }
    }

    final remnawaveMarkers = <String>[
      'remnawave',
      '→ remnawave',
      'service link',
      'service links',
      'null route',
    ];
    final hasRemnawaveMarker = remnawaveMarkers.any(joined.contains);
    final noHostsMarkers = <String>[
      'did you forget to add hosts',
      'no hosts found',
      'check hosts tab',
      'hosts tab',
    ];
    final hasNoHostsMarker = noHostsMarkers.any(joined.contains);
    if (hasNullRouteEndpoint && hasNoHostsMarker) {
      return 'Provider returned service links because no hosts are configured for this subscription. '
          'Open provider panel and add/assign hosts in the Hosts tab.';
    }
    if (hasNullRouteEndpoint && hasRemnawaveMarker) {
      return 'Provider returned service links (0.0.0.0:1) instead of real nodes. '
          'This usually means HWID is required but not bound/approved yet in provider panel.';
    }
    return null;
  }

  static String? _extractConfigName(String raw) {
    try {
      if (CustomXrayConfig.looksLikeJson(raw)) {
        final remarks = CustomXrayConfig.tryParse(raw)?.remarks ?? '';
        return remarks.isEmpty ? null : remarks;
      }

      if (raw.toLowerCase().startsWith('ssr://')) {
        final remarks = SsrLink.tryParse(raw)?.remarks.trim() ?? '';
        if (remarks.isNotEmpty) return remarks;
      }

      if (raw.startsWith('vmess://')) {
        final payload = raw.substring('vmess://'.length).trim();
        final decoded = _tryDecodeBase64Flexible(payload);
        if (decoded != null) {
          final j = jsonDecode(decoded);
          if (j is Map<String, dynamic>) {
            final ps = (j['ps'] ?? '').toString().trim();
            if (ps.isNotEmpty) return ps;
          }
        }
      }

      final uri = Uri.parse(_parsableUri(raw));
      final fragment = uri.fragment.trim();
      if (fragment.isEmpty) return null;
      return Uri.decodeComponent(fragment).trim();
    } on Object {
      return null;
    }
  }

  static ({int? usedBytes, int? totalBytes, DateTime? expiresAt}) _extractMetaFromBody(
    String content,
  ) {
    final remarks = <String>{};
    final original = content.trim();
    final candidates = <String>{original};

    final singleDecoded = _tryDecodeBase64Flexible(original);
    if (singleDecoded != null && singleDecoded.trim().isNotEmpty) {
      candidates.add(singleDecoded);
      final doubleDecoded = _tryDecodeBase64Flexible(singleDecoded);
      if (doubleDecoded != null && doubleDecoded.trim().isNotEmpty) {
        candidates.add(doubleDecoded);
      }
    }

    for (final candidate in candidates) {
      for (final line in LineSplitter.split(candidate)
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)) {
        if (!_isValidConfig(line)) continue;
        final name = _extractConfigName(line);
        if (name != null && name.isNotEmpty) remarks.add(name);
      }
    }

    int? usedBytes;
    int? totalBytes;
    DateTime? expiresAt;

    for (final remark in remarks) {
      final dateMatch = RegExp(r'(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})').firstMatch(remark);
      if (dateMatch != null && expiresAt == null) {
        final d = int.tryParse(dateMatch.group(1)!);
        final m = int.tryParse(dateMatch.group(2)!);
        var y = int.tryParse(dateMatch.group(3)!);
        if (d != null && m != null && y != null) {
          if (y < 100) y += 2000;
          try {
            expiresAt = DateTime(y, m, d, 23, 59, 59);
          } on Object {
            // дата битая
          }
        }
      }

      final trafficMatch = RegExp(
        r'(\d+(?:[.,]\d+)?)\s*(kb|mb|gb|tb|кб|мб|гб|тб)\s*[/|]\s*(\d+(?:[.,]\d+)?|∞|infinity|unlimited)\s*(kb|mb|gb|tb|кб|мб|гб|тб)?',
        caseSensitive: false,
      ).firstMatch(remark);
      if (trafficMatch != null) {
        usedBytes ??= _toBytes(trafficMatch.group(1), trafficMatch.group(2));
        final totalRaw = (trafficMatch.group(3) ?? '').toLowerCase();
        if (totalRaw == '∞' || totalRaw == 'infinity' || totalRaw == 'unlimited') {
          totalBytes ??= 0;
        } else {
          totalBytes ??= _toBytes(
            trafficMatch.group(3),
            trafficMatch.group(4) ?? trafficMatch.group(2),
          );
        }
      } else {
        final usedOnly = RegExp(
          r'(?:used|usage|трафик|израсходовано)\D*(\d+(?:[.,]\d+)?)\s*(kb|mb|gb|tb|кб|мб|гб|тб)',
          caseSensitive: false,
        ).firstMatch(remark);
        if (usedOnly != null) {
          usedBytes ??= _toBytes(usedOnly.group(1), usedOnly.group(2));
        }
      }
    }

    return (usedBytes: usedBytes, totalBytes: totalBytes, expiresAt: expiresAt);
  }

  static int? _toBytes(String? value, String? unitRaw) {
    if (value == null || unitRaw == null) return null;
    final v = double.tryParse(value.replaceAll(',', '.'));
    if (v == null) return null;
    final unit = unitRaw.toLowerCase();
    final multiplier = switch (unit) {
      'kb' || 'кб' => 1024.0,
      'mb' || 'мб' => 1024.0 * 1024.0,
      'gb' || 'гб' => 1024.0 * 1024.0 * 1024.0,
      'tb' || 'тб' => 1024.0 * 1024.0 * 1024.0 * 1024.0,
      _ => 0.0,
    };
    if (multiplier == 0.0) return null;
    return (v * multiplier).round();
  }

  Future<UpdateResult> updateSubscription(Subscription sub,
      {CancelToken? cancelToken}) async {
    try {
      final result = await fetchRaw(
        sub.url,
        cancelToken: cancelToken,
        userAgent: sub.userAgent,
        identity: sub.fetchIdentity,
      );

      final activeId = _storage.getActiveServerId();
      final oldServers = (await _storage.getServers())
          .where((s) => s.subscriptionId == sub.id)
          .toList();

      final oldByStableKey = <String, ServerItem>{
        for (final s in oldServers) _stableKey(s.config): s,
      };

      // дубли конфигов дали бы два сервера с одним id и duplicate ValueKey в списке
      final uniqueConfigs = result.configs.toSet().toList();

      // близкие конфиги могут сойтись на одном stable-ключе, второму новый id
      final usedOldIds = <String>{};
      final matched = uniqueConfigs.map((config) {
        final exactMatch = oldServers.cast<ServerItem?>().firstWhere(
              (s) => s?.config == config,
          orElse: () => null,
        );
        if (exactMatch != null && usedOldIds.add(exactMatch.id)) {
          return exactMatch;
        }

        final key = _stableKey(config);
        final stableMatch = oldByStableKey[key];
        if (stableMatch != null && usedOldIds.add(stableMatch.id)) {
          // правленный руками конфиг не затираем, пока сервер тот же
          if (stableMatch.configOverridden) return stableMatch;
          return stableMatch.copyWith(config: config);
        }
        return null;
      }).toList();

      // провайдер сменил адрес, uuid или первый выход json-сервера: узнаём по имени и протоколу,
      // иначе сервер приходил новым, без пинга и выбранным сервером переставал быть
      String nameKey(String config) {
        final probe = ServerItem.fromRaw(config);
        return '${probe.protocol}|${probe.derivedName}';
      }
      final unmatchedOld = <String, List<ServerItem>>{};
      for (final s in oldServers) {
        if (usedOldIds.contains(s.id) || s.configOverridden) continue;
        unmatchedOld.putIfAbsent(nameKey(s.config), () => []).add(s);
      }
      final unmatchedNew = <String, int>{};
      for (var i = 0; i < matched.length; i++) {
        if (matched[i] != null) continue;
        final key = nameKey(uniqueConfigs[i]);
        unmatchedNew[key] = (unmatchedNew[key] ?? 0) + 1;
      }

      ServerItem byName(String config) {
        final key = nameKey(config);
        final same = unmatchedOld[key];
        // два сервера с одним именем по имени не различить
        if (same != null &&
            same.length == 1 &&
            unmatchedNew[key] == 1 &&
            usedOldIds.add(same.single.id)) {
          return same.single.copyWith(config: config);
        }
        return ServerItem.fromRaw(config, subscriptionId: sub.id);
      }

      final servers = [
        for (var i = 0; i < matched.length; i++)
          matched[i] ?? byName(uniqueConfigs[i]),
      ];

      // правленные руками серверы, разошедшиеся по ключу, рефреш не стирает
      servers.addAll(
        oldServers.where(
          (s) => s.configOverridden && !usedOldIds.contains(s.id),
        ),
      );

      await _storage.replaceServersBySubscription(sub.id, servers);

      if (activeId != null) {
        final wasInThisSub = oldServers.any((s) => s.id == activeId);
        final stillExists  = servers.any((s) => s.id == activeId);
        if (wasInThisSub && !stillExists) {
          await _storage.setActiveServerId(null);
        }
      }

      final wasFirstFetch = sub.lastUpdatedAt == null;
      final updated = sub
          .copyWith(
            lastUpdatedAt: DateTime.now(),
            usedBytes: result.usedBytes,
            totalBytes: result.totalBytes,
            expiresAt: result.expiresAt,
            serverCount: servers.length,
            // закреплённый UA не сохраняем как рабочий, иначе после выключения подмены он действовал бы молча
            userAgent: sub.fetchIdentity.activeUserAgent != null
                ? null
                : result.usedUserAgent,
          )
          .withProfileHeaders(
            title: result.profile.title,
            announce: result.profile.announce,
            supportUrl: result.profile.supportUrl,
            webPageUrl: result.profile.webPageUrl,
            // интервал панели только при первой загрузке, дальше это выбор человека
            updateIntervalHours:
                wasFirstFetch ? result.profile.updateIntervalHours : null,
          );
      await _storage.upsertSubscription(updated);

      return UpdateResult(
        success: true,
        serverCount: servers.length,
        subscription: updated,
      );
    } catch (e, st) {
      // только хост: в полном URL секретный токен
      final host = Uri.tryParse(sub.url)?.host ?? '<unparsable url>';
      AppLogger.instance.error(
        'Subscription update failed for $host',
        error: e,
        stackTrace: st,
      );
      return UpdateResult(
        success: false,
        error: e.toString(),
        subscription: sub,
      );
    }
  }

  Future<List<UpdateResult>> updateAll() async {
    final subs = await _storage.getSubscriptions();
    final toUpdate = subs.where((s) => s.autoUpdate).toList();
    final results = <UpdateResult>[];

    for (var i = 0; i < toUpdate.length; i += 3) {
      final batch = toUpdate.skip(i).take(3).toList();
      final batchResults = await Future.wait(
        batch.map(updateSubscription),
        eagerError: false,
      );
      results.addAll(batchResults);
    }
    return results;
  }

  Future<List<Subscription>> getDueForUpdate({
    Duration defaultInterval = const Duration(hours: 12),
  }) async {
    final subs = await _storage.getSubscriptions();
    final now = DateTime.now();
    return subs.where((s) {
      if (!s.autoUpdate) return false;
      final interval = s.updateIntervalHours > 0
          ? Duration(hours: s.updateIntervalHours)
          : defaultInterval;
      final last = s.lastUpdatedAt;
      if (last == null) return true;
      return now.difference(last) >= interval;
    }).toList();
  }
}
