import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/windows_tun_service.dart';

const _channel = MethodChannel('keqdroid/tun_service');

Future<void> _fromNative(String method, Map<String, Object?> args) =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          _channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, args),
          ),
          (_) {},
        );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  Object? status;

  setUp(() {
    calls = [];
    status = null;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'status':
          return status;
        case 'startCore':
          return {'pid': 4242, 'removedAdapters': <String>[]};
      }
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  group('состояние службы', () {
    test('нет службы', () async {
      status = {'installed': false, 'trusted': false};
      expect(await WindowsTunService.state(), TunServiceState.missing);
    });

    test(
      'служба от прошлой версии с другими ядрами просит обновления',
      () async {
        status = {'installed': true, 'trusted': false};
        expect(await WindowsTunService.state(), TunServiceState.outdated);
      },
    );

    test('служба узнаёт ядра приложения', () async {
      status = {'installed': true, 'trusted': true};
      expect(await WindowsTunService.state(), TunServiceState.ready);
    });
  }, skip: !Platform.isWindows);

  test(
    'ядро службы ведёт себя как процесс: вывод, выход, мягкая и жёсткая остановка',
    () async {
      final process = await WindowsTunService.startCore(
        kind: 'mihomo',
        config: '{}',
        geoDir: r'C:\app',
        adapterIds: const [r'SWD\Wintun\{1}'],
      );
      expect(process.pid, 4242);
      final start = calls.single;
      expect(start.arguments, containsPair('kind', 'mihomo'));
      expect(start.arguments, containsPair('geoDir', r'C:\app'));
      expect(start.arguments, containsPair('adapterIds', [r'SWD\Wintun\{1}']));

      final lines = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .toList();

      await _fromNative('onOutput', {
        'line': 'Tun adapter listening\r\n[Info] [1] first\n[Info] [2] second',
      });
      await process.stdin.close();
      expect(calls.last.method, 'stopCore');
      expect(calls.last.arguments, {'graceful': true});

      process.kill();
      expect(calls.last.arguments, {'graceful': false});

      await _fromNative('onExit', {'code': 1});
      expect(await process.exitCode, 1);
      expect(await lines, [
        'Tun adapter listening',
        '[Info] [1] first',
        '[Info] [2] second',
      ]);
    },
  );

  group('xray для службы', () {
    test('путь в log.access и log.error убирается, остальное как было', () {
      final out =
          jsonDecode(
                WindowsTunService.xrayForService(
                  jsonEncode({
                    'log': {
                      'access': r'C:\x.txt',
                      'Error': r'C:\y.txt',
                      'loglevel': 'info',
                    },
                    'outbounds': [
                      {'protocol': 'freedom'},
                    ],
                  }),
                ),
              )
              as Map<String, dynamic>;
      expect(out['log'], {'access': '', 'Error': '', 'loglevel': 'info'});
      expect(out['outbounds'], [
        {'protocol': 'freedom'},
      ]);
    });

    test('разделы, которых приложение не пишет, и ключи с диска выпадают', () {
      final out =
          jsonDecode(
                WindowsTunService.xrayForService(
                  jsonEncode({
                    'env': {'XRAY_LOCATION_ASSET': r'C:\'},
                    'geodata': {'file': r'C:\Windows\x.dat'},
                    'API': {'tag': 'api'},
                    'routing': {
                      'script': 'r.lua',
                      'rules': [
                        {
                          'webhook': {'url': 'http://x'},
                          'outboundTag': 'direct',
                        },
                      ],
                    },
                    'dns': {
                      'Script': 'd.lua',
                      'servers': ['1.1.1.1'],
                    },
                    'outbounds': [
                      {
                        'protocol': 'vless',
                        'streamSettings': {
                          'tlsSettings': {
                            'certificates': [
                              {
                                'certificateFile': r'C:\k.pem',
                                'keyFile': r'C:\k.key',
                              },
                            ],
                          },
                        },
                      },
                    ],
                  }),
                ),
              )
              as Map<String, dynamic>;
      expect(out.keys, unorderedEquals(['routing', 'dns', 'outbounds']));
      expect(out['routing'], {
        'rules': [
          {'outboundTag': 'direct'},
        ],
      });
      expect(out['dns'], {
        'servers': ['1.1.1.1'],
      });
      expect(jsonEncode(out['outbounds']), isNot(contains('File')));
    });

    test('конфиг без файлового лога не трогается', () {
      const config = '{"log": {"access": "none", "loglevel": "warning"}}';
      expect(WindowsTunService.xrayForService(config), config);
      expect(WindowsTunService.xrayForService('not json'), 'not json');
    });
  });
}
