import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/geo_asset_index.dart';
import 'package:keqdroid/utils/geo_dat_reader.dart';
import 'package:keqdroid/utils/routing_presets.dart';

/// Вшитая в APK база стран урезана до кодов, которые приложение выпускает само
/// (`tool/geo_lite.dart`). Всё, чего в ней нет, санитайзер выбрасывает ДО
/// генерации конфига — молча для пользователя, потому что иначе неизвестный код
/// уронил бы конфиг ядра целиком.
///
/// Отсюда риск, ради которого этот файл и существует: добавить пресет с новой
/// страной и забыть пересобрать урезанную базу. Приложение соберётся, тесты
/// пройдут, а правило будет тихо пропадать у всех.
void main() {
  final lite = File('assets/geo/geoip-lite.dat');

  /// Все `geoip:`-коды, которые приложение может положить в конфиг без участия
  /// пользователя: пресеты маршрутизации плюс правила по умолчанию.
  Set<String> presetGeoipCodes() {
    final out = <String>{};
    void scan(Iterable<String> values) {
      for (final v in values) {
        for (final token in v.split(',')) {
          final t = token.trim().toLowerCase();
          if (!t.startsWith('geoip:')) continue;
          // `geoip:!ru` — отрицание того же кода, в базе он один.
          out.add(t.substring('geoip:'.length).replaceFirst('!', ''));
        }
      }
    }

    for (final preset in RoutingPresets.all) {
      scan(preset.values);
    }
    scan([
      RoutingPresets.defaultDirectRules,
      RoutingPresets.defaultProxyRules,
      RoutingPresets.defaultBlockedRules,
    ]);
    return out;
  }

  test('урезанная база покрывает все коды, которые приложение выпускает само',
      () async {
    final present = await GeoDatReader.codes(lite);
    expect(present, isNotEmpty, reason: 'assets/geo/geoip-lite.dat не читается');

    final needed = presetGeoipCodes()
      // Генераторы конфига дописывают его сами, в пресетах его нет.
      ..add('private');

    final missing = needed.difference(present);
    expect(
      missing,
      isEmpty,
      reason: 'этих кодов нет во вшитой базе: ${missing.join(", ")}. '
          'Добавь их в _defaultCodes и пересобери: dart run tool/geo_lite.dart',
    );
  });

  test('база по умолчанию не считается полной', () async {
    // Порог отделяет вшитую базу от догруженной, и обе стороны должны быть от
    // него далеко: иначе «полная база» покажется установленной там, где её нет.
    final present = await GeoDatReader.codes(lite);
    expect(present.length, lessThan(GeoAssetIndex.fullGeoipCodeThreshold));

    final index = GeoAssetIndex(geoipCodes: present, geositeCodes: const {});
    expect(index.hasFullGeoip, isFalse);
  });

  test('дефолтные правила приложения не ссылаются на страны вне базы', () async {
    // Тот же вопрос с другой стороны: не «есть ли код в базе», а «что увидит
    // человек сразу после установки». Санитайзер не должен выбросить ничего.
    final present = await GeoDatReader.codes(lite);
    final index = GeoAssetIndex(geoipCodes: present, geositeCodes: const {});
    for (final code in presetGeoipCodes()) {
      expect(
        index.geoipCodes.contains(code),
        isTrue,
        reason: 'geoip:$code выпадет из маршрутизации на свежей установке',
      );
    }
  });
}
