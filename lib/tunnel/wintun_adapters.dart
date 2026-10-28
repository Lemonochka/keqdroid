import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../utils/desktop_tun.dart';

const kTunFallbackInterfaceName = 'tun-keqdis2';

// wintun делает из GUID ID устройства. 27.10.2026 Windows раз за разом отказывала одному GUID xray, а GUID mihomo пускала
String xrayTunNameForAttempt(int attempt) =>
    attempt == 1 ? kTunInterfaceName : kTunFallbackInterfaceName;

// GUID у xray это MD5 имени (proxy/tun/tun_windows.go), у sing-tun в mihomo MD5 от wintun и имени
String xrayWintunInstanceId(String name) =>
    _instanceId(md5.convert(utf8.encode(name)).bytes);

String mihomoWintunInstanceId(String name) =>
    _instanceId(md5.convert(utf8.encode('wintun$name')).bytes);

List<String> ourWintunInstanceIds() => [
  xrayWintunInstanceId(kTunInterfaceName),
  xrayWintunInstanceId(kTunFallbackInterfaceName),
  mihomoWintunInstanceId(kTunInterfaceName),
];

// ядра кладут windows.GUID прямо на байты MD5, и первые три поля читаются little-endian
String _instanceId(List<int> b) {
  String hex(Iterable<int> bytes) => bytes
      .map((x) => x.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
  return 'SWD\\Wintun\\{${hex(b.sublist(0, 4).reversed)}-'
      '${hex(b.sublist(4, 6).reversed)}-${hex(b.sublist(6, 8).reversed)}-'
      '${hex(b.sublist(8, 10))}-${hex(b.sublist(10, 16))}}';
}
