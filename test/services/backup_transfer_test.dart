import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/backup_transfer.dart';

// настоящий сокет на петле: сервер слушает 127.0.0.1, а в код подставляем частный адрес только для разбора ссылки
BackupTransferLink _local(BackupTransferLink link) => BackupTransferLink(
      host: '127.0.0.1',
      port: link.port,
      direction: link.direction,
      key: link.key,
    );

final _payload = utf8.encode('{"format":"keqdis_backup","secret":"token-42"}');

void main() {
  group('link', () {
    test('round trips through the code on the screen', () {
      final link = BackupTransferLink(
        host: '192.168.1.47',
        port: 41873,
        direction: BackupTransferDirection.give,
        key: List<int>.generate(32, (i) => i),
      );
      final back = BackupTransferLink.parse(link.toLink())!;
      expect(back.host, '192.168.1.47');
      expect(back.port, 41873);
      expect(back.direction, BackupTransferDirection.give);
      expect(back.key, link.key);
    });

    test('a code pointing outside the home network is refused', () {
      final key = base64Url.encode(List<int>.filled(32, 1)).replaceAll('=', '');
      for (final host in ['8.8.8.8', 'evil.example', '100.64.0.1', '127.0.0.1']) {
        expect(
          BackupTransferLink.parse('keqdroid://backup?h=$host&p=1&d=r&k=$key'),
          isNull,
          reason: host,
        );
      }
      expect(
        BackupTransferLink.parse('keqdroid://backup?h=10.0.0.2&p=80&d=r&k=short'),
        isNull,
      );
      expect(
        BackupTransferLink.parse('keqdroid://tv-send?h=10.0.0.2&p=80&t=abc'),
        isNull,
      );
    });
  });

  test('a backup sent to the receiving screen arrives once', () async {
    final received = Completer<Uint8List>();
    final server = await BackupTransferServer.start(
      lanAddress: '192.168.1.47',
      direction: BackupTransferDirection.receive,
      onReceived: (plain) async => received.complete(plain),
      bindAddress: InternetAddress.loopbackIPv4,
    );
    addTearDown(server.close);

    await sendBackup(_local(server.link), _payload);
    expect(await received.future, _payload);

    await expectLater(
      sendBackup(_local(server.link), _payload),
      throwsA(
        isA<BackupTransferException>().having(
          (e) => e.failure,
          'failure',
          BackupTransferFailure.expired,
        ),
      ),
    );
  });

  test('a backup encrypted with another key is not taken', () async {
    var received = 0;
    final server = await BackupTransferServer.start(
      lanAddress: '192.168.1.47',
      direction: BackupTransferDirection.receive,
      onReceived: (_) async => received++,
      bindAddress: InternetAddress.loopbackIPv4,
    );
    addTearDown(server.close);
    final stranger = BackupTransferLink(
      host: '127.0.0.1',
      port: server.link.port,
      direction: BackupTransferDirection.receive,
      key: List<int>.filled(32, 7),
    );
    await expectLater(
      sendBackup(stranger, _payload),
      throwsA(isA<BackupTransferException>()),
    );
    expect(received, 0);
    await sendBackup(_local(server.link), _payload);
    expect(received, 1, reason: 'the right device still gets through');
  });

  test('the giving screen hands its backup only to the device with the code',
      () async {
    final given = Completer<void>();
    final server = await BackupTransferServer.start(
      lanAddress: '192.168.1.47',
      direction: BackupTransferDirection.give,
      provide: () async => _payload,
      onGiven: given.complete,
      bindAddress: InternetAddress.loopbackIPv4,
    );
    addTearDown(server.close);

    // чужой в сети без ключа: отказ, и код после него всё ещё действует
    final client = HttpClient();
    addTearDown(client.close);
    final probe = await (await client.get('127.0.0.1', server.link.port, '/backup')).close();
    await probe.drain<void>();
    expect(probe.statusCode, HttpStatus.forbidden);

    expect(await fetchBackup(_local(server.link)), _payload);
    // сервер отмечает выдачу, когда дописал ответ, это может быть позже, чем клиент его прочёл
    await given.future.timeout(const Duration(seconds: 5));
    await expectLater(
      fetchBackup(_local(server.link)),
      throwsA(isA<BackupTransferException>()),
    );
  });

  test('nothing in the traffic shows the backup or the key', () async {
    final sealed = await sealForTransfer(_payload, List<int>.filled(32, 5));
    expect(latin1.decode(sealed), isNot(contains('token-42')));
    expect(await openFromTransfer(sealed, List<int>.filled(32, 5)), _payload);
  });

  test('a device that is gone reads as unreachable', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close(force: true);
    await expectLater(
      sendBackup(
        BackupTransferLink(
          host: '127.0.0.1',
          port: port,
          direction: BackupTransferDirection.receive,
          key: List<int>.filled(32, 1),
        ),
        _payload,
      ),
      throwsA(
        isA<BackupTransferException>().having(
          (e) => e.failure,
          'failure',
          BackupTransferFailure.unreachable,
        ),
      ),
    );
  });
}
