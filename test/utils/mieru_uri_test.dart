import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/mieru_uri.dart';

/// Одна ссылка mieru описывает столько серверов, сколько в ней пар
/// порт/протокол. У нас «одна ссылка — один сервер», поэтому на импорте она
/// раскладывается; иначе в списке был бы один сервер вместо трёх, и работал бы
/// только его первый порт.
void main() {
  test('несколько пар раскладываются в несколько ссылок', () {
    final links = MieruLink.expand(
      'mierus://user:pass@mieru.example'
      '?port=2999&protocol=TCP&port=3000&protocol=UDP&multiplexing=high#Node',
    );

    expect(links, hasLength(2));
    final first = MieruLink.tryParse(links.first)!;
    final second = MieruLink.tryParse(links.last)!;
    expect(first.port, 2999);
    expect(first.transport, 'TCP');
    expect(second.port, 3000);
    expect(second.transport, 'UDP');
    // Прочие параметры достаются обеим.
    expect(first.multiplexing, 'high');
    expect(second.multiplexing, 'high');
    // Имена должны различаться, иначе в списке два одинаковых сервера.
    expect(Uri.parse(links.first).fragment, 'Node:2999/TCP');
    expect(Uri.parse(links.last).fragment, 'Node:3000/UDP');
  });

  test('одна пара остаётся одной ссылкой, байт в байт', () {
    const link = 'mierus://user:pass@mieru.example?port=2999&protocol=TCP#Node';
    expect(MieruLink.expand(link), [link]);
  });

  test('чужие схемы не трогаем', () {
    const link = 'vless://uuid@host:443?port=1&protocol=TCP';
    expect(MieruLink.expand(link), [link]);
  });

  test('неполная пара — ссылка остаётся как есть, разбор отказывает', () {
    const broken = 'mierus://user:pass@mieru.example?port=2999&port=3000';
    expect(MieruLink.expand(broken), [broken]);
    expect(MieruLink.tryParse(broken), isNull);
  });

  test('диапазон портов отличается от одиночного', () {
    final range = MieruLink.tryParse(
      'mierus://u:p@mieru.example?port=2999-3010&protocol=TCP',
    )!;
    expect(range.port, isNull);
    expect(range.portRange, '2999-3010');
  });

  test('имя берётся из profile, а потом из адреса', () {
    final byProfile = MieruLink.expand(
      'mierus://u:p@mieru.example'
      '?profile=Home&port=1&protocol=TCP&port=2&protocol=TCP',
    );
    expect(Uri.parse(byProfile.first).fragment, 'Home:1/TCP');

    final byHost = MieruLink.expand(
      'mierus://u:p@mieru.example?port=1&protocol=TCP&port=2&protocol=TCP',
    );
    expect(Uri.parse(byHost.first).fragment, 'mieru.example:1/TCP');
  });
}
