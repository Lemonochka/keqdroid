import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/tunnel/app_routing_mode.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';


/// Режим сплита без правил по процессам отправлял ВЕСЬ трафик мимо прокси.
///
/// Финал у `onlySelected` — `DIRECT` («не выбранные приложения идут
/// напрямую»), и держится этот смысл на правилах `PROCESS-NAME`, которые ставят
/// выбранным приложениям прокси. Там, где ядро владельца соединения не знает
/// (десктопный proxy-режим — туннеля у ядра нет; Android — владельца не отдаёт
/// система), правил нет, а финал оставался. Ядро честно исполняло его на всём:
/// `[TCP] ... match Match using DIRECT` на каждое соединение при живом
/// «подключено», то есть «прокси-режим не работает вообще».
const _link = 'vless://uuid@example.com:443?type=tcp&security=none';

List<String> _rules(Map<String, dynamic> config) =>
    (config['rules'] as List).cast<String>();

void main() {
  const split = AppRoutingMode.onlySelected;
  const selected = ['firefox.exe', 'Discord.exe'];

  test('proxy-режим: финал остаётся прокси, а не DIRECT', () {
    final config = MihomoConfigGen.build(
      _link,
      const AppSettings(),
      socksPort: 2080,
      httpPort: 2081,
      // Туннеля у ядра нет — это и есть proxy-режим десктопа.
      routingMode: split,
      managedProcessNames: selected,
      appProcessName: 'keqdroid.exe',
      windows: true,
    );

    final rules = _rules(config);
    expect(
      rules.last,
      isNot('MATCH,DIRECT'),
      reason: 'иначе через прокси не идёт ничего вообще',
    );
    expect(rules.last, startsWith('MATCH,'));
    expect(
      rules.any((r) => r.startsWith('PROCESS-NAME,')),
      isFalse,
      reason: 'процесс-владельца ядро в этой схеме не знает',
    );
  });

  test('TUN-режим: сплит по процессам работает как раньше', () {
    final config = MihomoConfigGen.build(
      _link,
      const AppSettings(),
      socksPort: 2080,
      httpPort: 2081,
      tun: const MihomoTunOptions(device: 'tun-keqdis', stack: 'gvisor'),
      routingMode: split,
      managedProcessNames: selected,
      appProcessName: 'keqdroid.exe',
      windows: true,
    );

    final rules = _rules(config);
    expect(
      rules.last,
      'MATCH,DIRECT',
      reason: 'не выбранные приложения обязаны идти напрямую',
    );
    expect(
      rules.where((r) => r.startsWith('PROCESS-NAME,firefox.exe')).length,
      1,
    );
  });

  test('Android (fd-туннель): финал прокси, сплит исполняет VpnService', () {
    final config = MihomoConfigGen.build(
      _link,
      const AppSettings(),
      socksPort: 2080,
      tun: const MihomoTunOptions(
        fromFileDescriptor: true,
        stack: 'gvisor',
        autoRoute: false,
      ),
      routingMode: split,
      managedProcessNames: const ['org.mozilla.firefox'],
      windows: false,
    );

    final rules = _rules(config);
    expect(rules.last, isNot('MATCH,DIRECT'));
    expect(rules.any((r) => r.startsWith('PROCESS-NAME,')), isFalse);
  });
}
