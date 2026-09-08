import 'dart:io';

/// Есть ли у машины рабочий глобальный IPv6.
///
/// Нужно ровно одному решению: заводить ли IPv6 на TUN-интерфейсе. Ставить его
/// всем подряд нельзя — на машине с выключенным в реестре IPv6 sing-box падает
/// на настройке адаптера («set ipv6 dns: Access is denied»), и TUN не
/// поднимается вовсе. Не ставить никому тоже нельзя: без адреса ядро не берёт
/// IPv6-маршруты, и весь IPv6-трафик идёт мимо туннеля — то есть утекает.
///
/// Считаем только глобальные адреса. Link-local (`fe80::/10`) есть всегда, даже
/// когда IPv6 наружу не ходит; за ULA (`fc00::/7`) нет интернета; Teredo и 6to4
/// — туннели поверх IPv4, Windows заводит их сама, и глобальными они по сути не
/// являются. Свой TUN-интерфейс, если он жив с прошлой сессии, тоже не в счёт.
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
