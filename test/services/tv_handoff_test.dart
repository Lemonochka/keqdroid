import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/tv_handoff.dart';

/// Подписка с телефона на телевизор: код из QR, выбор адреса и сам обмен по
/// HTTP. Обмен гоняется на 127.0.0.1 настоящими сокетами — так проверяется
/// протокол целиком, а не его пересказ.
void main() {
  group('код телевизора', () {
    test('собранный код разбирается обратно', () {
      const tv = TvPairing(
        host: '192.168.1.40',
        port: 40123,
        token: 'AbCdEfGhIjKlMnOpQrStUv',
      );
      final parsed = TvPairing.parse(tv.toLink())!;
      expect(parsed.host, tv.host);
      expect(parsed.port, tv.port);
      expect(parsed.token, tv.token);
    });

    test('принимается и старая схема keqdis', () {
      expect(
        TvPairing.parse(
          'keqdis://tv-send?h=10.0.0.7&p=8080&t=AbCdEfGhIjKlMnOpQrStUv',
        ),
        isNotNull,
      );
    });

    test('адрес не из домашней сети отвергается', () {
      // Подложенный QR не должен увести подписку на сервер в интернете.
      for (final h in ['8.8.8.8', 'evil.example.com', '172.32.0.1', '::1']) {
        expect(
          TvPairing.parse(
            'keqdroid://tv-send?h=$h&p=8080&t=AbCdEfGhIjKlMnOpQrStUv',
          ),
          isNull,
          reason: h,
        );
      }
    });

    test('без ключа, с битым портом или чужой ссылкой — не код телевизора', () {
      for (final raw in [
        'keqdroid://tv-send?h=192.168.1.2&p=8080',
        'keqdroid://tv-send?h=192.168.1.2&p=8080&t=short',
        'keqdroid://tv-send?h=192.168.1.2&p=70000&t=AbCdEfGhIjKlMnOpQrStUv',
        'keqdroid://install-config?url=https://example.com/sub',
        'https://192.168.1.2:8080/add',
      ]) {
        expect(TvPairing.parse(raw), isNull, reason: raw);
      }
    });
  });

  group('адрес телевизора в QR', () {
    test('туннель VPN пропускается, Wi-Fi — вперёд', () {
      expect(
        pickLanAddress([
          (name: 'tun0', address: '172.19.0.1'),
          (name: 'p2p0', address: '192.168.49.1'),
          (name: 'wlan0', address: '192.168.1.40'),
        ]),
        '192.168.1.40',
      );
    });

    test('на ПК код показывает адрес Wi-Fi, а не WSL, Hyper-V или Docker', () {
      expect(
        pickLanAddress([
          (name: 'vEthernet (WSL (Hyper-V firewall))', address: '172.27.160.1'),
          (name: 'vEthernet (Default Switch)', address: '172.20.48.1'),
          (name: 'VirtualBox Host-Only Network', address: '192.168.56.1'),
          (name: 'Meta Tunnel', address: '172.19.0.1'),
          (name: 'Wi-Fi', address: '192.168.1.71'),
        ]),
        '192.168.1.71',
      );
      expect(
        pickLanAddress([
          (name: 'docker0', address: '172.17.0.1'),
          (name: 'virbr0', address: '192.168.122.1'),
          (name: 'wlp3s0', address: '192.168.0.12'),
        ]),
        '192.168.0.12',
      );
      expect(
        pickLanAddress([(name: 'Ethernet', address: '10.0.0.5')]),
        '10.0.0.5',
      );
    });

    test('кабель годится так же, как Wi-Fi', () {
      expect(
        pickLanAddress([(name: 'eth0', address: '10.0.2.15')]),
        '10.0.2.15',
      );
    });

    test('без домашней сети адреса нет', () {
      expect(
        pickLanAddress([
          (name: 'tun0', address: '172.19.0.1'),
          (name: 'rmnet0', address: '10.120.5.3'),
          (name: 'wlan0', address: '100.70.1.2'),
        ]),
        isNull,
      );
    });
  });

  group('что прислал телефон', () {
    test('ссылка обязана быть http(s)', () {
      expect(
        TvSubscriptionOffer.fromJson({'url': 'vless://abc@host:443'}),
        isNull,
      );
      expect(TvSubscriptionOffer.fromJson({'url': 'https://'}), isNull);
      expect(TvSubscriptionOffer.fromJson({}), isNull);
    });

    test('без имени имя автоматическое', () {
      final offer = TvSubscriptionOffer.fromJson({
        'url': ' https://sub.example/x ',
        'name': ' ',
      })!;
      expect(offer.url, 'https://sub.example/x');
      expect(offer.name, isNull);
      expect(offer.nameIsAuto, isTrue);
    });

    test('имя, данное руками, остаётся ручным', () {
      final offer = TvSubscriptionOffer.fromJson({
        'url': 'https://sub.example/x',
        'name': 'Дом',
        'auto': false,
      })!;
      expect(offer.name, 'Дом');
      expect(offer.nameIsAuto, isFalse);
    });
  });

  group('обмен', () {
    late TvReceiveServer server;
    final received = <TvSubscriptionOffer>[];
    String? answer;

    setUp(() async {
      received.clear();
      answer = null;
      server = await TvReceiveServer.start(
        lanAddress: '127.0.0.1',
        onOffer: (offer) async {
          received.add(offer);
          return answer;
        },
      );
    });

    tearDown(() => server.close());

    test('подписка доходит до телевизора', () async {
      await sendToTv(
        server.pairing,
        const TvSubscriptionOffer(
          url: 'https://sub.example/abc',
          name: 'Kequinq VPN',
          nameIsAuto: false,
        ),
      );
      expect(received, hasLength(1));
      expect(received.single.url, 'https://sub.example/abc');
      expect(received.single.name, 'Kequinq VPN');
      expect(received.single.nameIsAuto, isFalse);
    });

    test('чужой ключ — код устарел, телевизор ничего не добавляет', () async {
      final stale = TvPairing(
        host: server.pairing.host,
        port: server.pairing.port,
        token: 'x' * server.pairing.token.length,
      );
      await expectLater(
        sendToTv(stale, const TvSubscriptionOffer(url: 'https://a.example/')),
        throwsA(
          isA<TvSendException>().having(
            (e) => e.failure,
            'failure',
            TvSendFailure.expired,
          ),
        ),
      );
      expect(received, isEmpty);
    });

    test('отказ телевизора приходит на телефон его словами', () async {
      answer = 'Подписка уже добавлена';
      await expectLater(
        sendToTv(
          server.pairing,
          const TvSubscriptionOffer(url: 'https://a.example/'),
        ),
        throwsA(
          isA<TvSendException>()
              .having((e) => e.failure, 'failure', TvSendFailure.rejected)
              .having((e) => e.message, 'message', 'Подписка уже добавлена'),
        ),
      );
    });

    test('закрытый экран приёма — телевизор не отвечает', () async {
      final pairing = server.pairing;
      await server.close();
      await expectLater(
        sendToTv(pairing, const TvSubscriptionOffer(url: 'https://a.example/')),
        throwsA(
          isA<TvSendException>().having(
            (e) => e.failure,
            'failure',
            TvSendFailure.unreachable,
          ),
        ),
      );
    });

    test('кроме POST /add сервер ничего не делает', () async {
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final port = server.pairing.port;

      final get = await (await client.get('127.0.0.1', port, '/add')).close();
      expect(get.statusCode, HttpStatus.methodNotAllowed);
      await get.drain<void>();

      final other = await (await client.post('127.0.0.1', port, '/')).close();
      expect(other.statusCode, HttpStatus.notFound);
      await other.drain<void>();

      // Сервер отвечает, не дочитав тело, и клиент может словить обрыв
      // раньше ответа — годится и то и другое, лишь бы не «принято».
      int? hugeStatus;
      try {
        final huge = await client.post('127.0.0.1', port, '/add');
        huge.write(
          jsonEncode({
            't': server.pairing.token,
            'url': 'https://a.example/${'a' * TvReceiveServer.maxBodyBytes}',
          }),
        );
        final hugeResponse = await huge.close();
        hugeStatus = hugeResponse.statusCode;
        await hugeResponse.drain<void>();
      } on IOException {
        hugeStatus = null;
      }
      expect(hugeStatus, anyOf(isNull, HttpStatus.requestEntityTooLarge));

      expect(received, isEmpty);
    });
  });
}
