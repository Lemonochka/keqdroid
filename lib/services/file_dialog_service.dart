import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/app_logger.dart';
import '../core/exceptions.dart';

/// Системные диалоги «открыть файл» и «сохранить файл».
///
/// Везде, кроме Linux, это тонкая обёртка над file_picker: у Windows свои
/// FFI-диалоги, у Android/iOS — системный пикер, они не подводят.
///
/// На Linux своего диалога у приложения нет: file_picker 12 ходит по D-Bus в
/// портал XDG (`org.freedesktop.portal.Desktop`), а тот сам ничего не рисует —
/// за FileChooser отвечает backend (`xdg-desktop-portal-gtk`, `-kde`,
/// `-gnome`). На голых сессиях без backend'а (niri, sway и прочие
/// wlroots-композиторы, где портал ставят ради одного screencast'а) кнопка
/// «Импорт из файла» молчала: портал отвечает «отменено» — тем же кодом, что и
/// живой диалог, который человек закрыл сам, — и file_picker отдаёт `null`.
/// Отличить одно от другого можно только по времени: рукой отмену за 400 мс не
/// успеть, поэтому мгновенный `null` считаем поломкой портала и переспрашиваем
/// через zenity/qarma/kdialog. Если и их нет — бросаем
/// [FileDialogUnavailableException], чтобы экран сказал, чего не хватает,
/// вместо очередного «ничего не произошло».
abstract final class AppFileDialogs {
  /// Быстрее этого человек диалог не закроет — значит, его и не показывали.
  static const _silentFailureWindow = Duration(milliseconds: 400);

  /// Порядок важен: zenity — GTK, как и само приложение; qarma — её же
  /// аргументы под Qt; kdialog последний, у него свой синтаксис.
  static const _cliTools = ['zenity', 'qarma', 'kdialog'];

  /// Выбор одного файла. `null` — человек отказался.
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

  /// Диалог сохранения: возвращает путь, по которому уже лежат [bytes], или
  /// `null`, если человек отказался.
  static Future<String?> saveFile({
    required String fileName,
    required Uint8List bytes,
    String? dialogTitle,
  }) async {
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
      // Портальный saveFile пишет файл сам, CLI-утилиты отдают только путь:
      // дописываем, чтобы у обеих веток был один и тот же итог.
      await File(path).writeAsBytes(bytes, flush: true);
      return path;
    }

    throw FileDialogUnavailableException(cause: portal.error);
  }

  /// Прогон портального диалога с разбором двух его немых отказов: исключения
  /// D-Bus (портала нет вовсе) и мгновенного `null` (портал есть, backend'а
  /// нет). `trusted` — ответу можно верить, дальше идти не нужно.
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

  /// Первая утилита, которая реально запустилась, и решает исход: её «отмена»
  /// — отмена, а не повод показать человеку второй диалог подряд.
  static Future<({bool ran, String? path})> _runCliDialog(
    List<String> Function(String tool) args,
  ) async {
    for (final tool in _cliTools) {
      final ProcessResult res;
      try {
        res = await Process.run(tool, args(tool));
      } on ProcessException {
        continue; // утилиты нет в PATH
      }
      // 1 — «Отмена»/закрытое окно; всё остальное ненулевое (нет дисплея,
      // неизвестный аргумент) — поломка самой утилиты, пробуем следующую.
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

  /// Аргументы CLI-диалогов наружу ради тестов: сам диалог проверяется только
  /// руками и только на Linux, а порядок аргументов у kdialog ломкий —
  /// перепутанные местами каталог и фильтр дают ту же немую неудачу, ради
  /// которой всё это и написано.
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
        // Стартовый каталог позиционный и обязателен: без него kdialog примет
        // за него сам фильтр.
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
    // `--confirm-overwrite` не передаём: в свежих zenity он выпилен, а
    // неизвестный аргумент — это выход с ошибкой вместо диалога.
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
