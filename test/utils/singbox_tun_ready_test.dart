import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/singbox_tun_config.dart';

/// В TUN-режиме keqrnel — один процесс, и в его выводе перемешаны строки
/// sing-box и встроенного xray. Ядро стартует АУТБАУНДЫ раньше инбаундов
/// (`Box.preStart` → outbound, затем `Box.start` → inbound), поэтому баннер
/// xray появляется до того, как создан адаптер и прописаны маршруты.
///
/// Прежняя проверка («в логе есть "started" и где-нибудь есть "tun"») на этом
/// баннере и срабатывала: приложение показывало «Подключено» и заводило таймер
/// сессии, пока трафик ещё шёл мимо туннеля. Это и есть жалоба «работает
/// только через 20 секунд после включения».
void main() {
  const xrayBannerOnly = '''
+0300 2026-08-23 01:00:01 INFO outbound/xray[proxy]: starting engine
Xray 26.7.28 (Xray, Penetrates Everything.) Custom (go1.26.5 windows/amd64)
[Info] proxy/vless/outbound: tunneling request to tcp:example.com:443
[Warning] core: Xray 26.7.28 started
''';

  test('баннер встроенного xray готовностью не считается', () {
    expect(singboxTunReady(xrayBannerOnly), isFalse);
  });

  test('tun-инбаунд поднялся — готово', () {
    expect(
      singboxTunReady(
        '$xrayBannerOnly'
        '+0300 2026-08-23 01:00:04 INFO inbound/tun[tun-in]: started at tun-keqdis\n',
      ),
      isTrue,
    );
  });

  test('финальная строка ядра — тоже готово', () {
    expect(
      singboxTunReady(
        '$xrayBannerOnly'
        '+0300 2026-08-23 01:00:04 INFO sing-box started (3.42s)\n',
      ),
      isTrue,
    );
  });

  test('строка обёртки keqrnel — тоже готово', () {
    expect(
      singboxTunReady('$xrayBannerOnly+0300 INFO keqrnel started\n'),
      isTrue,
    );
  });

  test('пустой лог — не готово', () {
    expect(singboxTunReady(''), isFalse);
  });
}
