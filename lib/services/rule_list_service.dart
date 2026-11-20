import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/app_logger.dart';
import '../models/app_settings.dart';
import '../utils/local_vpn_proxy.dart';
import '../utils/rule_lists.dart';

enum RuleListFailure {
  // подменённый по дороге список увёл бы сайты мимо VPN
  insecure,

  http,

  tooLarge,

  empty,

  network,
}

class RuleListStatus {
  const RuleListStatus({
    required this.url,
    this.domains = 0,
    this.updatedAt,
    this.failure,
    this.httpStatus,
    this.loading = false,
  });

  final String url;
  final int domains;

  final DateTime? updatedAt;

  final RuleListFailure? failure;
  final int? httpStatus;

  final bool loading;

  bool get loaded => updatedAt != null;

  RuleListStatus copyWith({bool? loading}) => RuleListStatus(
    url: url,
    domains: domains,
    updatedAt: updatedAt,
    failure: failure,
    httpStatus: httpStatus,
    loading: loading ?? this.loading,
  );

  Map<String, dynamic> toJson() => {
    'url': url,
    'domains': domains,
    if (updatedAt != null) 'updatedAt': updatedAt!.millisecondsSinceEpoch,
    if (failure != null) 'failure': failure!.name,
    if (httpStatus != null) 'httpStatus': httpStatus,
  };

  static RuleListStatus fromJson(String url, Map<String, dynamic> json) {
    final updated = json['updatedAt'];
    final failure = json['failure'];
    return RuleListStatus(
      url: url,
      domains: (json['domains'] as num?)?.toInt() ?? 0,
      updatedAt: updated is num
          ? DateTime.fromMillisecondsSinceEpoch(updated.toInt())
          : null,
      failure: RuleListFailure.values
          .where((f) => f.name == failure)
          .firstOrNull,
      httpStatus: (json['httpStatus'] as num?)?.toInt(),
    );
  }
}

class RuleListService {
  RuleListService({
    LocalProxyPortResolver? localProxyPort,
    Future<Directory> Function()? root,
    @visibleForTesting this.allowPlainHttp = false,
    @visibleForTesting this.maxBytes = defaultMaxBytes,
  }) : _localProxyPort = localProxyPort,
       _root = root ?? getApplicationSupportDirectory;

  final LocalProxyPortResolver? _localProxyPort;
  final Future<Directory> Function() _root;
  final bool allowPlainHttp;
  final int maxBytes;

  static const defaultMaxBytes = 30 * 1024 * 1024;

  static const staleAfter = Duration(hours: 24);

  Future<Directory> _dir() async {
    final dir = Directory(p.join((await _root()).path, 'rule_lists'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  static String fileId(String url) =>
      sha1.convert(utf8.encode(url)).toString().substring(0, 16);

  Future<RuleListStatus> status(String url) async {
    final meta = File(p.join((await _dir()).path, '${fileId(url)}.json'));
    try {
      if (!meta.existsSync()) return RuleListStatus(url: url);
      final json = jsonDecode(await meta.readAsString());
      if (json is Map<String, dynamic> && json['url'] == url) {
        return RuleListStatus.fromJson(url, json);
      }
    } catch (e) {
      AppLogger.instance.warn('Rule list meta unreadable for $url: $e');
    }
    return RuleListStatus(url: url);
  }

  Future<RuleListStatus> refresh(String url) async {
    final previous = await status(url);
    final uri = Uri.tryParse(url.trim());
    final secure =
        uri != null &&
        uri.host.isNotEmpty &&
        (uri.scheme == 'https' || (allowPlainHttp && uri.scheme == 'http'));
    if (!secure) {
      return _saveFailure(previous, RuleListFailure.insecure);
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = 'keqdroid';
    final resolver = _localProxyPort;
    if (resolver != null) configureHttpClientForLocalVpnProxy(client, resolver);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 20));
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>().catchError((_) {});
        return _saveFailure(
          previous,
          RuleListFailure.http,
          httpStatus: response.statusCode,
        );
      }
      final declared = response.contentLength;
      if (declared > maxBytes) {
        return _saveFailure(previous, RuleListFailure.tooLarge);
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 60))) {
        bytes.add(chunk);
        if (bytes.length > maxBytes) {
          return _saveFailure(previous, RuleListFailure.tooLarge);
        }
      }
      final body = bytes.takeBytes();
      final domains = await Isolate.run(() => _parseSorted(body));
      if (domains.isEmpty) {
        return _saveFailure(previous, RuleListFailure.empty);
      }
      final dir = await _dir();
      final id = fileId(url);
      await _writeAtomically(
        File(p.join(dir.path, '$id.txt')),
        domains.join('\n'),
      );
      final next = RuleListStatus(
        url: url,
        domains: domains.length,
        updatedAt: DateTime.now(),
      );
      await _saveMeta(next);
      AppLogger.instance.info(
        'Rule list updated: ${uri.host} (${domains.length} domains)',
      );
      return next;
    } catch (e) {
      AppLogger.instance.warn('Rule list download failed: ${uri.host}: $e');
      return _saveFailure(previous, RuleListFailure.network);
    } finally {
      client.close(force: true);
    }
  }

  Future<RuleListDomains> domainsFor(AppSettings settings) async {
    final direct = ruleListUrls(settings.directRules);
    final proxy = ruleListUrls(settings.proxyRules);
    final blocked = ruleListUrls(settings.blockedRules);
    if (direct.isEmpty && proxy.isEmpty && blocked.isEmpty) {
      return RuleListDomains.none;
    }
    final dir = (await _dir()).path;
    List<String> paths(List<String> urls) => [
      for (final url in urls) p.join(dir, '${fileId(url)}.txt'),
    ];
    final directPaths = paths(direct);
    final proxyPaths = paths(proxy);
    final blockedPaths = paths(blocked);
    return Isolate.run(
      () => RuleListDomains(
        direct: _readMerged(directPaths),
        proxy: _readMerged(proxyPaths),
        blocked: _readMerged(blockedPaths),
      ),
    );
  }

  // для маршрутов на другие серверы, у которых своих полей нет
  Future<List<String>> domainsForEntries(String entries) async {
    final urls = ruleListUrls(entries);
    if (urls.isEmpty) return const [];
    final dir = (await _dir()).path;
    final paths = [for (final url in urls) p.join(dir, '${fileId(url)}.txt')];
    return Isolate.run(() => _readMerged(paths));
  }

  Future<void> prune(Set<String> keepUrls) async {
    final keep = {for (final url in keepUrls) fileId(url)};
    try {
      await for (final entity in (await _dir()).list()) {
        if (entity is! File) continue;
        final id = p.basenameWithoutExtension(entity.path).split('.').first;
        if (!keep.contains(id)) await entity.delete();
      }
    } catch (e) {
      AppLogger.instance.warn('Rule list cleanup failed: $e');
    }
  }

  Future<RuleListStatus> _saveFailure(
    RuleListStatus previous,
    RuleListFailure failure, {
    int? httpStatus,
  }) async {
    final next = RuleListStatus(
      url: previous.url,
      domains: previous.domains,
      updatedAt: previous.updatedAt,
      failure: failure,
      httpStatus: httpStatus,
    );
    await _saveMeta(next);
    return next;
  }

  Future<void> _saveMeta(RuleListStatus status) async {
    try {
      final dir = await _dir();
      await _writeAtomically(
        File(p.join(dir.path, '${fileId(status.url)}.json')),
        jsonEncode(status.toJson()),
      );
    } catch (e) {
      AppLogger.instance.warn('Rule list meta not saved: $e');
    }
  }

  // через временный файл: ядро, запущенное посреди записи, получило бы обрезанный список
  static Future<void> _writeAtomically(File file, String content) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(file.path);
  }
}

List<String> _parseSorted(Uint8List body) {
  final text = utf8.decode(body, allowMalformed: true);
  return parseFilterList(text).toList()..sort();
}

List<String> _readMerged(List<String> paths) {
  final out = <String>{};
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    for (final line in file.readAsLinesSync()) {
      if (line.isNotEmpty) out.add(line);
    }
  }
  return out.toList();
}
