import 'dart:io';

/// Чем поднимать ядро TUN на Linux: [executable] с [args], и идёт ли это через
/// pkexec (тогда без polkit запуск невозможен в принципе).
typedef ElevationLaunch = ({
  String executable,
  List<String> args,
  bool viaPkexec,
});

/// Уже ли мы root.
///
/// `dart:io` не даёт geteuid, а `id -u` — лишний процесс на каждом подключении;
/// `/proc/self/status` отдаёт то же самое чтением файла. Поля строки `Uid:` —
/// real, effective, saved, fs; решает effective, потому что именно с ним ядро
/// будет открывать `/dev/net/tun` и править маршруты.
bool runningAsRoot() {
  if (!Platform.isLinux) return false;
  try {
    for (final line in File('/proc/self/status').readAsLinesSync()) {
      if (!line.startsWith('Uid:')) continue;
      final fields = line.split(RegExp(r'\s+'));
      return fields.length > 2 && fields[2] == '0';
    }
  } catch (_) {
    // Нет procfs (контейнер с урезанным /proc) — считаем, что не root:
    // ошибочное «да» увело бы запуск мимо pkexec и уронило TUN без объяснений.
  }
  return false;
}

/// Как запускать root-обёртку ядра.
///
/// Три случая, и различать их приходится до запуска, потому что первый из них
/// не требует ни polkit, ни пароля:
///
/// - приложение уже под root (`sudo keqdroid`) — обёртка исполняется сразу, и
///   pkexec не нужен вовсе; иначе система без polkit отказывала бы в TUN даже
///   тому, у кого права уже есть;
/// - установлено беспарольное правило — pkexec зовёт фиксированный root-хелпер,
///   polkit пропускает его без пароля (см. `installPasswordlessTun`);
/// - обычный случай — pkexec с inline-обёрткой, polkit спросит пароль.
///
/// Тело обёртки читает свои аргументы как `$1`..`$8`, поэтому и под `sh -c`, и
/// под pkexec порядок [coreArgs] один и тот же; лишнее `sh` перед ними — имя
/// нулевого аргумента для `sh -c`.
ElevationLaunch planElevation({
  required List<String> coreArgs,
  required String wrapperBody,
  required String helperPath,
  required bool asRoot,
  required bool passwordless,
}) {
  if (asRoot) {
    return (
      executable: 'sh',
      args: <String>['-c', wrapperBody, 'sh', ...coreArgs],
      viaPkexec: false,
    );
  }
  if (passwordless) {
    return (
      executable: 'pkexec',
      args: <String>[helperPath, ...coreArgs],
      viaPkexec: true,
    );
  }
  return (
    executable: 'pkexec',
    args: <String>['sh', '-c', wrapperBody, 'sh', ...coreArgs],
    viaPkexec: true,
  );
}
