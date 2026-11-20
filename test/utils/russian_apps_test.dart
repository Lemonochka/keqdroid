import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/russian_apps.dart';

// Кнопка русские приложения мимо VPN решает по имени пакета. Жалоб было
// две: отмечает не всё, а у одного пользователя отметила полтелефона, включая
// системные приложения.
void main() {
  bool user(String pkg) => isRussianApp(pkg, isSystem: false);
  bool system(String pkg) => isRussianApp(pkg, isSystem: true);

  // Не из прежнего списка префиксов: раньше такие пропускались.
  test('любой ru.* и su.* — русский', () {
    for (final pkg in const [
      'ru.instamart',
      'ru.tander.magnit',
      'ru.more.play',
      'ru.oneme.app',
      'ru.rostel',
      'su.example.app',
    ]) {
      expect(user(pkg), isTrue, reason: pkg);
    }
  });

  // Сверены с Google Play и RuStore: международный домен, российский сервис.
  test('российские сервисы с com.*-пакетом', () {
    for (final pkg in const [
      'com.vkontakte.android',
      'com.vk.vkvideo',
      'com.avito.android',
      'com.idamob.tinkoff.android',
      'com.wildberries.ru',
      'com.lamoda.lite',
      'com.yandex.browser',
      'com.kms.free',
      'com.kaspersky.passwordmanager',
      'com.drweb',
      'com.citymobil',
      'com.taxsee.taxsee',
      'com.deliveryclub',
      'com.punicapp.whoosh',
      'gpm.tnt_premier',
    ]) {
      expect(user(pkg), isTrue, reason: pkg);
    }
  });

  test('системные приложения производителей и Google — не русские', () {
    for (final pkg in const [
      'com.android.settings',
      'com.android.chrome',
      'com.google.android.gms',
      'com.miui.securitycenter',
      'com.xiaomi.market',
      'com.samsung.android.dialer',
      'com.huawei.appmarket',
      'org.futo.inputmethod.latin',
    ]) {
      expect(system(pkg), isFalse, reason: pkg);
      expect(user(pkg), isFalse, reason: pkg);
    }
  });

  // Российские предустановки остаются: RuStore ставят на все телефоны,
  // проданные в России, Яндекс на многие.
  test('российские предустановки отмечаются и как системные', () {
    expect(system('ru.vk.store'), isTrue);
    expect(system('com.yandex.searchapp'), isTrue);
    expect(system('ru.mts.mymts'), isTrue);
  });

  // Хвост .ru у производителя может означать региональную сборку своей же
  // программы, а не российский сервис.
  test('хвост .ru засчитывается только несистемным', () {
    expect(user('com.example.shop.ru'), isTrue);
    expect(system('com.vendor.launcher.ru'), isFalse);
  });

  // Прежний поиск подстрок ловил их в любом месте имени.
  test('подстроки внутри чужого имени больше не срабатывают', () {
    for (final pkg in const [
      'com.oplus.ozone',
      'com.example.vtbox',
      'com.acme.yandexclient',
      'com.brand.apteki',
      'com.shop.avitotools',
    ]) {
      expect(user(pkg), isFalse, reason: pkg);
    }
  });

  test('регистр и пробелы не мешают, пустое не русское', () {
    expect(user('  RU.Sberbankmobile '), isTrue);
    expect(user(''), isFalse);
    expect(user('ru'), isFalse);
  });
}
