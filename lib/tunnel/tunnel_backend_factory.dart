import 'dart:io';

import 'android_tunnel_backend.dart';
import 'linux_tunnel_backend.dart';
import 'tunnel_backend.dart';
import 'windows_tunnel_backend.dart';

TunnelBackend createTunnelBackend() {
  if (Platform.isAndroid) return AndroidTunnelBackend();
  if (Platform.isWindows) return WindowsTunnelBackend();
  if (Platform.isLinux) return LinuxTunnelBackend();
  throw UnsupportedError(
    'Tunnel backend is not implemented for ${Platform.operatingSystem}',
  );
}
