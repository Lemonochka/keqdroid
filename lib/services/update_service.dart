import 'dart:io';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// инфа о доступном обновлении
class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final String? releaseNotes;
  final int apkSize;
  final bool openInBrowser;

  UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    this.releaseNotes,
    required this.apkSize,
    this.openInBrowser = false,
  });

  String get formattedSize {
    if (apkSize < 1024) return '$apkSize B';
    if (apkSize < 1024 * 1024) return '${(apkSize / 1024).toStringAsFixed(1)} KB';
    return '${(apkSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get displayCurrentVersion => UpdateService.displayVersion(currentVersion);
  String get displayLatestVersion => UpdateService.displayVersion(latestVersion);

  bool get hasNewVersion {
    return UpdateService.isNewerRelease(latestVersion, currentVersion);
  }
}

class UpdateService {
  static const _owner = 'Lemonochka';
  static const _repo = 'keqdroid';

  /// Единый semver-тег релиза: v0.1.0, v0.4.1 (Android + Windows в одном release).
  static final _releaseTagPattern = RegExp(
    r'^v\d+\.\d+(\.\d+)?(-[\w.]+)?$',
    caseSensitive: false,
  );

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  static const _prefSkipVersion = 'skip_update_version';
  static const _prefUpdateCheckCount = 'update_check_count';
  static const _checkInterval = 3;

  static Future<UpdateInfo?> checkForUpdate({bool force = false}) async {
    try {
      if (!force) {
        final prefs = await SharedPreferences.getInstance();
        final checkCount = prefs.getInt(_prefUpdateCheckCount) ?? 0;
        if (checkCount > 0 && checkCount % _checkInterval != 0) {
          await prefs.setInt(_prefUpdateCheckCount, checkCount + 1);
          return null;
        }
        await prefs.setInt(_prefUpdateCheckCount, checkCount + 1);
      }

      final currentVersion = await _getCurrentVersion();
      final releases = await _fetchReleases();
      if (releases.isEmpty) return null;

      final latestRelease = releases.first;

      if (!force) {
        final prefs = await SharedPreferences.getInstance();
        final skippedVersion = prefs.getString(_prefSkipVersion);
        if (skippedVersion == latestRelease['tag_name']) {
          return null;
        }
      }

      final latestTag = (latestRelease['tag_name'] ?? '').toString();
      final currentRelease = _findReleaseForVersion(releases, currentVersion);
      final latestPublished = _releaseDate(latestRelease);
      final currentPublished =
          currentRelease != null ? _releaseDate(currentRelease) : null;

      if (!isNewerRelease(
        latestTag,
        currentVersion,
        latestPublished: latestPublished,
        currentPublished: currentPublished,
      )) {
        return null;
      }

      final assets = latestRelease['assets'] as List?;
      final asset = Platform.isWindows
          ? _findDesktopAsset(assets)
          : _findApkAsset(assets);
      if (asset == null) return null;

      return UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestTag,
        downloadUrl: asset['browser_download_url'],
        releaseNotes: latestRelease['body'],
        apkSize: asset['size'] ?? 0,
        openInBrowser: Platform.isWindows && _shouldOpenDesktopAssetInBrowser(asset),
      );
    } catch (e) {
      return null;
    }
  }

  static Future<String> _getCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  static Future<List<Map<String, dynamic>>> _fetchReleases() async {
    final response = await _dio.get(
      'https://api.github.com/repos/$_owner/$_repo/releases',
      options: Options(
        headers: {
          'Accept': 'application/vnd.github+json',
        },
      ),
    );

    if (response.statusCode != 200) return [];

    final releases = response.data as List;
    final filtered = <Map<String, dynamic>>[];

    for (final release in releases) {
      final tagName = (release['tag_name'] ?? '').toString();
      if (!_isValidReleaseTag(tagName)) {
        continue;
      }
      if (release['prerelease'] == true) continue;
      if (release['draft'] == true) continue;
      if (_releaseDate(release) == null) continue;
      filtered.add(Map<String, dynamic>.from(release as Map));
    }

    filtered.sort((a, b) {
      final da = _releaseDate(a)!;
      final db = _releaseDate(b)!;
      return db.compareTo(da);
    });

    return filtered;
  }

  static DateTime? _releaseDate(Map<String, dynamic> release) {
    return DateTime.tryParse(release['published_at']?.toString() ?? '');
  }

  static Map<String, dynamic>? _findReleaseForVersion(
    List<Map<String, dynamic>> releases,
    String currentVersion,
  ) {
    for (final release in releases) {
      final tagName = (release['tag_name'] ?? '').toString();
      if (compareVersions(tagName, currentVersion) == 0) return release;
      if (_extractVersion(tagName) == _extractVersion(currentVersion)) {
        return release;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _findApkAsset(List? assets) {
    if (assets == null) return null;
    for (final asset in assets) {
      final name = (asset['name'] ?? '').toString().toLowerCase();
      if (name.endsWith('.apk')) {
        return asset;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _findDesktopAsset(List? assets) {
    if (assets == null) return null;
    const preferred = ['.zip', '.msix', '.msi', '.exe'];
    for (final ext in preferred) {
      for (final asset in assets) {
        final name = (asset['name'] ?? '').toString().toLowerCase();
        if (name.endsWith(ext)) return asset;
      }
    }
    return null;
  }

  static bool _shouldOpenDesktopAssetInBrowser(Map<String, dynamic> asset) {
    final name = (asset['name'] ?? '').toString().toLowerCase();
    return name.endsWith('.msix') || name.endsWith('.msi');
  }

  static bool _isValidReleaseTag(String tagName) {
    return _releaseTagPattern.hasMatch(tagName.trim());
  }

  /// Извлекает semver из тега (v0.4.1 → 0.4.1; legacy Android/Desktop — для skip pref).
  static String _extractVersion(String tag) {
    var cleaned = tag.trim();
    if (cleaned.toLowerCase().startsWith('v') &&
        cleaned.length > 1 &&
        RegExp(r'^\d').hasMatch(cleaned.substring(1))) {
      cleaned = cleaned.substring(1);
    }
    cleaned = cleaned.replaceFirst(
      RegExp(r'^(Android|Desktop)', caseSensitive: false),
      '',
    );
    cleaned = cleaned.split(RegExp(r'[^0-9.]')).first;
    return cleaned.isEmpty ? '0.0.0' : cleaned;
  }

  static String displayVersion(String tag) => _extractVersion(tag);

  static int compareVersions(String latest, String current) {
    final latestVersion = _extractVersion(latest);
    final currentVersion = _extractVersion(current);

    final latestParts =
        latestVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final currentParts =
        currentVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    final maxLen = latestParts.length > currentParts.length
        ? latestParts.length
        : currentParts.length;
    for (var i = 0; i < maxLen; i++) {
      final l = i < latestParts.length ? latestParts[i] : 0;
      final c = i < currentParts.length ? currentParts[i] : 0;
      if (l > c) return 1;
      if (l < c) return -1;
    }
    return 0;
  }

  static bool isNewerRelease(
    String latestTag,
    String currentTag, {
    DateTime? latestPublished,
    DateTime? currentPublished,
  }) {
    final cmp = compareVersions(latestTag, currentTag);
    if (cmp == 0) return false;

    final hasDates = latestPublished != null && currentPublished != null;

    if (cmp > 0) {
      if (hasDates && currentPublished.isAfter(latestPublished)) {
        return false;
      }
      return true;
    }

    if (hasDates && latestPublished.isAfter(currentPublished)) {
      return true;
    }
    return false;
  }

  static Future<void> skipVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefSkipVersion, version);
  }

  static Future<void> downloadAndInstall(
    UpdateInfo info, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (info.openInBrowser) {
      await _openUrlInBrowser(info.downloadUrl);
      return;
    }

    final dir = await getTemporaryDirectory();
    final ext = _extensionFromUrl(info.downloadUrl);
    final file = File('${dir.path}/keqdroid_update_${info.latestVersion}$ext');

    if (await file.exists()) {
      await file.delete();
    }

    await _dio.download(
      info.downloadUrl,
      file.path,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          onProgress?.call(received, total);
        }
      },
    );

    await OpenFilex.open(file.path);
  }

  static String _extensionFromUrl(String url) {
    final path = Uri.parse(url).path.toLowerCase();
    for (final ext in ['.zip', '.msix', '.msi', '.exe', '.apk']) {
      if (path.endsWith(ext)) return ext;
    }
    return Platform.isWindows ? '.zip' : '.apk';
  }

  static Future<void> _openUrlInBrowser(String url) async {
    if (Platform.isWindows) {
      await Process.start('cmd', ['/c', 'start', '', url], runInShell: true);
      return;
    }
    if (Platform.isMacOS) {
      await Process.start('open', [url]);
      return;
    }
    if (Platform.isLinux) {
      await Process.start('xdg-open', [url]);
      return;
    }
    await OpenFilex.open(url);
  }
}
