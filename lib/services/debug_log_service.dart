import 'dart:io';

import 'package:flutter/services.dart';

import '../tunnel/windows_tunnel_backend.dart';

class DebugLogService {
  DebugLogService._();

  static const MethodChannel _channel = MethodChannel('keqdis_vpn_channel');

  static Future<String> getXrayLogs({int maxLines = 300}) async {
    if (Platform.isWindows) {
      final backend = WindowsTunnelBackend.activeInstance;
      if (backend != null) {
        final text = backend.exportSessionLogs(maxLines: maxLines);
        if (text.trim().isNotEmpty) return text;
      }
      return 'No Xray session logs yet. Connect VPN first.';
    }
    final text = await _channel.invokeMethod<String>('getXrayLogs', {
      'maxLines': maxLines,
    });
    return text ?? '';
  }

  /// Windows: WinINet/registry proxy diagnostics (also written to %TEMP% file).
  static Future<String> getProxyDebugLogs({int maxLines = 400}) async {
    if (!Platform.isWindows) {
      return 'Proxy debug logs are only available on Windows.';
    }
    final text = await _channel.invokeMethod<String>('getProxyDebugLogs', {
      'maxLines': maxLines,
    });
    return text ?? '';
  }

  static Future<String> getProxyDebugLogPath() async {
    if (!Platform.isWindows) {
      return '';
    }
    final path = await _channel.invokeMethod<String>('getProxyDebugLogPath');
    return path ?? '';
  }

  static Future<void> clearProxyDebugLogs() async {
    if (!Platform.isWindows) return;
    await _channel.invokeMethod<void>('clearProxyDebugLogs');
  }
}
