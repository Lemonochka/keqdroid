import 'dart:io';

typedef ElevationLaunch = ({
  String executable,
  List<String> args,
  bool viaPkexec,
});

// dart:io не даёт geteuid, а id -u лишний процесс. решает effective uid
bool runningAsRoot() {
  if (!Platform.isLinux) return false;
  try {
    for (final line in File('/proc/self/status').readAsLinesSync()) {
      if (!line.startsWith('Uid:')) continue;
      final fields = line.split(RegExp(r'\s+'));
      return fields.length > 2 && fields[2] == '0';
    }
  } catch (_) {
    // без procfs считаем не root: ошибочное да увело бы запуск мимо pkexec
  }
  return false;
}

// реальный, а не effective: обёртка под pkexec узнаёт владельца из PKEXEC_UID, а это реальный uid вызвавшего
int linuxRealUid() {
  try {
    for (final line in File('/proc/self/status').readAsLinesSync()) {
      if (!line.startsWith('Uid:')) continue;
      final fields = line.split(RegExp(r'\s+'));
      if (fields.length > 1) return int.tryParse(fields[1]) ?? 0;
    }
  } catch (_) {}
  return 0;
}

// три случая: уже root (pkexec не нужен), беспарольное правило polkit для фиксированного хелпера,
// обычный pkexec с паролем. аргументы обёртка читает как $1..$6, sh перед ними это $0
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
