import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:zxing2/qrcode.dart';

class GrayImage {
  const GrayImage(this.width, this.height, this.pixels);

  final int width;
  final int height;
  final Uint8List pixels;
}

class QrImageDecoder {
  QrImageDecoder._();

  // снимок четырёх мониторов 4K весь в памяти изолята, крупнее картинку ужимаем
  static const _maxSide = 8192;

  static Future<String?> fromGray(GrayImage image) =>
      compute(decodeGraySync, image);

  static Future<String?> fromFile(String path) async {
    final bytes = await File(path).readAsBytes();
    return fromEncoded(bytes);
  }

  static Future<String?> fromEncoded(Uint8List bytes) async {
    final gray = await grayFromEncoded(bytes);
    if (gray == null) return null;
    return fromGray(gray);
  }

  // декодирует движок, а значит те же форматы, что Image.file: PNG, JPEG, WebP, BMP, GIF
  static Future<GrayImage?> grayFromEncoded(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final longest = descriptor.width > descriptor.height
        ? descriptor.width
        : descriptor.height;
    final scale = longest > _maxSide ? _maxSide / longest : 1.0;
    final codec = await descriptor.instantiateCodec(
      targetWidth: (descriptor.width * scale).round(),
      targetHeight: (descriptor.height * scale).round(),
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgba == null) return null;
      return GrayImage(
        image.width,
        image.height,
        grayFromRgba(rgba.buffer.asUint8List(), image.width, image.height),
      );
    } finally {
      image.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }

  // та же формула, что RGBLuminanceSource у zxing: (r + 2g + b) / 4
  @visibleForTesting
  static Uint8List grayFromRgba(Uint8List rgba, int width, int height) {
    final out = Uint8List(width * height);
    for (var i = 0, p = 0; i < out.length; i++, p += 4) {
      final alpha = rgba[p + 3];
      // прозрачный фон PNG считаем белым, иначе чёрный код на прозрачном сливался с фоном
      if (alpha < 128) {
        out[i] = 255;
        continue;
      }
      out[i] = (rgba[p] + 2 * rgba[p + 1] + rgba[p + 2]) >> 2;
    }
    return out;
  }

  @visibleForTesting
  static String? decodeGraySync(GrayImage image) {
    final source = _GraySource(image);
    final hints = DecodeHints()..put(DecodeHintType.tryHarder);
    // светлый код на тёмной теме Telegram: zxing ищет только тёмные модули
    for (final candidate in <LuminanceSource>[
      source,
      InvertedLuminanceSource(source),
    ]) {
      for (final binarizer in <Binarizer Function(LuminanceSource)>[
        HybridBinarizer.new,
        GlobalHistogramBinarizer.new,
      ]) {
        try {
          final result = QRCodeReader()
              .decode(BinaryBitmap(binarizer(candidate)), hints: hints);
          final text = restoreByteSegments(
            result.text,
            result.resultMetadata[ResultMetadataType.byteSegments],
          ).trim();
          if (text.isNotEmpty) return text;
        } on ReaderException {
          // дальше следующий способ
        } on ArgumentError {
          // zxing2 кидает и RangeError на обрывке кода у края кадра
        }
      }
    }
    return null;
  }

  // zxing2 0.2.4 отдаёт декодеру байты со знаком (Int8List), и каждый байт за 0x7F становится U+FFFD:
  // кириллица в имени сервера читалась «�����». исходные байты сегментов лежат в метаданных
  @visibleForTesting
  static String restoreByteSegments(String text, Object? segments) {
    if (!text.contains('�') || segments is! List) return text;
    final out = StringBuffer();
    var cursor = 0;
    for (final segment in segments) {
      if (segment is! Int8List) continue;
      final garbled = String.fromCharCodes([
        for (final b in segment) b >= 0 ? b : 0xFFFD,
      ]);
      final at = text.indexOf(garbled, cursor);
      if (at < 0) continue;
      final bytes = Uint8List.view(
        segment.buffer,
        segment.offsetInBytes,
        segment.lengthInBytes,
      );
      String fixed;
      try {
        fixed = utf8.decode(bytes);
      } on FormatException {
        fixed = latin1.decode(bytes);
      }
      out
        ..write(text.substring(cursor, at))
        ..write(fixed);
      cursor = at + garbled.length;
    }
    out.write(text.substring(cursor));
    return out.toString();
  }
}

// PlanarYUVLuminanceSource пакет не экспортирует, а серый кадр и есть плоскость Y
class _GraySource extends LuminanceSource {
  _GraySource(GrayImage image)
      : _data = Int8List.view(
          image.pixels.buffer,
          image.pixels.offsetInBytes,
          image.pixels.lengthInBytes,
        ),
        super(image.width, image.height);

  final Int8List _data;

  @override
  Int8List getRow(int y, Int8List? row) {
    final out = row == null || row.length < width ? Int8List(width) : row;
    out.setRange(0, width, _data, y * width);
    return out;
  }

  @override
  Int8List getMatrix() => _data;
}
