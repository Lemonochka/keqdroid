import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/app_logger.dart';
import '../core/exceptions.dart';

// портал без backend'а отвечает отменой мгновенно, рукой за 400 мс диалог не закрыть,
// поэтому быстрый null считаем поломкой и идём в zenity/qarma/kdialog
abstract final class AppFileDialogs {
  static const _nativeChannel = MethodChannel('keqdroid_vpn_channel');

  static const _silentFailureWindow = Duration(milliseconds: 400);

  static const _cliTools = ['zenity', 'qarma', 'kdialog'];

  static Future<PlatformFile?> pickFile({
    String? dialogTitle,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) async {
    if (!Platform.isLinux) {
      return FilePicker.pickFile(
        dialogTitle: dialogTitle,
        type: type,
        allowedExtensions: allowedExtensions,
      );
    }

    final portal = await _tryPortal(
      () => FilePicker.pickFile(
        dialogTitle: dialogTitle,
        type: type,
        allowedExtensions: allowedExtensions,
      ),
    );
    if (portal.trusted) return portal.value;

    final filter = _filterFor(type, allowedExtensions);
    final cli = await _runCliDialog(
      (tool) => _openArgs(tool, dialogTitle ?? 'Open file', filter),
    );
    if (cli.ran) {
      final path = cli.path;
      return path == null ? null : _platformFile(path);
    }

    throw FileDialogUnavailableException(cause: portal.error);
  }

  static Future<String?> saveFile({
    required String fileName,
    required Uint8List bytes,
    String? dialogTitle,
    String mimeType = 'application/octet-stream',
  }) async {
    if (Platform.isAndroid) {
      // пишет натив: file_picker не обрезает файл при перезаписи
      return _nativeChannel.invokeMethod<String>('saveDocument', {
        'fileName': fileName,
        'mimeType': mimeType,
        'bytes': bytes,
      });
    }
    if (!Platform.isLinux) {
      return FilePicker.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        bytes: bytes,
      );
    }

    final portal = await _tryPortal(
      () => FilePicker.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        bytes: bytes,
      ),
    );
    if (portal.trusted) return portal.value;

    final cli = await _runCliDialog(
      (tool) => _saveArgs(tool, dialogTitle ?? 'Save file', fileName),
    );
    if (cli.ran) {
      final path = cli.path;
      if (path == null) return null;
      await File(path).writeAsBytes(bytes, flush: true);
      return path;
    }

    throw FileDialogUnavailableException(cause: portal.error);
  }

  static Future<({bool trusted, T? value, Object? error})> _tryPortal<T>(
    Future<T?> Function() pick,
  ) async {
    final started = DateTime.now();
    try {
      final result = await pick();
      if (result != null) return (trusted: true, value: result, error: null);
      if (DateTime.now().difference(started) >= _silentFailureWindow) {
        return (trusted: true, value: null, error: null);
      }
      AppLogger.instance.warn(
        'XDG portal file dialog answered "cancelled" instantly — no FileChooser '
        'backend, falling back to CLI dialogs',
      );
      return (trusted: false, value: null, error: null);
    } catch (e) {
      AppLogger.instance.warn('XDG portal file dialog failed: $e');
      return (trusted: false, value: null, error: e);
    }
  }

  static Future<({bool ran, String? path})> _runCliDialog(
    List<String> Function(String tool) args,
  ) async {
    for (final tool in _cliTools) {
      final ProcessResult res;
      try {
        res = await Process.run(tool, args(tool));
      } on ProcessException {
        continue;
      }
      // 1 значит отмена, остальное ненулевое это поломка утилиты
      if (res.exitCode == 1) return (ran: true, path: null);
      if (res.exitCode != 0) {
        AppLogger.instance.warn(
          '$tool file dialog failed (exit ${res.exitCode}): ${res.stderr}',
        );
        continue;
      }
      final path = '${res.stdout}'.split('\n').first.trim();
      return (ran: true, path: path.isEmpty ? null : path);
    }
    return (ran: false, path: null);
  }

  @visibleForTesting
  static List<String> cliOpenArgs(
    String tool, {
    String title = 'Open file',
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) =>
      _openArgs(tool, title, _filterFor(type, allowedExtensions));

  @visibleForTesting
  static List<String> cliSaveArgs(
    String tool, {
    String title = 'Save file',
    required String fileName,
  }) =>
      _saveArgs(tool, title, fileName);

  static List<String> _openArgs(String tool, String title, _Filter? filter) {
    if (tool == 'kdialog') {
      return [
        '--title',
        title,
        '--getopenfilename',
        // без стартового каталога kdialog примет за него фильтр
        _homeDir(),
        if (filter != null) '${filter.patterns.join(' ')}|${filter.label}',
      ];
    }
    return [
      '--file-selection',
      '--title=$title',
      if (filter != null)
        '--file-filter=${filter.label} | ${filter.patterns.join(' ')}',
    ];
  }

  static List<String> _saveArgs(String tool, String title, String fileName) {
    final suggested = p.join(_homeDir(), fileName);
    if (tool == 'kdialog') {
      return ['--title', title, '--getsavefilename', suggested];
    }
    // --confirm-overwrite в свежих zenity выпилен, неизвестный аргумент даёт ошибку
    return [
      '--file-selection',
      '--save',
      '--title=$title',
      '--filename=$suggested',
    ];
  }

  static _Filter? _filterFor(FileType type, List<String>? allowedExtensions) {
    switch (type) {
      case FileType.image:
        return const _Filter(
          'Images',
          ['*.png', '*.jpg', '*.jpeg', '*.gif', '*.webp', '*.bmp'],
        );
      case FileType.custom:
        if (allowedExtensions == null || allowedExtensions.isEmpty) return null;
        final patterns = allowedExtensions.map((e) => '*.$e').toList();
        return _Filter(patterns.join(' '), patterns);
      default:
        return null;
    }
  }

  static PlatformFile _platformFile(String path) {
    final file = File(path);
    return PlatformFile(
      path: path,
      name: p.basename(path),
      size: file.existsSync() ? file.lengthSync() : 0,
    );
  }

  static String _homeDir() =>
      Platform.environment['HOME'] ?? Directory.current.path;
}

class _Filter {
  final String label;
  final List<String> patterns;

  const _Filter(this.label, this.patterns);
}
