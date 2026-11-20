import '../tunnel/app_routing_mode.dart';

// так мост отвечает ядру, когда Android назвал соединение чужим для нашего VPN (INVALID_UID), то есть приложение
// вне VPN привязалось к tun0; то же имя в ConnectionOwnerServer.kt и tool/patches/mihomo-uid-owner-guard.patch
const kOutsideVpnOwner = 'keqdroid:outside-vpn';

// DNS самого Android в режиме только выбранные тоже приходит без владельца: его мост узнаёт по адресу и маркером не называет
enum OwnerGuard { off, all }

// Без сплита вне VPN никого нет, а сокет, привязанный к tun0, Android не находит и у своих, и защита резала бы их.
// Версия неизвестна, когда канал без окна молчит; тогда защита остаётся, ниже 10-й мост всё равно ответит пусто
OwnerGuard ownerGuardFor({
  required bool android,
  required bool tun,
  required AppRoutingMode routingMode,
  required int? sdkInt,
}) =>
    android &&
            tun &&
            routingMode != AppRoutingMode.allProxy &&
            (sdkInt ?? 29) >= 29
        ? OwnerGuard.all
        : OwnerGuard.off;
