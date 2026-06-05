import 'dart:io';

import 'android_tunnel_backend.dart';
import 'tunnel_backend.dart';
import 'windows_tunnel_backend.dart';

TunnelBackend createTunnelBackend() {
  if (Platform.isAndroid) return AndroidTunnelBackend();
  if (Platform.isWindows) return WindowsTunnelBackend();
  throw UnsupportedError(
    'Tunnel backend is not implemented for ${Platform.operatingSystem}',
  );
}
