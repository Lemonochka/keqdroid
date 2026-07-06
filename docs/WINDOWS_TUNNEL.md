# Туннель на Windows

## Процессы по режимам

| Режим | Процессы (дефолт, `coreEngine: keqrnel`) | Что происходит |
|-------|------------------------------------------|----------------|
| **Proxy** | `keqrnel.exe` | ядро поднимает локальный SOCKS/HTTP; Chrome/Edge идут через системный прокси Windows, Firefox — через правку `user.js` (`firefox_proxy_helper`, нужен его перезапуск после подключения) |
| **TUN** | `keqrnel.exe` | ядро создаёт wintun-адаптер и само же терминирует протокол встроенным xray-движком — один процесс на всё |

С `coreEngine: chain` вместо keqrnel работает классическая связка `xray.exe` →
`sing-box.exe`: sing-box владеет TUN-устройством, его `proxy`-outbound смотрит на
`127.0.0.1:<localPort>` с кредами SOCKS-инбаунда из сгенерированного xray-конфига.
В поставку эти два бинарника **не входят** — chain на Windows заработает, только если
положить их рядом с приложением (см. [`assets/bin/windows/README.md`](../assets/bin/windows/README.md)).

AmneziaWG (`VpnBackend.awg`) идёт мимо обоих вариантов: в Proxy его обслуживает
`wireproxy.exe`, в TUN ядро само владеет адаптером.

## Где код

- `lib/tunnel/windows_tunnel_backend.dart` — реализация `TunnelBackend`: спавн процессов,
  ожидание готовности, статистика;
- `lib/tunnel/windows_core_paths.dart` — резолв путей к ядрам/geo (рядом с exe);
- `lib/utils/singbox_tun_config.dart` — sing-box TUN-JSON;
- `lib/utils/keqrnel_config.dart` — склейка sing-box-конфига со встроенным xray;
- `lib/services/tunnel_session_builder.dart` — сборка `TunnelSessionRequest`;
- `lib/services/vpn_engine.dart` — фасад, с которым говорит UI.

## Нативная часть (`windows/runner/`)

`tunnel_channel_handler.cpp` ставит системный прокси через
`INTERNET_OPTION_PER_CONNECTION_OPTION`: заполняет `DefaultConnectionSettings` (чтобы
прокси был виден на странице настроек Windows), выставляет `ProxyServer`
(`http=;https=;socks=`) для Chromium, импортирует конфиг в WinHTTP и проверяет elevation
перед стартом TUN. Жизненный цикл процессов ядра — `windows_core_lifecycle.cpp`, счётчики
трафика адаптера — `windows_traffic_stats.cpp`.

Статистика в Proxy-режиме берётся не с адаптера, а из xray StatsService API на
`127.0.0.1:10985` (`lib/tunnel/xray_session_stats.dart`).

Сопоставление с Android — в [WINDOWS_ANDROID_PARITY.md](WINDOWS_ANDROID_PARITY.md).
