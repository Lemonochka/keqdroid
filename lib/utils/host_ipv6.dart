import 'dart:io';

/// Есть ли у машины РАБОЧИЙ глобальный IPv6.
///
/// Нужно ровно одному решению: заводить ли IPv6 на TUN-интерфейсе. Ставить его
/// всем подряд нельзя — на машине с выключенным в реестре IPv6 sing-box падает
/// на настройке адаптера («set ipv6 dns: Access is denied»), и TUN не
/// поднимается вовсе. Не ставить никому тоже нельзя: без адреса ядро не берёт
/// IPv6-маршруты, и весь IPv6-трафик идёт МИМО туннеля — то есть утекает.
///
/// Считаем только глобальные адреса. Отдельно выброшены:
///  * link-local (`fe80::/10`) — есть всегда, даже когда IPv6 наружу не ходит;
///  * ULA (`fc00::/7`) — адрес локальной сети, интернета за ним нет;
///  * Teredo (`2001:0::/32`) и 6to4 (`2002::/16`) — туннели поверх IPv4, у
///    Windows они появляются сами и глобальными по сути не являются;
///  * наш собственный TUN-интерфейс, если он ещё жив от прошлой сессии.
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
    // Перечисление интерфейсов не удалось — считаем, что IPv6 нет: лишний
    // адрес на адаптере опаснее пропущенной утечки.
  }
  return false;
}

/// Глобальный ли это IPv6-адрес (см. оговорки в [hostHasGlobalIpv6]).
bool isGlobalIpv6(String raw) {
  final address = raw.split('%').first.trim().toLowerCase();
  if (address.isEmpty || !address.contains(':')) return false;
  if (address == '::1' || address == '::') return false;
  if (address.startsWith('fe80')) return false; // link-local
  // ULA: fc00::/7 — это fc.. и fd..
  if (address.startsWith('fc') || address.startsWith('fd')) return false;
  if (address.startsWith('2002:')) return false; // 6to4
  if (address.startsWith('2001:0:') || address.startsWith('2001::')) {
    return false; // Teredo
  }
  return true;
}
