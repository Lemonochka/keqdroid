// Creates secrets/backup_key.json: the release key for backup files, split into
// two halves the build passes as --dart-define-from-file (key = A xor B).
// The file stays out of git. Replacing it makes every backup saved by earlier
// releases unreadable, so the script refuses to overwrite it.
//
// Usage: dart run tool/new_backup_key.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

void main() {
  final file = File('secrets/backup_key.json');
  if (file.existsSync()) {
    stderr.writeln('${file.path} already exists; backups of earlier releases '
        'need this key, so it is left as is.');
    exitCode = 1;
    return;
  }
  final random = Random.secure();
  int word() => random.nextInt(1 << 16) << 16 | random.nextInt(1 << 16);
  final defines = <String, String>{};
  for (var i = 0; i < 8; i++) {
    final key = word();
    final a = word();
    defines['KEQ_BK_A$i'] = '$a';
    defines['KEQ_BK_B$i'] = '${key ^ a}';
  }
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(defines)}\n',
  );
  stdout.writeln('Written ${file.path}. Put its whole content into the '
      'KEQDROID_BACKUP_KEY secret of the GitHub repository.');
}
