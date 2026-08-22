import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/subscription_card_theme.dart';
import 'package:keqdroid/services/card_image_service.dart';
import 'package:path/path.dart' as p;

/// Сам выбор файла (диалог) не тестируется — тестируется всё, что вокруг:
/// какие файлы считаются принадлежащими подписке и какие переживают уборку.
/// Каталог подсовывается через [SubscriptionCardTheme.customDirectory]: это тот
/// же кэш пути, которым пользуется приложение, path_provider тут не при чём.
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('card_images_test');
    SubscriptionCardTheme.customDirectory = dir.path;
  });

  tearDown(() {
    SubscriptionCardTheme.customDirectory = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File touch(String name) =>
      File(p.join(dir.path, name))..writeAsBytesSync(const [0]);

  List<String> names() => dir
      .listSync()
      .map((e) => p.basename(e.path))
      .toList()
    ..sort();

  test('уборка оставляет выбранную картинку и уносит прошлую', () async {
    touch('sub1-100.jpg');
    final kept = touch('sub1-200.png');

    await CardImageService.prune('sub1', 'file:sub1-200.png');

    expect(names(), ['sub1-200.png']);
    expect(kept.existsSync(), isTrue);
  });

  test('уборка не трогает картинки других подписок', () async {
    touch('sub1-100.jpg');
    touch('sub2-100.jpg');

    await CardImageService.prune('sub1', 'file:sub1-100.jpg');

    expect(names(), ['sub1-100.jpg', 'sub2-100.jpg']);
  });

  test('уборка признаёт старое имя без метки времени', () async {
    // Так назывались картинки до перехода на уникальные имена: у тех, кто уже
    // выбрал картинку, на диске лежит именно такой файл.
    touch('sub1.jpg');
    touch('sub1-300.jpg');

    await CardImageService.prune('sub1', 'file:sub1-300.jpg');

    expect(names(), ['sub1-300.jpg']);
  });

  test('переход на палитру уносит картинку подписки', () async {
    touch('sub1-100.jpg');

    await CardImageService.prune('sub1', 'aurora');

    expect(names(), isEmpty);
  });

  test('удаление подписки уносит все её картинки', () async {
    touch('sub1-100.jpg');
    touch('sub1-200.jpg');
    touch('sub2-100.jpg');

    await CardImageService.remove('sub1');

    expect(names(), ['sub2-100.jpg']);
  });

  test('уборка по несуществующему каталогу молчит', () async {
    dir.deleteSync(recursive: true);
    await expectLater(CardImageService.remove('sub1'), completes);
  });

  test('путь отдаётся только для своей и существующей картинки', () async {
    touch('sub1-100.jpg');

    expect(await CardImageService.resolvePath('file:sub1-100.jpg'),
        p.join(dir.path, 'sub1-100.jpg'));
    // Картинку удалили мимо приложения — слайдер покажет кнопку выбора, а не
    // сломанную миниатюру.
    expect(await CardImageService.resolvePath('file:sub1-999.jpg'), isNull);
    // Встроенная тема — не своя картинка.
    expect(await CardImageService.resolvePath('aurora'), isNull);
  });
}
