import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/ephemeral_xray_ping.dart';

/// Пачку серверов на ПК меряет один процесс ядра, как на Android.
///
/// Вся тонкость в том, что вернуть, когда ядро не поднялось. null значит
/// «поделить пачку пополам и попробовать ещё»: так PingService ищет сервер,
/// из-за которого ядро не приняло общий конфиг. Список отказов той же длины
/// он принял бы за ответ, и десяток живых соседей ушёл бы в красные.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('keqdroid_vpn_channel');

  setUp(() {
    // привязка процесса к job object уходит в нативную часть, в тесте её нет
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
  });

  tearDown(() {
    EphemeralXrayPing.debugResolveCore = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<List<(String, int)>> freeProbes(List<String> ids) async => [
    for (final id in ids)
      (
        id,
        await () async {
          final socket = await ServerSocket.bind(
            InternetAddress.loopbackIPv4,
            0,
          );
          final port = socket.port;
          await socket.close();
          return port;
        }(),
      ),
  ];

  test('ядра нет: у каждой пробы отказ с причиной, делить нечего', () async {
    EphemeralXrayPing.debugResolveCore = (_) async => null;

    final results = await EphemeralXrayPing.urlTestMulti(
      configJson: '{}',
      probes: await freeProbes(['a', 'b']),
      testUrl: 'https://example.com/',
      timeoutMs: 1000,
    );

    expect(results, isNotNull);
    expect(results!.map((r) => r.id), ['a', 'b']);
    expect(results.every((r) => !r.success), isTrue);
    expect(results.every((r) => r.error.contains('not found')), isTrue);
  });

  test('ядро вышло сразу: null, чтобы пачку поделили', () async {
    // так выглядит ядро, не принявшее конфиг; вместо него программа, которая выходит сама
    EphemeralXrayPing.debugResolveCore = (_) async =>
        Platform.isWindows ? r'C:\Windows\System32\where.exe' : '/bin/false';

    final results = await EphemeralXrayPing.urlTestMulti(
      configJson: '{}',
      probes: await freeProbes(['a', 'b', 'c']),
      testUrl: 'https://example.com/',
      timeoutMs: 1000,
    );

    expect(results, isNull);
  });

  test('пустая пачка не запускает ядро', () async {
    var asked = false;
    EphemeralXrayPing.debugResolveCore = (_) async {
      asked = true;
      return null;
    };

    final results = await EphemeralXrayPing.urlTestMulti(
      configJson: '{}',
      probes: const [],
      testUrl: 'https://example.com/',
      timeoutMs: 1000,
    );

    expect(results, isEmpty);
    expect(asked, isFalse);
  });

  test('срок на старт ядра не короче, чем ему нужно на медленном ПК', () {
    // ядра стартуют пачкой и делят диск с антивирусом: 5 с не хватало уже при
    // шести разом. До 14.11.2026 срок обрезался таймаутом пробы (8 с у «пинга
    // всех», 4 у автовыбора), и записанные 12 с не действовали никогда
    expect(
      EphemeralXrayPing.coreStartupBudget.inSeconds,
      greaterThanOrEqualTo(12),
    );
  });
}
