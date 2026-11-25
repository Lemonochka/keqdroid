import 'dart:io';

typedef MacosElevationLaunch = ({
  String executable,
  List<String> args,
  bool viaOsascript,
});

int? _cachedUid;

int macosRealUid() {
  if (!Platform.isMacOS) return 0;
  final cached = _cachedUid;
  if (cached != null) return cached;
  try {
    final r = Process.runSync('/usr/bin/id', const ['-u']);
    if (r.exitCode == 0) {
      final parsed = int.tryParse('${r.stdout}'.trim());
      if (parsed != null) return _cachedUid = parsed;
    }
  } catch (_) {}
  return 0;
}

bool macosRunningAsRoot() => Platform.isMacOS && macosRealUid() == 0;

String posixShellQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";

String appleScriptEscape(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

String appleScriptAdminCommand(List<String> argv) {
  final shellCommand = argv.map(posixShellQuote).join(' ');
  return 'do shell script "${appleScriptEscape(shellCommand)}" '
      'with administrator privileges';
}

// Уже root — напрямую, иначе только после интерактивного подтверждения.
MacosElevationLaunch planMacosElevation({
  required List<String> coreArgs,
  required String wrapperScriptPath,
  required bool asRoot,
}) {
  if (asRoot) {
    return (
      executable: '/bin/sh',
      args: <String>[wrapperScriptPath, ...coreArgs],
      viaOsascript: false,
    );
  }
  final script = appleScriptAdminCommand([
    '/bin/sh',
    wrapperScriptPath,
    ...coreArgs,
  ]);
  return (
    executable: '/usr/bin/osascript',
    args: <String>['-e', script],
    viaOsascript: true,
  );
}
