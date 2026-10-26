import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/subscription_card_theme.dart';
import 'card_video.dart';
import 'file_dialog_service.dart';

enum CardImageRejection {
  aspect,

  tooSmall,

  tooLarge,

  unreadable,
}

class CardImageResult {
  const CardImageResult.picked(this.theme)
      : rejection = null,
        cancelled = false;
  const CardImageResult.rejected(this.rejection)
      : theme = null,
        cancelled = false;
  const CardImageResult.cancelled()
      : theme = null,
        rejection = null,
        cancelled = true;

  final SubscriptionCardTheme? theme;
  final CardImageRejection? rejection;
  final bool cancelled;
}

class CardImageService {
  CardImageService._();

  static const minAspect = 1.2;
  static const maxAspect = 5.0;
  static const minWidth = 600;
  static const maxWidth = 4000;

  static String get sizeHint => '$minWidth–$maxWidth px';

  static Future<void> warmUp() async {
    try {
      await rescan();
    } catch (_) {}
  }

  static Future<void> rescan() async {
    final dir = Directory(await _directoryPath());
    if (!dir.existsSync()) {
      SubscriptionCardTheme.customFiles = <String>{};
      return;
    }
    final names = <String>{};
    await for (final entry in dir.list()) {
      if (entry is File) names.add(p.basename(entry.path));
    }
    SubscriptionCardTheme.customFiles = names;
  }

  static Future<String> _directoryPath() async {
    final known = SubscriptionCardTheme.customDirectory;
    if (known != null) return known;
    final base = await getApplicationSupportDirectory();
    final path = p.join(base.path, 'card_themes');
    SubscriptionCardTheme.customDirectory = path;
    return path;
  }

  static Future<Directory> _directory() async {
    final dir = Directory(await _directoryPath());
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  static Future<CardImageResult> pick({required String subscriptionId}) async {
    final picked = await AppFileDialogs.pickFile(
      type: CardVideo.supported ? FileType.media : FileType.image,
    );
    final path = picked?.path;
    if (path == null) return const CardImageResult.cancelled();

    final dir = await _directory();
    final ext = p.extension(path).toLowerCase();
    // метка времени в имени: Flutter кэширует картинки по пути, и перезаписанный файл показывался бы старым
    final stamp = '$subscriptionId-${DateTime.now().millisecondsSinceEpoch}';
    // прошлую картинку не трогаем до Сохранить, уборка в prune
    if (CardVideo.supported && CardVideo.extensions.contains(ext)) {
      return _pickVideo(path, dir.path, '$stamp.mp4');
    }

    final rejection = await _validate(File(path));
    if (rejection != null) return CardImageResult.rejected(rejection);

    if (CardVideo.supported && ext == '.gif') {
      final video = await _gifToVideo(path, dir.path, '$stamp.mp4');
      if (video != null) return CardImageResult.picked(video);
    }
    final fileName = '$stamp$ext';
    await File(path).copy(p.join(dir.path, fileName));
    SubscriptionCardTheme.customFiles?.add(fileName);

    return CardImageResult.picked(
      SubscriptionCardTheme.file(fileName, dir.path),
    );
  }

  static Future<CardImageResult> _pickVideo(
    String path,
    String dir,
    String fileName,
  ) async {
    final out = p.join(dir, fileName);
    try {
      final info = await CardVideo.probe(path);
      if (!info.hasVideo) {
        return const CardImageResult.rejected(CardImageRejection.unreadable);
      }
      final rejection = _checkSize(info.width, info.height);
      if (rejection != null) return CardImageResult.rejected(rejection);
      await CardVideo.transcode(
        input: path,
        output: out,
        width: info.width,
        height: info.height,
      );
    } catch (_) {
      _deleteVideo(out);
      return const CardImageResult.rejected(CardImageRejection.unreadable);
    }
    await _register(dir, fileName);
    return CardImageResult.picked(SubscriptionCardTheme.file(fileName, dir));
  }

  // гифка уходит в видео; не вышло, остаётся гифкой, как раньше
  static Future<SubscriptionCardTheme?> _gifToVideo(
    String path,
    String dir,
    String fileName,
  ) async {
    final out = p.join(dir, fileName);
    try {
      if (!await CardVideo.encodeGif(path, out)) return null;
    } catch (_) {
      _deleteVideo(out);
      return null;
    }
    await _register(dir, fileName);
    return SubscriptionCardTheme.file(fileName, dir);
  }

  /// гифки, выбранные до перехода на видео; null, если перекодировать нечего
  static Future<String?> migrateGif(
    String themeId,
    String subscriptionId,
  ) async {
    if (!CardVideo.supported) return null;
    final path = await resolvePath(themeId);
    if (path == null || p.extension(path).toLowerCase() != '.gif') return null;
    final dir = await _directory();
    final video = await _gifToVideo(
      path,
      dir.path,
      '$subscriptionId-${DateTime.now().millisecondsSinceEpoch}.mp4',
    );
    return video?.id;
  }

  static Future<void> _register(String dir, String videoName) async {
    SubscriptionCardTheme.customFiles
      ?..add(videoName)
      ..add(SubscriptionCardTheme.posterFor(videoName));
    // постер в кэше картинок заранее: иначе при подмене темы карточка кадр-другой пустая
    final ready = Completer<void>();
    final stream = FileImage(
      File(p.join(dir, SubscriptionCardTheme.posterFor(videoName))),
    ).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (_, _) {
        if (!ready.isCompleted) ready.complete();
      },
      onError: (_, _) {
        if (!ready.isCompleted) ready.complete();
      },
    );
    stream.addListener(listener);
    await ready.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    stream.removeListener(listener);
  }

  static void _deleteVideo(String path) {
    for (final f in [path, SubscriptionCardTheme.posterFor(path)]) {
      try {
        File(f).deleteSync();
      } catch (_) {}
    }
  }

  static Future<String?> resolvePath(String themeId) async {
    if (!themeId.startsWith(SubscriptionCardTheme.filePrefix)) return null;
    final name = themeId.substring(SubscriptionCardTheme.filePrefix.length);
    final file = File(p.join(await _directoryPath(), name));
    return file.existsSync() ? file.path : null;
  }

  static Future<void> remove(String subscriptionId) =>
      prune(subscriptionId, null);

  static Future<Map<String, String>> exportForThemes(
    Iterable<String> themeIds,
  ) async {
    final out = <String, String>{};
    for (final id in themeIds) {
      if (!id.startsWith(SubscriptionCardTheme.filePrefix)) continue;
      final name = id.substring(SubscriptionCardTheme.filePrefix.length);
      if (out.containsKey(name)) continue;
      try {
        final path = await resolvePath(id);
        if (path == null) continue;
        out[name] = base64.encode(await File(path).readAsBytes());
        if (SubscriptionCardTheme.isVideoFile(name)) {
          final poster = File(SubscriptionCardTheme.posterFor(path));
          if (poster.existsSync()) {
            out[SubscriptionCardTheme.posterFor(name)] =
                base64.encode(await poster.readAsBytes());
          }
        }
      } catch (_) {}
    }
    return out;
  }

  // ключ из бэкапа обязан быть именем файла, иначе ../ писал бы за пределы каталога
  static Future<void> importAll(Map<String, String> files) async {
    if (files.isEmpty) return;
    final dir = await _directory();
    for (final entry in files.entries) {
      if (!isSafeImageFileName(entry.key)) continue;
      final List<int> bytes;
      try {
        bytes = base64.decode(entry.value);
      } catch (_) {
        continue;
      }
      if (bytes.isEmpty || bytes.length > maxRestoredBytes) continue;
      try {
        await File(p.join(dir.path, entry.key)).writeAsBytes(bytes, flush: true);
        SubscriptionCardTheme.customFiles?.add(entry.key);
      } catch (_) {}
    }
  }

  static const maxRestoredBytes = 16 * 1024 * 1024;

  static bool isSafeImageFileName(String name) {
    if (name.isEmpty || name.length > 128) return false;
    if (name == '.' || name == '..') return false;
    if (name.contains(RegExp(r'[\\/:*?"<>|]'))) return false;
    return p.basename(name) == name;
  }

  static Future<void> prune(String subscriptionId, String? keepThemeId) async {
    final keep = keepThemeId != null &&
            keepThemeId.startsWith(SubscriptionCardTheme.filePrefix)
        ? keepThemeId.substring(SubscriptionCardTheme.filePrefix.length)
        : null;
    final dir = Directory(await _directoryPath());
    if (!dir.existsSync()) return;
    await for (final entry in dir.list()) {
      if (entry is! File) continue;
      final name = p.basename(entry.path);
      if (name == keep ||
          (keep != null && name == SubscriptionCardTheme.posterFor(keep)) ||
          !_belongsTo(name, subscriptionId)) {
        continue;
      }
      try {
        await entry.delete();
        SubscriptionCardTheme.customFiles?.remove(name);
      } catch (_) {}
    }
  }

  static bool _belongsTo(String fileName, String subscriptionId) {
    final base = p.basenameWithoutExtension(fileName);
    return base == subscriptionId || base.startsWith('$subscriptionId-');
  }

  static Future<CardImageRejection?> _validate(File file) async {
    final ui.Image image;
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      image = (await codec.getNextFrame()).image;
    } catch (_) {
      return CardImageRejection.unreadable;
    }
    try {
      return _checkSize(image.width, image.height);
    } finally {
      image.dispose();
    }
  }

  static CardImageRejection? _checkSize(int width, int height) {
    if (width < minWidth) return CardImageRejection.tooSmall;
    if (width > maxWidth) return CardImageRejection.tooLarge;
    if (height <= 0) return CardImageRejection.unreadable;
    final aspect = width / height;
    if (aspect < minAspect || aspect > maxAspect) {
      return CardImageRejection.aspect;
    }
    return null;
  }
}
