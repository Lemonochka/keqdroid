# Windows tunnel architecture

## Cores

| Mode | Processes | Purpose |
|------|-----------|---------|
| **Proxy** | `xray.exe` only | All subscription protocols via Xray; Chrome/Edge use Windows system proxy; Firefox gets `user.js` HTTP proxy (restart Firefox after connect) |
| **TUN** | `xray.exe` → `sing-box.exe` | sing-box owns TUN; upstream is Xray SOCKS5 |

sing-box outbound `proxy` points to `127.0.0.1:<localPort>` with the same SOCKS5 username/password as in the generated Xray inbound.

## Dart layout

- `lib/tunnel/` — `TunnelBackend`, Android/Windows implementations
- `lib/utils/singbox_tun_config.dart` — TUN JSON for sing-box
- `lib/services/tunnel_session_builder.dart` — builds `TunnelSessionRequest`
- `lib/services/vpn_engine.dart` — facade used by UI

## Native (Windows)

- `windows/runner/tunnel_channel_handler.cpp` — system proxy via `INTERNET_OPTION_PER_CONNECTION_OPTION` (fills `DefaultConnectionSettings` for the Settings UI) plus `ProxyServer` `http=;https=;socks=` for Chromium; WinHTTP import; elevation check for TUN

## Next milestones

1. Tray icon, autostart, MSI updates
2. Background subscription refresh (Task Scheduler or in-app timer)
3. Live VPN telemetry on Windows (optional stats channel)

See [WINDOWS_ANDROID_PARITY.md](WINDOWS_ANDROID_PARITY.md) for the full matrix.
