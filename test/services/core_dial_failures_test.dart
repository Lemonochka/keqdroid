import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/core_dial_failures.dart';

/// Какие строки вывода ядра — отказ дозвона до сервера.
///
/// Строки взяты в том виде, в каком ядра их пишут (формат — из исходников
/// mihomo 1.19.31, xray 26.9.9 и sing-box 1.13: tunnel.logMetadataErr,
/// vless/outbound, route/conn.go). На Android то же правило живёт в
/// forkexec.c, и расходиться им нельзя: одна и та же настройка на телефоне и
/// на ПК должна срабатывать от одних и тех же событий.
void main() {
  group('отказ до сервера — считается', () {
    test('mihomo', () {
      expect(
        CoreDialFailures.isServerDialFailure(
          'time="2026-09-23T10:00:00Z" level=warning msg="[TCP] dial proxy '
          '(match Match/) 172.19.0.1:45400 --> www.google.com:443 error: '
          'dial tcp 1.2.3.4:443: i/o timeout"',
        ),
        isTrue,
      );
    });

    test('xray', () {
      // Уровень info: исходящий обработчик xray 26.x логирует свою ошибку
      // через LogInfo, какой бы важной она ни была.
      expect(
        CoreDialFailures.isServerDialFailure(
          '2026/09/23 10:00:00.123456 [Info] [1234567] app/proxyman/'
          'outbound: app/proxyman/outbound: failed to process outbound '
          'traffic > proxy/vless/outbound: failed to find an available '
          'destination > common/retry: all retry attempts failed',
        ),
        isTrue,
      );
    });

    test('xray с XHTTP: отказ приходит строкой транспорта', () {
      // Живой тест: погашенный Vless на XHTTP, строка как есть из лога.
      // «failed to find an available destination» у XHTTP не бывает — он
      // отдаёт соединение сразу, а дозванивается потом.
      expect(
        CoreDialFailures.isServerDialFailure(
          '2026/09/22 22:33:40.007 [Info] [3321485634] transport/internet/'
          'splithttp: failed to POST https://onet.pl/ > Post '
          '"https://onet.pl/": dial tcp 144.31.2.167:443: connect: '
          'connection refused',
        ),
        isTrue,
      );
      expect(
        CoreDialFailures.isServerDialFailure(
          '2026/09/22 22:33:40.007 [Info] [42] transport/internet/'
          'splithttp: unexpected status 502',
        ),
        isTrue,
      );
    });

    test('sing-box в десктопном TUN', () {
      expect(
        CoreDialFailures.isServerDialFailure(
          'ERROR[0012] [2957417810 5.0s] connection: open connection to '
          'www.google.com:443 using outbound/vless[proxy]: dial tcp '
          '1.2.3.4:443: i/o timeout',
        ),
        isTrue,
      );
    });
  });

  group('не отказ сервера — не считается', () {
    test('XHTTP просто дозванивается или не собрал запрос', () {
      expect(
        CoreDialFailures.isServerDialFailure(
          '[Info] [1] transport/internet/splithttp: XHTTP is dialing to '
          'tcp:sub.example.com:443, mode stream-one, HTTP version 2',
        ),
        isFalse,
      );
      expect(
        CoreDialFailures.isServerDialFailure(
          '[Info] [1] transport/internet/splithttp: failed to create HTTP '
          'request for https://x/ > net/url: invalid control character',
        ),
        isFalse,
      );
    });

    test('мёртвый сайт на прямом маршруте', () {
      // Мёртвый сайт — не мёртвый сервер.
      expect(
        CoreDialFailures.isServerDialFailure(
          'level=warning msg="[TCP] dial DIRECT (match GeoSite/category-ru) '
          '172.19.0.1:1 --> ya.ru:443 error: connection refused"',
        ),
        isFalse,
      );
      expect(
        CoreDialFailures.isServerDialFailure(
          'ERROR[0001] connection: open connection to ya.ru:443 using '
          'outbound/direct[direct]: connection refused',
        ),
        isFalse,
      );
    });

    test('блокировка по правилу', () {
      expect(
        CoreDialFailures.isServerDialFailure(
          'level=warning msg="[TCP] dial REJECT (match GeoSite/ads) '
          '172.19.0.1:1 --> ads.example.com:443 error: rejected"',
        ),
        isFalse,
      );
    });

    test('UDP — сервер без UDP живой', () {
      // Каждый QUIC-запрос ютуба к серверу без UDP — отказ, и от одного
      // открытого видео живой сервер выглядел бы мёртвым.
      expect(
        CoreDialFailures.isServerDialFailure(
          'level=warning msg="[UDP] dial proxy (match Match/) '
          '172.19.0.1:40110 --> i.ytimg.com:443 error: udp not supported"',
        ),
        isFalse,
      );
    });

    test('удачное соединение', () {
      expect(
        CoreDialFailures.isServerDialFailure(
          'level=info msg="[TCP] 172.19.0.1:45412 --> www.google.com:443 '
          'match GeoIP(refilter) using proxy"',
        ),
        isFalse,
      );
    });
  });

  test('счётчик растёт только на отказах', () {
    final before = CoreDialFailures.count;
    CoreDialFailures.observe('level=info msg="Initial configuration complete"');
    CoreDialFailures.observe(
      'level=warning msg="[TCP] dial proxy (match Match/) a --> b:443 '
      'error: i/o timeout"',
    );
    expect(CoreDialFailures.count, before + 1);
  });
}
