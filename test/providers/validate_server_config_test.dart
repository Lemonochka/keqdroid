import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/utils/ssr_uri.dart';

/// Ручное добавление ссылок, у которых адрес не там, где его ищет `Uri`.
///
/// У SSR хост и порт лежат внутри base64, у Mieru порт — в запросе. Общая
/// проверка находила у них пустой хост или нулевой порт и отказывала: руками
/// нельзя было добавить ни то, ни другое, хотя из подписки они приходили.
void main() {
  final ssr = const SsrLink(
    host: '198.51.100.32',
    port: 8388,
    protocol: 'origin',
    method: 'aes-256-cfb',
    obfs: 'plain',
    password: 'secret',
    obfsParam: '',
    protocolParam: '',
    remarks: 'ssr',
  ).encode();

  test('ssr-ссылка проходит проверку', () {
    expect(ServersNotifier.validateServerConfig(ssr), isNull);
  });

  test('битая ssr-ссылка — отказ со своей причиной', () {
    // base64 от `not-a-link`: шести частей в ней нет.
    expect(
      ServersNotifier.validateServerConfig('ssr://bm90LWEtbGluaw'),
      contains('SSR'),
    );
  });

  test('mieru с портом в запросе проходит проверку', () {
    expect(
      ServersNotifier.validateServerConfig(
        'mierus://user:pass@198.51.100.33?port=2999&protocol=TCP',
      ),
      isNull,
    );
  });

  test('mieru с несколькими парами — тоже: раскладывает её addManual', () {
    expect(
      ServersNotifier.validateServerConfig(
        'mierus://user:pass@198.51.100.33'
        '?port=2999&protocol=TCP&port=3000&protocol=UDP',
      ),
      isNull,
    );
  });

  test('mieru без пары порт/протокол — отказ со своей причиной', () {
    expect(
      ServersNotifier.validateServerConfig('mierus://user:pass@198.51.100.33'),
      contains('Mieru'),
    );
  });
}
