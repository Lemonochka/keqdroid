# Документация keqdroid (KEQDIS)

Если проект для тебя новый — читай сверху вниз:

| Документ | О чём |
|----------|-------|
| [ONBOARDING.md](ONBOARDING.md) | окружение, сборка, запуск и тесты по каждой платформе |
| [ARCHITECTURE.md](ARCHITECTURE.md) | слои, поток данных, ядра, генерация конфигов, путь от кнопки «Подключить» до туннеля |
| [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) | карта репозитория: где что лежит |
| [GLOSSARY.md](GLOSSARY.md) | термины: протоколы, Proxy/TUN, xray/sing-box/keqrnel, подписки, маршрутизация |
| [PITFALLS.md](PITFALLS.md) | грабли: кодировки, Defender, кэши Kotlin, SHA-256, трей |
| [WINDOWS_TUNNEL.md](WINDOWS_TUNNEL.md) | как устроен туннель на Windows |
| [WINDOWS_ANDROID_PARITY.md](WINDOWS_ANDROID_PARITY.md) | чем Android и Windows отличаются и почему это намеренно |

**keqdroid** (бренд KEQDIS) — клиент прокси/VPN на Flutter для Android, Windows и Linux:
подписки и ручные конфиги (VLESS / VMess / Trojan / Shadowsocks / Hysteria2 / AmneziaWG),
пинг и спидтест серверов, маршрутизация, split tunneling, kill switch, автообновление из
GitHub Releases.

Dart-слой — это UI и оркестрация: он генерирует JSON-конфиги и управляет **нативными
ядрами** (`keqrnel`, `xray`, `sing-box`, `wireproxy`), которые и гоняют трафик. Серверов
приложение не предоставляет — пользователь приносит свои подписки.

Пользовательское описание фич — в корневом [README.md](../README.md).
