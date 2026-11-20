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
        AppInternalsService.formatVersion('v0.0.0-20230101000000-abcdefabcdef'),
        'v0.0.0 · abcdefabcdef',
      );
    });

    test('(devel) — это отсутствие версии, а не версия', () {
      // keqrnel собирается из рабочего дерева: показывать (devel) как версию
      // ядра было бы враньём, панель в этом случае говорит про движки внутри.
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
      List<ProcessExit> processExits = const [],
    }) {
      return AppInternals(
        processExits: processExits,
        cores:
            cores ??
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
              const CoreInfo.missing(name: 'mihomo.exe', role: CoreRole.core),
            ],
        geoBases: const [
          GeoBaseInfo(name: 'geoip.dat', codeCount: 253, sizeBytes: 23490631),
          GeoBaseInfo(name: 'geosite.dat', codeCount: 0, missing: true),
        ],
        session:
            session ??
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

      expect(report, contains('mihomo.exe: missing'));
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
      // На Android режима нет вовсе: прочерк, а не выдуманный TUN.
      expect(report, contains('mode: n/a'));
      expect(report, isNot(contains('pid ')));
      expect(report, isNot(contains('elevated:')));
      expect(report, isNot(contains('uptime:')));
      expect(report, isNot(contains('## process exits')));
    });

    test('смерти процесса — с причиной, статусом VPN и словами убийцы', () {
      final report = AppInternalsService.report(
        sample(
          processExits: [
            ProcessExit(
              time: DateTime(2026, 9, 27, 3, 12, 44),
              reason: 13,
              reasonName: 'OTHER',
              importance: 125,
              description: 'athena kill',
              vpnStatus: 'connected',
            ),
            ProcessExit(
              time: DateTime(2026, 9, 26, 22, 1, 5),
              reason: 10,
              reasonName: 'USER_REQUESTED',
              status: 0,
              importance: 400,
            ),
          ],
        ),
      );

      expect(report, contains('## process exits'));
      expect(
        report,
        contains(
          '2026-09-27 03:12:44 OTHER status=0 importance=125 '
          'vpn=connected "athena kill"',
        ),
      );
      // Без пометки о VPN и без описания: так и пишем, не выдумывая.
      expect(
        report,
        contains(
          '2026-09-26 22:01:05 USER_REQUESTED status=0 importance=400\n',
        ),
      );
    });
  });

  group('смерть процесса', () {
    ProcessExit exitWith(int reason, {int? sdkInt = 35}) => ProcessExit(
      time: DateTime(2026, 9, 27),
      reason: reason,
      reasonName: '$reason',
      sdkInt: sdkInt,
    );

    test('разбор ответа нативной стороны', () {
      final exit = ProcessExit.fromMap({
        'timestamp': DateTime(2026, 9, 27, 3, 12).millisecondsSinceEpoch,
        'reason': 2,
        'reasonName': 'SIGNALED',
        'status': 9,
        'importance': 125,
        'description': '  ',
        'vpnStatus': 'connected',
      }, sdkInt: 33)!;

      expect(exit.time, DateTime(2026, 9, 27, 3, 12));
      expect(exit.reasonName, 'SIGNALED');
      expect(exit.status, 9);
      expect(exit.importance, 125);
      // Пустое описание приравнено к отсутствию описания.
      expect(exit.description, isNull);
      expect(exit.vpnWasOn, isTrue);
    });

    test('запись без времени отбрасывается, без остального — нет', () {
      expect(ProcessExit.fromMap({'reason': 2}), isNull);
      final bare = ProcessExit.fromMap({'timestamp': 0})!;
      expect(bare.reason, 0);
      expect(bare.reasonName, '0');
      expect(bare.vpnStatus, isNull);
      expect(bare.vpnWasOn, isFalse);
    });

    test('VPN считается включённым, только пока сессия жила', () {
      ProcessExit withVpn(String? status) => ProcessExit(
        time: DateTime(2026),
        reason: 2,
        reasonName: 'SIGNALED',
        vpnStatus: status,
      );
      expect(withVpn('connected').vpnWasOn, isTrue);
      expect(withVpn('connecting').vpnWasOn, isTrue);
      expect(withVpn('disconnected').vpnWasOn, isFalse);
      expect(withVpn('error').vpnWasOn, isFalse);
      expect(withVpn(null).vpnWasOn, isFalse);
    });

    test('причины сводятся к тому, что можно сказать человеку', () {
      // Коды из ApplicationExitInfo.REASON_*.
      expect(exitWith(0).cause, ProcessExitCause.system); // UNKNOWN
      expect(exitWith(1).cause, ProcessExitCause.self); // EXIT_SELF
      expect(exitWith(2).cause, ProcessExitCause.system); // SIGNALED
      expect(exitWith(3).cause, ProcessExitCause.memory); // LOW_MEMORY
      expect(exitWith(4).cause, ProcessExitCause.crash); // CRASH
      expect(exitWith(5).cause, ProcessExitCause.crash); // CRASH_NATIVE
      expect(exitWith(6).cause, ProcessExitCause.crash); // ANR
      expect(
        exitWith(7).cause,
        ProcessExitCause.crash,
      ); // INITIALIZATION_FAILURE
      expect(exitWith(8).cause, ProcessExitCause.update); // PERMISSION_CHANGE
      expect(
        exitWith(9).cause,
        ProcessExitCause.system,
      ); // EXCESSIVE_RESOURCE_USAGE
      expect(exitWith(10).cause, ProcessExitCause.user); // USER_REQUESTED
      expect(exitWith(11).cause, ProcessExitCause.user); // USER_STOPPED
      expect(exitWith(12).cause, ProcessExitCause.system); // DEPENDENCY_DIED
      expect(exitWith(13).cause, ProcessExitCause.system); // OTHER
      expect(exitWith(14).cause, ProcessExitCause.system); // FREEZER
      expect(
        exitWith(15).cause,
        ProcessExitCause.update,
      ); // PACKAGE_STATE_CHANGE
      expect(exitWith(16).cause, ProcessExitCause.update); // PACKAGE_UPDATED
      expect(exitWith(99).cause, ProcessExitCause.system);
    });

    test('до Android 14 ручная остановка неотличима от обновления', () {
      expect(exitWith(10, sdkInt: 33).cause, ProcessExitCause.userOrUpdate);
      expect(exitWith(10, sdkInt: 34).cause, ProcessExitCause.user);
      // Остальные причины от версии не зависят.
      expect(exitWith(2, sdkInt: 30).cause, ProcessExitCause.system);
    });
  });

  group('версия Windows', () {
    // Жалоба: почему у меня 11 винда, а пишет, что десятая. В реестре у
    // одиннадцатой и правда записана десятка, отличает их только сборка.
    test('сборка 22000 и выше — это 11', () {
      expect(
        AppInternalsService.prettyWindowsVersion(
          '"Windows 10 Pro" 10.0 (Build 26100)',
        ),
        'Windows 11 Pro (build 26100)',
      );
    });

    test('настоящая десятка остаётся десяткой', () {
      expect(
        AppInternalsService.prettyWindowsVersion(
          '"Windows 10 Home" 10.0 (Build 19045)',
        ),
        'Windows 10 Home (build 19045)',
      );
    });

    test('серверные редакции не переименовываются', () {
      expect(
        AppInternalsService.prettyWindowsVersion(
          '"Windows Server 2025 Standard" 10.0 (Build 26100)',
        ),
        'Windows Server 2025 Standard (build 26100)',
      );
    });

    test('локализованное имя не ломается', () {
      expect(
        AppInternalsService.prettyWindowsVersion(
          '"Майкрософт Windows 11 Pro" 10.0 (Build 26100)',
        ),
        'Майкрософт Windows 11 Pro (build 26100)',
      );
    });

    test('строку незнакомого вида не трогаем', () {
      expect(
        AppInternalsService.prettyWindowsVersion('Windows 10.0 (Build 26100)'),
        'Windows 10.0 (Build 26100)',
      );
    });
  });
}
