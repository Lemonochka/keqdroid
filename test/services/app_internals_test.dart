import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_internals.dart';
import 'package:keqdroid/services/app_internals_service.dart';
import 'package:keqdroid/tunnel/connection_mode.dart';
import 'package:keqdroid/tunnel/tunnel_state.dart';
import 'package:keqdroid/utils/byte_format.dart';

void main() {
  group('версия модуля', () {
    test('обычная версия остаётся как есть', () {
      expect(AppInternalsService.formatVersion('v2.7.0'), 'v2.7.0');
      expect(AppInternalsService.formatVersion('v1.13.19'), 'v1.13.19');
    });

    test('псевдоверсия ужимается до версии и короткого коммита', () {
      expect(
        AppInternalsService.formatVersion(
          'v1.260327.1-0.20260728075948-5ca6f4b7d4dc',
        ),
        'v1.260327.1 · 5ca6f4b7d4dc',
      );
      // Форма без предшествующего тега.
      expect(
        AppInternalsService.formatVersion(
          'v0.0.0-20230101000000-abcdefabcdef',
        ),
        'v0.0.0 · abcdefabcdef',
      );
    });

    test('(devel) — это отсутствие версии, а не версия', () {
      // keqrnel собирается из рабочего дерева: показывать «(devel)» как версию
      // ядра значит врать, панель в этом случае говорит про движки внутри.
      expect(AppInternalsService.formatVersion('(devel)'), isNull);
      expect(AppInternalsService.formatVersion(''), isNull);
      expect(AppInternalsService.formatVersion(null), isNull);
    });
  });

  test('версия Dart — без даты сборки SDK', () {
    expect(
      AppInternalsService.dartVersion(
        '3.11.3 (stable) (Tue Jun 3 2026) on "windows_x64"',
      ),
      '3.11.3',
    );
    expect(AppInternalsService.dartVersion('3.11.3'), '3.11.3');
  });

  group('размер файла', () {
    test('двоичные приставки', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1.0 KiB');
      // Реальный keqrnel.exe: проводник показывает ровно столько же.
      expect(formatBytes(61360128), '58.5 MiB');
      expect(formatBytes(23490631), '22.4 MiB');
    });

    test('у трёхзначных значений дробной части нет', () {
      expect(formatBytes(1024 * 1024 * 100), '100 MiB');
      expect(formatBytes(1024 * 1024 * 1024 * 2), '2.0 GiB');
    });
  });

  test('дата файла — только день, в локальной зоне', () {
    expect(formatFileDate(DateTime(2026, 8, 5, 21, 18)), '2026-08-05');
    expect(formatFileDate(DateTime(2026, 12, 31)), '2026-12-31');
  });

  group('отчёт для буфера', () {
    AppInternals sample({
      List<CoreInfo>? cores,
      SessionInfo? session,
    }) {
      return AppInternals(
        cores: cores ??
            [
              CoreInfo(
                name: 'keqrnel.exe',
                role: CoreRole.core,
                goVersion: 'go1.26.0',
                sizeBytes: 61360128,
                modified: DateTime.utc(2026, 8, 19),
                engines: const {
                  'xray-core': 'v1.260327.1 · 5ca6f4b7d4dc',
                  'sing-box': 'v1.13.19',
                },
              ),
              const CoreInfo.missing(
                name: 'wireproxy.exe',
                role: CoreRole.amneziawg,
              ),
            ],
        geoBases: const [
          GeoBaseInfo(name: 'geoip.dat', codeCount: 253, sizeBytes: 23490631),
          GeoBaseInfo(name: 'geosite.dat', codeCount: 0, missing: true),
        ],
        session: session ??
            const SessionInfo(
              status: VpnStatus.connected,
              engine: 'keqrnel',
              mode: ConnectionMode.tun,
              socksPort: 2080,
              httpPort: 8080,
              corePids: {'keqrnel': 4242},
              elevated: true,
              clashApiPort: 9090,
            ),
        build: const BuildInfo(
          appVersion: '0.9.2',
          buildNumber: '35',
          packageName: 'com.keqdroid.keqdroid',
          operatingSystem: 'windows',
          osVersion: 'Windows 11',
          abi: 'windows_x64',
          dartVersion: '3.11.3',
          releaseMode: true,
        ),
      );
    }

    test('несёт версии движков внутри ядра', () {
      final report = AppInternalsService.report(sample());

      expect(report, contains('keqrnel.exe: (no own version)'));
      expect(report, contains('xray-core: v1.260327.1 · 5ca6f4b7d4dc'));
      expect(report, contains('sing-box: v1.13.19'));
      expect(report, contains('built with go1.26.0'));
    });

    test('отсутствующее ядро и база помечены, а не пропущены', () {
      final report = AppInternalsService.report(sample());

      expect(report, contains('wireproxy.exe: missing'));
      expect(report, contains('geosite.dat: missing'));
      expect(report, contains('geoip.dat: 253 codes'));
    });

    test('сессия и сборка попадают целиком', () {
      final report = AppInternalsService.report(sample());

      expect(report, contains('app: 0.9.2 (35)'));
      expect(report, contains('abi: windows_x64'));
      expect(report, contains('mode: release'));
      expect(report, contains('status: connected'));
      expect(report, contains('mode: tun'));
      expect(report, contains('socks: 2080, http: 8080'));
      expect(report, contains('clash api: 9090'));
      expect(report, contains('elevated: true'));
      expect(report, contains('pid keqrnel: 4242'));
    });

    test('без сессии отчёт не падает и не выдумывает данных', () {
      final report = AppInternalsService.report(
        sample(
          session: const SessionInfo(
            status: VpnStatus.disconnected,
            engine: 'libxray',
            socksPort: 2080,
            httpPort: 8080,
          ),
        ),
      );

      expect(report, contains('status: disconnected'));
      // На Android режима нет вовсе — прочерк, а не выдуманный TUN.
      expect(report, contains('mode: n/a'));
      expect(report, isNot(contains('pid ')));
      expect(report, isNot(contains('elevated:')));
      expect(report, isNot(contains('uptime:')));
    });
  });
}
