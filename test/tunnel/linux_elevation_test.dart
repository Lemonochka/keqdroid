import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/tunnel/linux_elevation.dart';

/// Чем поднимать ядро TUN на Linux.
///
/// Способов три, и путают их дорого: лишний pkexec на системе без polkit
/// отказывает в TUN тому, у кого права уже есть, а пропущенный — молча
/// запускает ядро без прав, и оно падает на `/dev/net/tun` без внятной причины.
/// Порядок аргументов — контракт с телом обёртки, которое читает их как
/// `$1`..`$8`: сдвиг на один превратит путь к конфигу в путь к логу.
void main() {
  const wrapper = 'SB="\$1"; CFG="\$2"';
  const helper = '/usr/local/lib/keqdroid/keqrnel-tun-root';
  const coreArgs = ['/tmp/s/keqrnel', '/tmp/s/cfg.json', '/tmp/s/geo'];

  test('под root pkexec не нужен вовсе', () {
    final launch = planElevation(
      coreArgs: coreArgs,
      wrapperBody: wrapper,
      helperPath: helper,
      asRoot: true,
      passwordless: false,
    );

    expect(launch.executable, 'sh');
    expect(launch.viaPkexec, isFalse);
    // sh перед аргументами — имя нулевого аргумента, иначе первый путь
    // достанется `$0` и обёртка прочитает конфиг вместо бинаря.
    expect(launch.args, ['-c', wrapper, 'sh', ...coreArgs]);
  });

  test('беспарольное правило — фиксированный root-хелпер', () {
    final launch = planElevation(
      coreArgs: coreArgs,
      wrapperBody: wrapper,
      helperPath: helper,
      asRoot: false,
      passwordless: true,
    );

    expect(launch.executable, 'pkexec');
    expect(launch.viaPkexec, isTrue);
    // Правило polkit матчит ровно этот путь, поэтому inline-обёртки здесь быть
    // не должно: с ней pkexec снова спросит пароль.
    expect(launch.args, [helper, ...coreArgs]);
  });

  test('обычный случай — pkexec с inline-обёрткой', () {
    final launch = planElevation(
      coreArgs: coreArgs,
      wrapperBody: wrapper,
      helperPath: helper,
      asRoot: false,
      passwordless: false,
    );

    expect(launch.executable, 'pkexec');
    expect(launch.viaPkexec, isTrue);
    expect(launch.args, ['sh', '-c', wrapper, 'sh', ...coreArgs]);
  });

  test('root старше беспарольного правила', () {
    // Правило может остаться от прежних запусков, но под root оно ничего не
    // даёт: polkit в такой системе может быть вовсе не установлен.
    final launch = planElevation(
      coreArgs: coreArgs,
      wrapperBody: wrapper,
      helperPath: helper,
      asRoot: true,
      passwordless: true,
    );

    expect(launch.viaPkexec, isFalse);
    expect(launch.executable, 'sh');
  });

  test('на не-Linux root не мерещится', () {
    // Тесты гоняются под Windows: procfs нет, и ответ обязан быть «нет», иначе
    // логика выбора ушла бы в ветку без pkexec на ровном месте.
    expect(runningAsRoot(), isFalse);
  });
}
