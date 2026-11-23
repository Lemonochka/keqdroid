import 'dart:io';

typedef MacosElevationLaunch = ({
  String executable,
  List<String> args,
  bool viaOsascript,
  bool viaSudo,
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

String posixShellQuote(String value) =>
    "'${value.replaceAll("'", r"'\''")}'";

String appleScriptEscape(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

String appleScriptAdminCommand(List<String> argv) {
  final shellCommand = argv.map(posixShellQuote).join(' ');
  return 'do shell script "${appleScriptEscape(shellCommand)}" '
      'with administrator privileges';
}

// Three launch paths: already root (direct sh), installed passwordless helper (sudo -n),
// or interactive macOS admin prompt via osascript running a staged wrapper script.
MacosElevationLaunch planMacosElevation({
  required List<String> coreArgs,
  required String wrapperScriptPath,
  required String helperPath,
  required bool asRoot,
  required bool passwordless,
}) {
  if (asRoot) {
    return (
      executable: '/bin/sh',
      args: <String>[wrapperScriptPath, ...coreArgs],
      viaOsascript: false,
      viaSudo: false,
    );
  }
  if (passwordless) {
    return (
      executable: '/usr/bin/sudo',
      args: <String>['-n', helperPath, ...coreArgs],
      viaOsascript: false,
      viaSudo: true,
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
    viaSudo: false,
  );
}
