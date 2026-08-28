import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/go_build_info.dart';

/// Собирает блок build info в том виде, в каком его кладёт в бинарь Go 1.18+:
/// метка, размер указателя, флаги, затем две строки с длиной-uvarint впереди.
Uint8List buildBlob({
  required String goVersion,
  required String modinfo,
  int flags = 0x02,
  bool frame = true,
}) {
  // Маркеры — намеренно невалидный UTF-8: ровно из-за них рамку нельзя резать
  // после декодирования.
  final head = List<int>.filled(16, 0xf9);
  final tail = List<int>.filled(16, 0xf2);
  final body = <int>[
    if (frame) ...head,
    ...utf8.encode(modinfo),
    if (frame) ...tail,
  ];

  List<int> uvarint(int value) {
    final out = <int>[];
    var v = value;
    while (v >= 0x80) {
      out.add((v & 0x7f) | 0x80);
      v >>= 7;
    }
    out.add(v);
    return out;
  }

  final version = utf8.encode(goVersion);
  return Uint8List.fromList([
    ...GoBuildInfo.magic,
    8, // ptrSize
    flags,
    // Слоты под указатели на версию и модули: в inline-варианте они нулевые,
    // но заголовок всё равно занимает 32 байта — строки идут только за ними.
    ...List<int>.filled(16, 0),
    ...uvarint(version.length),
    ...version,
    ...uvarint(body.length),
    ...body,
  ]);
}

void main() {
  group('разбор блока', () {
    test('версия тулчейна, свой модуль и зависимости', () {
      final blob = buildBlob(
        goVersion: 'go1.26.0',
        modinfo: 'path\tkeqrnel/cmd/keqrnel\n'
            'mod\tkeqrnel\t(devel)\t\n'
            'dep\tgithub.com/sagernet/sing-box\tv1.13.19\th1:abc\n'
            'dep\tgithub.com/xtls/xray-core\tv1.260327.1\th1:def\n'
            'build\t-buildmode=exe\n',
      );

      final info = GoBuildInfo.parse(blob)!;

      expect(info.goVersion, 'go1.26.0');
      expect(info.modulePath, 'keqrnel');
      expect(info.moduleVersion, '(devel)');
      expect(info.deps, hasLength(2));
      expect(info.depVersion('xtls/xray-core'), 'v1.260327.1');
      expect(info.depVersion('sagernet/sing-box'), 'v1.13.19');
    });

    test('флаги сборки: по ним видно, что ядро умеет', () {
      // `-tags` решает судьбу TUN: без `with_gvisor` ядро падает на СТАРТЕ со
      // `stack: gvisor`, а это наше умолчание.
      final info = GoBuildInfo.parse(buildBlob(
        goVersion: 'go1.26.0',
        modinfo: 'mod\tkeqrnel\t(devel)\t\n'
            'build\t-buildmode=exe\n'
            'build\t-tags=with_gvisor,with_quic\n'
            'build\tCGO_ENABLED=0\n'
            'build\t-ldflags=-s -w\n',
      ))!;

      expect(info.hasBuildSettings, isTrue);
      expect(info.buildTags, {'with_gvisor', 'with_quic'});
      expect(info.settings['CGO_ENABLED'], '0');
      // Значение со своими '=' режется по ПЕРВОМУ разделителю.
      expect(info.settings['-ldflags'], '-s -w');
    });

    test('без флагов сборки «тега нет» означает «неизвестно»', () {
      final info = GoBuildInfo.parse(buildBlob(
        goVersion: 'go1.26.0',
        modinfo: 'mod\tkeqrnel\t(devel)\t\n',
      ))!;

      expect(info.hasBuildSettings, isFalse);
      expect(info.buildTags, isEmpty);
    });

    test('зависимость ищется и по полному пути, и по хвосту', () {
      final info = GoBuildInfo.parse(buildBlob(
        goVersion: 'go1.26.0',
        modinfo: 'dep\tgithub.com/xtls/xray-core\tv1.2.3\t\n',
      ))!;

      expect(info.depVersion('github.com/xtls/xray-core'), 'v1.2.3');
      expect(info.depVersion('xtls/xray-core'), 'v1.2.3');
      // Хвост совпадает по границе сегмента, а не по подстроке: иначе
      // `ray-core` и `core` выдавали бы чужую версию за свою.
      expect(info.depVersion('core'), isNull);
      expect(info.depVersion('нет-такого'), isNull);
    });

    test('мажорная версия в пути модуля не прячет зависимость', () {
      // Выпуск мажора переименовывает модуль целиком: amneziawg-go 3.1 живёт
      // по пути `…/amneziawg-go/v3`. Панель обязана показать его версию, не
      // дожидаясь, пока кто-нибудь допишет `/v3` в свой список движков.
      final info = GoBuildInfo.parse(buildBlob(
        goVersion: 'go1.26.0',
        modinfo: 'mod\tgithub.com/artem-russkikh/wireproxy-awg\tv1.0.18\t\n'
            'dep\tgithub.com/amnezia-vpn/amneziawg-go/v3\tv3.1.20260814\t\n',
      ))!;

      expect(info.depVersion('amnezia-vpn/amneziawg-go'), 'v3.1.20260814');
      expect(info.depVersion('amnezia-vpn/amneziawg-go/v3'), 'v3.1.20260814');
      // Мажор отбрасывается, а не игнорируется целый сегмент.
      expect(info.depVersion('amnezia-vpn'), isNull);
    });

    test('своё ядро узнаётся по пути с мажорной версией', () {
      final info = GoBuildInfo.parse(buildBlob(
        goVersion: 'go1.26.0',
        modinfo: 'mod\tgithub.com/xjasonlyu/tun2socks/v2\tv2.7.0\t\n',
      ))!;

      expect(info.isModule('xjasonlyu/tun2socks/v2'), isTrue);
      expect(info.isModule('xjasonlyu/tun2socks'), isTrue);
      expect(info.isModule('sagernet/sing-box'), isFalse);
    });

    test('маркеры рамки не утекают в текст модулей', () {
      final info = GoBuildInfo.parse(buildBlob(
        goVersion: 'go1.26.0',
        modinfo: 'mod\tkeqrnel\t(devel)\t\n',
      ))!;

      expect(info.modulePath, 'keqrnel');
      expect(info.moduleVersion, '(devel)');
    });

    test('чужие и обрезанные данные не разбираются', () {
      expect(GoBuildInfo.parse(Uint8List.fromList([1, 2, 3])), isNull);
      expect(
        GoBuildInfo.parse(Uint8List.fromList(List.filled(64, 0))),
        isNull,
      );
      // Go младше 1.18: строки по указателям, разбирать нечего.
      expect(
        GoBuildInfo.parse(buildBlob(
          goVersion: 'go1.16',
          modinfo: 'mod\tx\tv1\t\n',
          flags: 0x00,
        )),
        isNull,
      );
      // Заявленная длина больше самих данных.
      final truncated = buildBlob(goVersion: 'go1.26.0', modinfo: 'mod\tx\tv1\t\n');
      expect(GoBuildInfo.parse(truncated.sublist(0, 20)), isNull);
    });

    test('блок без рамки не выдаёт мусор за модули', () {
      final info = GoBuildInfo.parse(buildBlob(
        goVersion: 'go1.26.0',
        modinfo: 'mod\tkeqrnel\t(devel)\t\n',
        frame: false,
      ))!;

      expect(info.goVersion, 'go1.26.0');
      expect(info.deps, isEmpty);
      expect(info.modulePath, isNull);
    });
  });

  group('поставляемые ядра', () {
    // Бинари лежат в репозитории, но на голом клоне без них тест не должен
    // краснеть — он проверяет ФОРМАТ, а не наличие файла.
    Future<void> expectCore(
      String path,
      void Function(GoBuildInfo info) checks,
    ) async {
      final file = File(path);
      if (!file.existsSync()) {
        markTestSkipped('нет $path');
        return;
      }
      final info = await GoBuildInfo.fromFile(file);
      expect(info, isNotNull, reason: '$path — Go-бинарь, build info обязан быть');
      checks(info!);
    }

    // keqrnel собирается из рабочего дерева, поэтому своей версии у него нет
    // (`(devel)`) — показывать про него можно только версии движков внутри.
    test('keqrnel несёт версии xray и sing-box', () async {
      await expectCore(
        'assets/bin/windows/keqrnel.exe',
        (info) {
          expect(info.goVersion, startsWith('go1.'));
          expect(info.modulePath, 'github.com/Lemonochka/keqrnel');
          expect(info.depVersion('xtls/xray-core'), startsWith('v'));
          expect(info.depVersion('sagernet/sing-box'), startsWith('v'));
        },
      );
    });

    // А libxray — это сам xray-core, и его версия лежит в `mod`, не в `dep`.
    test('libxray сам является xray-core', () async {
      await expectCore(
        'android/app/src/main/jniLibs/arm64-v8a/libxray.so',
        (info) {
          expect(info.modulePath, 'github.com/xtls/xray-core');
          expect(info.moduleVersion, startsWith('v'));
          expect(info.depVersion('xtls/xray-core'), isNull);
        },
      );
    });

    test('tun2socks отдаёт свою версию', () async {
      await expectCore(
        'android/app/src/main/jniLibs/arm64-v8a/libtun2socks.so',
        (info) {
          expect(info.modulePath, 'github.com/xjasonlyu/tun2socks/v2');
          expect(info.moduleVersion, startsWith('v'));
        },
      );
    });

    test('wireproxy отдаёт свою версию и версию amneziawg внутри', () async {
      await expectCore(
        'assets/bin/windows/wireproxy.exe',
        (info) {
          expect(info.moduleVersion, startsWith('v'));
          expect(info.depVersion('amnezia-vpn/amneziawg-go'), startsWith('v'));
        },
      );
    });
  });
}
