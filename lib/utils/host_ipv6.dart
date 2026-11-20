import 'dart:io';

// без IPv6 на TUN весь IPv6-трафик утекает мимо туннеля, а при выключенном IPv6 ядро не поднимает TUN с IPv6-адресом;
// считаем только глобальные: fe80 есть всегда, за ULA нет интернета, Teredo и 6to4 сами туннели поверх IPv4
Future<bool> hostHasGlobalIpv6({String? excludeInterfaceName}) async {
  try {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: InternetAddressType.IPv6,
    );
    for (final iface in interfaces) {
      if (excludeInterfaceName != null && iface.name == excludeInterfaceName) {
        continue;
      }
      final lowerName = iface.name.toLowerCase();
      if (lowerName.contains('teredo') || lowerName.contains('isatap')) {
        continue;
      }
      for (final addr in iface.addresses) {
        if (isGlobalIpv6(addr.address)) return true;
      }
    }
  } catch (_) {
    // не перечислилось, считаем что IPv6 нет: лишний адрес на адаптере опаснее пропущенной утечки
  }
  return false;
}

bool isGlobalIpv6(String raw) {
  final address = raw.split('%').first.trim().toLowerCase();
  if (address.isEmpty || !address.contains(':')) return false;
  if (address == '::1' || address == '::') return false;
  if (address.startsWith('fe80')) return false; // link-local
  // ULA: fc00::/7, то есть fc.. и fd..
  if (address.startsWith('fc') || address.startsWith('fd')) return false;
  if (address.startsWith('2002:')) return false; // 6to4
  if (address.startsWith('2001:0:') || address.startsWith('2001::')) {
    return false; // Teredo
  }
  return true;
}
