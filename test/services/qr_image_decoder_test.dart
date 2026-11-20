import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:keqdroid/services/qr_image_decoder.dart';
import 'package:zxing2/qrcode.dart';

const _link =
    'vless://0b8f6c1e-7d2a-4c55-9a1b-2f3e4d5c6b7a@pl.example.net:443'
    '?type=xhttp&security=reality&pbk=abc&sni=www.example.com#Польша';

// кадр «экрана» с шумом и кодом где-то сбоку, как окно Telegram на втором мониторе
GrayImage _screen({
  required String text,
  bool eci = true,
  int width = 2560,
  int height = 1080,
  int left = 1700,
  int top = 300,
  int module = 6,
  bool inverted = false,
}) {
  final pixels = Uint8List(width * height);
  final random = math.Random(7);
  for (var i = 0; i < pixels.length; i++) {
    pixels[i] = inverted ? 20 + random.nextInt(40) : 180 + random.nextInt(60);
  }
  // с ECI как zxing, без него как qrcode.js и Python qrcode: те же байты UTF-8 без пометки кодировки
  final hints = EncodeHints();
  if (eci) hints.put(EncodeHintType.characterSet, CharacterSetECI.UTF8);
  final content = eci ? text : String.fromCharCodes(utf8.encode(text));
  final matrix = Encoder.encode(
    content,
    ErrorCorrectionLevel.m,
    hints: hints,
  ).matrix!;
  const quiet = 4;
  final side = (matrix.width + 2 * quiet) * module;
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final mx = x ~/ module - quiet;
      final my = y ~/ module - quiet;
      final inside =
          mx >= 0 && my >= 0 && mx < matrix.width && my < matrix.height;
      final dark = inside && matrix.get(mx, my) == 1;
      final value = dark != inverted ? 0 : 255;
      pixels[(top + y) * width + left + x] = value;
    }
  }
  return GrayImage(width, height, pixels);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('finds a code somewhere on a wide noisy screen', () {
    expect(QrImageDecoder.decodeGraySync(_screen(text: _link)), _link);
  });

  test('keeps a Cyrillic name from a code without an ECI mark', () {
    expect(
      QrImageDecoder.decodeGraySync(_screen(text: _link, eci: false)),
      _link,
    );
  });

  test(
    'restoreByteSegments puts the real bytes back only where zxing broke them',
    () {
      final bytes = Int8List.fromList(utf8.encode('#Польша'));
      final garbled = String.fromCharCodes([
        for (final b in bytes) b >= 0 ? b : 0xFFFD,
      ]);
      expect(
        QrImageDecoder.restoreByteSegments('vless://a@b:1$garbled', [bytes]),
        'vless://a@b:1#Польша',
      );
      expect(
        QrImageDecoder.restoreByteSegments('https://sub.example/x', [bytes]),
        'https://sub.example/x',
      );
      expect(QrImageDecoder.restoreByteSegments('a�b', null), 'a�b');
    },
  );

  test('reads a light code on a dark theme', () {
    expect(
      QrImageDecoder.decodeGraySync(_screen(text: _link, inverted: true)),
      _link,
    );
  });

  test('a small code from a chat preview is still found', () {
    expect(
      QrImageDecoder.decodeGraySync(_screen(text: _link, module: 3)),
      _link,
    );
  });

  test('a screen without a code gives nothing, not an error', () {
    final blank = GrayImage(
      800,
      600,
      Uint8List(800 * 600)..fillRange(0, 800 * 600, 200),
    );
    expect(QrImageDecoder.decodeGraySync(blank), isNull);
  });

  test('a code cut by the edge of the screen gives nothing', () {
    expect(
      QrImageDecoder.decodeGraySync(
        _screen(text: _link, width: 1800, left: 1700),
      ),
      isNull,
    );
  }, skip: false);

  test(
    'grayFromRgba weights green like zxing and treats transparency as white',
    () {
      final rgba = Uint8List.fromList([
        255, 0, 0, 255, // красный
        0, 255, 0, 255, // зелёный
        0, 0, 0, 0, // прозрачный
      ]);
      expect(QrImageDecoder.grayFromRgba(rgba, 3, 1), [63, 127, 255]);
    },
  );

  test('decodes a PNG and a JPEG picked as a file', () async {
    final screen = _screen(
      text: _link,
      width: 900,
      height: 700,
      left: 300,
      top: 150,
    );
    final picture = img.Image(width: screen.width, height: screen.height);
    for (var y = 0; y < screen.height; y++) {
      for (var x = 0; x < screen.width; x++) {
        final v = screen.pixels[y * screen.width + x];
        picture.setPixelRgb(x, y, v, v, v);
      }
    }
    expect(
      await QrImageDecoder.fromEncoded(
        Uint8List.fromList(img.encodePng(picture)),
      ),
      _link,
    );
    expect(
      await QrImageDecoder.fromEncoded(
        Uint8List.fromList(img.encodeJpg(picture, quality: 80)),
      ),
      _link,
    );
  });
}
