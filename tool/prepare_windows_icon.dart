// icon_windows_launcher.png из icon_foreground.png: обрезка полей, прозрачность,
// лого почти на весь квадрат (иначе в таскбаре windows иконка мелкая).
// dart run tool/prepare_windows_icon.dart
// dart run flutter_launcher_icons

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const _size = 1024;
/// доля квадрата под лого (как у типичных windows-иконок)
const _fill = 0.92;

void main() {
  final srcFile = File('assets/icon_foreground.png');
  if (!srcFile.existsSync()) {
    stderr.writeln('Missing ${srcFile.path}');
    exit(1);
  }

  final decoded = img.decodeImage(srcFile.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('Failed to decode icon_foreground.png');
    exit(1);
  }

  final rgba = decoded.hasAlpha
      ? decoded
      : _dropBlackBackground(decoded);

  final bounds = _contentBounds(rgba);
  if (bounds == null) {
    stderr.writeln('No visible pixels in icon_foreground.png');
    exit(1);
  }

  final cropped = img.copyCrop(
    rgba,
    x: bounds.left,
    y: bounds.top,
    width: bounds.width,
    height: bounds.height,
  );

  final canvas = img.Image(width: _size, height: _size, numChannels: 4);
  final target = (_size * _fill).round();
  final scale = target / math.max(cropped.width, cropped.height);
  final w = (cropped.width * scale).round().clamp(1, _size);
  final h = (cropped.height * scale).round().clamp(1, _size);
  final resized = img.copyResize(
    cropped,
    width: w,
    height: h,
    interpolation: img.Interpolation.cubic,
  );

  final x = (_size - w) ~/ 2;
  final y = (_size - h) ~/ 2;
  img.compositeImage(
    canvas,
    resized,
    dstX: x,
    dstY: y,
    blend: img.BlendMode.alpha,
  );

  final out = File('assets/icon_windows_launcher.png');
  out.writeAsBytesSync(img.encodePng(canvas));

  final fillPct = (bounds.width / rgba.width * 100).toStringAsFixed(0);
  stdout.writeln(
    'Source content used $fillPct% of canvas before trim; '
    'output ${_size}x$_size at ${(_fill * 100).round()}% fill.',
  );
  stdout.writeln('Wrote ${out.path}');
}

img.Image _dropBlackBackground(img.Image src) {
  final out = img.Image(width: src.width, height: src.height, numChannels: 4);
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      if (r < 8 && g < 8 && b < 8) {
        out.setPixelRgba(x, y, 0, 0, 0, 0);
      } else {
        out.setPixelRgba(x, y, r, g, b, 255);
      }
    }
  }
  return out;
}

class _Bounds {
  _Bounds(this.left, this.top, this.width, this.height);
  final int left;
  final int top;
  final int width;
  final int height;
}

_Bounds? _contentBounds(img.Image image) {
  var minX = image.width;
  var minY = image.height;
  var maxX = 0;
  var maxY = 0;
  var found = false;

  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (image.getPixel(x, y).a.toInt() < 16) continue;
      found = true;
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
    }
  }
  if (!found) return null;
  return _Bounds(minX, minY, maxX - minX + 1, maxY - minY + 1);
}
