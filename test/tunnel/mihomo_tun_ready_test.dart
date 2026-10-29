import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/tunnel/mihomo_tun_ready.dart';

void main() {
  group('готов ли TUN у mihomo', () {
    test('пока API молчит, ждём, сколько бы адаптеров ни было в системе', () {
      expect(
        mihomoTunState(coreOutput: 'mixed listening at 127.0.0.1:2080'),
        MihomoTunState.pending,
      );
    });

    test('API отвечает tun.enable: true — туннель его', () {
      expect(
        mihomoTunState(coreOutput: '', configs: {
          'tun': {'enable': true, 'device': 'tun-keqdis'},
        }),
        MihomoTunState.up,
      );
    });

    // так mihomo отвечает, когда туннель не поднялся, а сам он остался жить
    test('API отвечает tun.enable: false — туннеля нет', () {
      expect(
        mihomoTunState(coreOutput: '', configs: {
          'tun': {'enable': false},
        }),
        MihomoTunState.failed,
      );
      expect(
        mihomoTunState(coreOutput: '', configs: const {'mode': 'rule'}),
        MihomoTunState.failed,
      );
    });

    test('ошибка TUN в выводе сильнее всего остального', () {
      expect(
        mihomoTunState(
          coreOutput: 'level=error msg="Start TUN listening error: '
              'configure tun interface: Cannot create a file"',
          configs: {
            'tun': {'enable': true},
          },
        ),
        MihomoTunState.failed,
      );
    });

    test('строка «Tun adapter listening at» при подробном логе — готово', () {
      expect(
        mihomoTunState(
          coreOutput: 'level=info msg="[TUN] Tun adapter listening at: '
              'tun-keqdis([198.18.0.1/30],[])"',
        ),
        MihomoTunState.up,
      );
    });
  });

  group('запрос /configs', () {
    late HttpServer server;
    late List<String?> auth;

    setUp(() async {
      auth = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        auth.add(request.headers.value(HttpHeaders.authorizationHeader));
        if (request.uri.path != '/configs' ||
            request.headers.value(HttpHeaders.authorizationHeader) !=
                'Bearer s3cret') {
          request.response.statusCode = HttpStatus.unauthorized;
          await request.response.close();
          return;
        }
        request.response.write(jsonEncode({
          'tun': {'enable': true},
        }));
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('с токеном отдаёт ответ ядра', () async {
      final configs = await fetchMihomoConfigs(server.port, 's3cret');
      expect(mihomoTunState(coreOutput: '', configs: configs),
          MihomoTunState.up);
      expect(auth, ['Bearer s3cret']);
    });

    test('чужой токен — не ответ, а ожидание', () async {
      final configs = await fetchMihomoConfigs(server.port, 'wrong');
      expect(configs, isNull);
    });

    test('порт ещё никто не слушает — не ответ', () async {
      final port = server.port;
      await server.close(force: true);
      expect(await fetchMihomoConfigs(port, 's3cret'), isNull);
    });
  });
}
