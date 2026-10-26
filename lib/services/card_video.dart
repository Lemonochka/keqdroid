import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import '../models/subscription_card_theme.dart';

// шапки подписок видео: гифку разбирал процессор, ~50% ядра Pixel 6a на потоке io (26.10.2026),
// видео разбирает аппаратный декодер. Кодирует и режет нативная часть, CardMedia.kt
class CardVideo {
  CardVideo._();

  static const _channel = MethodChannel('keqdis_media');

  // у video_player нет реализации для Windows и Linux: там гифка остаётся гифкой
  static bool get supported => Platform.isAndroid;

  static const maxDuration = Duration(seconds: 30);

  // шапка во всю ширину телефона около 1080 px, крупнее декодер работал бы впустую
  static const maxSide = 1280;

  static const extensions = {'.mp4', '.m4v', '.mov', '.webm', '.mkv', '.3gp'};

  /// false: в гифке один кадр, видео из неё не нужно
  static Future<bool> encodeGif(String gifPath, String outPath) async {
    final codec = await ui.instantiateImageCodec(
      await File(gifPath).readAsBytes(),
    );
    try {
      if (codec.frameCount < 2) return false;
      var frame = await codec.getNextFrame();
      final source = frame.image.width;
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      await File(SubscriptionCardTheme.posterFor(outPath))
          .writeAsBytes(png!.buffer.asUint8List(), flush: true);
      final fps = (1e6 / _frameMicros(frame.duration)).round().clamp(5, 60);
      final id = await _channel.invokeMethod<int>('start', {
        'path': outPath,
        // кодировщик H.264 берёт только чётные стороны
        'width': source & ~1,
        'height': frame.image.height & ~1,
        'fps': fps,
      });
      try {
        var pts = 0;
        for (var i = 0; i < codec.frameCount; i++) {
          if (i > 0) frame = await codec.getNextFrame();
          final rgba = await frame.image.toByteData();
          await _channel.invokeMethod<void>('frame', {
            'id': id,
            'rgba': rgba!.buffer.asUint8List(),
            'stride': source * 4,
            'pts': pts,
          });
          pts += _frameMicros(frame.duration);
          frame.image.dispose();
        }
        await _channel.invokeMethod<void>('finish', {'id': id});
        return true;
      } catch (_) {
        await _channel.invokeMethod<void>('cancel', {'id': id});
        rethrow;
      }
    } finally {
      codec.dispose();
    }
  }

  // как в браузерах: кадр короче 20 мс в гифках означает «по умолчанию», 100 мс
  static int _frameMicros(Duration duration) =>
      duration.inMilliseconds < 20 ? 100000 : duration.inMicroseconds;

  static Future<({int width, int height, Duration duration, bool hasVideo})>
      probe(String path) async {
    final info = await _channel.invokeMapMethod<String, Object?>(
      'probe',
      {'path': path},
    );
    return (
      width: info?['width'] as int? ?? 0,
      height: info?['height'] as int? ?? 0,
      duration: Duration(milliseconds: (info?['durationMs'] as num? ?? 0).toInt()),
      hasVideo: info?['hasVideo'] == true,
    );
  }

  /// без звука, не длиннее [maxDuration], длинная сторона не больше [maxSide]
  static Future<void> transcode({
    required String input,
    required String output,
    required int width,
    required int height,
  }) async {
    final scale = min(1.0, maxSide / max(width, height));
    await _channel.invokeMethod<bool>('transcode', {
      'input': input,
      'output': output,
      'maxMs': maxDuration.inMilliseconds,
      'width': (width * scale).round() & ~1,
      'height': (height * scale).round() & ~1,
    });
    final posted = await _channel.invokeMethod<bool>('poster', {
      'path': output,
      'out': SubscriptionCardTheme.posterFor(output),
    });
    if (posted != true) throw Exception('No video frame in $input');
  }
}
