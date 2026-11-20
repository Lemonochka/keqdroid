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
import '../services/auto_select_home.dart';
import '../services/auto_server_select.dart';
import '../services/storage_service.dart';
import '../services/subscription_body_parser.dart';
import '../utils/clash_template.dart';
import '../utils/custom_clash_config.dart';
import '../utils/custom_xray_config.dart';
import '../utils/identity_presets.dart';
import '../utils/protocol_filter.dart';
import '../utils/provider_routing.dart';
import '../utils/routing_profiles.dart';
import '../utils/same_server_key.dart';
import '../utils/singbox_outbounds.dart';
import '../utils/subscription_url.dart';
import '../utils/ssr_uri.dart';
import '../core/exceptions.dart';

class SubscriptionProfileHeaders {
  final String? title;
  final String? announce;
  final String? supportUrl;
  final String? webPageUrl;
  final int? updateIntervalHours;
  final String? newUrl;
  final String? newDomain;
  final String? fallbackUrl;
  final bool remindExpiry;

  const SubscriptionProfileHeaders({
    this.title,
    this.announce,
    this.supportUrl,
    this.webPageUrl,
    this.updateIntervalHours,
    this.newUrl,
    this.newDomain,
    this.fallbackUrl,
    this.remindExpiry = false,
  });

  static const empty = SubscriptionProfileHeaders();

  bool get isEmpty =>
      title == null &&
      announce == null &&
      supportUrl == null &&
      webPageUrl == null &&
      updateIntervalHours == null &&
      newUrl == null &&
      newDomain == null &&
      fallbackUrl == null &&
      !remindExpiry;

  static final _bodyLine = RegExp(
    r'^#\s*(new-url|new-domain|fallback-url|notification-subs-expire)\s*:?\s*(\S+)\s*$',
    caseSensitive: false,
    multiLine: true,
  );

  // Happ пишет их и в тело строкой #new-url ..., так шлют подписки без своих заголовков; тело сильнее заголовка
  SubscriptionProfileHeaders withBody(String body) {
    final found = <String, String>{};
    final decoded = SubscriptionBodyParser.tryDecodeBase64Flexible(body.trim());
    for (final text in [body, ?decoded]) {
      for (final m in _bodyLine.allMatches(text)) {
        found.putIfAbsent(m.group(1)!.toLowerCase(), () => m.group(2)!);
      }
    }
    if (found.isEmpty) return this;
    final remind = found['notification-subs-expire'];
    return SubscriptionProfileHeaders(
      title: title,
      announce: announce,
      supportUrl: supportUrl,
      webPageUrl: webPageUrl,
      updateIntervalHours: updateIntervalHours,
      newUrl: SubscriptionService._sanitizeUrl(found['new-url']) ?? newUrl,
      newDomain: found['new-domain'] ?? newDomain,
      fallbackUrl:
          SubscriptionService._sanitizeUrl(found['fallback-url']) ??
          fallbackUrl,
      remindExpiry: remind == null
          ? remindExpiry
          : SubscriptionService._isOn(remind),
    );
  }
}

class SubscriptionFetchResult {
  final List<String> configs;
  final int? usedBytes;
  final int? totalBytes;
  final DateTime? expiresAt;

  final String? usedUserAgent;

  final SubscriptionProfileHeaders profile;

  final ProviderRouting? routing;

  final String? clashTemplate;

  const SubscriptionFetchResult({
    required this.configs,
    required this.usedBytes,
    required this.totalBytes,
    required this.expiresAt,
    required this.usedUserAgent,
    required this.profile,
    this.routing,
    this.clashTemplate,
  });
}

class UpdateResult {
  final bool success;
  final int serverCount;
  final String? error;
  final Subscription subscription;

  final bool routingChanged;

  const UpdateResult({
    required this.success,
    this.serverCount = 0,
    this.error,
    required this.subscription,
    this.routingChanged = false,
  });
}

class SubscriptionService {
  final StorageService _storage;
  final Dio _dio;

  final LocalProxyPortResolver? _localProxyPort;
  String? _cachedHwid;
  String? _cachedDeviceModel;
  static const MethodChannel _platform = MethodChannel('keqdroid_vpn_channel');

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
  }) : _localProxyPort = localProxyPort,
       _dio = dio ?? _buildDio(localProxyPort: localProxyPort);

  // при включённом VPN только через локальный инбаунд: пакет приложения исключён из TUN
  static Dio _buildDio({LocalProxyPortResolver? localProxyPort}) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'User-Agent': browserUserAgent,
          'Accept': '*/*',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      ),
    );

    if (localProxyPort != null) {
      configureDioForLocalVpnProxy(dio, localProxyPort);
    }

    return dio;
  }

  static const _maxBodyLength = 10 * 1024 * 1024;

  static const _blockedHostnames = {
    'metadata.google.internal',
    '169.254.169.254', // AWS/GCP/Azure IMDS
    'fd00:ec2::254', // AWS IMDSv2 IPv6
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
      if (b[0] == 100 && b[1] >= 64 && b[1] <= 127) {
        return true; // CGNAT 100.64/10
      }
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

      // Uri.parse не берёт порт вида host:20000-20050, и ключ уходил бы в запасной вариант, меняясь вместе с именем
      final uri = Uri.parse(SubscriptionBodyParser.parsableUri(rawConfig));
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

      // из сырой строки: uri.host портит регистр base64, и ключ уходил бы в запасной вариант вместе с именем
      if (rawConfig.startsWith('vmess://')) {
        try {
          final payload = rawConfig.substring('vmess://'.length);
          final decoded = SubscriptionBodyParser.tryDecodeBase64Flexible(
            payload,
          );
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
      if (schemeLower == 'hysteria' ||
          schemeLower == 'hysteria2' ||
          schemeLower == 'hy2') {
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

  Future<SubscriptionFetchResult> fetchRaw(
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

    // настройку читаем на каждый запрос: в фоновых изолятах значение по умолчанию расходится с переключателем
    final shareHwid = (await _storage.getSettings()).shareDeviceHwid;
    // выключенный тумблер HWID главнее подмены
    final hwid = shareHwid
        ? await _getOrCreateHwid(override: identity.activeHwid)
        : null;
    final hwidHeaders = hwid != null
        ? await _buildRemnawaveHeaders(
            hwid,
            overrideOs: identity.activeDeviceOs,
            overrideModel: identity.activeDeviceModel,
            overrideOsVersion: identity.activeOsVersion,
          )
        : const <String, String>{};
    // закреплённый UA не перебираем, иначе подмена схлопнется в наш; кириллица в заголовке роняет dart:io
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
        routing: result.routing,
        clashTemplate: result.clashTemplate,
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

  Future<SubscriptionFetchResult> _fetchWithRetry(
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
    // свой UA из сохранённого не берём: в нём версия с первой загрузки, панель видела keqdroid/0.8.7 на 0.34.1
    final ownSaved =
        savedUserAgent == 'keqdroid' ||
        (savedUserAgent?.startsWith('keqdroid/') ?? false);
    final initialUa =
        pinnedUserAgent ??
        ((savedUserAgent != null && savedUserAgent.isNotEmpty && !ownSaved)
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
        throw SubscriptionFetchException(
          'HTTP ${response.statusCode}',
          url: url,
        );
      }

      final body = response.data ?? '';
      if (body.length > _maxBodyLength) {
        throw SubscriptionFetchException(
          'Response too large (>10MB)',
          url: url,
        );
      }
      final contentType =
          response.headers.value('content-type')?.toLowerCase() ?? '';

      int? usedBytes, totalBytes;
      DateTime? expiresAt;

      final headerMetaInitial = _parseUserInfoHeader(response.headers);
      profile = _parseProfileHeaders(response.headers);
      usedBytes = headerMetaInitial.usedBytes;
      totalBytes = headerMetaInitial.totalBytes;
      expiresAt = headerMetaInitial.expiresAt;

      var looksLikeHtml =
          contentType.contains('text/html') ||
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
          final uaType = (uaResponse.headers.value('content-type') ?? '')
              .toLowerCase();
          looksLikeHtml =
              uaType.contains('text/html') ||
              effectiveBody.trimLeft().startsWith('<!doctype html') ||
              effectiveBody.trimLeft().startsWith('<html');
          usedUserAgent =
              uaResponse.requestOptions.headers['User-Agent'] as String?;
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
        configs =
            SubscriptionBodyParser.extractConfigsFromHtml(effectiveBody) ??
            const [];
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
      final summary = SubscriptionBodyParser.skippedNodesSummary(
        CustomClashConfig.looksLikeClash(effectiveBody)
            ? SubscriptionBodyParser.unsupportedClashNodes(effectiveBody)
            : SingboxOutbounds.translate(effectiveBody).skipped,
      );
      if (summary != null) {
        AppLogger.instance.warn(
          'Subscription: skipped nodes this client cannot run: $summary',
        );
      }

      if (usedBytes == null || totalBytes == null || expiresAt == null) {
        final meta = SubscriptionBodyParser.extractMetaFromBody(effectiveBody);
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
        profile: profile.withBody(effectiveBody),
        routing: _routingOf(response.headers, effectiveBody),
        clashTemplate: await _templateOffThread(effectiveBody),
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
          throw SubscriptionFetchException(fe.message, url: url, cause: fe);
        }
      }

      // сбой сокета или TLS посреди обмена dio отдаёт как unknown, он разовый
      final isRetryable =
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError ||
          (e.type == DioExceptionType.unknown && e.error is IOException);

      if (isRetryable && attempt == 0) {
        await Future<void>.delayed(const Duration(seconds: 2));
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

  Future<SubscriptionFetchResult?> _tryParseFromErrorResponse(
    DioException e,
  ) async {
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
      final configs = SubscriptionBodyParser.parseBody(body);
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
        profile: _parseProfileHeaders(response.headers).withBody(body),
        routing: _routingOf(response.headers, body),
        clashTemplate: _templateOf(body),
      );
    } on Object {
      return null;
    }
  }

  Future<SubscriptionFetchResult?> _tryParseWithClientUserAgents(
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
    if (body.length > _maxBodyLength) {
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
    final bodyMeta = SubscriptionBodyParser.extractMetaFromBody(body);
    return SubscriptionFetchResult(
      configs: configs,
      usedBytes: headerMeta.usedBytes ?? bodyMeta.usedBytes,
      totalBytes: headerMeta.totalBytes ?? bodyMeta.totalBytes,
      expiresAt: headerMeta.expiresAt ?? bodyMeta.expiresAt,
      usedUserAgent: response.requestOptions.headers['User-Agent'] as String?,
      profile: _parseProfileHeaders(response.headers).withBody(body),
      routing: _routingOf(response.headers, body),
      clashTemplate: _templateOf(body),
    );
  }

  Future<SubscriptionFetchResult?> _tryFetchWithHttpClientFallback(
    String url, {
    required String? hwid,
    Map<String, String>? hwidHeaders,
    String? pinnedUserAgent,
  }) async {
    final effectiveHwidHeaders =
        hwidHeaders ??
        (hwid == null
            ? const <String, String>{}
            : await _buildRemnawaveHeaders(hwid));
    final candidates = _fallbackUrlCandidates(url, hwid);
    FormatException? lastFormatError;
    for (final candidate in candidates) {
      HttpClient? client;
      try {
        client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
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
            (resp.headers.contentType?.mimeType ??
                    dioLikeHeaders.value('content-type') ??
                    '')
                .toLowerCase();
        final looksLikeHtml =
            contentType.contains('text/html') ||
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
          configs =
              SubscriptionBodyParser.extractConfigsFromHtml(body) ?? const [];
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
            configs =
                SubscriptionBodyParser.extractConfigsFromHtml(body) ?? const [];
            if (configs.isEmpty) rethrow;
          }
        }
        if (configs.isEmpty) continue;
        final headerMeta = _parseUserInfoHeader(dioLikeHeaders);
        final bodyMeta = SubscriptionBodyParser.extractMetaFromBody(body);
        return SubscriptionFetchResult(
          configs: configs,
          usedBytes: headerMeta.usedBytes ?? bodyMeta.usedBytes,
          totalBytes: headerMeta.totalBytes ?? bodyMeta.totalBytes,
          expiresAt: headerMeta.expiresAt ?? bodyMeta.expiresAt,
          usedUserAgent: null,
          profile: _parseProfileHeaders(dioLikeHeaders).withBody(body),
          routing: _routingOf(dioLikeHeaders, body),
          clashTemplate: _templateOf(body),
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
    } on Object catch (e) {
      AppLogger.instance.debug('Subscription body not decompressed', error: e);
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

  Options _hwidOptions(Map<String, String> headers) =>
      Options(headers: headers);

  // подставной HWID не кэшируем и не сохраняем, иначе он станет HWID устройства для всех подписок
  Future<String> _getOrCreateHwid({String? override}) async {
    final custom = override?.trim().toLowerCase();
    if (custom != null && custom.isNotEmpty) return custom;

    if (_cachedHwid != null && _cachedHwid!.isNotEmpty) return _cachedHwid!;

    String? androidId;
    try {
      androidId = (await _platform.invokeMethod<String>(
        'getAndroidId',
      ))?.trim().toLowerCase();
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
    final os =
        _trimmedOrNull(overrideOs) ??
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
    _cachedDeviceModel = Platform.isAndroid
        ? 'Android Device'
        : 'Unknown Device';
    return _cachedDeviceModel!;
  }

  void _throwIfRemnawaveHwidHeadersIndicateError(
    Headers headers, {
    required String url,
  }) {
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
    final maxReached =
        headers.value('x-hwid-max-devices-reached')?.toLowerCase() == 'true' ||
        headers.value('x-hwid-limit')?.toLowerCase() == 'true';
    if (maxReached) {
      throw SubscriptionFetchException(
        'Remnawave device limit reached for this subscription. Remove old device in panel or raise limit.',
        url: url,
      );
    }
  }

  @visibleForTesting
  static SubscriptionProfileHeaders parseProfileHeadersForTest(
    Headers headers,
  ) => _parseProfileHeaders(headers);

  // в теле сильнее, чем в заголовке, как у остальных метаданных Happ
  static ProviderRouting? _routingOf(Headers headers, String body) =>
      providerRoutingInBody(body) ??
      providerRoutingFromHeaders((name) => headers.value(name));

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
      webPageUrl: _sanitizeUrl(
        pick(['profile-web-page-url', 'profile-webpage-url']),
      ),
      updateIntervalHours: (interval != null && interval > 0) ? interval : null,
      newUrl: _sanitizeUrl(pick(['new-url'])),
      newDomain: pick(['new-domain']),
      fallbackUrl: _sanitizeUrl(pick(['fallback-url'])),
      remindExpiry: _isOn(pick(['notification-subs-expire'])),
    );
  }

  // у Happ включает true или 1, любое другое значение выключает
  static bool _isOn(String? raw) {
    final v = raw?.trim().toLowerCase();
    return v == '1' || v == 'true';
  }

  // голый base64 только если раскодировался в осмысленный текст: Announce тоже валидный base64
  static String? _decodeHeaderText(String? raw) {
    if (raw == null || raw.isEmpty) return null;

    String? tryDecode(String s) {
      var normalized = s
          .replaceAll(RegExp(r'\s'), '')
          .replaceAll('-', '+')
          .replaceAll('_', '/');
      if (normalized.isEmpty) return null;
      final pad = normalized.length % 4;
      if (pad != 0) {
        normalized = normalized.padRight(normalized.length + (4 - pad), '=');
      }
      try {
        final bytes = base64.decode(normalized);
        if (bytes.isEmpty) return null;
        final text = utf8.decode(bytes, allowMalformed: false).trim();
        if (text.isEmpty) return null;
        if (text.runes.any((r) => r < 0x20 && r != 0x0A && r != 0x09)) {
          return null;
        }
        return text;
      } catch (_) {
        return null;
      }
    }

    const prefix = 'base64:';
    if (raw.toLowerCase().startsWith(prefix)) {
      return tryDecode(raw.substring(prefix.length)) ??
          raw.substring(prefix.length);
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

  static ({int? usedBytes, int? totalBytes, DateTime? expiresAt})
  _parseUserInfoHeader(Headers headers) {
    final userInfo =
        headers.value('x-subscription-userinfo') ??
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
    final usedBytes = (upload != null || download != null)
        ? (upload ?? 0) + (download ?? 0)
        : null;
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
        final isHtml =
            type.contains('text/html') ||
            body.startsWith('<!doctype html') ||
            body.startsWith('<html');
        if (!isHtml) return resp;
      } on Object catch (e) {
        AppLogger.instance.debug(
          'Subscription fetch with UA $ua failed',
          error: e,
        );
      }
    }
    return null;
  }

  @visibleForTesting
  static String stableKeyForTest(String rawConfig) => _stableKey(rawConfig);

  static Future<List<String>> _parseBodyOffThread(String content) =>
      compute(SubscriptionBodyParser.parseBody, content);

  static String? _encodeTemplate(String body) =>
      ClashTemplate.fromBody(body)?.encode();

  // шаблон довесок к серверам: его ошибка не должна ронять обновление подписки
  static String? _templateOf(String body) {
    try {
      return _encodeTemplate(body);
    } catch (e) {
      AppLogger.instance.warn('Clash template not parsed: $e');
      return null;
    }
  }

  static Future<String?> _templateOffThread(String body) async {
    if (!CustomClashConfig.looksLikeClash(body)) return null;
    try {
      return await compute(_encodeTemplate, body);
    } catch (e) {
      AppLogger.instance.warn('Clash template not parsed: $e');
      return null;
    }
  }

  Future<List<String>> _crawlHtmlForSubscriptionConfigs({
    required String html,
    required String pageUrl,
    CancelToken? cancelToken,
  }) async {
    final visited = <String>{pageUrl};
    var frontier = SubscriptionBodyParser.extractSubscriptionUrlsFromHtml(
      html,
      baseUrl: pageUrl,
    );
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

          final ctype = (resp.headers.value('content-type') ?? '')
              .toLowerCase();
          final looksHtml =
              ctype.contains('text/html') ||
              body.startsWith('<!doctype html') ||
              body.startsWith('<html');
          if (!looksHtml) {
            try {
              final parsed = await _parseBodyOffThread(body);
              if (parsed.isNotEmpty) return parsed;
            } on Object {
              final extracted = SubscriptionBodyParser.extractConfigsFromHtml(
                body,
              );
              if (extracted != null && extracted.isNotEmpty) return extracted;
            }
          } else {
            final extracted = SubscriptionBodyParser.extractConfigsFromHtml(
              body,
            );
            if (extracted != null && extracted.isNotEmpty) return extracted;
            next.addAll(
              SubscriptionBodyParser.extractSubscriptionUrlsFromHtml(
                body,
                baseUrl: u,
              ),
            );
          }
        } on Object catch (e) {
          AppLogger.instance.debug(
            'Subscription fallback address failed',
            error: e,
          );
        }
      }
      frontier = next;
    }
    return const [];
  }

  // окно из трея будит автообновление провайдера и DesktopBackgroundService разом, и подписку качали дважды
  static final _inFlight = <String, Future<UpdateResult>>{};

  Future<UpdateResult> updateSubscription(
    Subscription sub, {
    CancelToken? cancelToken,
  }) {
    if (cancelToken != null) return _update(sub, cancelToken: cancelToken);
    final key = '${sub.id}\n${sub.url}\n${sub.userAgent}';
    return _inFlight[key] ??= _update(sub).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  Future<SubscriptionFetchResult> _fetchFor(
    Subscription sub,
    String url,
    CancelToken? cancelToken,
  ) => fetchRaw(
    url,
    cancelToken: cancelToken,
    userAgent: sub.userAgent,
    identity: sub.fetchIdentity,
  );

  // запасной адрес провайдера только читаем: основной остаётся прежним, вдруг он вернётся
  Future<SubscriptionFetchResult> _fetchOrFallback(
    Subscription sub,
    CancelToken? cancelToken,
  ) async {
    try {
      return await _fetchFor(sub, sub.url, cancelToken);
    } catch (e, st) {
      final fallback = sub.fallbackUrl;
      if (fallback == null ||
          fallback == sub.url ||
          (cancelToken?.isCancelled ?? false)) {
        rethrow;
      }
      AppLogger.instance.warn(
        'Subscription main address failed, trying the fallback one '
        '(${Uri.tryParse(fallback)?.host ?? '?'})',
      );
      try {
        return await _fetchFor(sub, fallback, cancelToken);
      } catch (_) {
        Error.throwWithStackTrace(e, st);
      }
    }
  }

  // Переезд по new-url и new-domain: та же подписка с тем же id, меняется только адрес, поэтому карточка,
  // серверы, профиль и HWID остаются. Новый адрес сперва проверяем, чтобы сломанный переезд не увёл подписку в никуда
  Future<({SubscriptionFetchResult result, String url})> _followMove(
    Subscription sub,
    SubscriptionFetchResult result,
    CancelToken? cancelToken,
  ) async {
    final target = movedSubscriptionUrl(
      sub.url,
      newUrl: result.profile.newUrl,
      newDomain: result.profile.newDomain,
    );
    if (target == null) return (result: result, url: sub.url);
    final key = normalizeSubscriptionUrl(target);
    final taken = (await _storage.getSubscriptions()).any(
      (s) => s.id != sub.id && normalizeSubscriptionUrl(s.url) == key,
    );
    final host = Uri.tryParse(target)?.host ?? '?';
    if (taken) {
      AppLogger.instance.warn(
        'Subscription move to $host skipped: already added',
      );
      return (result: result, url: sub.url);
    }
    try {
      final moved = await _fetchFor(sub, target, cancelToken);
      AppLogger.instance.info('Subscription moved to $host');
      return (result: moved, url: target);
    } catch (e) {
      AppLogger.instance.warn('Subscription move to $host failed, staying: $e');
      return (result: result, url: sub.url);
    }
  }

  Future<UpdateResult> _update(
    Subscription sub, {
    CancelToken? cancelToken,
  }) async {
    try {
      final fetched = await _fetchOrFallback(sub, cancelToken);
      final move = await _followMove(sub, fetched, cancelToken);
      final result = move.result;

      final activeId = _storage.getActiveServerId();
      final oldServers = (await _storage.getServers())
          .where((s) => s.subscriptionId == sub.id)
          .toList();

      final oldByStableKey = <String, ServerItem>{
        for (final s in oldServers) _stableKey(s.config): s,
      };

      // точный дубль давал два сервера с одним id и duplicate ValueKey в списке;
      // выбранная или помеченная копия остаётся вместо первой, иначе выбор слетал бы при обновлении
      final activeConfig = oldServers
          .where((s) => s.id == activeId)
          .firstOrNull
          ?.config;
      final marked = {
        for (final s in oldServers)
          if (s.isPinned || s.customName != null || s.autoSkip) s.config,
      };
      final sifted = siftProtocols(
        withoutNameCopies(
          result.configs,
          rank: (c) => c == activeConfig ? 2 : (marked.contains(c) ? 1 : 0),
        ),
        sub.excludedProtocols,
      );
      final uniqueConfigs = sifted.kept;

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

      // правленные руками серверы, разошедшиеся по ключу, обновление не стирает
      servers.addAll(
        oldServers.where(
          (s) =>
              s.configOverridden &&
              !usedOldIds.contains(s.id) &&
              !sub.excludedProtocols.contains(protocolFilterKey(s.protocol)),
        ),
      );

      await _storage.replaceServersBySubscription(sub.id, servers);
      // серверы уже записаны: без шаблона они работают узлами, как раньше
      try {
        await _storage.setClashTemplate(sub.id, result.clashTemplate);
      } catch (e, st) {
        AppLogger.instance.warn(
          'Clash template not saved',
          error: e,
          stackTrace: st,
        );
      }

      if (activeId != null) {
        final wasInThisSub = oldServers.any((s) => s.id == activeId);
        final stillExists = servers.any((s) => s.id == activeId);
        if (wasInThisSub && !stillExists) {
          await _storage.setActiveServerId(
            await _autoSelectReplacement(sub, activeId, oldServers, servers),
          );
        }
      }

      final wasFirstFetch = sub.lastUpdatedAt == null;
      final updated = sub
          .copyWith(
            url: move.url,
            lastUpdatedAt: DateTime.now(),
            usedBytes: result.usedBytes,
            totalBytes: result.totalBytes,
            expiresAt: result.expiresAt,
            serverCount: servers.length,
            protocolCounts: sifted.counts,
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
            // интервал панели только при первой загрузке, дальше его выбирает пользователь
            updateIntervalHours: wasFirstFetch
                ? result.profile.updateIntervalHours
                : null,
            fallbackUrl: result.profile.fallbackUrl,
            remindExpiry: result.profile.remindExpiry,
          );
      await _storage.upsertSubscription(updated);
      final routingChanged = await _applyProviderRouting(
        updated,
        result.routing,
      );

      return UpdateResult(
        success: true,
        serverCount: servers.length,
        subscription: updated,
        routingChanged: routingChanged,
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

  // в режиме авто пустой выбор выключил бы и сам автовыбор: сторож ведёт только выбранный сервер
  Future<String?> _autoSelectReplacement(
    Subscription sub,
    String goneId,
    List<ServerItem> oldServers,
    List<ServerItem> servers,
  ) async {
    try {
      final owner = (await _storage.getSubscriptions())
          .where((s) => s.autoSelect)
          .firstOrNull;
      if (owner == null) return null;
      final home = await AutoSelectHomeStore.load();
      final ledHere =
          home != null &&
          home.subscriptionId == owner.id &&
          home.pickedId == goneId;
      if (owner.id != sub.id && !ledHere) return null;
      final pick = AutoServerSelect.pick(servers, subscriptionId: sub.id);
      if (pick == null) return null;
      if (ledHere) {
        await AutoSelectHomeStore.save(
          AutoSelectHome.afterNeighbourFailover(
            home,
            subscriptionId: owner.id,
            fromId: goneId,
            toId: pick.id,
          ),
        );
      }
      await AutoSelectFollowStore.save(pick.id);
      final gone = oldServers.firstWhere((s) => s.id == goneId);
      AppLogger.instance.info(
        'Auto select: ${gone.displayName} left the subscription, '
        'picked ${pick.displayName}',
      );
      return pick.id;
    } catch (e, st) {
      AppLogger.instance.warn(
        'Auto select replacement failed',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  Future<bool> _applyProviderRouting(
    Subscription sub,
    ProviderRouting? routing,
  ) async {
    if (routing == null) return false;
    // серверы уже записаны: сбой с профилем не должен выдать обновление за неудачное
    try {
      final settings = await _storage.getSettings();
      if (settings.ignoreProviderRules) return false;
      final profiles = await _storage.getRoutingProfiles();
      final next = withProviderRouting(
        profiles,
        subscriptionId: sub.id,
        fallbackName: sub.name,
        routing: routing,
      );
      if (jsonEncode(next) == jsonEncode(profiles)) return false;
      await _storage.saveRoutingProfiles(next);
      return true;
    } catch (e, st) {
      AppLogger.instance.warn(
        'Provider routing profile not saved',
        error: e,
        stackTrace: st,
      );
      return false;
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
