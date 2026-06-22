import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'windows_zip_updater.dart';

/// инфа о доступном обновлении
class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final String? releaseNotes;
  final int apkSize;
  final bool openInBrowser;

  /// File name of the release asset being downloaded (e.g. `keqdroid-0.5.0.apk`).
  /// Used to locate its SHA-256 line inside a multi-asset checksums file.
  final String assetName;

  /// `browser_download_url` of the SHA-256 sidecar for [assetName], if the
  /// release published one. `null` means no checksum is available.
  final String? checksumUrl;

  UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    this.releaseNotes,
    required this.apkSize,
    this.openInBrowser = false,
    this.assetName = '',
    this.checksumUrl,
  });

  String get formattedSize {
    if (apkSize < 1024) return '$apkSize B';
    if (apkSize < 1024 * 1024) {
      return '${(apkSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(apkSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get displayCurrentVersion =>
      UpdateService.displayVersion(currentVersion);
  String get displayLatestVersion =>
      UpdateService.displayVersion(latestVersion);

  bool get hasNewVersion {
    return UpdateService.isNewerRelease(latestVersion, currentVersion);
  }
}

class UpdateService {
  static const _owner = 'Lemonochka';
  static const _repo = 'keqdroid';

  /// Единый semver-тег релиза: v0.1.0, v0.4.1 (Android + Windows в одном release).
  // Tags may or may not carry a leading "v" (e.g. both `v0.5.1` and `0.5.1`).
  // Requiring the "v" silently dropped releases tagged without it, so the app
  // never offered them as updates.
  static final _releaseTagPattern = RegExp(
    r'^v?\d+\.\d+(\.\d+)?(-[\w.]+)?$',
    caseSensitive: false,
  );

  static final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

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
      final currentPublished = currentRelease != null
          ? _releaseDate(currentRelease)
          : null;

      if (!isNewerRelease(
        latestTag,
        currentVersion,
        latestPublished: latestPublished,
        currentPublished: currentPublished,
      )) {
        return null;
      }

      final assets = latestRelease['assets'] as List?;
      final asset = _findAssetForCurrentPlatform(assets);
      if (asset == null) return null;

      final assetName = (asset['name'] ?? '').toString();
      final checksumAsset = _findChecksumAsset(assets, assetName);

      return UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestTag,
        downloadUrl: asset['browser_download_url'],
        releaseNotes: latestRelease['body'],
        apkSize: asset['size'] ?? 0,
        openInBrowser:
            Platform.isWindows && _shouldOpenDesktopAssetInBrowser(asset),
        assetName: assetName,
        checksumUrl: checksumAsset?['browser_download_url'] as String?,
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
      options: Options(headers: {'Accept': 'application/vnd.github+json'}),
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

  static Map<String, dynamic>? _findAssetForCurrentPlatform(List? assets) {
    if (Platform.isWindows) return _findWindowsAsset(assets);
    if (Platform.isLinux) return _findLinuxAsset(assets);
    return _findApkAsset(assets);
  }

  static String? findAssetNameForPlatform(List? assets, String platform) {
    final asset = switch (platform) {
      'windows' => _findWindowsAsset(assets),
      'linux' => _findLinuxAsset(assets),
      'android' => _findApkAsset(assets),
      _ => null,
    };
    return asset?['name']?.toString();
  }

  static Map<String, dynamic>? _findWindowsAsset(List? assets) {
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

  static Map<String, dynamic>? _findLinuxAsset(List? assets) {
    if (assets == null) return null;
    const preferredSuffixes = [
      '-x86_64.appimage',
      '.appimage',
      '-linux-x64.tar.gz',
      'linux-x64.tar.gz',
      '_amd64.deb',
      '.deb',
    ];
    for (final suffix in preferredSuffixes) {
      for (final asset in assets) {
        final name = (asset['name'] ?? '').toString().toLowerCase();
        if (name.endsWith(suffix)) return asset;
      }
    }
    return null;
  }

  /// Locates the SHA-256 checksum asset for [assetName]. Supports either a
  /// per-asset sidecar (`<assetName>.sha256`) or a shared checksums file
  /// (`SHA256SUMS` / `checksums.txt`) listing `<hash>  <filename>` lines.
  static Map<String, dynamic>? _findChecksumAsset(
    List? assets,
    String assetName,
  ) {
    if (assets == null || assetName.isEmpty) return null;
    final target = '${assetName.toLowerCase()}.sha256';

    // 1) dedicated sidecar next to the asset.
    for (final asset in assets) {
      final name = (asset['name'] ?? '').toString().toLowerCase();
      if (name == target) return asset as Map<String, dynamic>;
    }

    // 2) shared checksums manifest.
    const shared = {
      'sha256sums',
      'sha256sums.txt',
      'checksums.txt',
      'checksums.sha256',
    };
    for (final asset in assets) {
      final name = (asset['name'] ?? '').toString().toLowerCase();
      if (shared.contains(name)) return asset as Map<String, dynamic>;
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

    final latestParts = latestVersion
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    final currentParts = currentVersion
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();

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

  /// Returns `true` when the app is exiting to apply a Windows portable update.
  static Future<bool> downloadAndInstall(
    UpdateInfo info, {
    void Function(int received, int total)? onProgress,
    Future<void> Function()? beforeRestart,
  }) async {
    if (info.openInBrowser) {
      await _openUrlInBrowser(info.downloadUrl);
      return false;
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

    // Never hand an unverified binary to the OS installer / portable updater.
    try {
      await _verifyDownloadedFile(file, info);
    } catch (_) {
      if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    }

    if (Platform.isWindows && ext == '.zip') {
      return WindowsZipUpdater.applyPortableZipUpdate(
        zipPath: file.path,
        beforeRestart: beforeRestart,
      );
    }

    await OpenFilex.open(file.path);
    return false;
  }

  static String _extensionFromUrl(String url) {
    final path = Uri.parse(url).path.toLowerCase();
    for (final ext in [
      '.tar.gz',
      '.appimage',
      '.deb',
      '.zip',
      '.msix',
      '.msi',
      '.exe',
      '.apk',
    ]) {
      if (path.endsWith(ext)) return ext;
    }
    if (Platform.isWindows) return '.zip';
    if (Platform.isLinux) return '.AppImage';
    return '.apk';
  }

  /// Fail closed: refuse to install an update whose SHA-256 can't be verified.
  /// Set to `false` only if you must support releases published without a
  /// checksum sidecar (weakens the integrity guarantee).
  static const bool _requireChecksum = true;

  /// Throws if the downloaded [file] doesn't match the release's published
  /// SHA-256. A `null`/missing checksum is treated as a failure when
  /// [_requireChecksum] is set.
  static Future<void> _verifyDownloadedFile(File file, UpdateInfo info) async {
    final checksumUrl = info.checksumUrl;
    if (checksumUrl == null || checksumUrl.isEmpty) {
      if (_requireChecksum) {
        throw StateError(
          'No SHA-256 checksum published for ${info.assetName.isEmpty ? 'this update' : info.assetName}; '
          'refusing to install an unverified build.',
        );
      }
      return;
    }

    final expected = await _fetchExpectedSha256(checksumUrl, info.assetName);
    if (expected == null) {
      throw StateError(
        'Could not read the SHA-256 checksum for ${info.assetName}; aborting update.',
      );
    }

    final actual = await _sha256OfFile(file);
    if (actual.toLowerCase() != expected.toLowerCase()) {
      throw StateError(
        'Update integrity check failed for ${info.assetName} '
        '(expected $expected, got $actual). The download was discarded.',
      );
    }
  }

  /// Streams [file] through SHA-256 so large updates aren't loaded into memory.
  static Future<String> _sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString(); // lowercase hex
  }

  static Future<String?> _fetchExpectedSha256(
    String url,
    String assetName,
  ) async {
    try {
      final response = await _dio.get<String>(url);
      if (response.statusCode != 200) return null;
      return _parseSha256(response.data ?? '', assetName);
    } catch (_) {
      return null;
    }
  }

  /// Test hook for [_parseSha256] (kept public like the other version helpers).
  static String? extractSha256(String manifest, String assetName) =>
      _parseSha256(manifest, assetName);

  /// Extracts the 64-hex-char SHA-256 for [assetName]. Handles a bare hash, a
  /// `sha256sum`-style `<hash>  <file>` line, and multi-asset manifests.
  static String? _parseSha256(String text, String assetName) {
    final hexPattern = RegExp(r'\b[a-fA-F0-9]{64}\b');
    final lowerAsset = assetName.toLowerCase();

    if (lowerAsset.isNotEmpty) {
      for (final line in const LineSplitter().convert(text)) {
        if (line.toLowerCase().contains(lowerAsset)) {
          final m = hexPattern.firstMatch(line);
          if (m != null) return m.group(0)!.toLowerCase();
        }
      }
    }

    // Dedicated sidecar usually contains exactly one hash and no filename.
    final m = hexPattern.firstMatch(text);
    return m?.group(0)?.toLowerCase();
  }

  /// Только https и без shell-метасимволов — защита от инъекции в `cmd /c start`,
  /// если имя релизного ассета вдруг содержит `&`, `^`, `"` и т.п.
  static bool _isSafeHttpsUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
    return !RegExp(r'''[\s&|<>^"'`%]''').hasMatch(url);
  }

  static Future<void> _openUrlInBrowser(String url) async {
    if (!_isSafeHttpsUrl(url)) return;
    if (Platform.isWindows) {
      // без runInShell; url уже провалидирован (нет метасимволов cmd)
      await Process.start('cmd', ['/c', 'start', '', url]);
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
