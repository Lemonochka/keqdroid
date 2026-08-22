import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/system_accent.dart';

/// Цепочка источников цвета системной темы. Проверяем то, из-за чего она и
/// появилась: на прошивках без Material You прежний путь отдавал константу
/// AOSP, и «динамическая» тема была всегда одного цвета.
void main() {
  group('выбор источника', () {
    test('настройка темы важнее обоев и ресурса', () {
      final picked = pickSystemAccent(
        const SystemAccentCandidates(
          themeSetting: 0xFF112233,
          wallpaper: 0xFF445566,
          systemResource: 0xFF778899,
        ),
      );
      expect(picked!.source, SystemAccentSource.themeSetting);
      expect(picked.color, const Color(0xFF112233));
    });

    // Живые обои не обязаны отдавать цвета, а на китайских прошивках стоят из
    // коробки — тогда остаётся ресурс палитры.
    test('без настройки берём обои, без обоев — ресурс', () {
      expect(
        pickSystemAccent(
          const SystemAccentCandidates(
            wallpaper: 0xFF445566,
            systemResource: 0xFF778899,
          ),
        )!.source,
        SystemAccentSource.wallpaper,
      );
      expect(
        pickSystemAccent(
          const SystemAccentCandidates(systemResource: 0xFF778899),
        )!.source,
        SystemAccentSource.systemResource,
      );
    });

    test('пустые кандидаты — сида нет, останемся на фирменном', () {
      expect(pickSystemAccent(const SystemAccentCandidates.empty()), isNull);
    });
  });

  group('непеpекрашенная палитра AOSP', () {
    // Суть починки: ресурс есть на любом API 31+, но там, где OEM не включил
    // ThemeOverlayController, он отдаёт константу. Принять её за «цвет
    // системы» — это и есть жалоба «у меня всегда один цвет».
    test('дефолт не считается системным цветом', () {
      expect(looksLikeAospDefault(aospDefaultAccent), isTrue);
      expect(
        pickSystemAccent(
          SystemAccentCandidates(systemResource: aospDefaultAccent),
        ),
        isNull,
      );
    });

    test('но обои с ним не спорят: дефолтный ресурс их не отменяет', () {
      final picked = pickSystemAccent(
        SystemAccentCandidates(
          wallpaper: 0xFF445566,
          systemResource: aospDefaultAccent,
        ),
      );
      expect(picked!.source, SystemAccentSource.wallpaper);
    });

    test('перекрашенный ресурс проходит', () {
      expect(looksLikeAospDefault(0xFFB33A3A), isFalse);
      expect(
        pickSystemAccent(
          const SystemAccentCandidates(systemResource: 0xFFB33A3A),
        )!.source,
        SystemAccentSource.systemResource,
      );
    });

    // Округление тона у прошивок расходится на единицу — точное сравнение
    // пропустило бы дефолт как «настоящий» цвет.
    test('допуск в один шаг на канал', () {
      final r = (aospDefaultAccent >> 16) & 0xFF;
      final rest = aospDefaultAccent & 0x0000FFFF;
      expect(
        looksLikeAospDefault(0xFF000000 | ((r + 1) << 16) | rest),
        isTrue,
      );
      expect(
        looksLikeAospDefault(0xFF000000 | ((r + 40) << 16) | rest),
        isFalse,
      );
    });
  });

  group('разбор ответа платформы', () {
    test('нули и мусор считаются отсутствием, а не чёрным цветом', () {
      final candidates = SystemAccentCandidates.fromMap(const {
        'themeSetting': 0,
        'wallpaper': null,
        'systemResource': 'не число',
      });
      expect(candidates, const SystemAccentCandidates.empty());
      expect(pickSystemAccent(candidates), isNull);
    });

    test('пустой ответ платформы не роняет разбор', () {
      expect(
        SystemAccentCandidates.fromMap(null),
        const SystemAccentCandidates.empty(),
      );
    });
  });
}
