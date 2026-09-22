import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/services/ping_service.dart';

/// Кого можно измерить общим конфигом, а кого нельзя.
///
/// Общий конфиг складывает серверы в один документ: у каждого свой инбаунд,
/// свой аутбаунд и свои правила. Сервер, который сам себе конфиг — готовый
/// Clash или Xray от провайдера, цепочка, AmneziaWG — туда не вкладывается:
/// он несёт собственные инбаунды, роутинг и DNS, и попытка его «вложить»
/// молча измерила бы не то. Такие остаются на поштучном пути.
void main() {
  const vless =
      'vless://bfd62637-6d18-49ea-b726-82274f5dda83@a.example.com:443?encryption=none&type=tcp&security=reality&sni=www.nvidia.com&pbk=KlybaLW0-grtjEATyTVFIYoWIaoW-Duxi4lcM54_t2U#a';
  const hysteria = 'hy2://secret@b.example.com:443?sni=b.example.com#b';
  const awg = '''
[Interface]
PrivateKey = aQ==
Address = 10.0.0.2/32

[Peer]
PublicKey = bQ==
Endpoint = c.example.com:51820
''';
  const clashYaml = '''
proxies:
  - name: node
    type: vless
    server: d.example.com
    port: 443
    uuid: bfd62637-6d18-49ea-b726-82274f5dda83
''';
  const xrayJson = '{"outbounds":[{"protocol":"vless","tag":"proxy"}]}';

  test('обычные ссылки складываются', () {
    expect(PingService.mergeableForMultiPing(vless), isTrue);
    expect(PingService.mergeableForMultiPing(hysteria), isTrue);
  });

  test('сервер, который сам себе конфиг, — нет', () {
    expect(PingService.mergeableForMultiPing(clashYaml), isFalse);
    expect(PingService.mergeableForMultiPing(xrayJson), isFalse);
    expect(PingService.mergeableForMultiPing(awg), isFalse);
  });

  test('мусор не складывается тоже', () {
    // Иначе первая же непонятная строка уронила бы весь общий конфиг, а с ним
    // и замеры двадцати здоровых серверов рядом.
    expect(PingService.mergeableForMultiPing('какая-то строка'), isFalse);
    expect(PingService.mergeableForMultiPing(''), isFalse);
  });

  test('групповой путь включается только там, где его умеют', () {
    // На десктопе процессов не жалко, и общий конфиг там пришлось бы
    // заворачивать в keqrnel, чьи инбаунды принадлежат sing-box.
    expect(PingService.multiPingSupported, isFalse, reason: 'тесты идут на Windows');

    PingService.debugMultiPingSupported = true;
    addTearDown(() => PingService.debugMultiPingSupported = null);
    expect(PingService.multiPingSupported, isTrue);
  });

  test('на десктопе замеров идёт больше, чем на телефоне', () {
    // Цена замера — процесс ядра: 28 МБ у keqrnel, 19 у mihomo (замерено).
    // На ПК шестнадцать таких стоят 450 МБ на несколько секунд, на телефоне
    // столько не удержать — там подписку меряет общий конфиг.
    PlatformBootstrap.debugIsDesktopOverride = true;
    addTearDown(() => PlatformBootstrap.debugIsDesktopOverride = null);
    expect(PingService.urlPingConcurrency, 16);

    PlatformBootstrap.debugIsDesktopOverride = false;
    expect(PingService.urlPingConcurrency, 6);
  });

  test('размер чанка не «все разом»', () {
    // Батч падает целиком из-за одного негодного сервера: чем он больше, тем
    // дороже деление пополам, которым мы ищем виноватого.
    expect(PingService.multiPingChunk, lessThanOrEqualTo(25));
    expect(PingService.multiPingChunk, greaterThan(1));
  });
}
