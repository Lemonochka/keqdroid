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
import '../utils/custom_xray_config.dart';
import '../core/exceptions.dart';

/// Косметика, которую панель отдаёт заголовками ответа на запрос подписки.
///
/// Отдельный класс, а не поля в record'е результата: их пять, а record с
/// десятком позиций пришлось бы переписывать в каждом месте возврата.
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
  String? _cachedHwid;
  String? _cachedDeviceModel;
  static const MethodChannel _platform = MethodChannel('keqdis_vpn_channel');

  /// браузерный UA: базовый для краулинга html-страниц и последний резерв
  /// в переборе (часть cdn/waf отдаёт payload только браузеру)
  static const browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// UA нашего клиента — им идёт первый запрос (если у подписки нет
  /// сохранённого рабочего UA) и он первый в переборе. Версия подтягивается
  /// из PackageInfo один раз; без платформенного канала (тесты, изоляты)
  /// остаёмся на голом 'keqdroid'.
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
        // нет платформы — оставляем дефолт
      }
      _appUserAgentResolved = true;
    }
    return _appUserAgentCache;
  }

  SubscriptionService(this._storage, {Dio? dio, int? proxyHttpPort})
      : _dio = dio ?? _buildDio(proxyHttpPort: proxyHttpPort);

  /// dio с опциональным локальным HTTP-прокси (порт keqrnel/xray HTTP inbound).
  /// нужно в фоновом workmanager-изоляте, чтобы апдейт подписок шёл через туннель.
  /// без [proxyHttpPort] работает напрямую.
  static Dio _buildDio({int? proxyHttpPort}) {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'User-Agent': browserUserAgent,
        'Accept': '*/*',
        'Accept-Language': 'en-US,en;q=0.9',
      },
    ));

    if (proxyHttpPort != null) {
      configureDioForActiveVpn(
        dio,
        useLocalProxy: true,
        httpPort: proxyHttpPort,
      );
    }

    return dio;
  }

  // безопасность

  static const _blockedHostnames = {
    'metadata.google.internal',
    '169.254.169.254',           // AWS/GCP/Azure IMDS
    'fd00:ec2::254',             // AWS IMDSv2 IPv6
  };

  static bool isSafeUrl(String url) {
    try {
      if (url.length > 2048) return false;
      final uri = Uri.parse(url);
      // Только https: payload подписки несёт серверные секреты (пароли, uuid,
      // ключи), по plain http их читает и подменяет любой MITM по пути.
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

  /// True when [host] is (or is written as) an IP address in a range a
  /// subscription URL must never target — loopback, private, link-local, CGNAT,
  /// IPv6 ULA. Also rejects numeric shorthands (decimal `2130706433`,
  /// hex `0x7f000001`) that spell a private IP while sneaking past dotted-quad
  /// string checks. A plain hostname returns false here (DNS-rebinding SSRF is
  /// out of scope; this is input hardening, not a full egress firewall).
  static bool _isDisallowedIpHost(String host) {
    if (RegExp(r'^0x[0-9a-f]+$').hasMatch(host)) return true;
    if (RegExp(r'^\d+$').hasMatch(host)) return true; // bare-integer IP form

    final addr = InternetAddress.tryParse(host);
    if (addr == null) return false; // hostname, not a literal IP
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

  /// стабильный ключ для сопоставления серверов между обновлениями.
  /// reality-провайдеры ротируют sid/spx/pbk, полный конфиг меняется, а сервер тот же.
  /// ключ = scheme + uuid/userinfo + host + port. для vmess uuid внутри base64-json (поле "id"),
  /// если распарсить не вышло — fallback на host+port.
  static String _stableKey(String rawConfig) {
    try {
      // Готовый конфиг ядра: сам json провайдер переписывает (ключи reality,
      // порядок правил), стабильны имя и адрес основного аутбаунда.
      if (CustomXrayConfig.looksLikeJson(rawConfig)) {
        final custom = CustomXrayConfig.tryParse(rawConfig);
        if (custom != null) {
          final endpoint = custom.endpoint;
          return 'custom:${custom.remarks.toLowerCase()}'
              '@${endpoint.address.toLowerCase()}:${endpoint.port}';
        }
      }

      final uri = Uri.parse(rawConfig);
      final host = uri.host.toLowerCase();
      final port = uri.port.toString();

      // vmess: uuid внутри base64-json payload. Декодируем из СЫРОЙ строки:
      // uri.host лоуэркейсит base64 (регистрозависимый), декод падает, и ключ
      // уходит в фоллбэк с полным конфигом — тогда смена имени сервера
      // (ps внутри payload) ломает сопоставление, теряя ping/избранное/
      // активный сервер при обновлении подписки.
      if (rawConfig.startsWith('vmess://')) {
        try {
          final payload = rawConfig.substring('vmess://'.length);
          final decoded = _tryDecodeBase64Flexible(payload);
          if (decoded == null) return 'vmess:@$host:$port';
          final json = jsonDecode(decoded) as Map<String, dynamic>;
          final id = (json['id'] as String? ?? '').toLowerCase();
          final add = (json['add'] as String? ?? '').toLowerCase();
          final portJ = json['port']?.toString() ?? port;
          return 'vmess:$id@$add:$portJ';
        } catch (_) {
          return 'vmess:@$host:$port';
        }
      }

      // hysteria/hy2: стабильность по auth из query или userInfo
      final schemeLower = uri.scheme.toLowerCase();
      if (schemeLower == 'hysteria' || schemeLower == 'hysteria2' || schemeLower == 'hy2') {
        final qp = uri.queryParameters;
        var auth = (qp['auth'] ?? qp['password'] ?? '').toLowerCase();
        if (auth.isEmpty && uri.userInfo.isNotEmpty) {
          auth = Uri.decodeComponent(uri.userInfo).toLowerCase();
        }
        return '$schemeLower:$auth@$host:$port';
      }

      // vless/trojan/ss/ssr: userInfo (uuid/password) стабилен, меняются только query (sid, spx, pbk)
      final userInfo = uri.userInfo.toLowerCase();
      return '${uri.scheme}:$userInfo@$host:$port';
    } catch (_) {
      // совсем крайний случай — первые 80 символов без fragment
      final noFragment = rawConfig.split('#').first;
      return noFragment.substring(0, noFragment.length.clamp(0, 80));
    }
  }

  // загрузка подписки

  /// качает подписку и отдаёт список raw-конфигов.
  /// заодно парсит X-Subscription-Userinfo для трафика. при сетевой ошибке один retry через 2с.
  /// [userAgent] — сохранённый рабочий UA подписки: первый запрос идёт с ним.
  Future<({List<String> configs, int? usedBytes, int? totalBytes, DateTime? expiresAt, String? usedUserAgent, SubscriptionProfileHeaders profile})>
  fetchRaw(String url, {CancelToken? cancelToken, String? userAgent}) async {
    if (!isSafeUrl(url)) {
      // http выделяем в отдельное сообщение: у него в UI точечный фикс
      // («Исправить на https» в карточке подписки), а не generic Forbidden URL.
      if (Uri.tryParse(url)?.scheme.toLowerCase() == 'http') {
        throw SubscriptionFetchException('Insecure http URL', url: url);
      }
      throw SubscriptionFetchException('Forbidden URL', url: url);
    }

    // hwid только если разрешено в настройках. Настройку читаем на каждый
    // запрос (getSettings кэширован), а не держим в поле: поле с дефолтом
    // расходится с тумблером в фоновых изолятах (WorkManager, desktop-таймер)
    // и после перезапуска.
    final shareHwid = (await _storage.getSettings()).shareDeviceHwid;
    final hwid = shareHwid ? await _getOrCreateHwid() : null;
    final hwidHeaders = hwid != null
        ? await _buildRemnawaveHeaders(hwid)
        : const <String, String>{};

    try {
      final result = await _fetchWithRetry(
        url,
        cancelToken: cancelToken,
        attempt: 0,
        hwid: hwid,
        hwidHeaders: hwidHeaders,
        savedUserAgent: userAgent,
      );

      return (
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
          );
        }
      }
      rethrow;
    }
  }

  Future<({List<String> configs, int? usedBytes, int? totalBytes, DateTime? expiresAt, String? usedUserAgent, SubscriptionProfileHeaders profile})>
  _fetchWithRetry(
    String url, {
    CancelToken? cancelToken,
    required int attempt,
    required String? hwid,
    required Map<String, String> hwidHeaders,
    String? savedUserAgent,
  }) async {
    String? usedUserAgent;
    var profile = SubscriptionProfileHeaders.empty;
    // первый запрос: сохранённый рабочий UA подписки, иначе UA приложения.
    // если он перестал работать (html/4xx/5xx) — перебор ниже, без него
    final initialUa = (savedUserAgent != null && savedUserAgent.isNotEmpty)
        ? savedUserAgent
        : await appUserAgent();
    try {
      Response<String> response = await _dio.get<String>(
        url,
        cancelToken: cancelToken,
        options: _hwidOptions({'User-Agent': initialUa, ...hwidHeaders}),
      );
      _logRemnawaveHwidHeaders(response.headers, source: 'DIO');
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
        );
        if (uaResponse != null) {
          response = uaResponse;
          effectiveBody = uaResponse.data ?? '';
          final uaType = (uaResponse.headers.value('content-type') ?? '').toLowerCase();
          looksLikeHtml = uaType.contains('text/html') ||
              effectiveBody.trimLeft().startsWith('<!doctype html') ||
              effectiveBody.trimLeft().startsWith('<html');
          // запоминаем сработавший User-Agent
          usedUserAgent = uaResponse.requestOptions.headers['User-Agent'] as String?;
          // часть панелей отдаёт userinfo только под клиентским User-Agent
          if (usedBytes == null || totalBytes == null || expiresAt == null) {
            final headerMetaUa = _parseUserInfoHeader(uaResponse.headers);
            profile = _parseProfileHeaders(uaResponse.headers);
            usedBytes ??= headerMetaUa.usedBytes;
            totalBytes ??= headerMetaUa.totalBytes;
            expiresAt ??= headerMetaUa.expiresAt;
          }
        }
      } else {
        // первый запрос отдал payload — запоминаем его UA как рабочий
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
      // fallback для панелей, которые суют дату/трафик в служебные ноды
      if (usedBytes == null || totalBytes == null || expiresAt == null) {
        final meta = _extractMetaFromBody(effectiveBody);
        usedBytes ??= meta.usedBytes;
        totalBytes ??= meta.totalBytes;
        expiresAt ??= meta.expiresAt;
      }

      return (
      configs: configs,
      usedBytes: usedBytes,
      totalBytes: totalBytes,
      expiresAt: expiresAt,
      usedUserAgent: usedUserAgent,
      profile: profile,
      );
    } on DioException catch (e) {
      // некоторые бэкенды отдают не-200 (502 и т.п.), но в body уже валидный payload.
      // пробуем достать конфиги из тела до общей обработки ошибки
      final parsedFromError = await _tryParseFromErrorResponse(e);
      if (parsedFromError != null) {
        return parsedFromError;
      }

      // часть панелей маршрутизирует по User-Agent: браузерному отдаёт
      // отдельную html-страницу подписки (и её бэкенд может лежать → 502),
      // а клиентским UA — сам payload. UA-ретрай в успешной ветке сюда не
      // добирается (dio кидает на не-2xx раньше), поэтому пробуем здесь
      if ((e.response?.statusCode ?? 0) >= 400) {
        final parsedWithClientUa = await _tryParseWithClientUserAgents(
          url,
          cancelToken: cancelToken,
          hwidHeaders: hwidHeaders,
          skipUserAgents: {initialUa},
        );
        if (parsedWithClientUa != null) {
          return parsedWithClientUa;
        }
      }

      // часть cdn/waf отдаёт 502 с пустым body именно для dio.
      // пробуем забрать payload нативным HttpClient с браузерными заголовками
      try {
        final parsedViaHttpClient = await _tryFetchWithHttpClientFallback(
          url,
          hwid: hwid,
          hwidHeaders: hwidHeaders,
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

      // отменённые и http-ошибки (4xx/5xx) не ретраим
      final isRetryable = e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError;

      // один retry при сетевой ошибке через 2с
      if (isRetryable && attempt == 0) {
        await Future.delayed(const Duration(seconds: 2));
        return _fetchWithRetry(
          url,
          cancelToken: cancelToken,
          attempt: 1,
          hwid: hwid,
          hwidHeaders: hwidHeaders,
          savedUserAgent: savedUserAgent,
        );
      }

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw TimeoutException('Request timed out', cause: e);
      }
      throw SubscriptionFetchException(
        e.message ?? 'Network error',
        url: url,
        cause: e,
      );
    }
  }

  Future<({List<String> configs, int? usedBytes, int? totalBytes, DateTime? expiresAt, String? usedUserAgent, SubscriptionProfileHeaders profile})?>
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
      return (
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

  Future<({List<String> configs, int? usedBytes, int? totalBytes, DateTime? expiresAt, String? usedUserAgent, SubscriptionProfileHeaders profile})?>
  _tryParseWithClientUserAgents(
    String url, {
    CancelToken? cancelToken,
    required Map<String, String> hwidHeaders,
    Set<String> skipUserAgents = const {},
  }) async {
    final response = await _retryWithSubscriptionUserAgents(
      url,
      cancelToken: cancelToken,
      hwidHeaders: hwidHeaders,
      skipUserAgents: skipUserAgents,
    );
    if (response == null) {
      return null;
    }
    _logRemnawaveHwidHeaders(response.headers, source: 'UA-RETRY');
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
    return (
      configs: configs,
      usedBytes: headerMeta.usedBytes ?? bodyMeta.usedBytes,
      totalBytes: headerMeta.totalBytes ?? bodyMeta.totalBytes,
      expiresAt: headerMeta.expiresAt ?? bodyMeta.expiresAt,
      usedUserAgent: response.requestOptions.headers['User-Agent'] as String?,
      profile: _parseProfileHeaders(response.headers),
    );
  }

  Future<({List<String> configs, int? usedBytes, int? totalBytes, DateTime? expiresAt, String? usedUserAgent, SubscriptionProfileHeaders profile})?>
  _tryFetchWithHttpClientFallback(
    String url, {
    required String? hwid,
    Map<String, String>? hwidHeaders,
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
        final uri = Uri.parse(candidate);
        final req = await client.getUrl(uri);
        req.headers.set(HttpHeaders.userAgentHeader, browserUserAgent);
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
        _logRemnawaveHwidHeaders(
          dioLikeHeaders,
          source: 'HTTPCLIENT',
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
        AppLogger.instance.debug(
          'HttpClient fallback candidate response: $candidate '
          '(status=${resp.statusCode}, type=$contentType, len=${body.length}, html=$looksLikeHtml)',
        );
        final preview = body.replaceAll(RegExp(r'\s+'), ' ').trim();
        AppLogger.instance.debug(
          'HttpClient fallback body preview: '
          '${preview.substring(0, preview.length > 180 ? 180 : preview.length)}',
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
            // бывает payload внутри html/js даже при text/plain
            configs = _extractConfigsFromHtml(body) ?? const [];
            if (configs.isEmpty) rethrow;
          }
        }
        if (configs.isEmpty) continue;
        final headerMeta = _parseUserInfoHeader(dioLikeHeaders);
        final bodyMeta = _extractMetaFromBody(body);
        return (
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
      // keep raw payload
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

    // частый кейс: backend/cdn по-разному реагирует на trailing slash
    if (!uri.path.endsWith('/')) {
      out.add(uri.replace(path: '${uri.path}/').toString());
    } else {
      final p = uri.path.substring(0, uri.path.length - 1);
      out.add(uri.replace(path: p.isEmpty ? '/' : p).toString());
    }

    // НЕ добавляем http-вариант для https-подписок: URL содержит секретный
    // токен, а к запросу идут hwid-заголовки — открытый HTTP отдал бы их
    // любому наблюдателю сети (для VPN-клиента это недопустимо).
    // query-вариант только для проблемного домена, чтобы не ломать обычные подписки
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
    // Только специфичные фразы: голое вхождение "hwid" ловило случайный
    // HTML/JS страниц-заглушек и подменяло реальную ошибку ложным диагнозом.
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

  Future<String> _getOrCreateHwid() async {
    if (_cachedHwid != null && _cachedHwid!.isNotEmpty) return _cachedHwid!;
    
    // android_id is the primary hwid source
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
      // prefer android_id, it's stable and device-bound
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

    // fallback: random uuid
    final created = const Uuid().v4().replaceAll('-', '');
    await _storage.setHwid(created);
    _cachedHwid = created;
    return created;
  }

  Future<Map<String, String>> _buildRemnawaveHeaders(String hwid) async {
    final os = Platform.isAndroid
        ? 'Android'
        : Platform.isIOS
            ? 'iOS'
            : Platform.isWindows
                ? 'Windows'
                : Platform.isMacOS
                    ? 'macOS'
                    : Platform.isLinux
                        ? 'Linux'
                        : Platform.operatingSystem;
    final model = await _getDeviceModel();
    final osVersion = Platform.operatingSystemVersion;
    
    return {
      'x-hwid': hwid, // required by remnawave
      // алиасы для панелей со строгой проверкой регистра/имени
      'X-HWID': hwid,
      'hwid': hwid,
      'x-device-os': os,
      'X-Device-Os': os,
      'x-ver-os': osVersion,
      'X-Ver-Os': osVersion,
      'x-device-model': model,
      'X-Device-Model': model,
    };
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
      // fallback below
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

  void _logRemnawaveHwidHeaders(Headers headers, {required String source}) {
    // пока не логируем
  }

  /// Косметические заголовки подписки по [XTLS Subscription Standards].
  ///
  /// `profile-title` и `announce` спека предписывает слать с префиксом
  /// `base64:`; часть панелей шлёт голый текст, поэтому декодируем только то,
  /// что действительно похоже на base64 (см. [_decodeHeaderText]).
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
      // Отрицательный или нулевой интервал — мусор, а не «обновлять всегда».
      updateIntervalHours: (interval != null && interval > 0) ? interval : null,
    );
  }

  /// Текст заголовка: `base64:...` по спеке, иначе как есть.
  ///
  /// Голый base64 без префикса встречается у старых панелей, поэтому пробуем и
  /// его — но только когда строка целиком укладывается в алфавит base64 и
  /// раскодировалась в осмысленный UTF-8. Иначе обычное слово вроде `Announce`
  /// (валидный base64!) превратилось бы в мусор.
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
        // управляющие символы = раскодировали не то
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

  /// Пускаем только http(s): заголовок приходит с чужого сервера, а ссылка
  /// потом открывается в браузере пользовательницы.
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
  }) async {
    // [skipUserAgents] — уже опробованные (первый запрос), их не повторяем
    final userAgents = <String>[
      // свой UA первым — панели могут держать его в белом списке
      await appUserAgent(),
      'v2rayNG/1.9.28',
      'NekoBox/1.3.9',
      'ClashMetaForAndroid/2.11.5',
      'clash-verge/v2.2.2',
      'sing-box',
      'QuantumultX',
      'Shadowrocket',
      // браузерный — последний резерв
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
        // пробуем следующий ua
      }
    }
    return null;
  }

  // парсинг тела

  /// Test-only hook over the private body parser (extraction → raw config list).
  @visibleForTesting
  static List<String> parseBodyForTest(String content) => _parseBody(content);

  /// [_parseBody] в отдельном изоляте. Тело подписки бывает большим (сотни
  /// URI, несколько base64-вариантов, regex-проходы), а auto-update дёргается
  /// на onResume — на главном изоляте это давало хитч кадров ровно в момент
  /// разворачивания приложения. Функция статическая и чистая → compute-safe.
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
      // Готовые конфиги ядра идут вперёд ссылок, но не вместо них: payload
      // бывает смешанным (часть серверов ссылками, часть — конфигом целиком).
      final customConfigs = _extractCustomConfigs(candidate);
      if (extractedLinks.isNotEmpty || customConfigs.isNotEmpty) {
        return [...customConfigs, ...extractedLinks];
      }

      final structured = _extractConfigsFromStructuredContent(candidate);
      if (structured.isNotEmpty) return structured;

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

    // Формат ищем по всем вариантам, а не только по последнему: у json-тела
    // вариантов обычно один, но у завёрнутого в base64 распознаваемым будет
    // именно распакованный — иначе диагноз подменялся общим «ссылок не нашли».
    for (final candidate in candidates) {
      final unsupported = _detectUnsupportedFormat(candidate);
      if (unsupported != null) {
        throw FormatException(unsupported);
      }
    }
    throw const FormatException(
      'No supported proxy links found. Expected URI lines like vless://, vmess://, trojan://, ss://, ssr://, hysteria://, hysteria2:// or hy2://',
    );
  }

  /// Готовые конфиги ядра из payload подписки: тело целиком (json-объект или
  /// массив объектов) либо по одному конфигу в строке, в том числе в base64.
  ///
  /// Так провайдеры отдают «сервера с готовым роутингом» — в v2rayNG это
  /// CUSTOM-сервер: не ссылка, а конфиг xray со своими правилами и dns.
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
      // Строка целиком в base64 — распространённый вид json-подписки. Гоняем
      // декод только на то, что вообще похоже на base64: на списке из сотен
      // ссылок это иначе лишний проход по каждой строке.
      if (line.length < 40 || !_base64Line.hasMatch(line)) continue;
      final decoded = _tryDecodeBase64Flexible(line);
      if (decoded == null) continue;
      out.addAll(CustomXrayConfig.extractConfigs(decoded));
    }
    return out.where(_isUsableCustomConfig).toList();
  }

  /// Годится ли готовый конфиг из подписки в качестве сервера.
  ///
  /// Кроме служебных заглушек по имени ([_isMetadataConfig]) отсекаем конфиги
  /// без адреса сервера: панели отдают такую болванку (только `freedom`, пустой
  /// `vnext`), когда подписка истекла или не привязан HWID. Формально это
  /// валидный конфиг ядра, и без проверки он превращался бы в молчаливо
  /// нерабочий сервер — весь трафик мимо туннеля, пинг никакой. Внятная ошибка
  /// обновления полезнее (её текст даёт [_detectUnsupportedFormat]).
  static bool _isUsableCustomConfig(String config) {
    if (_isMetadataConfig(config)) return false;
    final custom = CustomXrayConfig.tryParse(config);
    return custom != null && custom.address.isNotEmpty;
  }

  static final _base64Line = RegExp(r'^[A-Za-z0-9+/_=-]+$');

  static List<String> _collectTextVariants(String input) {
    // лимиты на обход: в release r8 даже итеративный код жрёт стек из-за base64+regex
    const maxVariants = 12;
    const maxQueueSize = 50;

    final queue = <String>[input];
    final seen = <String>{};
    final out = <String>[];

    int iterations = 0;
    const maxIterations = 200; // защита от бесконечного цикла

    while (queue.isNotEmpty && out.length < maxVariants && iterations < maxIterations) {
      iterations++;
      
      // очередь растёт слишком быстро — сбрасываем
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

      // _decodeBase64Tokens сюда НЕ добавляем — он плодит варианты и раздувает очередь

      final nextCandidates = [html, js, decoded, decodedCompact, uriDecoded]
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty && !seen.contains(s.trim()))
          .take(4) // не больше 4 новых кандидатов за итерацию
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
    // чистим пробелы/переносы, поддерживаем url-safe base64 (-,_)
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
        lower.contains('\nproxy-providers:')) {
      return 'Unsupported subscription format: Clash YAML';
    }

    if (text.startsWith('{') || text.startsWith('[')) {
      try {
        final parsed = jsonDecode(text);
        if (parsed is Map<String, dynamic>) {
          final keys = parsed.keys.map((k) => k.toLowerCase()).toSet();
          if (keys.contains('outbounds') || keys.contains('inbounds') || keys.contains('proxies')) {
            // Рабочий конфиг xray сюда не доходит — его забирает
            // _extractCustomConfigs. Значит либо это болванка без адреса
            // сервера (истёкшая подписка, непривязанный HWID), либо sing-box /
            // clash, которых наше ядро не исполняет.
            if (CustomXrayConfig.tryParse(text) != null) {
              return 'Subscription returned an Xray config without a server address. '
                  'This is usually a provider stub: check subscription status and '
                  'HWID binding in the provider panel.';
            }
            return 'Unsupported subscription format: sing-box/Clash JSON '
                '(only Xray JSON configs are supported)';
          }
        } else if (parsed is List && parsed.isNotEmpty) {
          return 'Unsupported subscription format: JSON array config';
        }
      } on Object {
        // не json — ниже вернём общий текст ошибки
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
        // not json
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

  // итеративный обход вместо рекурсии: рекурсивная версия переполняла стек
  // на глубоких/широких json из подписок
  static void _walkStructured(Object? node, Set<String> found) {
    const maxTotalNodes = 5000;
    const maxQueueSize = 200;
    const maxDepth = 8;

    // очередь пар (node, depth, isDirectConfigString)
    final queue = <(Object?, int, bool)>[];
    final seen = <Object>{};

    if (node != null) {
      queue.add((node, 0, false));
    }

    int iterations = 0;
    const maxIterations = 1000; // защита от бесконечного цикла

    while (queue.isNotEmpty && found.length < maxTotalNodes && iterations < maxIterations) {
      iterations++;

      // очередь растёт слишком быстро — подрезаем
      if (queue.length > maxQueueSize) {
        queue.removeRange(0, (queue.length - maxQueueSize ~/ 2).clamp(1, queue.length));
      }

      final (current, depth, isDirect) = queue.removeAt(0);

      if (current == null || depth > maxDepth) continue;

      // примитивы обрабатываем сразу
      if (current is String) {
        if (isDirect) {
          // строка уже похожа на uri конфига — тащим ссылки напрямую
          for (final uri in _extractUriLinks(current)) {
            if (!_isMetadataConfig(uri)) found.add(uri);
          }
        } else {
          // _collectTextVariants гоняем только на поверхностном уровне
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
        // ограничиваем размер списка
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

        // пробуем собрать uri конфига из map
        final uri = _proxyMapToUri(map);
        if (uri != null && !_isMetadataConfig(uri)) {
          found.add(uri);
        }

        // в очередь кладём только важные значения
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
              if (entriesAdded >= 20) break; // не больше 20 записей на map
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

  static List<Map<String, dynamic>> _extractYamlLikeProxies(String content) {
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
        // вышли из секции proxies
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

  static String? _proxyMapToUri(Map<String, dynamic> raw) {
    final map = <String, String>{};
    raw.forEach((k, v) => map[k.toLowerCase()] = v?.toString().trim() ?? '');

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
      final vmess = <String, String>{
        'v': '2',
        'ps': name,
        'add': host,
        'port': '$port',
        'id': id,
        'aid': pick(['alterid', 'alter_id', 'aid']).isNotEmpty ? pick(['alterid', 'alter_id', 'aid']) : '0',
        'net': pick(['network', 'net']).isNotEmpty ? pick(['network', 'net']) : 'tcp',
        'type': pick(['header', 'header_type']).isNotEmpty ? pick(['header', 'header_type']) : 'none',
        'host': pick(['servername', 'sni', 'host']),
        'path': pick(['path']),
        'tls': _normalizeTlsValue(pick(['tls', 'security'])),
      };
      final encoded = base64.encode(utf8.encode(jsonEncode(vmess)));
      return 'vmess://$encoded';
    }

    if (type == 'vless') {
      final id = pick(['uuid', 'id']);
      if (host.isEmpty || port <= 0 || id.isEmpty) return null;
      final query = <String, String>{};
      final security = pick(['security', 'tls']);
      if (security.isNotEmpty) query['security'] = _normalizeTlsValue(security);
      final sni = pick(['servername', 'sni', 'host']);
      if (sni.isNotEmpty) query['sni'] = sni;
      final network = pick(['network', 'net', 'type']);
      if (network.isNotEmpty) query['type'] = network;
      final path = pick(['path']);
      if (path.isNotEmpty) query['path'] = path;
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
      final query = <String, String>{};
      final sni = pick(['servername', 'sni', 'host']);
      if (sni.isNotEmpty) query['sni'] = sni;
      final network = pick(['network', 'net', 'type']);
      if (network.isNotEmpty) query['type'] = network;
      final path = pick(['path']);
      if (path.isNotEmpty) query['path'] = path;
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
      return 'ss://$userInfo@$host:$port$fragment';
    }

    if (type == 'hysteria' || type == 'hysteria2' || type == 'hy2') {
      final auth = pick(['auth', 'password', 'psk', 'auth_str', 'auth-str']);
      if (host.isEmpty || port <= 0 || auth.isEmpty) return null;
      final isV2 = type == 'hysteria2' || type == 'hy2';
      final scheme = isV2 ? 'hy2' : 'hysteria';
      final ver = pick(['version']);
      // xray 26+ hysteria outbound takes only version 2 in hysteriaSettings
      final query = <String, String>{
        'auth': auth,
        'version': ver.isNotEmpty ? ver : '2',
      };
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
      final pin = pick(['pinSHA256', 'pinsha256']);
      if (pin.isNotEmpty) query['pinSHA256'] = pin;
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

  static String _normalizeTlsValue(String raw) {
    final v = raw.toLowerCase();
    if (v == '1' || v == 'true' || v == 'tls') return 'tls';
    if (v == 'reality') return 'reality';
    return 'none';
  }

  static List<String>? _extractConfigsFromHtml(String html) {
    final candidates = <String>[];

    // частые контейнеры с payload
    final blockMatches = RegExp(
      r'<(?:pre|code|textarea)[^>]*>([\s\S]*?)</(?:pre|code|textarea)>',
      caseSensitive: false,
    ).allMatches(html);
    for (final m in blockMatches) {
      final v = m.group(1);
      if (v != null && v.trim().isNotEmpty) candidates.add(v);
    }

    // в скриптах payload бывает строкой/переменной
    final scriptMatches = RegExp(
      r'<script[^>]*>([\s\S]*?)</script>',
      caseSensitive: false,
    ).allMatches(html);
    for (final m in scriptMatches) {
      final v = m.group(1);
      if (v != null && v.trim().isNotEmpty) candidates.add(v);
    }

    // js-переменные вида payload="...", subData='...'
    final jsMatches = RegExp(
      r'''(?:payload|subscription|subdata|content|data)\s*[:=]\s*["']([\s\S]*?)["']''',
      caseSensitive: false,
    ).allMatches(html);
    for (final m in jsMatches) {
      final v = m.group(1);
      if (v != null && v.trim().isNotEmpty) candidates.add(v);
    }

    // длинные base64-подобные блоки внутри html
    final base64Like = RegExp(
      r'[A-Za-z0-9+/_=\r\n-]{300,}',
      caseSensitive: false,
    ).allMatches(html);
    for (final m in base64Like) {
      final v = m.group(0);
      if (v != null && v.trim().isNotEmpty) candidates.add(v);
    }

    // иногда backend ставит text/html, а тело уже сырое
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

        // прямой поиск uri в тексте
        final directLinks = _extractUriLinks(cleaned);
        if (directLinks.isNotEmpty) return directLinks;

        // без рекурсивного _parseBody — он давал stackoverflow в release, тут ограниченные трансформации
        final configs = _parseBodyNoRecursion(cleaned);
        if (configs.isNotEmpty) return configs;
      }
    }
    return null;
  }

  /// упрощённый _parseBody без рекурсии — чтобы не зациклить
  /// parseBody → extractStructured → walkStructured → collectVariants → parseBody
  static List<String> _parseBodyNoRecursion(String content) {
    final original = content.trim();

    // Готовый конфиг ядра. Сюда payload приходит из html-ветки (панель отдаёт
    // подписку страницей, конфиг лежит в <pre>/<script>/js-переменной), а по
    // одним ссылкам её экстрактор конфиг найти не мог.
    final custom = _extractCustomConfigs(original);
    if (custom.isNotEmpty) return custom;

    // одинарный base64
    final singleDecoded = _tryDecodeBase64Flexible(original);
    if (singleDecoded != null && singleDecoded.trim().isNotEmpty) {
      final configs = _extractUrisDirectly(singleDecoded);
      if (configs.isNotEmpty) return configs;
      final customDecoded = _extractCustomConfigs(singleDecoded);
      if (customDecoded.isNotEmpty) return customDecoded;
    }

    // double-decode (base64 в base64)
    if (singleDecoded != null) {
      final doubleDecoded = _tryDecodeBase64Flexible(singleDecoded);
      if (doubleDecoded != null && doubleDecoded.trim().isNotEmpty) {
        final configs = _extractUrisDirectly(doubleDecoded);
        if (configs.isNotEmpty) return configs;
      }
    }

    // plain-text uri
    final directConfigs = _extractUrisDirectly(original);
    if (directConfigs.isNotEmpty) return directConfigs;

    return const [];
  }

  /// тащит uri напрямую, без других парсеров
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
      // href="...", src="...", data-url="..."
      RegExp(r'''(?:href|src|data-url)\s*=\s*["']([^"']+)["']''', caseSensitive: false),
      // fetch("..."), axios.get("..."), open("...")
      RegExp(r'''(?:fetch|axios\.get|open)\s*\(\s*["']([^"']+)["']''', caseSensitive: false),
      // location = "...", window.location = "..."
      RegExp(r'''(?:window\.)?location(?:\.href)?\s*=\s*["']([^"']+)["']''', caseSensitive: false),
    ];

    for (final re in patterns) {
      for (final m in re.allMatches(html)) {
        final raw = (m.group(1) ?? '').trim();
        if (raw.isEmpty) continue;
        final unescaped = _htmlUnescape(raw).replaceAll(r'\/', '/');
        final resolved = base.resolve(unescaped).toString();
        final lower = resolved.toLowerCase();
        // отсекаем явно не-подписочные ссылки
        if (lower.endsWith('.js') ||
            lower.endsWith('.css') ||
            lower.endsWith('.png') ||
            lower.endsWith('.jpg') ||
            lower.endsWith('.svg') ||
            lower.contains('/login') ||
            lower.contains('/register')) {
          continue;
        }
        // берём то, что похоже на subscription/api
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
              // как сырую подписку не зашло — пробуем html-экстрактор
              final extracted = _extractConfigsFromHtml(body);
              if (extracted != null && extracted.isNotEmpty) return extracted;
            }
          } else {
            final extracted = _extractConfigsFromHtml(body);
            if (extracted != null && extracted.isNotEmpty) return extracted;
            next.addAll(_extractSubscriptionUrlsFromHtml(body, baseUrl: u));
          }
        } on Object {
          // отдельные неудачные fallback-запросы просто игнорим
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
    // Пробел внутри ссылки — валиден: во fragment'е (#имя сервера) он встречается
    // сплошь и рядом ("#🇷🇺 Белый интернет #1 | Все операторы"), и обрыв по первому
    // пробелу оставлял от имени один флаг-эмодзи (который cleanDisplayName затем
    // срезает — имя пустое). Поэтому режем только по переводам строк / html-кавычкам,
    // а negative lookahead разделяет два URI на одной строке. Сырые пробелы
    // Uri.parse перекодирует сам, внутренний '#' остаётся текстом fragment'а.
    // Negative lookbehind по символам scheme (RFC 3986: ALPHA/DIGIT/+/-/.) —
    // иначе `wss://host` из JS/HTML панелей матчился как `ss://host`, плодя
    // фантомные shadowsocks-сервера при HTML-краулинге подписки.
    final matches = RegExp(
      r'''(?<![A-Za-z0-9+.\-])(?:vless|vmess|trojan|ss|ssr|hysteria2?|hy2)://(?:(?!(?:vless|vmess|trojan|ssr|ss|hysteria2?|hy2)://)[^\r\n<>"'])+''',
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
        links.add(normalized);
      }
    }
    return links.toSet().toList();
  }

  static bool _isValidConfig(String s) {
    final lower = s.toLowerCase();
    return lower.startsWith('vless://') ||
        lower.startsWith('vmess://') ||
        lower.startsWith('trojan://') ||
        lower.startsWith('ss://') ||
        lower.startsWith('ssr://') ||
        lower.startsWith('hysteria://') ||
        lower.startsWith('hysteria2://') ||
        lower.startsWith('hy2://');
  }

  static bool _isMetadataConfig(String raw) {
    // заглушка от панелей: не сервер, а служебный маркер
    try {
      final uri = Uri.parse(raw);
      final host = uri.host.toLowerCase();
      if ((host == '0.0.0.0' || host == '::' || host == '::1') && uri.port <= 1) {
        return true;
      }
    } on Object {
      // ignore parse errors; continue with name markers
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
        // ignore parse errors
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
      // Готовый конфиг ядра: имя лежит в корневом `remarks` (как в v2rayNG).
      if (CustomXrayConfig.looksLikeJson(raw)) {
        final remarks = CustomXrayConfig.tryParse(raw)?.remarks ?? '';
        return remarks.isEmpty ? null : remarks;
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

      final uri = Uri.parse(raw);
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
      // дата вида "До: 24.04.2026" / "expire: 24.04.2026"
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
            // ignore invalid date
          }
        }
      }

      // трафик вида "12.5 / 100 GB", "1200MB/∞"
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
        // вариант "used: 12.3 GB"
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

  // полное обновление подписки

  Future<UpdateResult> updateSubscription(Subscription sub,
      {CancelToken? cancelToken}) async {
    try {
      final result = await fetchRaw(
        sub.url,
        cancelToken: cancelToken,
        userAgent: sub.userAgent,
      );

      final activeId = _storage.getActiveServerId();
      final oldServers = (await _storage.getServers())
          .where((s) => s.subscriptionId == sub.id)
          .toList();

      // индекс старых серверов по стабильному ключу — чтобы найти тот же сервер при смене sid/spx/pbk
      final oldByStableKey = <String, ServerItem>{
        for (final s in oldServers) _stableKey(s.config): s,
      };

      // Дедуп конфигов: построчные пути парсера не дедуплицируют, а два
      // одинаковых конфига дали бы два ServerItem с ОДНИМ id (exactMatch
      // возвращает один и тот же элемент) → duplicate ValueKey в списке UI.
      final uniqueConfigs = result.configs.toSet().toList();

      // Один старый сервер нельзя переиспользовать дважды: близкие конфиги
      // могут сойтись на одном stable-ключе — второму выдаём новый id.
      final usedOldIds = <String>{};
      final servers = uniqueConfigs.map((config) {
        // быстрый путь: точное совпадение конфига
        final exactMatch = oldServers.cast<ServerItem?>().firstWhere(
              (s) => s?.config == config,
          orElse: () => null,
        );
        if (exactMatch != null && usedOldIds.add(exactMatch.id)) {
          return exactMatch;
        }

        // медленный путь: совпадение по uuid+host+port
        final key = _stableKey(config);
        final stableMatch = oldByStableKey[key];
        if (stableMatch != null && usedOldIds.add(stableMatch.id)) {
          // Переиспользуем id и метаданные (pingMs, customName, pinnedAt и
          // т.д.), но берём новый конфиг. Исключение — пользователь правил
          // конфиг руками (configOverridden): его правки не затираем, пока
          // сервер остаётся тем же (stable key совпал).
          if (stableMatch.configOverridden) return stableMatch;
          return stableMatch.copyWith(config: config);
        }

        return ServerItem.fromRaw(config, subscriptionId: sub.id);
      }).toList();

      // Правленные вручную серверы, не совпавшие ни с одним конфигом подписки
      // (пользователь сменил host/port/uuid — stable key разошёлся): рефреш не
      // должен молча стирать правки, оставляем их в группе. Удалить такой
      // сервер можно только вручную.
      servers.addAll(
        oldServers.where(
          (s) => s.configOverridden && !usedOldIds.contains(s.id),
        ),
      );

      await _storage.replaceServersBySubscription(sub.id, servers);

      // сбрасываем activeServerId только если сервер реально пропал
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
            // null (payload пришёл фолбэком без UA-перебора) не затирает сохранённый
            userAgent: result.usedUserAgent,
          )
          .withProfileHeaders(
            title: result.profile.title,
            announce: result.profile.announce,
            supportUrl: result.profile.supportUrl,
            webPageUrl: result.profile.webPageUrl,
            // Предложенный панелью интервал берём только на первой загрузке:
            // дальше это уже выбор пользовательницы, и перетирать его на
            // каждом обновлении нельзя.
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
      // Только хост: полный URL подписки содержит секретный токен.
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

  /// обновляет все подписки с autoUpdate=true, батчами по 3.
  /// ошибка одного батча не валит остальные — updateSubscription сам ловит их в UpdateResult.
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

  /// подписки, у которых истёк интервал обновления.
  /// defaultInterval — fallback, если updateIntervalHours не задан (0).
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