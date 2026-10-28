import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/core/exceptions.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/tunnel/tun_failure_hints.dart';
import 'package:keqdroid/tunnel/wintun_adapters.dart';
import 'package:keqdroid/tunnel/wintun_retry.dart';
import 'package:keqdroid/utils/desktop_tun.dart';
import 'package:keqdroid/utils/error_messages.dart';

/// 27.10.2026 Windows раз за разом отказывала в TUN-адаптере (код 31 в
/// диспетчере устройств) обоим ядрам, а со следующей попытки пускала. Человек
/// видел «Ошибка сети: сервер недоступен» у xray (в выводе ядра есть Timed out)
/// и «запустите от администратора, проверьте wintun.dll» у mihomo, хотя права
/// были и dll загрузилась. Строки ниже взяты из её журнала как есть.
const _xrayLog = '''
Xray 26.10.10 (Xray, Penetrates Everything.) Custom (go1.27.0 windows/amd64)
2026/10/27 23:58:36.631609 Failed to find matching adapter name: Элемент не найден. (Code 0x00000490)
2026/10/27 23:58:36.677716 Using existing driver 0.14
2026/10/27 23:58:36.684346 Creating adapter
2026/10/27 23:58:51.709397 Timed out waiting for device query: Время ожидания операции истекло. (Code 0x00000102)
2026/10/27 23:58:51.709879 Failed to setup adapter (problem code: 0x1F, ntstatus: 0xC00002F0): Не удается найти указанный файл. (Code 0x00000002)
Failed to start: app/proxyman/inbound: failed to start proxy > The system cannot find the file specified.
''';

const _mihomoLog = '''
time="2026-10-28T00:20:05.694386500+04:00" level=info msg="SOCKS proxy listening at: 127.0.0.1:2080"
time="2026-10-28T00:20:05.704784000+04:00" level=warning msg="[TUN] default interface changed by monitor, => Ethernet"
time="2026-10-28T00:20:20.795632200+04:00" level=warning msg="Start Tun interface timeout: The system cannot find the file specified. [retrying 1/3]"
''';

const _fallback = 'The TUN tunnel did not start. Run the app as '
    'Administrator and make sure wintun.dll sits next to xray.exe.';

// так сообщение собирает WindowsTunnelBackend, когда xray вышел до подъёма TUN
VpnStartException _xrayFailure() => VpnStartException(
      'xray exited with code -1 before the tunnel came up.\n'
      '${tunStartFailureMessage(
        fallback: _fallback,
        coreOutput: _xrayLog,
        windows: true,
        tail: _xrayLog.trim().split('\n').skip(3).join('\n'),
      )}',
    );

Future<String> _renderFor(
  WidgetTester tester,
  String locale,
  Object error,
) async {
  late String rendered;
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          rendered = friendlyError(error, context);
          return const SizedBox();
        },
      ),
    ),
  );
  return rendered;
}

void main() {
  group('признак отказа', () {
    test('xray и mihomo опознаются по своему выводу', () {
      expect(isWintunAdapterRefused(_xrayLog), isTrue);
      expect(isWintunAdapterRefused(_mihomoLog), isTrue);
      expect(tunFailureHint(_xrayLog, windows: true)?.id, 'wintun-refused');
      expect(tunFailureHint(_mihomoLog, windows: true)?.id, 'wintun-refused');
    });

    test('чужие отказы TUN сюда не попадают', () {
      expect(
        isWintunAdapterRefused(
          'create adapter: Failed to load wintun.dll: The specified module '
          'could not be found.',
        ),
        isFalse,
      );
      expect(
        isWintunAdapterRefused(
          'create adapter: error creating adapter: Object already exists',
        ),
        isFalse,
      );
      expect(isWintunAdapterRefused('dial tcp: i/o timeout'), isFalse);
    });

    test('совет про администратора и wintun.dll из сообщения уходит', () {
      final message = _xrayFailure().message;
      expect(message, contains('Windows refused to set up the TUN network'));
      expect(message, isNot(contains('Run the app as Administrator')));
      expect(message, contains('ntstatus: 0xC00002F0'),
          reason: 'хвост лога остаётся для разбора');
    });
  });

  group('текст на экране', () {
    test('отказ Windows больше не выдаёт себя за ошибку сети', () {
      expect(explainError(_xrayFailure()).code, UiErrorCode.tunAdapterRefused);
    });

    test('обычный таймаут по-прежнему ошибка сети', () {
      expect(explainError('Connection timed out').code, UiErrorCode.network);
    });

    testWidgets('на en текст тот же, что в коде', (tester) async {
      expect(
        await _renderFor(tester, 'en', _xrayFailure()),
        explainError(_xrayFailure()).full,
      );
    });

    testWidgets('по-русски и три строки на каждом языке', (tester) async {
      final ru = await _renderFor(tester, 'ru', _xrayFailure());
      expect(ru.split('\n').first, 'Windows не создала адаптер');
      expect(ru, contains('трижды'));
      expect(kWintunAttempts, 3, reason: 'текст обещает три попытки');

      for (final locale in ['en', 'ru', 'de', 'zh', 'fa']) {
        final rendered = await _renderFor(tester, locale, _xrayFailure());
        expect(rendered.split('\n').length, 3, reason: 'локаль $locale');
      }
    });

    // под кнопкой подключения текст режется на пятой строке, а окно ПК сужается до 480 точек:
    // минус боковая панель и поля остаётся около 320. фарси и китайского в этих шрифтах нет,
    // в тесте их буквы рисует заглушка, мерить нечего
    testWidgets('влезает под кнопку в узком окне', (tester) async {
      for (final family in ['Rubik', 'Montserrat']) {
        final bytes = File('assets/fonts/$family-Variable.ttf').readAsBytesSync();
        await (FontLoader(family)
              ..addFont(Future.value(ByteData.sublistView(bytes))))
            .load();
      }
      for (final locale in ['en', 'ru', 'de']) {
        final text = await _renderFor(tester, locale, _xrayFailure());
        for (final family in ['Rubik', 'Montserrat']) {
          final painter = TextPainter(
            text: TextSpan(
              text: text,
              style: TextStyle(fontFamily: family, fontSize: 12, height: 16 / 12),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 5,
          )..layout(maxWidth: 300);
          expect(painter.didExceedMaxLines, isFalse,
              reason: '$locale, $family: конец совета обрезан многоточием');
        }
      }
    });
  });

  group('повтор', () {
    var output = '';

    Future<void> run({
      required List<Object?> outcomes,
      bool Function()? cancelled,
      List<int>? retries,
      List<int>? attempts,
      void Function()? onReset,
    }) {
      var i = 0;
      return retryWhileWintunRefused(
        attempt: (n) async {
          attempts?.add(n);
          final outcome = outcomes[i++];
          if (outcome is String) {
            output = outcome;
            throw const VpnStartException('xray exited with code -1');
          }
          if (outcome != null) throw outcome;
        },
        coreOutput: () => output,
        resetAttempt: () async {
          output = '';
          onReset?.call();
        },
        cancelled: cancelled ?? () => false,
        onRetry: retries?.add,
        pause: Duration.zero,
      );
    }

    test('после отказа Windows вторая попытка поднимает TUN', () async {
      final retries = <int>[];
      var resets = 0;
      await run(
        outcomes: [_xrayLog, null],
        retries: retries,
        onReset: () => resets++,
      );
      expect(retries, [1]);
      expect(resets, 1, reason: 'упавшее ядро снимается до новой попытки');
    });

    test('после трёх отказов наружу уходит ошибка', () async {
      final retries = <int>[];
      await expectLater(
        run(outcomes: [_xrayLog, _xrayLog, _xrayLog], retries: retries),
        throwsA(isA<VpnStartException>()),
      );
      expect(retries, [1, 2]);
    });

    // 27.10.2026 в 21:15 и 21:15:51 по журналу Windows GUID xray отказ получил дважды подряд,
    // а GUID mihomo в 21:16:25 прошёл. повтор с тем же именем дал бы тот же GUID
    test('со второй попытки xray создаёт адаптер с другим GUID', () async {
      final attempts = <int>[];
      await expectLater(
        run(outcomes: [_xrayLog, _xrayLog, _xrayLog], attempts: attempts),
        throwsA(isA<VpnStartException>()),
      );
      expect(attempts, [1, 2, 3]);
      final ids = attempts
          .map((n) => xrayWintunInstanceId(xrayTunNameForAttempt(n)))
          .toList();
      expect(ids[0], xrayWintunInstanceId(kTunInterfaceName));
      expect(ids[1], isNot(ids[0]));
      expect(ids[2], ids[1], reason: 'запасной GUID один, лишних сетей в Windows не плодим');
    });

    test('другую ошибку не повторяем', () async {
      final retries = <int>[];
      await expectLater(
        run(outcomes: ['bind: address already in use'], retries: retries),
        throwsA(isA<VpnStartException>()),
      );
      expect(retries, isEmpty);
    });

    test('Отключить в паузе останавливает повтор', () async {
      var cancelled = false;
      final outcomes = <Object?>[_xrayLog, null];
      await expectLater(
        run(
          outcomes: outcomes,
          cancelled: () => cancelled,
          onReset: () => cancelled = true,
        ),
        throwsA(isA<VpnStartException>()),
      );
    });
  });
}
