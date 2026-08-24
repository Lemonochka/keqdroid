import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/tunnel/local_port_plan.dart';

/// Локальные порты — пожелание, а не факт.
///
/// 2080 держит сосед (второй клиент, наше же осиротевшее ядро, локальный
/// сервер), а на Windows целые диапазоны изымает Hyper-V/WSL: слушателя нет,
/// `netstat` пуст, бинд запрещён. До этого любой из случаев означал отказ
/// подключаться — снаружи «прокси/TUN не работает», причём чинить надо руками
/// и в другом месте.
/// Свободный порт, названный самой системой. Константы тут были бы флаки:
/// тесты гоняются параллельно и на чужой машине, где занято может быть что
/// угодно.
Future<int> _freePort([String host = '127.0.0.1']) async {
  final s = await ServerSocket.bind(host, 0);
  final port = s.port;
  await s.close();
  return port;
}

void main() {
  test('свободные порты остаются как в настройках', () async {
    final socks = await _freePort();
    final http = await _freePort();

    final plan = await LocalPortResolver.resolve(
      AppSettings(localPort: socks, httpPort: http),
      includeLan: false,
    );

    expect(plan.socksPort, socks);
    expect(plan.httpPort, http);
    expect(plan.changes, isEmpty);
  });

  test('занятый порт заменяется свободным, а не роняет подключение', () async {
    final squatter = await ServerSocket.bind('127.0.0.1', 0);
    addTearDown(squatter.close);

    final plan = await LocalPortResolver.resolve(
      AppSettings(localPort: squatter.port, httpPort: await _freePort()),
      includeLan: false,
    );

    expect(plan.socksPort, isNot(squatter.port));
    expect(plan.socksPort, greaterThan(squatter.port));

    final change = plan.changes.firstWhere((c) => c.label == 'SOCKS');
    expect(change.requested, squatter.port);
    expect(change.issue, LocalPortIssue.occupied);
    expect(change.describe(), contains('${plan.socksPort}'));
  });

  test('два инбаунда не получают один и тот же порт', () async {
    // Пользователь вписал один порт в оба поля: для системы он свободен, но
    // ядро поднимает инбаунды одновременно и упадёт на втором.
    final port = await _freePort();
    final plan = await LocalPortResolver.resolve(
      AppSettings(localPort: port, httpPort: port),
      includeLan: false,
    );

    expect(plan.socksPort, port);
    expect(plan.httpPort, isNot(port));
  });

  test('порты раздачи проверяются только когда раздача включена', () async {
    final squatter = await ServerSocket.bind('0.0.0.0', 0);
    addTearDown(squatter.close);

    final settings = AppSettings(
      localPort: await _freePort(),
      httpPort: await _freePort(),
      lanSocksPort: squatter.port,
      lanHttpPort: await _freePort('0.0.0.0'),
    );

    final off = await LocalPortResolver.resolve(settings, includeLan: false);
    expect(
      off.lanSocksPort,
      squatter.port,
      reason: 'выключенную раздачу ядро не слушает — трогать её незачем',
    );

    final on = await LocalPortResolver.resolve(settings, includeLan: true);
    expect(
      on.lanSocksPort,
      isNot(squatter.port),
      reason: 'занятый 8080 у dev-сервера ронял старт ядра целиком',
    );
  });

  test('план переносится в настройки сессии, не трогая остальное', () async {
    final plan = const LocalPortPlan(
      socksPort: 1,
      httpPort: 2,
      lanSocksPort: 3,
      lanHttpPort: 4,
    );
    final applied = plan.applyTo(const AppSettings(killSwitch: true));

    expect(applied.localPort, 1);
    expect(applied.httpPort, 2);
    expect(applied.lanSocksPort, 3);
    expect(applied.lanHttpPort, 4);
    expect(applied.killSwitch, isTrue);
  });

  test('сообщение об отказе называет причину, а не «занят»', () {
    final reserved = localPortBlockedMessage(
      label: 'SOCKS',
      port: 2080,
      issue: LocalPortIssue.reserved,
    );
    expect(reserved, contains('excludedportrange'));
    expect(reserved, contains('Hyper-V'));

    final occupied = localPortBlockedMessage(
      label: 'HTTP',
      port: 2081,
      issue: LocalPortIssue.occupied,
    );
    expect(occupied, contains('another program'));
  });

  test('порты живой сессии видны коду, который знает только настройку', () {
    final ports = ActiveLocalPorts()..clear();
    expect(ports.httpPortOr(2081), 2081);

    ports.set(socksPort: 3080, httpPort: 3081);
    expect(ports.httpPortOr(2081), 3081);
    expect(ports.socksPortOr(2080), 3080);

    ports.clear();
    expect(ports.httpPortOr(2081), 2081);
  });
}
