import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/services/auto_server_select.dart';

/// Кого выбирает «Авто».
///
/// Неудачный замер обнуляет `pingMs`, поэтому «красный» сервер и «ни разу не
/// меренный» в списке выглядят одинаково — различает их `lastTestedAt`, и
/// путать их нельзя: первый не работал, а про второй мы просто не знаем.
ServerItem _server(
  String id, {
  required String sub,
  int? ping,
  DateTime? tested,
}) =>
    ServerItem(
      id: id,
      config: 'vless://uuid@$id.example.com:443?type=tcp&security=none#$id',
      type: ServerItemType.subscription,
      subscriptionId: sub,
      addedAt: DateTime(2026),
      pingMs: ping,
      lastTestedAt: tested,
    );

void main() {
  final tested = DateTime(2026, 9, 22);

  test('берёт лучший по замеру внутри своей подписки', () {
    final servers = [
      _server('a', sub: 's1', ping: 120, tested: tested),
      _server('b', sub: 's1', ping: 40, tested: tested),
      // Чужая подписка быстрее, но она не наше дело.
      _server('c', sub: 's2', ping: 10, tested: tested),
    ];

    expect(
      AutoServerSelect.pick(servers, subscriptionId: 's1')?.id,
      'b',
    );
  });

  test('сервер, с которого съехали, второй раз не берём', () {
    final servers = [
      _server('a', sub: 's1', ping: 40, tested: tested),
      _server('b', sub: 's1', ping: 90, tested: tested),
    ];

    expect(
      AutoServerSelect.pick(servers, subscriptionId: 's1', exclude: 'a')?.id,
      'b',
    );
  });

  test('единственный сервер берём даже после отказа', () {
    // «Совсем никого» и «один и тот же» — разные вещи: во втором случае
    // честнее попробовать ещё раз, чем не подключаться вовсе.
    final servers = [_server('a', sub: 's1', ping: 40, tested: tested)];

    expect(
      AutoServerSelect.pick(servers, subscriptionId: 's1', exclude: 'a')?.id,
      'a',
    );
  });

  test('непомеренный идёт раньше того, чей замер провалился', () {
    final servers = [
      _server('failed', sub: 's1', tested: tested),
      _server('unknown', sub: 's1'),
    ];

    expect(
      AutoServerSelect.pick(servers, subscriptionId: 's1')?.id,
      'unknown',
    );
  });

  test('когда все красные — всё равно кто-то, а не пустота', () {
    final servers = [
      _server('a', sub: 's1', tested: tested),
      _server('b', sub: 's1', tested: tested),
    ];

    expect(AutoServerSelect.pick(servers, subscriptionId: 's1'), isNotNull);
  });

  test('подписка без серверов не выбирает никого', () {
    expect(
      AutoServerSelect.pick(
        [_server('a', sub: 's2', ping: 10, tested: tested)],
        subscriptionId: 's1',
      ),
      isNull,
    );
  });
}
