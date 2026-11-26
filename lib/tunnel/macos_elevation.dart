import 'dart:io';

typedef MacosAdminCommandPlan = ({
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

MacosAdminCommandPlan planMacosAdminCommand(
  List<String> argv, {
  required bool asRoot,
}) {
  if (asRoot) {
    return (
      executable: argv.first,
      args: argv.sublist(1),
      viaOsascript: false,
    );
  }
  return (
    executable: '/usr/bin/osascript',
    args: <String>['-e', appleScriptAdminCommand(argv)],
    viaOsascript: true,
  );
}

bool macosAdminCancelled(String stderrText) {
  final lower = stderrText.toLowerCase();
  return lower.contains('user canceled') || lower.contains('(-128)');
}

Future<({int exitCode, String stderr})> runMacosAdminCommand(
  List<String> argv,
) async {
  final plan = planMacosAdminCommand(argv, asRoot: macosRunningAsRoot());
  final result = await Process.run(plan.executable, plan.args);
  return (exitCode: result.exitCode, stderr: '${result.stderr}'.trim());
}
