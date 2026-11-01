import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// адаптивный ic_launcher в строке состояния выходит белым кругом, а значок,
// который Dart называет строкой, R8 не видит и вырезает без keep.xml
void main() {
  const res = 'android/app/src/main/res';

  Map<String, String> sources(String dir, String ext) => {
        for (final f in Directory(dir).listSync(recursive: true))
          if (f is File && f.path.endsWith(ext)) f.path: f.readAsStringSync(),
      };

  test('Dart notifications use a kept status bar drawable', () {
    final dart = sources('lib', '.dart');
    final launcher = [
      for (final e in dart.entries)
        if (e.value.contains("'@mipmap/")) e.key,
    ];
    expect(launcher, isEmpty);

    final names = {
      for (final src in dart.values)
        ...RegExp(r"'@drawable/(\w+)'").allMatches(src).map((m) => m[1]!),
    };
    expect(names, isNotEmpty);
    final keep = File('$res/raw/keep.xml').readAsStringSync();
    for (final name in names) {
      expect(File('$res/drawable/$name.xml').existsSync(), isTrue,
          reason: name);
      expect(keep, contains('@drawable/$name'), reason: name);
    }
  });

  test('native notifications use the same drawable', () {
    final icons = {
      for (final src in sources('android/app/src/main/kotlin', '.kt').values)
        ...RegExp(r'setSmallIcon\(([^)]*)\)').allMatches(src).map((m) => m[1]),
    };
    expect(icons, {'R.drawable.ic_notification'});
  });

  test('quick settings tile uses the same drawable', () {
    final tile = File('android/app/src/main/kotlin/com/keqdroid/keqdroid/'
            'VpnQuickTileService.kt')
        .readAsStringSync();
    expect(RegExp(r'TILE_ICON_RES = (\S+)').firstMatch(tile)?[1],
        'R.drawable.ic_notification');

    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(
        RegExp(r'VpnQuickTileService"[^>]*?android:icon="([^"]+)"')
            .firstMatch(manifest)?[1],
        '@drawable/ic_notification');
  });
}
