import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/services/macos_tun_service.dart';
import 'package:keqdroid/tunnel/macos_core_paths.dart';
import 'package:keqdroid/ui/desktop/desktop_connection_mode.dart';
import 'package:path/path.dart' as p;

Uint8List _encodeFrame(String text) {
  final body = utf8.encode(text);
  final hdr = ByteData(4)..setUint32(0, body.length, Endian.little);
  return Uint8List(4 + body.length)
    ..setRange(0, 4, hdr.buffer.asUint8List())
    ..setRange(4, 4 + body.length, body);
}

Stream<String> _decodeFrames(Stream<Uint8List> input) async* {
  final buf = BytesBuilder(copy: false);
  await for (final chunk in input) {
    buf.add(chunk);
    while (true) {
      final bytes = buf.toBytes();
      if (bytes.length < 4) break;
      final len = ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.little);
      if (bytes.length < 4 + len) break;
      final frame = utf8.decode(Uint8List.sublistView(bytes, 4, 4 + len));
      buf.clear();
      if (bytes.length > 4 + len) {
        buf.add(Uint8List.sublistView(bytes, 4 + len));
      }
      yield frame;
    }
  }
}

void main() {
  late Directory tmp;
  late bool plistExists;
  late String daemonXraySha;
  late String daemonMihomoSha;
  late String startError;
  late List<String> receivedCommands;
  late List<List<String>> adminCommands;
  late ({int exitCode, String stderr}) nextAdminResult;

  Future<ServerSocket> startMockDaemon() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((client) async {
      await for (final frame in _decodeFrames(client)) {
        receivedCommands.add(frame);
        if (frame == 'version') {
          client.add(
            _encodeFrame('version\n1\n$daemonXraySha\n$daemonMihomoSha'),
          );
          await client.flush();
        } else if (frame.startsWith('start\n')) {
          if (startError.isNotEmpty) {
            client.add(_encodeFrame('error\n$startError'));
            await client.flush();
            continue;
          }
          client.add(_encodeFrame('ok\n9001'));
          client.add(_encodeFrame('out\nXray 1.26 started'));
          await client.flush();
        } else if (frame == 'stop') {
          client.add(_encodeFrame('exit\n0'));
          await client.flush();
        } else if (frame == 'kill') {
          client.add(_encodeFrame('exit\n137'));
          await client.flush();
        }
      }
    });
    return server;
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('keq_macos_tun_svc_');
    final binDir = Directory(
      p.join(tmp.path, 'keqdroid.app', 'Contents', 'Resources', 'bin'),
    )..createSync(recursive: true);
    File(p.join(binDir.path, 'keqdroid-tun')).writeAsStringSync('daemon');
    File(p.join(binDir.path, 'xray')).writeAsStringSync('xray');
    File(p.join(binDir.path, 'mihomo')).writeAsStringSync('mihomo');
    MacosCorePaths.executableOverride = p.join(
      tmp.path,
      'keqdroid.app',
      'Contents',
      'MacOS',
      'keqdroid',
    );

    plistExists = true;
    daemonXraySha = 'xray-sha';
    daemonMihomoSha = 'mihomo-sha';
    startError = '';
    receivedCommands = [];
    adminCommands = [];
    nextAdminResult = (exitCode: 0, stderr: '');

    MacosTunService.plistExistsOverride = () => plistExists;
    MacosTunService.coreHashesOverride = () async =>
        (xray: 'xray-sha', mihomo: 'mihomo-sha');
    MacosTunService.uidOverride = 501;
    MacosTunService.runAdminOverride = (argv) async {
      adminCommands.add(argv);
      if (nextAdminResult.exitCode == 0 &&
          argv.length >= 2 &&
          argv[1] == 'install') {
        plistExists = true;
        daemonXraySha = 'xray-sha';
        daemonMihomoSha = 'mihomo-sha';
      }
      return nextAdminResult;
    };
  });

  tearDown(() {
    MacosTunService.plistExistsOverride = null;
    MacosTunService.coreHashesOverride = null;
    MacosTunService.connectOverride = null;
    MacosTunService.transportOverride = null;
    MacosTunService.uidOverride = null;
    MacosTunService.runAdminOverride = null;
    MacosCorePaths.executableOverride = null;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('socket protocol', () {
    late ServerSocket server;

    setUp(() async {
      server = await startMockDaemon();
      MacosTunService.connectOverride = () =>
          Socket.connect(InternetAddress.loopbackIPv4, server.port);
    });

    tearDown(() => server.close());

    test('state distinguishes missing, outdated, and ready', () async {
      plistExists = false;
      expect(await MacosTunService.state(), TunServiceState.missing);

      plistExists = true;
      daemonXraySha = 'old-sha';
      expect(await MacosTunService.state(), TunServiceState.outdated);

      daemonXraySha = 'xray-sha';
      expect(await MacosTunService.state(), TunServiceState.ready);
    });

    test('install passes caller uid and handles user cancel', () async {
      final ok = await MacosTunService.install();
      expect(ok, (ok: true, cancelled: false));
      expect(adminCommands.single[1], 'install');
      expect(adminCommands.single[2], '501');

      nextAdminResult = (
        exitCode: 1,
        stderr: 'execution error: User canceled. (-128)',
      );
      final cancelled = await MacosTunService.install();
      expect(cancelled, (ok: false, cancelled: true));
    });

    test(
      'startCore streams stdout, closes gracefully on stdin EOF, and surfaces errors',
      () async {
        final proc = await MacosTunService.startCore(
          kind: 'xray',
          config: '{"log":{}}',
          geoDir: '/geo',
        );
        expect(proc.pid, 9001);

        final lines = proc.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .toList();

        await proc.stdin.close();
        expect(await proc.exitCode, 0);
        expect(await lines, ['Xray 1.26 started']);
        expect(receivedCommands, contains('stop'));

        startError = 'the core is already running';
        await expectLater(
          MacosTunService.startCore(kind: 'xray', config: '{}'),
          throwsA(isA<ProcessException>()),
        );
      },
    );
  });

  testWidgets('macOS dialog shows macOS wording and installs service', (
    tester,
  ) async {
    final steps = <String>[];
    MacosTunService.transportOverride = () async {
      steps.add('open');
      final ctrl = StreamController<Uint8List>();
      return (
        incoming: ctrl.stream,
        send: (Uint8List packet) async {
          steps.add('send');
          final frame = utf8.decode(packet.sublist(4));
          if (frame == 'version') {
            ctrl.add(
              _encodeFrame('version\n1\n$daemonXraySha\n$daemonMihomoSha'),
            );
          }
        },
        close: () async {
          steps.add('close');
          unawaited(ctrl.close());
        },
      );
    };

    plistExists = false;
    var restoredWindow = false;
    bool? allowed;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                allowed = await ensureMacosTunService(
                  context,
                  showWindow: true,
                  restoreWindow: () async => restoredWindow = true,
                );
              },
              child: const Text('enable-tun'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('enable-tun'));
    await tester.pumpAndSettle();

    expect(restoredWindow, isTrue);
    expect(
      find.textContaining('macOS asks for an administrator password'),
      findsOneWidget,
    );
    expect(find.textContaining('Windows'), findsNothing);

    await tester.tap(find.text('Install the service'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));

    expect(find.byType(AlertDialog), findsNothing);
    expect(adminCommands, hasLength(1));
    expect(steps, ['open', 'send', 'close']);
    expect(allowed, isTrue);
  });

  test(
    'startCore handles fragmented and coalesced frames and closes before exitCode',
    () async {
      var closed = false;
      MacosTunService.transportOverride = () async {
        final ctrl = StreamController<Uint8List>();
        return (
          incoming: ctrl.stream,
          send: (Uint8List packet) async {
            final frame = utf8.decode(packet.sublist(4));
            if (frame.startsWith('start\n')) {
              // Coalesce ok + two out frames + split across odd chunk boundaries.
              final combined = Uint8List.fromList([
                ..._encodeFrame('ok\n4242'),
                ..._encodeFrame('out\nline-1'),
                ..._encodeFrame('out\nline-2'),
              ]);
              ctrl.add(Uint8List.sublistView(combined, 0, 2));
              ctrl.add(Uint8List.sublistView(combined, 2, 11));
              ctrl.add(Uint8List.sublistView(combined, 11));
            } else if (frame == 'stop') {
              ctrl.add(_encodeFrame('exit\n0'));
            }
          },
          close: () async {
            closed = true;
            unawaited(ctrl.close());
          },
        );
      };

      final proc = await MacosTunService.startCore(kind: 'xray', config: '{}');
      expect(proc.pid, 4242);

      final linesFuture = proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .toList();

      await proc.stdin.close();
      final exitCode = await proc.exitCode;
      expect(exitCode, 0);
      expect(closed, isTrue);
      expect(await linesFuture, ['line-1', 'line-2']);
    },
  );

  testWidgets('ensureMacosTunService retries state check after install', (
    tester,
  ) async {
    var connectAttempts = 0;
    MacosTunService.transportOverride = () async {
      connectAttempts++;
      if (connectAttempts < 3) {
        throw const SocketException('daemon socket still starting');
      }
      final ctrl = StreamController<Uint8List>();
      return (
        incoming: ctrl.stream,
        send: (Uint8List packet) async {
          final frame = utf8.decode(packet.sublist(4));
          if (frame == 'version') {
            ctrl.add(
              _encodeFrame('version\n1\n$daemonXraySha\n$daemonMihomoSha'),
            );
          }
        },
        close: () async {
          unawaited(ctrl.close());
        },
      );
    };

    plistExists = false;
    bool? allowed;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                allowed = await ensureMacosTunService(context);
              },
              child: const Text('enable-tun'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('enable-tun'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Install the service'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(connectAttempts, 3);
    expect(allowed, isTrue);
  });
}
