import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/subscription_card_theme.dart';
import 'file_dialog_service.dart';

/// Почему картинку не взяли. Текст подбирает экран — здесь только причина.
enum CardImageRejection {
  /// Слишком узкая или слишком высокая: карточка низкая и широкая, портрет в
  /// ней превратится в полоску из середины.
  aspect,

  /// Слишком мелкая: растянутая на всю ширину карточки будет мылом.
  tooSmall,

  /// Неприлично большая: держать в памяти декодированные десятки мегапикселей
  /// ради полоски 3:1 незачем.
  tooLarge,

  /// Файл не читается или это не картинка.
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

/// Своя картинка на карточку подписки: выбор, проверка, копия в каталог
/// приложения.
class CardImageService {
  CardImageService._();

  /// Границы, при которых картинка на карточке выглядит картинкой, а не
  /// случайно обрезанным куском.
  ///
  /// Карточка широкая и низкая, картинка кроется по `BoxFit.cover` — значит из
  /// портрета в неё попадёт горизонтальная полоса из середины, а из панорамы
  /// 8:1 останется центральный огрызок. Поэтому берём только близкое к
  /// пропорциям самой карточки.
  static const minAspect = 1.2;
  static const maxAspect = 5.0;
  static const minWidth = 600;
  static const maxWidth = 4000;

  /// Диапазон для подписи под кнопкой: «от 600 до 4000 px по ширине».
  static String get sizeHint => '$minWidth–$maxWidth px';

  /// Узнать каталог картинок заранее — один раз на старте приложения.
  ///
  /// Карточка подписки рисуется синхронно, а путь к каталогу достаётся
  /// асинхронно. Без этого своя картинка не могла бы попасть на карточку
  /// вообще: id в настройках есть, а куда за файлом идти — неизвестно.
  static Future<void> warmUp() async {
    try {
      await rescan();
    } catch (_) {
      // path_provider не ответил — своя картинка просто не покажется, а
      // приложение стартует: из-за фона карточки падать не за что.
    }
  }

  /// Перечитать, какие свои картинки есть на диске.
  ///
  /// Набор нужен синхронно ([SubscriptionCardTheme.customFiles]): `cardThemeId`
  /// может ссылаться на картинку, которой нет — например подписка приехала из
  /// бэкапа, а байты картинки в него не попали.
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

  /// Каталог картинок. Однажды узнанный путь лежит в
  /// [SubscriptionCardTheme.customDirectory] — оттуда его берёт и карточка,
  /// которой некогда ждать асинхронный path_provider, и мы сами: миниатюра
  /// слайдера спрашивает путь на каждой перерисовке, и каждый раз ходить в
  /// платформенный канал незачем.
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

  /// Диалог выбора, проверка размеров и копия к себе.
  ///
  /// Копируем, а не запоминаем чужой путь: выбранный файл живёт в галерее или
  /// загрузках, его переименуют или удалят — и карточка облысеет. Своя копия
  /// принадлежит приложению и уезжает вместе с ним.
  static Future<CardImageResult> pick({required String subscriptionId}) async {
    final picked = await AppFileDialogs.pickFile(type: FileType.image);
    final path = picked?.path;
    if (path == null) return const CardImageResult.cancelled();

    final rejection = await _validate(File(path));
    if (rejection != null) return CardImageResult.rejected(rejection);

    final dir = await _directory();
    // Имя от подписки, а не от исходного файла: две подписки с картинками
    // `image.jpg` не должны затирать друг друга. Метка времени — потому что
    // Flutter кэширует картинки по пути: перезапиши файл на месте, и на
    // карточке ещё долго висела бы предыдущая.
    final ext = p.extension(path).toLowerCase();
    final fileName =
        '$subscriptionId-${DateTime.now().millisecondsSinceEpoch}$ext';
    // Прошлую картинку здесь не трогаем: выбор ещё не подтверждён кнопкой
    // «Сохранить», и отмена редактирования не должна оставлять карточку с
    // выбранной, но удалённой картинкой. Уборка — в [prune] при сохранении.
    await File(path).copy(p.join(dir.path, fileName));
    SubscriptionCardTheme.customFiles?.add(fileName);

    return CardImageResult.picked(
      SubscriptionCardTheme.file(fileName, dir.path),
    );
  }

  /// Путь к сохранённой картинке по id темы (`file:<имя>`); null — это не своя
  /// картинка либо файла уже нет.
  static Future<String?> resolvePath(String themeId) async {
    if (!themeId.startsWith(SubscriptionCardTheme.filePrefix)) return null;
    final name = themeId.substring(SubscriptionCardTheme.filePrefix.length);
    final file = File(p.join(await _directoryPath(), name));
    return file.existsSync() ? file.path : null;
  }

  /// Убрать все картинки подписки — при её удалении.
  static Future<void> remove(String subscriptionId) =>
      prune(subscriptionId, null);

  /// Картинки карточек для бэкапа: `{имя файла: base64}` по id тем подписок.
  ///
  /// В бэкап уезжают САМИ БАЙТЫ, а не путь. Картинка лежит в каталоге
  /// приложения, и на другой машине (или после переустановки) её там нет:
  /// `cardThemeId` восстанавливался, [resolveCardTheme] файла не находил и молча
  /// отдавал обычную карточку — со стороны «оформление не перенеслось».
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
      } catch (_) {
        // Файл занят, исчез между проверкой и чтением, или path_provider не
        // ответил и каталог неизвестен. Пропускаем картинку, а не роняем
        // экспорт целиком: подписки и настройки в бэкапе дороже.
      }
    }
    return out;
  }

  /// Разложить картинки из бэкапа обратно в каталог приложения.
  ///
  /// Файл бэкапа — данные откуда угодно, поэтому имена проверяются: ключ обязан
  /// быть именно именем файла. Без этого `../../` в ключе писал бы куда угодно
  /// за пределы каталога картинок.
  static Future<void> importAll(Map<String, String> files) async {
    if (files.isEmpty) return;
    final dir = await _directory();
    for (final entry in files.entries) {
      if (!isSafeImageFileName(entry.key)) continue;
      final List<int> bytes;
      try {
        bytes = base64.decode(entry.value);
      } catch (_) {
        continue; // не base64 — картинки просто не будет
      }
      if (bytes.isEmpty || bytes.length > maxRestoredBytes) continue;
      try {
        await File(p.join(dir.path, entry.key)).writeAsBytes(bytes, flush: true);
        SubscriptionCardTheme.customFiles?.add(entry.key);
      } catch (_) {
        // Каталог только для чтения, диск полон: карточка останется обычной,
        // но остальной импорт довести важнее.
      }
    }
  }

  /// Потолок на одну восстанавливаемую картинку. Своя укладывается в единицы
  /// мегабайт ([maxWidth] px по ширине); всё, что сильно больше, — либо чужой
  /// файл, либо мусор, и класть его на диск незачем.
  static const maxRestoredBytes = 16 * 1024 * 1024;

  /// Ключ из бэкапа — это имя файла, и ничего кроме.
  static bool isSafeImageFileName(String name) {
    if (name.isEmpty || name.length > 128) return false;
    if (name == '.' || name == '..') return false;
    if (name.contains(RegExp(r'[\\/:*?"<>|]'))) return false;
    // Windows-разделители ловит regexp выше, POSIX — тоже; basename остаётся
    // страховкой на случай форм, до которых regexp не добрался.
    return p.basename(name) == name;
  }

  /// Оставить у подписки только выбранную картинку, остальные — удалить.
  ///
  /// Зовётся при сохранении подписки: выбор копирует файл сразу, но
  /// подтверждается кнопкой «Сохранить». До неё на диске лежат обе картинки —
  /// старая (вдруг отмена) и новая. Здесь лишняя и убирается.
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
      if (name == keep || !_belongsTo(name, subscriptionId)) continue;
      try {
        await entry.delete();
        SubscriptionCardTheme.customFiles?.remove(name);
      } catch (_) {
        // Занят другим процессом — уберётся при следующем сохранении.
      }
    }
  }

  /// Файл этой подписки? Кроме нынешнего `<id>-<время>.jpg` признаём и старое
  /// `<id>.jpg`: у тех, кто уже выбрал картинку, она лежит под этим именем.
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
      if (image.width < minWidth) return CardImageRejection.tooSmall;
      if (image.width > maxWidth) return CardImageRejection.tooLarge;
      final aspect = image.width / image.height;
      if (aspect < minAspect || aspect > maxAspect) {
        return CardImageRejection.aspect;
      }
      return null;
    } finally {
      image.dispose();
    }
  }
}
