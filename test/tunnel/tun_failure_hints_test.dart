import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/tunnel/tun_failure_hints.dart';

/// Наружу все падения TUN выглядели одинаково — «did not start (exit code 1)»
/// плюс хвост лога, в котором пользователю нечего опознать. Причин же десяток,
/// и почти каждая чинится в одно действие.
void main() {
  String? id(String log, {bool windows = true}) =>
      tunFailureHint(log, windows: windows)?.id;

  test('снесённый антивирусом wintun.dll', () {
    expect(
      id(
        'FATAL[0000] start service: initialize inbound/tun[tun-in]: '
        'create adapter: Failed to load wintun.dll: The specified module '
        'could not be found.',
      ),
      'wintun-missing',
    );
  });

  test('адаптер прошлой сессии ещё не снят', () {
    expect(
      id('create adapter: error creating adapter: Object already exists'),
      'adapter-busy',
    );
  });

  test('нет прав: Windows и Linux советуют разное', () {
    expect(
      id('configure tun interface: set ipv4 address: Access is denied.'),
      'access-denied',
    );
    expect(
      id('configure tun interface: operation not permitted', windows: false),
      'no-privileges',
    );
  });

  test('модуль tun не загружен', () {
    expect(
      id('open /dev/net/tun: no such file or directory', windows: false),
      'devtun-missing',
    );
  });

  test('порт: «изъят системой» и «занят соседом» — разные причины', () {
    expect(
      id(
        'listen tcp 127.0.0.1:2080: bind: An attempt was made to access a '
        'socket in a way forbidden by its access permissions.',
      ),
      'port-reserved',
    );
    expect(
      id(
        'failed to start inbound/socks[socks-in]: listen tcp '
        '127.0.0.1:2080: bind: address already in use',
      ),
      'port-busy',
    );
  });

  test('сборка ядра без gVisor', () {
    expect(id('gVisor is not included in this build'), 'gvisor-missing');
  });

  test('сети нет вовсе', () {
    expect(id('network: missing default interface'), 'no-default-route');
  });

  test('IPv6 выключен в системе', () {
    expect(
      id('configure tun interface: set ipv6 dns: Access is denied.'),
      'ipv6-refused',
      reason: 'общий «access denied» тут увёл бы к правам администратора',
    );
  });

  test('ядро не приняло конфиг', () {
    expect(
      id('decode config at config.json: json: cannot unmarshal string'),
      'bad-config',
    );
  });

  test('незнакомый вывод остаётся без подсказки', () {
    expect(id('some brand new failure nobody has seen yet'), isNull);
    expect(id(''), isNull);
  });

  test('готовое сообщение несёт и подсказку, и хвост лога', () {
    final message = tunStartFailureMessage(
      fallback: 'The TUN tunnel did not start.',
      coreOutput: 'gVisor is not included in this build',
      windows: true,
      tail: 'FATAL[0000] start service',
    );

    expect(message, contains('gVisor'));
    expect(message, contains('The TUN tunnel did not start.'));
    expect(
      message,
      contains('FATAL[0000] start service'),
      reason:
          'подсказка объясняет типовой случай, разбирать приходится '
          'нетиповой — хвост обязателен',
    );
  });
}
