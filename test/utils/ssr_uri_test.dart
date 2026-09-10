import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/ssr_uri.dart';

/// У SSR внутри base64 лежит всё: адрес, пароль, параметры и имя. Пока
/// разборщика не было, сервер показывался куском base64 вместо адреса, пинг
/// мерил несуществующий хост, а ключ сопоставления менялся при переименовании
/// узла у провайдера.
String _b64(String value) =>
    base64Url.encode(utf8.encode(value)).replaceAll('=', '');

String _link({
  String host = 'ssr.example',
  String port = '8388',
  String protocol = 'auth_aes128_md5',
  String method = 'aes-256-cfb',
  String obfs = 'tls1.2_ticket_auth',
  String password = 'secret',
  String query = '',
}) {
  final payload =
      '$host:$port:$protocol:$method:$obfs:${_b64(password)}/?$query';
  return 'ssr://${_b64(payload)}';
}

void main() {
  test('разбирает все шесть полей и параметры из хвоста', () {
    final parsed = SsrLink.tryParse(_link(
      query: 'obfsparam=${_b64('cdn.example')}&protoparam=${_b64('32')}'
          '&remarks=${_b64('Узел RU')}',
    ));

    expect(parsed, isNotNull);
    expect(parsed!.host, 'ssr.example');
    expect(parsed.port, 8388);
    expect(parsed.protocol, 'auth_aes128_md5');
    expect(parsed.method, 'aes-256-cfb');
    expect(parsed.obfs, 'tls1.2_ticket_auth');
    expect(parsed.password, 'secret');
    expect(parsed.obfsParam, 'cdn.example');
    expect(parsed.protocolParam, '32');
    expect(parsed.remarks, 'Узел RU');
  });

  // Хвоста с параметрами может не быть вовсе: сервер описан уже первой
  // половиной. Ядро такую ссылку пропускает, мы — берём.
  test('ссылка без хвоста параметров разбирается', () {
    final payload = 'ssr.example:8388:origin:aes-256-cfb:plain:${_b64('pw')}';
    final parsed = SsrLink.tryParse('ssr://${_b64(payload)}');
    expect(parsed?.host, 'ssr.example');
    expect(parsed?.obfsParam, '');
  });

  test('обычный и url-safe base64 читаются одинаково', () {
    final payload = 'ssr.example:8388:origin:aes-256-cfb:plain:${_b64('pw')}/?';
    final standard = base64.encode(utf8.encode(payload));
    expect(SsrLink.tryParse('ssr://$standard')?.host, 'ssr.example');
  });

  test('мусор и чужие схемы — null, а не полупустой сервер', () {
    expect(SsrLink.tryParse('ssr://не-base64'), isNull);
    expect(SsrLink.tryParse('ss://YWVzOnB3@host:8388'), isNull);
    // Полей должно быть ровно шесть: меньше — ссылка не та.
    expect(SsrLink.tryParse('ssr://${_b64('host:8388:origin')}'), isNull);
    expect(
      SsrLink.tryParse('ssr://${_b64('host:notaport:a:b:c:d/?')}'),
      isNull,
    );
  });
}
