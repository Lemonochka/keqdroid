import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/server_flag.dart';

/// Картинки флагов мы берём из ассетов `country_flags` напрямую, минуя его
/// виджет (его таблица кодов беднее набора ассетов). Цена — список [FlagArt]
/// кодов и путь к ассету живут у нас и могут разойтись с пакетом при
/// обновлении. Эти два теста именно это и ловят.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('каждый код из flagArtCodes реально грузится из пакета', () async {
    final missing = <String>[];
    for (final code in flagArtCodes) {
      try {
        await rootBundle.load(FlagArt(code).assetPath);
      } catch (_) {
        missing.add(code);
      }
    }
    expect(missing, isEmpty, reason: 'нет ассета — будет пустой кругляш');
  });

  test('в пакете не появилось флагов, которых мы не знаем', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    const prefix = 'packages/country_flags/res/si/';
    final packaged = manifest
        .listAssets()
        .where((a) => a.startsWith(prefix) && a.endsWith('.si'))
        .map((a) => a.substring(prefix.length, a.length - '.si'.length))
        .toSet();

    expect(packaged, isNotEmpty, reason: 'ассеты пакета переехали');
    expect(
      packaged.difference(flagArtCodes),
      isEmpty,
      reason: 'пакет привёз новые флаги — допишите их в _artCodes',
    );
  });
}
