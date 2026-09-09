import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/services/ping_service.dart';
import 'package:keqdroid/tunnel/vpn_backend.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';

/// Замер обязан подниматься тем же ядром, каким сервер поедет. Пока он всегда
/// поднимал xray, «зелёный пинг» и «работает» были про разные ядра: сервер,
/// живой на mihomo, краснел из-за того, что его не понял xray.
void main() {
  const link = 'vless://uuid@nl.example:443?type=tcp&security=none#NL';

  group('выбор ядра для замера', () {
    test('выбранное ядро и решает', () {
      expect(
        PingService.pingCoreFor(
          link,
          const AppSettings(vpnCore: AppSettings.vpnCoreMihomo),
        ),
        VpnBackend.mihomo,
      );
      expect(
        PingService.pingCoreFor(
          link,
          const AppSettings(vpnCore: AppSettings.vpnCoreXray),
        ),
        VpnBackend.xray,
      );
    });

    test('«само» на ссылке — это xray, как и на подключении', () {
      // Не «замер решает сам»: он повторяет решение подключения, иначе снова
      // мерил бы не то ядро.
      expect(
        PingService.pingCoreFor(
          link,
          const AppSettings(vpnCore: AppSettings.vpnCoreAuto),
        ),
        VpnBackend.xray,
      );
    });

    test('формат ядра перебивает выбор', () {
      // Готовый конфиг Clash исполняет только mihomo — тут выбирать нечего, и
      // мерить его xray было бы заведомо красным.
      const clash = 'proxies:\n'
          '  - name: a\n'
          '    type: vless\n'
          '    server: nl.example\n'
          '    port: 443\n';
      expect(
        PingService.pingCoreFor(
          clash,
          const AppSettings(vpnCore: AppSettings.vpnCoreXray),
        ),
        VpnBackend.mihomo,
      );
    });
  });

  group('конфиг замера у mihomo', () {
    Map<String, dynamic> pingConfig({bool httpInbound = false}) =>
        jsonDecode(
          MihomoConfigGen.generatePingConfig(
            link,
            const AppSettings(),
            socksPort: 28150,
            httpInbound: httpInbound,
          ),
        ) as Map<String, dynamic>;

    test('один прокси, одно правило, петля', () {
      final config = pingConfig();
      expect((config['proxies'] as List).length, 1);
      expect(config['rules'], ['MATCH,${MihomoConfigGen.proxyName}']);
      expect(config['bind-address'], '127.0.0.1');
      expect(config['allow-lan'], isFalse);
    });

    test('транспорт пробы выбирается платформой', () {
      // Десктоп ходит по HTTP: HttpClient из dart:io не умеет SOCKS вовсе.
      expect(pingConfig(httpInbound: true)['port'], 28150);
      expect(pingConfig(httpInbound: true).containsKey('socks-port'), isFalse);
      // Android — по SOCKS, там пробу делает Java.
      expect(pingConfig()['socks-port'], 28150);
      expect(pingConfig().containsKey('port'), isFalse);
    });

    test('ничего, что стоит времени старта', () {
      // Geo-базы ядро разбирает полсекунды, и эти полсекунды уехали бы прямо в
      // измеренную задержку. Снифер и поиск процесса тоже лишние: соединение
      // здесь ровно одно и уже известно куда идёт.
      final config = pingConfig();
      expect(config.containsKey('sniffer'), isFalse);
      expect(config.containsKey('tun'), isFalse);
      expect(config['find-process-mode'], 'off');
      expect(config['geo-auto-update'], isFalse);
      expect(config['log-level'], 'silent');
      final rules = (config['rules'] as List).join(' ');
      expect(rules.contains('GEOIP'), isFalse);
      expect(rules.contains('GEOSITE'), isFalse);
    });

    test('меряют оба ядра одинаково: только IPv4', () {
      // У xray в ping-режиме жёстко `queryStrategy: UseIPv4`. Разойдись эти
      // двое — разница в цифрах оказалась бы разницей семейства адресов.
      final config = pingConfig();
      expect(config['ipv6'], isFalse);
      expect((config['dns'] as Map)['ipv6'], isFalse);
    });

    test('DNS замера не уходит в туннель, которого ещё нет', () {
      final dns = pingConfig()['dns'] as Map<String, dynamic>;
      for (final server in dns['nameserver'] as List) {
        // `system` резолвит сама ОС, остальным нужен явный «мимо правил».
        if (server == 'system') continue;
        expect(server, endsWith('#DIRECT'));
      }
      expect(dns.containsKey('respect-rules'), isFalse);
    });
  });
}
