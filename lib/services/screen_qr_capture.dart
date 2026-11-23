import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_logger.dart';
import '../platform/vpn_native_bridge.dart';
import 'qr_image_decoder.dart';

enum ScreenQrResult { found, notFound, failed }

class ScreenQrScan {
  const ScreenQrScan(this.result, [this.text]);

  final ScreenQrResult result;
  final String? text;
}

class ScreenQrCapture {
  ScreenQrCapture._();

  // linux/runner/screen_capture.cc
  @visibleForTesting
  static const linuxChannel = MethodChannel('keqdroid/linux_screen');

  // macos/Runner/MacosPlatformBridge.swift
  @visibleForTesting
  static const macosChannel = MethodChannel('keqdroid/macos_screen');

  static bool? _linuxAvailable;

  static Future<bool> available() async {
    if (Platform.isWindows || Platform.isMacOS) return true;
    if (!Platform.isLinux) return false;
    final known = _linuxAvailable;
    if (known != null) return known;
    var backend = 'none';
    try {
      backend = await linuxChannel.invokeMethod<String>('getBackend') ?? 'none';
    } on MissingPluginException {
      // старый раннер без канала
    } on PlatformException catch (e) {
      AppLogger.instance.warn('Screen capture check failed', error: e);
    }
    AppLogger.instance.info('Screen capture on Linux: $backend');
    return _linuxAvailable = backend != 'none';
  }

  static Future<ScreenQrScan> scan() async {
    final GrayImage? frame;
    try {
      frame = Platform.isWindows
          ? await _captureWindows()
          : Platform.isMacOS
          ? await _captureMacos()
          : await _captureLinux();
    } on PlatformException catch (e) {
      AppLogger.instance.warn('Screen capture for QR failed', error: e);
      return const ScreenQrScan(ScreenQrResult.failed);
    }
    if (frame == null) return const ScreenQrScan(ScreenQrResult.failed);
    final text = await QrImageDecoder.fromGray(frame);
    return text == null
        ? const ScreenQrScan(ScreenQrResult.notFound)
        : ScreenQrScan(ScreenQrResult.found, text);
  }

  // окно прячет и возвращает сам раннер, без анимации DWM
  static Future<GrayImage?> _captureWindows() async {
    final map = await VpnNativeBridge.channel.invokeMapMethod<String, Object?>(
      'captureScreenForQr',
    );
    return frameFromMap(map);
  }

  static Future<GrayImage?> _captureLinux() async {
    final wasVisible = await _windowVisible();
    if (wasVisible) {
      await windowManager.hide();
      // композитору нужен кадр без окна
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    try {
      final map = await linuxChannel.invokeMapMethod<String, Object?>(
        'capture',
      );
      final path = map?['path'];
      if (path is String) return await _readPortalShot(path);
      return frameFromMap(map);
    } finally {
      if (wasVisible) {
        await windowManager.show();
        await windowManager.focus();
      }
    }
  }

  static Future<GrayImage?> _captureMacos() async {
    final wasVisible = await _windowVisible();
    if (wasVisible) {
      await windowManager.hide();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    try {
      final map = await macosChannel.invokeMapMethod<String, Object?>(
        'capture',
      );
      final path = map?['path'];
      if (path is String) return await _readPortalShot(path);
      return frameFromMap(map);
    } finally {
      if (wasVisible) {
        await windowManager.show();
        await windowManager.focus();
      }
    }
  }

  static Future<bool> _windowVisible() async {
    try {
      return await windowManager.isVisible() &&
          !await windowManager.isMinimized();
    } catch (_) {
      return false;
    }
  }

  // снимок портала ложится файлом (у GNOME в «Изображения»), он нужен был только нам
  static Future<GrayImage?> _readPortalShot(String path) async {
    final file = File(path);
    try {
      return await QrImageDecoder.grayFromEncoded(await file.readAsBytes());
    } finally {
      try {
        await file.delete();
      } on FileSystemException catch (e) {
        AppLogger.instance.warn(
          'Could not remove the screenshot $path',
          error: e,
        );
      }
    }
  }

  @visibleForTesting
  static GrayImage? frameFromMap(Map<String, Object?>? map) {
    final width = map?['width'];
    final height = map?['height'];
    final gray = map?['gray'];
    if (width is! int || height is! int || gray is! Uint8List) return null;
    if (width <= 0 || height <= 0 || gray.length != width * height) return null;
    return GrayImage(width, height, gray);
  }
}
