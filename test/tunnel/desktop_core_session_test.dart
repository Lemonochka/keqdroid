import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/core/exceptions.dart';
import 'package:keqdroid/services/xray_route_decisions.dart';
import 'package:keqdroid/tunnel/linux_tunnel_backend.dart';
import 'package:keqdroid/tunnel/tun_failure_hints.dart';
import 'package:keqdroid/tunnel/tunnel_backend.dart';
import 'package:keqdroid/tunnel/tunnel_state.dart';
import 'package:keqdroid/tunnel/windows_tunnel_backend.dart';

import '../helpers/fake_core_process.dart';

// Вывод ядра, смерть ядра и штатная остановка у бэкендов Linux и Windows
// устроены одинаково, и оба гоняются здесь по одним и тем же сценариям.
// Расходятся они только там, где это сказано в тесте: Windows дописывает к
// сообщению о падении подсказку и хвост журнала, xray на Windows сперва
// просят выйти закрытым stdin.

abstract class _Backend {
  TunnelBackend get backend;
  String get name;
  bool get windows;
  Stream<VpnState> get states;
  void adopt(
    Process process, {
    bool mihomo = false,
    bool root = false,
    int logThreshold = 0,
  });
  bool get xrayStarted;
  String logs({int maxLines = 400});
  String connectionLines();
  Future<bool> waitForPort(
    int port, {
    Process? process,
    StringBuffer? log,
    String processLabel = 'Process',
  });
  Future<void> stop();
  Future<VpnState> current();
}

class _Windows implements _Backend {
  @override
  final WindowsTunnelBackend backend = WindowsTunnelBackend();

  @override
  String get name => 'Windows';
  @override
  bool get windows => true;
  @override
  Stream<VpnState> get states => backend.stateStream;
  @override
  void adopt(
    Process process, {
    bool mihomo = false,
    bool root = false,
    int logThreshold = 0,
  }) => backend.debugAdoptCore(
    process,
    mihomo: mihomo,
    logThreshold: logThreshold,
  );
  @override
  bool get xrayStarted => backend.debugXrayStarted;
  @override
  String logs({int maxLines = 400}) =>
      backend.exportSessionLogs(maxLines: maxLines);
  @override
  String connectionLines() => backend.exportConnectionLines();
  @override
  Future<bool> waitForPort(
    int port, {
    Process? process,
    StringBuffer? log,
    String processLabel = 'Process',
  }) => backend.debugWaitForPort(
    port,
    process: process,
    log: log,
    processLabel: processLabel,
  );
  @override
  Future<void> stop() => backend.stopSession();
  @override
  Future<VpnState> current() => backend.getCurrentState();
}

class _Linux implements _Backend {
  @override
  final LinuxTunnelBackend backend = LinuxTunnelBackend();

  @override
  String get name => 'Linux';
  @override
  bool get windows => false;
  @override
  Stream<VpnState> get states => backend.stateStream;
  @override
  void adopt(
    Process process, {
    bool mihomo = false,
    bool root = false,
    int logThreshold = 0,
  }) => backend.debugAdoptCore(
    process,
    mihomo: mihomo,
    root: root,
    logThreshold: logThreshold,
  );
  @override
  bool get xrayStarted => backend.debugXrayStarted;
  @override
  String logs({int maxLines = 400}) =>
      backend.exportSessionLogs(maxLines: maxLines);
  @override
  String connectionLines() => backend.exportConnectionLines();
  @override
  Future<bool> waitForPort(
    int port, {
    Process? process,
    StringBuffer? log,
    String processLabel = 'Process',
  }) => backend.debugWaitForPort(
    port,
    process: process,
    log: log,
    processLabel: processLabel,
  );
  @override
  Future<void> stop() => backend.stopSession();
  @override
  Future<VpnState> current() => backend.getCurrentState();
}

final _backends = <_Backend Function()>[_Windows.new, _Linux.new];

// на Linux stopSession возвращает прокси рабочего стола через gsettings и
// пишет журнал ядер в XDG_RUNTIME_DIR, то есть трогает систему того, кто гоняет тесты
Object _stopSkip(_Backend b) => !b.windows && Platform.isLinux
    ? 'остановка Linux-бэкенда правит настройки этой машины'
    : false;

final _numbered = RegExp(r'^line \d+', multiLine: true);

List<String> _numberedLines(String text) => [
  for (final m in _numbered.allMatches(text)) m.group(0)!,
];

class _Recorder {
  _Recorder(Stream<VpnState> states) {
    _sub = states.listen(seen.add);
  }

  final seen = <VpnState>[];
  late final StreamSubscription<VpnState> _sub;

  List<VpnStatus> get statuses => [for (final s in seen) s.status];

  Future<VpnState> firstError() async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!seen.any((s) => s.status == VpnStatus.error)) {
      if (DateTime.now().isAfter(deadline)) fail('error state not emitted');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return seen.firstWhere((s) => s.status == VpnStatus.error);
  }

  Future<void> close() => _sub.cancel();
}

const _wintunRefused =
    'Failed to setup adapter (problem code: 0x1F, ntstatus: 0xC00002F0): '
    'The system cannot find the file specified. (Code 0x00000002)';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('keqdroid_vpn_channel');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUpAll(
    () => messenger.setMockMethodCallHandler(channel, (_) async => null),
  );
  tearDownAll(() => messenger.setMockMethodCallHandler(channel, null));

  setUp(XrayRouteDecisions.reset);
  tearDown(() {
    XrayRouteDecisions.reset();
    WindowsTunnelBackend.lastSessionLogs = '';
  });

  for (final make in _backends) {
    final probe = make();
    group('${probe.name}: вывод ядра', () {
      test('строки режутся по всему потоку, а не по кускам из трубы', () async {
        final b = make();
        final core = FakeCoreProcess();
        b.adopt(core);

        core.out('first ha');
        core.out('lf\nsecond\r\n');
        core.err('from stderr\n');
        final word = utf8.encode('Привет\n');
        core.outBytes(word.sublist(0, 3));
        core.outBytes(word.sublist(3));
        core.outBytes([0xff, 0xfe, ...utf8.encode('broken\n')]);
        core.out('no newline at the end');
        core.closeOutput();
        await pumpEventQueue();

        final logs = b.logs();
        expect(logs, contains('first half\n'));
        expect(logs, contains('second\n'));
        expect(logs, isNot(contains('\r')));
        expect(logs, contains('from stderr'));
        expect(logs, contains('Привет'));
        expect(logs, contains('��broken'));
        // последний кусок без перевода строки отдаётся при закрытии трубы
        expect(logs, contains('no newline at the end'));
      });

      test('строка started замечается и ниже порога журнала', () async {
        final b = make();
        final core = FakeCoreProcess();
        // порог error: строку Warning журнал не берёт
        b.adopt(core, logThreshold: 3);
        expect(b.xrayStarted, isFalse);

        core.out('2026/11/04 12:00:00 [Warning] core: Xray 26.7.11 started\n');
        await pumpEventQueue();

        expect(b.xrayStarted, isTrue);
        expect(b.logs(), isNot(contains('started')));
      });

      test('порог режет журнал, но не строки Соединений', () async {
        final b = make();
        final core = FakeCoreProcess();
        b.adopt(core, logThreshold: 2);

        const info =
            '2026/11/04 12:00:02 [Info] [102] app/dispatcher: Hit route rule: '
            '[direct-domains] so taking detour [direct] for [tcp:vk.com:443]';
        const warning =
            '2026/11/04 12:00:05 [Warning] [105] app/dispatcher: '
            'non existing outTag: gone';
        core.out('$info\n$warning\nmihomo line without level\n');
        await pumpEventQueue();

        final logs = b.logs();
        expect(logs, isNot(contains('taking detour')));
        expect(logs, contains('non existing outTag'));
        expect(logs, contains('mihomo line without level'));
        expect(b.connectionLines(), contains(info));
        expect(b.connectionLines(), isNot(contains('mihomo line')));
      });

      test('после 64 КиБ журнал ужимается до последних 200 строк', () async {
        final b = make();
        final core = FakeCoreProcess();
        b.adopt(core);

        // строка со своим переводом 100 знаков: 64 КиБ переполняет 656-я,
        // после неё остаются 200 строк, и к ним дописываются ещё 44
        for (var i = 0; i < 700; i++) {
          core.out('line ${i.toString().padLeft(4, '0')} ${'x' * 89}\n');
        }
        await pumpEventQueue();

        final kept = _numberedLines(b.logs(maxLines: 1000));
        expect(kept.length, 244);
        expect(kept.first, 'line 0456');
        expect(kept.last, 'line 0699');
      });

      test('хвост берёт последние непустые строки', () async {
        final b = make();
        // у Linux журнал из двух разделов, у пустого остаются заголовки
        expect(
          b.logs(),
          b.windows ? '(no process output)' : '=== core ===\n=== root ===',
        );

        final core = FakeCoreProcess();
        b.adopt(core);
        core.out('line 1\n\n   \nline 2\nline 3\n');
        await pumpEventQueue();

        expect(
          b.logs(maxLines: 3),
          b.windows ? 'line 1\nline 2\nline 3' : 'line 2\nline 3\n=== root ===',
        );
      });
    });

    group('${probe.name}: смерть ядра', () {
      test(
        'ядро упало само: сессия снята, ошибка с кодом выхода',
        () async {
          final b = make();
          final states = _Recorder(b.states);
          final core = FakeCoreProcess();
          b.adopt(core);
          core.out('line 1\nline 2\n');
          await pumpEventQueue();

          core.exit(3);
          final error = await states.firstError();

          expect(states.statuses, [
            VpnStatus.disconnecting,
            VpnStatus.disconnected,
            VpnStatus.error,
          ]);
          expect(
            error.errorMessage,
            b.windows
                ? 'xray stopped unexpectedly (exit code 3). Disconnected.\n'
                      'line 1\nline 2'
                : 'xray stopped unexpectedly (exit code 3). Disconnected.',
          );
          expect((await b.current()).status, VpnStatus.disconnected);
          await states.close();
        },
        skip: _stopSkip(probe),
      );

      test(
        'на Windows к сообщению идёт подсказка по выводу ядра',
        () async {
          final b = make();
          final states = _Recorder(b.states);
          final core = FakeCoreProcess();
          b.adopt(core, mihomo: true);
          core.out('$_wintunRefused\n');
          await pumpEventQueue();

          core.exit(1);
          final error = await states.firstError();

          final hint = tunFailureHint(_wintunRefused, windows: true)!.message;
          expect(
            error.errorMessage,
            b.windows
                ? 'mihomo stopped unexpectedly (exit code 1). Disconnected.\n'
                      '$hint\n$_wintunRefused'
                : 'mihomo stopped unexpectedly (exit code 1). Disconnected.',
          );
          await states.close();
        },
        skip: _stopSkip(probe),
      );

      if (!probe.windows) {
        test('root-ядро TUN сторож тоже видит', () async {
          final b = make();
          final states = _Recorder(b.states);
          final core = FakeCoreProcess();
          b.adopt(core, root: true);

          core.exit(1);
          final error = await states.firstError();

          expect(
            error.errorMessage,
            'xray TUN stopped unexpectedly (exit code 1). Disconnected.',
          );
          expect((await b.current()).status, VpnStatus.disconnected);
          await states.close();
        }, skip: _stopSkip(probe));
      }

      test(
        'выход во время нашей остановки ошибкой не считается',
        () async {
          final b = make();
          final states = _Recorder(b.states);
          final core = FakeCoreProcess(exitOnStdinClose: true);
          b.adopt(core);

          await b.stop();
          await pumpEventQueue();

          expect(core.exited, isTrue);
          expect(states.statuses, [
            VpnStatus.disconnecting,
            VpnStatus.disconnected,
          ]);
          await states.close();
        },
        skip: _stopSkip(probe),
      );

      test('выход уже замененного ядра сессию не трогает', () async {
        final b = make();
        final states = _Recorder(b.states);
        final old = FakeCoreProcess();
        b.adopt(old);
        b.adopt(FakeCoreProcess());

        old.exit(1);
        await pumpEventQueue();

        expect(states.seen, isEmpty);
        expect((await b.current()).status, VpnStatus.connected);
        await states.close();
      }, skip: _stopSkip(probe));
    });

    group('${probe.name}: остановка', () {
      test(
        'xray просят выйти так, как он умеет на этой платформе',
        () async {
          final b = make();
          final core = FakeCoreProcess(exitOnStdinClose: true);
          b.adopt(core);

          await b.stop();

          if (b.windows) {
            expect(core.stdinClosed, isTrue);
            expect(core.signals, isEmpty);
          } else {
            expect(core.stdinClosed, isFalse);
            expect(core.signals, [ProcessSignal.sigterm]);
          }
          expect((await b.current()).status, VpnStatus.disconnected);
        },
        skip: _stopSkip(probe),
      );

      test(
        'глухое к SIGTERM ядро добивается SIGKILL через 3 с',
        () async {
          final b = make();
          final core = FakeCoreProcess(exitOn: {ProcessSignal.sigkill});
          // mihomo на обеих платформах гасится без stdin
          b.adopt(core, mihomo: true);

          final clock = Stopwatch()..start();
          await b.stop();

          expect(core.stdinClosed, isFalse);
          expect(core.signals, [ProcessSignal.sigterm, ProcessSignal.sigkill]);
          expect(
            clock.elapsed,
            greaterThanOrEqualTo(const Duration(seconds: 3)),
          );
          expect(clock.elapsed, lessThan(const Duration(seconds: 5)));
        },
        skip: _stopSkip(probe),
      );

      if (probe.windows) {
        test('xray, не вышедший по stdin за 5 с, получает SIGTERM', () async {
          final b = make();
          final core = FakeCoreProcess();
          b.adopt(core);

          final clock = Stopwatch()..start();
          await b.stop();

          expect(core.stdinClosed, isTrue);
          expect(core.signals, [ProcessSignal.sigterm]);
          expect(
            clock.elapsed,
            greaterThanOrEqualTo(const Duration(seconds: 5)),
          );
          expect(clock.elapsed, lessThan(const Duration(seconds: 7)));
        });
      }
    });

    group('${probe.name}: пинг', () {
      test('до открытого порта время, до закрытого null', () async {
        final b = make().backend;
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((s) => s.destroy());
        addTearDown(server.close);

        expect(await b.getPing('127.0.0.1', server.port), isNonNegative);
        expect(await b.getPing('127.0.0.1', await _closedPort()), isNull);
      });

      test('пустая пачка не запускает ядро', () async {
        final b = make().backend;

        expect(await b.xrayUrlTestBatch(items: [], socksPort: 1), isEmpty);
        expect(await b.xraySpeedTestBatch(items: [], socksPort: 1), isEmpty);
      });
    });

    group('${probe.name}: ожидание порта', () {
      test('открытый порт дождались', () async {
        final b = make();
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((s) => s.destroy());
        addTearDown(server.close);

        expect(await b.waitForPort(server.port), isTrue);
      });

      test('ядро вышло с нулём: порта не будет, без исключения', () async {
        final b = make();
        final core = FakeCoreProcess()..exit(0);
        final port = await _closedPort();

        expect(await b.waitForPort(port, process: core), isFalse);
      });

      test('ядро упало: исключение с кодом и хвостом журнала', () async {
        final b = make();
        final core = FakeCoreProcess()..exit(7);
        final port = await _closedPort();
        final log = StringBuffer()
          ..writeln('line 1')
          ..writeln(_wintunRefused);

        final hint = tunFailureHint(log.toString(), windows: true)!.message;
        await expectLater(
          b.waitForPort(port, process: core, log: log, processLabel: 'xray'),
          throwsA(
            isA<VpnStartException>().having(
              (e) => e.message,
              'message',
              b.windows
                  ? 'xray exited with code 7.\n$hint\nline 1\n$_wintunRefused'
                  : 'xray exited with code 7.\nline 1\n$_wintunRefused',
            ),
          ),
        );
      });

      test('без журнала хвост честно пустой', () async {
        final b = make();
        final core = FakeCoreProcess()..exit(2);
        final port = await _closedPort();

        await expectLater(
          b.waitForPort(port, process: core, processLabel: 'mihomo HTTP'),
          throwsA(
            isA<VpnStartException>().having(
              (e) => e.message,
              'message',
              'mihomo HTTP exited with code 2.\n(no process output)',
            ),
          ),
        );
      });
    });
  }
}

Future<int> _closedPort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  await s.close();
  return port;
}
