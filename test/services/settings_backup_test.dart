import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/routing_profile.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/models/subscription_card_layout.dart';
import 'package:keqdroid/models/subscription_card_theme.dart';
import 'package:keqdroid/models/traffic_route.dart';
import 'package:keqdroid/services/card_image_service.dart';
import 'package:keqdroid/services/settings_backup_service.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

class _MockStorageService extends Mock implements StorageService {}

/// Настройки, которые в бэкап НЕ уезжают, и причина у каждой группы своя.
///
/// Список живёт в тесте, а не рядом с белым в сервисе: в проде он никому не
/// нужен, а здесь работает второй половиной проверки «каждый ключ
/// классифицирован». Новое поле `AppSettings` попадёт ни в один из списков и
/// уронит тест — это и есть смысл затеи, решение принимает человек.
const _machineLocalKeys = <String>{
  // Порты этой машины: занятый сосед и зарезервированные Windows диапазоны —
  // свойство машины, а не выбор пользовательницы.
  'localPort',
  'httpPort',
  // LAN-раздача целиком: чужая сеть, чужие порты, а пароль ещё и лёг бы в
  // json-файл открытым текстом.
  'lanSharing',
  'lanSocksPort',
  'lanHttpPort',
  'lanUsername',
  'lanPassword',
  // Как поднимается туннель: зависит от прав, платформы и того, что за ядро
  // тут вообще есть.
  'tun',
  'connectionMode',
  // Вместе с самим режимом: «выбирали ли руками» — факт про эту установку, и на
  // чужой машине он означал бы, что за человека уже что-то решили.
  'connectionModeChosen',
  'proxyModeAuth',
  'proxyModeUser',
  'proxyModePass',
  'systemProxyEnabled',
  'coreEngine',
  // Десктопные флаги: на телефоне бессмысленны, на другом десктопе — сюрприз.
  'minimizeToTray',
  'launchAtStartup',
  // И то, чем именно он поднимается: задача планировщика заведена на пути
  // этого exe и на SID этого пользователя — на другой машине пустой звук.
  'launchAtStartupElevated',
  'autostartInTray',
  'hotkeys',
  // Состояние отладки, а не настройка: перевезти включённый debug на чистую
  // машину — это подарить себе многословные логи и вопрос «почему так».
  'debugMode',
};

void main() {
  setUpAll(() {
    registerFallbackValue(const AppSettings());
    registerFallbackValue(<Subscription>[]);
    registerFallbackValue(<TrafficRoute>[]);
    registerFallbackValue(<RoutingProfile>[]);
  });

  group('раздел «Настройки приложения»', () {
    test('каждый ключ настроек отнесён к переносимым или к машинным', () {
      final all = const AppSettings().toJson().keys.toSet();

      expect(
        all
            .difference(SettingsBackupService.portableSettingKeys)
            .difference(_machineLocalKeys),
        isEmpty,
        reason: 'новое поле AppSettings: реши, переносится оно между машинами '
            'или описывает эту машину, и допиши в нужный список',
      );
      expect(
        SettingsBackupService.portableSettingKeys.difference(all),
        isEmpty,
        reason: 'в белом списке ключ, которого нет в toJson() — опечатка или '
            'переименованное поле',
      );
      expect(
        SettingsBackupService.portableSettingKeys
            .intersection(_machineLocalKeys),
        isEmpty,
      );
    });

    test('переносимое приезжает, машинное остаётся от этой машины', () async {
      final source = const AppSettings().copyWith(
        directRules: 'ru, vk.com, mail.ru',
        finalOutbound: 'direct',
        themePresetId: 'ocean',
        appLanguageCode: 'ru',
        showTrafficStats: false,
        // машинное — не должно доехать
        localPort: 3080,
        lanPassword: 'hunter2',
        minimizeToTray: true,
      );

      final from = _MockStorageService();
      when(() => from.getSettings()).thenAnswer((_) async => source);
      when(() => from.getRoutes()).thenAnswer((_) async => const []);
      when(() => from.getRoutingProfiles()).thenAnswer((_) async => const []);
      final built = await SettingsBackupService.buildBackup(
        from,
        sections: {BackupSection.appSettings},
      );

      // Бэкап живёт файлом, а не объектом: гоняем через json, иначе проверка
      // прошла бы и на типах, которые до диска не доезжают.
      final text = built.toJsonString();
      expect(
        text,
        isNot(contains('hunter2')),
        reason: 'пароль LAN не должен попадать в файл, которым делятся',
      );
      final backup = KeqdisBackup.fromJson(
        jsonDecode(text) as Map<String, dynamic>,
      );
      expect(
        SettingsBackupService.detectSections(backup),
        contains(BackupSection.appSettings),
      );

      final target = const AppSettings().copyWith(
        localPort: 9090,
        lanPassword: 'local-secret',
        minimizeToTray: false,
      );
      AppSettings? saved;
      final to = _MockStorageService();
      when(() => to.getSettings()).thenAnswer((_) async => target);
      when(() => to.saveSettings(any())).thenAnswer((inv) async {
        saved = inv.positionalArguments.single as AppSettings;
      });
      when(() => to.getRoutes()).thenAnswer((_) async => const []);
      when(() => to.saveRoutes(any())).thenAnswer((_) async {});
      when(() => to.saveRoutingProfiles(any())).thenAnswer((_) async {});

      await SettingsBackupService.applyBackup(
        to,
        backup: backup,
        sections: {BackupSection.appSettings},
      );

      expect(saved, isNotNull);
      expect(saved!.directRules, 'ru, vk.com, mail.ru');
      expect(saved!.finalOutbound, 'direct');
      expect(saved!.themePresetId, 'ocean');
      expect(saved!.appLanguageCode, 'ru');
      expect(saved!.showTrafficStats, isFalse);

      expect(saved!.localPort, 9090);
      expect(saved!.lanPassword, 'local-secret');
      expect(saved!.minimizeToTray, isFalse);
    });

    // До 26.09.2026 fake-ip был настройкой одного mihomo и лежал в копии под
    // именем `mihomoFakeIp`: восстановление старой копии не должно его терять.
    test('fake-ip из старой копии доезжает под новым именем', () async {
      final from = _MockStorageService();
      when(() => from.getSettings())
          .thenAnswer((_) async => const AppSettings(fakeIp: true));
      when(() => from.getRoutes()).thenAnswer((_) async => const []);
      when(() => from.getRoutingProfiles()).thenAnswer((_) async => const []);
      final built = await SettingsBackupService.buildBackup(
        from,
        sections: {BackupSection.appSettings},
      );
      final json = jsonDecode(built.toJsonString()) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>;
      final app = data['appSettings'] as Map<String, dynamic>;
      app['mihomoFakeIp'] = app.remove('fakeIp');

      AppSettings? saved;
      final to = _MockStorageService();
      when(() => to.getSettings()).thenAnswer((_) async => const AppSettings());
      when(() => to.saveSettings(any())).thenAnswer((inv) async {
        saved = inv.positionalArguments.single as AppSettings;
      });
      when(() => to.saveRoutes(any())).thenAnswer((_) async {});
      when(() => to.saveRoutingProfiles(any())).thenAnswer((_) async {});
      await SettingsBackupService.applyBackup(
        to,
        backup: KeqdisBackup.fromJson(json),
        sections: {BackupSection.appSettings},
      );

      expect(saved!.fakeIp, isTrue);
    });
  });

  group('оформление карточек в бэкапе', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('keqdroid_cards');
      SubscriptionCardTheme.customDirectory = dir.path;
    });

    tearDown(() async {
      SubscriptionCardTheme.customDirectory = null;
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('палитровая тема, вуаль и состав едут полями подписки', () async {
      const sub = Subscription(
        id: 's1',
        name: 'S',
        url: 'https://a',
        cardThemeId: 'aurora',
        cardThemeInServers: false,
        hiddenCardElements: {SubscriptionCardElement.usage},
        cardVeil: CardVeil.strong,
      );

      final from = _MockStorageService();
      when(() => from.getSubscriptions()).thenAnswer((_) async => [sub]);
      final built = await SettingsBackupService.buildBackup(
        from,
        sections: {BackupSection.subscriptions},
      );
      final backup = KeqdisBackup.fromJson(
        jsonDecode(built.toJsonString()) as Map<String, dynamic>,
      );

      List<Subscription>? saved;
      final to = _MockStorageService();
      when(() => to.saveSubscriptions(any())).thenAnswer((inv) async {
        saved = inv.positionalArguments.single as List<Subscription>;
      });
      await SettingsBackupService.applyBackup(
        to,
        backup: backup,
        sections: {BackupSection.subscriptions},
      );

      expect(saved!.single.cardThemeId, 'aurora');
      expect(saved!.single.cardThemeInServers, isFalse);
      expect(saved!.single.hiddenCardElements, sub.hiddenCardElements);
      expect(saved!.single.cardVeil, CardVeil.strong);
    });

    test('своя картинка уезжает байтами и возвращается на месте', () async {
      // Ради этого всё и затевалось: id темы переносился и раньше, но файл
      // лежит в каталоге приложения, и на новой машине карточка молча
      // становилась обычной.
      const fileName = 's1-1787500014186.jpg';
      final bytes = List<int>.generate(64, (i) => i * 3 % 251);
      await File(p.join(dir.path, fileName)).writeAsBytes(bytes);

      const sub = Subscription(
        id: 's1',
        name: 'S',
        url: 'https://a',
        cardThemeId: '${SubscriptionCardTheme.filePrefix}$fileName',
      );

      final from = _MockStorageService();
      when(() => from.getSubscriptions()).thenAnswer((_) async => [sub]);
      final built = await SettingsBackupService.buildBackup(
        from,
        sections: {BackupSection.subscriptions},
      );
      final backup = KeqdisBackup.fromJson(
        jsonDecode(built.toJsonString()) as Map<String, dynamic>,
      );

      // Новая машина: подписки те же, картинки на диске нет.
      await File(p.join(dir.path, fileName)).delete();

      final to = _MockStorageService();
      when(() => to.saveSubscriptions(any())).thenAnswer((_) async {});
      await SettingsBackupService.applyBackup(
        to,
        backup: backup,
        sections: {BackupSection.subscriptions},
      );

      final restored = File(p.join(dir.path, fileName));
      expect(restored.existsSync(), isTrue);
      expect(await restored.readAsBytes(), bytes);
    });

    test('без своей картинки раздела картинок в файле нет', () async {
      const sub = Subscription(
        id: 's1',
        name: 'S',
        url: 'https://a',
        cardThemeId: 'aurora',
      );
      final from = _MockStorageService();
      when(() => from.getSubscriptions()).thenAnswer((_) async => [sub]);
      final built = await SettingsBackupService.buildBackup(
        from,
        sections: {BackupSection.subscriptions},
      );

      expect(built.data.containsKey('cardImages'), isFalse);
    });

    test('бэкап без картинок читается — старые файлы никуда не делись', () async {
      final backup = KeqdisBackup.fromJson(jsonDecode(jsonEncode({
        'format': 'keqdis_backup',
        'version': 1,
        'exportedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'data': {
          'subscriptions': [
            const Subscription(id: 's1', name: 'S', url: 'https://a').toJson(),
          ],
        },
      })) as Map<String, dynamic>);

      final to = _MockStorageService();
      when(() => to.saveSubscriptions(any())).thenAnswer((_) async {});

      await expectLater(
        SettingsBackupService.applyBackup(
          to,
          backup: backup,
          sections: {BackupSection.subscriptions},
        ),
        completes,
      );
    });

    test('имя файла из бэкапа не выводит за каталог картинок', () async {
      // Бэкап — файл откуда угодно, и ключ в нём это имя файла, а не путь.
      final payload = base64.encode(const [1, 2, 3]);
      await CardImageService.importAll({
        '../escaped.jpg': payload,
        '..\\escaped-win.jpg': payload,
        'nested/dir.jpg': payload,
        'ok.jpg': payload,
      });

      expect(File(p.join(dir.path, 'ok.jpg')).existsSync(), isTrue);
      expect(
        File(p.join(dir.parent.path, 'escaped.jpg')).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(dir.parent.path, 'escaped-win.jpg')).existsSync(),
        isFalse,
      );
      expect(dir.listSync().length, 1);
    });

    test('мусор вместо base64 не роняет импорт целиком', () async {
      await CardImageService.importAll({
        'broken.jpg': 'не base64 вовсе',
        'ok.jpg': base64.encode(const [7, 7, 7]),
      });

      expect(File(p.join(dir.path, 'ok.jpg')).existsSync(), isTrue);
      expect(File(p.join(dir.path, 'broken.jpg')).existsSync(), isFalse);
    });
  });

  group('проверка имени файла картинки', () {
    test('обычное имя проходит', () {
      expect(CardImageService.isSafeImageFileName('s1-123.jpg'), isTrue);
    });

    test('пути и служебные имена отклоняются', () {
      for (final bad in const [
        '',
        '.',
        '..',
        '../x.jpg',
        '..\\x.jpg',
        'a/b.jpg',
        'a\\b.jpg',
        'C:x.jpg',
      ]) {
        expect(
          CardImageService.isSafeImageFileName(bad),
          isFalse,
          reason: 'принято небезопасное имя "$bad"',
        );
      }
    });
  });

  group('чтение файла бэкапа', () {
    // Правила маршрутизации лежат в бэкапе строкой с JSON внутри — отсюда
    // экранированные кавычки и скобки внутри строк, как на жалобе
    // («}omain:rshb.ru\",\n …»).
    KeqdisBackup backupWithRules(List<String> rules) => KeqdisBackup(
          version: 1,
          exportedAt: DateTime.utc(2026, 9, 28),
          data: {
            'appSettings': {'directRules': jsonEncode(rules)},
          },
        );

    List<int> bytesOf(KeqdisBackup backup) => utf8.encode(backup.toJsonString());

    // Ровно то, что оставляет запись без обрезки: новый файл с начала, дальше
    // конец старого с того же байта.
    List<int> overwritten(List<int> fresh, List<int> old) =>
        [...fresh, ...old.sublist(fresh.length)];

    test('целый файл читается как раньше', () {
      final text = backupWithRules(['domain:rt.ru']).toJsonString();
      final backup = KeqdisBackup.parse(utf8.encode(text));
      expect(backup.data, jsonDecode(text)['data']);
    });

    test('новый бэкап поверх более длинного старого читается без хвоста', () {
      final old = bytesOf(backupWithRules([
        for (var i = 0; i < 40; i++) 'domain:site$i.ru',
        'domain:rshb.ru',
        'domain:rt.ru',
      ]));
      final fresh = backupWithRules(['domain:{x}.ru', 'regexp:"q"']);
      final onDisk = overwritten(bytesOf(fresh), old);
      expect(() => jsonDecode(utf8.decode(onDisk)), throwsFormatException);

      expect(KeqdisBackup.parse(onDisk).data, fresh.data);
    });

    test('хвост, начатый с середины русской буквы, тоже отрезается', () {
      final old = bytesOf(backupWithRules([
        for (var i = 0; i < 40; i++) 'domain:сайт$i.рф',
      ]));
      // Подбираем длину нового так, чтобы граница пришлась на второй байт
      // кириллической буквы старого файла.
      late KeqdisBackup fresh;
      late List<int> freshBytes;
      for (var pad = 0;; pad++) {
        fresh = backupWithRules(['domain:${'x' * pad}.ru']);
        freshBytes = bytesOf(fresh);
        final next = old[freshBytes.length];
        if (next >= 0x80 && next < 0xC0) break;
      }
      final onDisk = overwritten(freshBytes, old);
      expect(() => utf8.decode(onDisk), throwsFormatException);

      expect(KeqdisBackup.parse(onDisk).data, fresh.data);
    });

    test('оборванный файл по-прежнему не читается', () {
      final bytes = bytesOf(backupWithRules(['domain:rt.ru']));
      expect(
        () => KeqdisBackup.parse(bytes.sublist(0, bytes.length - 10)),
        throwsFormatException,
      );
    });

    test('мусор внутри объекта не прячется за обрезкой', () {
      final text = backupWithRules(['domain:rt.ru'])
          .toJsonString()
          .replaceFirst('"version"', 'version');
      expect(
        () => KeqdisBackup.parse(utf8.encode('$text tail')),
        throwsFormatException,
      );
    });

    test('не объект — не бэкап', () {
      expect(
        () => KeqdisBackup.parse(utf8.encode('[1, 2]')),
        throwsFormatException,
      );
    });
  });
}
