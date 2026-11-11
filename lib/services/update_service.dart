import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'linux_appimage_updater.dart';
import 'linux_install.dart';
import 'release_signature.dart';
import 'windows_install.dart';
import 'windows_setup_updater.dart';
import 'windows_zip_updater.dart';
import '../core/app_logger.dart';
import '../utils/local_vpn_proxy.dart';

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final String? releaseNotes;
  final int apkSize;
  final bool openInBrowser;

  final String assetName;

  final String? checksumUrl;

  final String? signatureUrl;

  UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    this.releaseNotes,
    required this.apkSize,
    this.openInBrowser = false,
    this.assetName = '',
    this.checksumUrl,
    this.signatureUrl,
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

  // ведущая v необязательна: в репозитории есть теги обоих видов
  static final _releaseTagPattern = RegExp(
    r'^v?\d+\.\d+(\.\d+)?(-[\w.]+)?$',
    caseSensitive: false,
  );

  static const _prefSkipVersion = 'skip_update_version';

  // найденное обновление не затираем null-ом, иначе бейдж в настройках пропадает после переключения VPN
  static UpdateInfo? _cachedAutoResult;
  static DateTime? _lastAutoCheckAt;
  static Future<UpdateInfo?>? _autoCheckInFlight;

  @visibleForTesting
  static Duration minAutoCheckGap = const Duration(minutes: 30);

  static DateTime? get lastAutoCheckAt => _lastAutoCheckAt;

  @visibleForTesting
  static Future<UpdateInfo?> Function({
    required bool viaLocalProxy,
    required int httpPort,
  }) fetchUpdate = _fetchUpdate;

  @visibleForTesting
  static void resetAutoCheck() {
    _cachedAutoResult = null;
    _lastAutoCheckAt = null;
    _autoCheckInFlight = null;
  }

  // при включённом VPN через локальный HTTP-инбаунд: пакет приложения исключён из TUN,
  // а release-assets.githubusercontent.com заблокирован
  static Dio _buildDio({bool viaLocalProxy = false, int httpPort = 2081}) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 60),
        // без User-Agent GitHub отвечает 403, Dart/x.y тоже режет
        headers: {'User-Agent': '$_repo-updater'},
      ),
    );
    configureDioForActiveVpn(
      dio,
      useLocalProxy: viaLocalProxy,
      httpPort: httpPort,
    );
    return dio;
  }

  // пропущенную версию отдаёт тоже: пропуск гасит только само всплывающее окно
  static Future<UpdateInfo?> checkForUpdate({
    bool force = false,
    bool viaLocalProxy = false,
    int httpPort = 2081,
  }) async {
    if (force) {
      return _checkLogged(
        viaLocalProxy: viaLocalProxy,
        httpPort: httpPort,
        force: true,
      );
    }
    final last = _lastAutoCheckAt;
    if (last != null && DateTime.now().difference(last) < minAutoCheckGap) {
      return _cachedAutoResult;
    }
    return _autoCheckInFlight ??=
        _autoCheck(viaLocalProxy: viaLocalProxy, httpPort: httpPort)
            .whenComplete(() => _autoCheckInFlight = null);
  }

  static Future<UpdateInfo?> _autoCheck({
    required bool viaLocalProxy,
    required int httpPort,
  }) async {
    try {
      final result = await _checkLogged(
        viaLocalProxy: viaLocalProxy,
        httpPort: httpPort,
        force: false,
      );
      _cachedAutoResult = result;
      _lastAutoCheckAt = DateTime.now();
      return result;
    } catch (_) {
      // до первой удачной проверки пустой ответ карточка показала бы как актуальную версию
      if (_lastAutoCheckAt == null) rethrow;
      return _cachedAutoResult;
    }
  }

  static Future<UpdateInfo?> _checkLogged({
    required bool viaLocalProxy,
    required int httpPort,
    required bool force,
  }) async {
    try {
      return await fetchUpdate(viaLocalProxy: viaLocalProxy, httpPort: httpPort);
    } catch (e) {
      AppLogger.instance.warn(
        'Update check failed '
        '(${viaLocalProxy ? 'via local proxy 127.0.0.1:$httpPort' : 'direct'}, '
        '${force ? 'manual' : 'auto'}): $e',
      );
      rethrow;
    }
  }

  static Future<UpdateInfo?> _fetchUpdate({
    required bool viaLocalProxy,
    required int httpPort,
  }) async {
    final dio = _buildDio(viaLocalProxy: viaLocalProxy, httpPort: httpPort);
    final currentVersion = await _getCurrentVersion();
    final linuxKind = Platform.isLinux ? await LinuxInstall.detect() : null;
    final windowsInstalled = await WindowsInstall.isInstalledCopy();
    final releases = await fetchReleases(dio);
    if (releases.isEmpty) {
      throw StateError('Could not fetch releases from GitHub');
    }
    return buildUpdateInfo(
      releases,
      currentVersion,
      linuxKind: linuxKind,
      windowsInstalled: windowsInstalled,
    );
  }

  @visibleForTesting
  static UpdateInfo? buildUpdateInfo(
    List<Map<String, dynamic>> releases,
    String currentVersion, {
    LinuxInstallKind? linuxKind,
    bool windowsInstalled = false,
  }) {
    final latestRelease = releases.first;
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
    final asset = linuxKind != null
        ? _findLinuxAsset(assets, linuxKind)
        : _findAssetForCurrentPlatform(assets, windowsInstalled: windowsInstalled);
    if (asset == null) return null;

    final assetName = (asset['name'] ?? '').toString();
    final checksumAsset = ReleaseSignature.sumsAsset(assets) ??
        _findChecksumAsset(assets, assetName);
    final signatureAsset = ReleaseSignature.signatureAsset(assets);

    return UpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestTag,
      // pacman обновляет pacman: ведём на страницу релиза, keqdroid-bin в AUR может и не быть
      downloadUrl: linuxKind == LinuxInstallKind.pacman
          ? (latestRelease['html_url'] ??
              'https://github.com/$_owner/$_repo/releases/latest')
          : asset['browser_download_url'],
      releaseNotes: latestRelease['body'],
      apkSize: asset['size'] ?? 0,
      openInBrowser: linuxKind == LinuxInstallKind.pacman ||
          linuxKind == LinuxInstallKind.readOnly ||
          (Platform.isWindows && _shouldOpenDesktopAssetInBrowser(asset)),
      assetName: assetName,
      checksumUrl: checksumAsset?['browser_download_url'] as String?,
      signatureUrl: signatureAsset?['browser_download_url'] as String?,
    );
  }

  static Future<String> _getCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  @visibleForTesting
  static Future<List<Map<String, dynamic>>> fetchReleases(Dio dio) async {
    final filtered = <Map<String, dynamic>>[];

    // двух страниц хватает, больше только жжёт лимит 60 запросов в час
    for (var page = 1; page <= 2; page++) {
      final Response response;
      try {
        response = await _getReleasesPage(dio, page);
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (status == 403 || status == 429) {
          throw StateError(
            'GitHub rate limit reached (HTTP $status). Try again in a few minutes'
            '${page == 1 ? '' : ', or check without the VPN connected'}.',
          );
        }
        rethrow;
      }

      if (response.statusCode != 200) break;

      final releases = response.data as List;
      if (releases.isEmpty) break;

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

      if (releases.length < 100) break;
    }

    filtered.sort((a, b) {
      final da = _releaseDate(a)!;
      final db = _releaseDate(b)!;
      return db.compareTo(da);
    });

    return filtered;
  }

  // один повтор: WRONG_VERSION_NUMBER бывает разовым, таймауты не повторяем
  static Future<Response> _getReleasesPage(Dio dio, int page) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await dio.get(
          'https://api.github.com/repos/$_owner/$_repo/releases',
          queryParameters: {'per_page': 100, 'page': page},
          options: Options(headers: {'Accept': 'application/vnd.github+json'}),
        );
      } on DioException catch (e) {
        if (attempt > 0 || !isBrokenConnection(e)) rethrow;
        AppLogger.instance.warn(
          'Releases page $page: connection broke before the response, '
          'retrying once: ${e.error ?? e.type}',
        );
      }
    }
  }

  @visibleForTesting
  static bool isBrokenConnection(DioException e) =>
      e.response == null &&
      (e.type == DioExceptionType.connectionError ||
          (e.type == DioExceptionType.unknown && e.error is IOException));

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

  static const _arm32ApkMarker = 'armeabi-v7a';

  // APK своей ABI: arm64 на 32-битную прошивку не встанет.
  // первый .apk брать нельзя, его выбирают версии до 32-битного APK
  static Map<String, dynamic>? _findApkAsset(
    List? assets, {
    required bool arm32,
  }) {
    if (assets == null) return null;
    for (final asset in assets) {
      final name = (asset['name'] ?? '').toString().toLowerCase();
      if (name.endsWith('.apk') && name.contains(_arm32ApkMarker) == arm32) {
        return asset;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _findAssetForCurrentPlatform(
    List? assets, {
    bool windowsInstalled = false,
  }) {
    if (Platform.isWindows) {
      return _findWindowsAsset(assets, installed: windowsInstalled);
    }
    return _findApkAsset(assets, arm32: Abi.current() == Abi.androidArm);
  }

  static String? findAssetNameForPlatform(
    List? assets,
    String platform, {
    LinuxInstallKind linuxKind = LinuxInstallKind.appImage,
  }) {
    final asset = switch (platform) {
      'windows' => _findWindowsAsset(assets),
      'windows-installed' => _findWindowsAsset(assets, installed: true),
      'linux' => _findLinuxAsset(assets, linuxKind),
      'android' => _findApkAsset(assets, arm32: false),
      'android-arm' => _findApkAsset(assets, arm32: true),
      _ => null,
    };
    return asset?['name']?.toString();
  }

  // без установщика в релизе установленная копия возьмёт zip: обновится, хоть версия в «Приложениях» и отстанет
  static Map<String, dynamic>? _findWindowsAsset(
    List? assets, {
    bool installed = false,
  }) {
    if (assets == null) return null;
    if (installed) {
      for (final asset in assets) {
        final name = (asset['name'] ?? '').toString().toLowerCase();
        if (name.endsWith(WindowsInstall.setupSuffix)) return asset;
      }
    }
    const preferred = ['.zip', '.msix', '.msi', '.exe'];
    for (final ext in preferred) {
      for (final asset in assets) {
        final name = (asset['name'] ?? '').toString().toLowerCase();
        if (name.endsWith(ext)) return asset;
      }
    }
    return null;
  }

  // файл того же вида, что установлен: AppImage вместо deb оставлял старую версию
  static Map<String, dynamic>? _findLinuxAsset(
    List? assets,
    LinuxInstallKind kind,
  ) {
    if (assets == null) return null;
    final preferredSuffixes = switch (kind) {
      LinuxInstallKind.appImage => const ['-x86_64.appimage', '.appimage'],
      LinuxInstallKind.deb => const ['_amd64.deb', '.deb'],
      LinuxInstallKind.rpm => const ['.x86_64.rpm', '.rpm'],
      LinuxInstallKind.pacman ||
      LinuxInstallKind.portable ||
      LinuxInstallKind.readOnly =>
        const ['-linux-x64.tar.gz'],
    };
    for (final suffix in preferredSuffixes) {
      for (final asset in assets) {
        final name = (asset['name'] ?? '').toString().toLowerCase();
        if (name.endsWith(suffix)) return asset;
      }
    }
    return null;
  }

  static Map<String, dynamic>? checksumAssetFor(
    List? assets,
    String assetName,
  ) =>
      _findChecksumAsset(assets, assetName);

  // хеш либо в <имя>.sha256 рядом, либо в общем SHA256SUMS/checksums.txt, с 0.19.0 только общий
  static Map<String, dynamic>? _findChecksumAsset(
    List? assets,
    String assetName,
  ) {
    if (assets == null || assetName.isEmpty) return null;
    final target = '${assetName.toLowerCase()}.sha256';

    for (final asset in assets) {
      final name = (asset['name'] ?? '').toString().toLowerCase();
      if (name == target) return asset as Map<String, dynamic>;
    }

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

  static Future<bool> isSkipped(String version) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefSkipVersion) == version;
  }

  static Future<bool> downloadAndInstall(
    UpdateInfo info, {
    bool viaLocalProxy = false,
    int httpPort = 2081,
    void Function(int received, int total)? onProgress,
    Future<void> Function()? beforeRestart,
  }) async {
    final dio = _buildDio(viaLocalProxy: viaLocalProxy, httpPort: httpPort);
    if (info.openInBrowser) {
      await _openUrlInBrowser(info.downloadUrl);
      return false;
    }

    final dir = await getTemporaryDirectory();
    final ext = extensionFromUrl(info.downloadUrl);
    final file = File('${dir.path}/keqdroid_update_${info.latestVersion}$ext');

    if (await file.exists()) {
      await file.delete();
    }

    await dio.download(
      info.downloadUrl,
      file.path,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          onProgress?.call(received, total);
        }
      },
    );

    // непроверенный файл установщику не отдаём
    try {
      await _verifyDownloadedFile(file, info, dio);
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

    if (Platform.isWindows &&
        info.assetName.toLowerCase().endsWith(WindowsInstall.setupSuffix) &&
        await WindowsInstall.isInstalledCopy()) {
      return WindowsSetupUpdater.runSilentSetup(
        setupPath: file.path,
        beforeRestart: beforeRestart,
      );
    }

    if (Platform.isLinux && ext == '.appimage') {
      final target = LinuxAppImageUpdater.currentAppImagePath();
      // только туда, куда можно писать, иначе скрипт молча запустит старую версию
      if (target != null && LinuxInstall.isWritableDir(p.dirname(target))) {
        return LinuxAppImageUpdater.applyInPlace(
          newAppImage: file.path,
          targetAppImage: target,
          beforeRestart: beforeRestart,
        );
      }
      final saved = await LinuxInstall.saveToDownloads(
        file.path,
        info.assetName,
        executable: true,
      );
      throw StateError(
        target == null
            ? 'The AppImage this app was started from has been moved or '
                'renamed, so it cannot be replaced in place. The new version '
                'is saved as $saved'
            : 'The AppImage is in ${p.dirname(target)}, where this user '
                'cannot write, so it cannot be replaced in place. The new '
                'version is saved as $saved',
      );
    }

    if (Platform.isLinux && (ext == '.deb' || ext == '.rpm')) {
      return LinuxInstall.installPackage(
        file.path,
        beforeRestart: beforeRestart,
      );
    }

    if (Platform.isLinux && ext == '.tar.gz') {
      return LinuxInstall.applyPortable(
        file.path,
        beforeRestart: beforeRestart,
      );
    }

    await OpenFilex.open(file.path);
    return false;
  }

  @visibleForTesting
  static String extensionFromUrl(String url) {
    final path = Uri.parse(url).path.toLowerCase();
    for (final ext in [
      '.tar.gz',
      '.appimage',
      '.deb',
      '.rpm',
      '.zip',
      '.msix',
      '.msi',
      '.exe',
      '.apk',
    ]) {
      if (path.endsWith(ext)) return ext;
    }
    // не угадываем: .zip ушёл бы в портейбл-апдейтер с распаковкой поверх приложения
    throw StateError(
      'Unsupported update file type: ${path.split('/').last}. '
      'Download the release manually.',
    );
  }

  static Future<void> _verifyDownloadedFile(
    File file,
    UpdateInfo info,
    Dio dio,
  ) async {
    final checksumUrl = info.checksumUrl;
    final signatureUrl = info.signatureUrl;
    if (checksumUrl == null ||
        checksumUrl.isEmpty ||
        signatureUrl == null ||
        signatureUrl.isEmpty) {
      throw StateError(
        'No signed SHA-256 checksum published for ${info.assetName.isEmpty ? 'this update' : info.assetName}; '
        'refusing to install an unverified build.',
      );
    }

    final manifest = await ReleaseSignature.fetchVerifiedSums(
      dio,
      sumsUrl: checksumUrl,
      signatureUrl: signatureUrl,
    );
    final expected = _parseSha256(manifest, info.assetName);
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

  static Future<String> _sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  static String? extractSha256(String manifest, String assetName) =>
      _parseSha256(manifest, assetName);

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

    final m = hexPattern.firstMatch(text);
    return m?.group(0)?.toLowerCase();
  }

  // только https и без метасимволов cmd: ссылка идёт в cmd /c start
  static bool _isSafeHttpsUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
    return !RegExp(r'''[\s&|<>^"'`%]''').hasMatch(url);
  }

  static Future<void> _openUrlInBrowser(String url) async {
    if (!_isSafeHttpsUrl(url)) {
      throw StateError(
        'Refusing to open unsafe download URL. '
        'Download the release manually from GitHub.',
      );
    }
    if (Platform.isWindows) {
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
