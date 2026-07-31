import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/singbox_tun_config.dart';

/// Имя TUN-интерфейса задаём САМИ на всех платформах.
///
/// Иначе sing-box берёт `tun.CalculateInterfaceName("")` → «tun0», а wintun
/// считает GUID адаптера как `MD5("wintun" + имя)` — один и тот же у любого
/// sing-box-клиента на машине (Happ, Nekoray, sing-box CLI). sing-tun при
/// занятом GUID делает `CreateAdapter` → ErrExist → `OpenAdapter(имя)`, то есть
/// молча забирает ЧУЖОЙ адаптер и настраивает на нём свои адреса и маршруты.
/// Симптомы: «TUN поднялся, ошибок нет, трафика нет» и падения через раз.
void main() {
  test('tun inbound always names the interface', () {
    final config = jsonDecode(
      SingBoxTunConfigGen.generate(
        localSocksPort: 2080,
        socksUsername: 'u',
        socksPassword: 'p',
        serverIpToExclude: '203.0.113.10',
        settings: const AppSettings(),
      ),
    ) as Map<String, dynamic>;

    final tun = (config['inbounds'] as List).first as Map<String, dynamic>;
    expect(tun['type'], 'tun');
    expect(
      tun['interface_name'],
      'tun-keqdis',
      reason: 'без своего имени адаптер делит GUID с другими sing-box-клиентами',
    );
  });
}
