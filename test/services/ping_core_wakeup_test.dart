import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/ephemeral_xray_ping.dart';
import 'package:keqdroid/tunnel/vpn_backend.dart';

/// Открытый порт ядра замера — ещё не готовность.
///
/// mihomo поднимает листенеры раньше, чем дочитывает конфиг, и до конца
/// загрузки молча закрывает всё, что успело подключиться. Проба видит ровно
/// то же, что на мёртвом сервере, поэтому первые секунды жизни ядра её отказ
/// ничего не доказывает. При живом туннеле ядро доходит до рабочего состояния
/// за 1.3-1.8 с (замерено на Pixel 6a) — отсюда и вся эта история с «при
/// включённом VPN пинг показывает N/A на всей подписке».
void main() {
  test('свежему mihomo дают время проснуться', () {
    expect(
      EphemeralXrayPing.retryProbeWhileCoreWakesUp(
        core: VpnBackend.mihomo,
        sinceCoreStart: const Duration(milliseconds: 300),
      ),
      isTrue,
    );
    expect(
      EphemeralXrayPing.retryProbeWhileCoreWakesUp(
        core: VpnBackend.mihomo,
        sinceCoreStart: const Duration(milliseconds: 1800),
      ),
      isTrue,
    );
  });

  test('запас кончается — дальше отказ принадлежит серверу', () {
    expect(
      EphemeralXrayPing.retryProbeWhileCoreWakesUp(
        core: VpnBackend.mihomo,
        sinceCoreStart: EphemeralXrayPing.coreWakeupGrace,
      ),
      isFalse,
    );
  });

  test('xray ждать не заставляем', () {
    // У него листенеры поднимаются последними: открытый порт и есть
    // готовность, а лишний повтор стоил бы секунд на каждом мёртвом сервере.
    expect(
      EphemeralXrayPing.retryProbeWhileCoreWakesUp(
        core: VpnBackend.xray,
        sinceCoreStart: const Duration(milliseconds: 300),
      ),
      isFalse,
    );
  });

  test('запас больше измеренного старта, но не бесконечный', () {
    // Ниже 2 с — снова гонка на медленном телефоне, выше 5 — мёртвый сервер
    // держит слот замера дольше, чем весь остальной батч.
    expect(EphemeralXrayPing.coreWakeupGrace.inMilliseconds, greaterThan(2000));
    expect(EphemeralXrayPing.coreWakeupGrace.inSeconds, lessThanOrEqualTo(5));
  });
}
