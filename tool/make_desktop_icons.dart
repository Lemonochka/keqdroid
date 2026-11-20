// значки ПК из assets/icon_windows_launcher.png: exe на Windows, трей обычный и с зелёной точкой подключения, png для Linux
// в ico кадр на каждый масштаб экрана: из одного кадра 256 Windows ужимала до 16 сама, края рвались
// flutter_launcher_icons кладёт в ico один кадр, поэтому exe рисуем здесь, а не им
// dart run tool/make_desktop_icons.dart

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

// SM_CXSMICON на масштабах 100-300%, 64 и 256 для крупных значков оболочки
const _traySizes = [16, 20, 24, 28, 32, 40, 48, 64, 256];
// плюс панель задач (24 x масштаб) и крупные виды проводника
const _appSizes = [
  16, 20, 24, 28, 30, 32, 36, 40, 42, 48, 56, 64, 72, 96, 128, 256, //
];
const _pngSize = 256;

const _dotDiameter = 0.40;
const _gap = 0.07;
const _green = (r: 0x3D, g: 0xB8, b: 0x6B);

void main() {
  final decoded = img.decodePng(
    File('assets/icon_windows_launcher.png').readAsBytesSync(),
  );
  if (decoded == null) {
    stderr.writeln('Failed to decode assets/icon_windows_launcher.png');
    exit(1);
  }
  final src = _Premultiplied(decoded);
  final frames = {
    for (final s in {..._traySizes, ..._appSizes}) s: src.shrink(s),
  };

  final plain = [for (final s in _traySizes) frames[s]!];
  final connected = [for (final frame in plain) withDot(frame)];
  final png = _traySizes.indexOf(_pngSize);

  File('assets/icon.png').writeAsBytesSync(img.encodePng(plain[png]));
  File(
    'assets/icon_connected.png',
  ).writeAsBytesSync(img.encodePng(connected[png]));
  File(
    'assets/tray_icon.ico',
  ).writeAsBytesSync(img.IcoEncoder().encodeImages(plain));
  File(
    'assets/tray_icon_connected.ico',
  ).writeAsBytesSync(img.IcoEncoder().encodeImages(connected));
  File('windows/runner/resources/app_icon.ico').writeAsBytesSync(
    img.IcoEncoder().encodeImages([for (final s in _appSizes) frames[s]!]),
  );
  stdout.writeln(
    'Wrote icon.png, icon_connected.png, tray_icon.ico, '
    'tray_icon_connected.ico (${_traySizes.join(', ')}), '
    'app_icon.ico (${_appSizes.join(', ')})',
  );
}

// усреднение по площади с премультиплицированной альфой: иначе прозрачный фон темнит края штриха
class _Premultiplied {
  _Premultiplied(img.Image image)
    : width = image.width,
      height = image.height,
      _rgba = Float64List(image.width * image.height * 4) {
    var i = 0;
    for (final p in image.convert(numChannels: 4)) {
      final a = p.a / 255;
      _rgba[i++] = p.r * a;
      _rgba[i++] = p.g * a;
      _rgba[i++] = p.b * a;
      _rgba[i++] = a;
    }
  }

  final int width;
  final int height;
  final Float64List _rgba;

  img.Image shrink(int size) {
    final out = img.Image(width: size, height: size, numChannels: 4);
    final sx = width / size;
    final sy = height / size;
    for (var ty = 0; ty < size; ty++) {
      final y0 = ty * sy;
      final y1 = y0 + sy;
      for (var tx = 0; tx < size; tx++) {
        final x0 = tx * sx;
        final x1 = x0 + sx;
        var r = 0.0, g = 0.0, b = 0.0, a = 0.0, area = 0.0;
        for (var y = y0.floor(); y < y1.ceil(); y++) {
          final wy = math.min(y1, y + 1) - math.max(y0, y.toDouble());
          for (var x = x0.floor(); x < x1.ceil(); x++) {
            final w = wy * (math.min(x1, x + 1) - math.max(x0, x.toDouble()));
            final i = (y * width + x) * 4;
            r += _rgba[i] * w;
            g += _rgba[i + 1] * w;
            b += _rgba[i + 2] * w;
            a += _rgba[i + 3] * w;
            area += w;
          }
        }
        if (a == 0) continue;
        out.setPixelRgba(
          tx,
          ty,
          (r / a).round(),
          (g / a).round(),
          (b / a).round(),
          (a / area * 255).round(),
        );
      }
    }
    return out;
  }
}

img.Image withDot(img.Image src) {
  final out = img.Image.from(src);
  final size = out.width;
  final r = size * _dotDiameter / 2;
  final cut = r + size * _gap;
  final c = size - r;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final d = math.sqrt(math.pow(x + 0.5 - c, 2) + math.pow(y + 0.5 - c, 2));
      final erase = (cut - d + 0.5).clamp(0.0, 1.0);
      if (erase == 0) continue;
      final dot = (r - d + 0.5).clamp(0.0, 1.0);
      final p = out.getPixel(x, y);
      final under = p.a / 255 * (1 - erase);
      final alpha = dot + under * (1 - dot);
      if (alpha == 0) {
        out.setPixelRgba(x, y, 0, 0, 0, 0);
        continue;
      }
      int mix(int dotChannel, num own) =>
          ((dotChannel * dot + own * under * (1 - dot)) / alpha).round();
      out.setPixelRgba(
        x,
        y,
        mix(_green.r, p.r),
        mix(_green.g, p.g),
        mix(_green.b, p.b),
        (alpha * 255).round(),
      );
    }
  }
  return out;
}
