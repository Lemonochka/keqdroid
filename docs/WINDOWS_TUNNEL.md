# Windows tunnel architecture

## Cores

| Mode | Processes | What happens |
|------|-----------|--------------|
| Proxy | `xray.exe` | Everything goes through Xray. Chrome and Edge follow the Windows system proxy; Firefox gets an HTTP proxy through `user.js` (restart it after connecting). |
| TUN | `xray.exe` → `sing-box.exe` | sing-box owns the TUN device and uses Xray's SOCKS5 as its upstream. |

In TUN mode the sing-box `proxy` outbound points at `127.0.0.1:<localPort>` and
reuses the SOCKS5 username and password from the generated Xray inbound.

## Where the code lives

- `lib/tunnel/` — `TunnelBackend` and the Android/Windows implementations
- `lib/utils/singbox_tun_config.dart` — builds the sing-box TUN JSON
- `lib/services/tunnel_session_builder.dart` — builds `TunnelSessionRequest`
- `lib/services/vpn_engine.dart` — the facade the UI talks to

## Native (Windows)

`windows/runner/tunnel_channel_handler.cpp` sets the system proxy via
`INTERNET_OPTION_PER_CONNECTION_OPTION`. It fills `DefaultConnectionSettings` so
the Windows Settings page shows the proxy, sets `ProxyServer`
(`http=;https=;socks=`) for Chromium, imports the WinHTTP config, and checks for
elevation before starting TUN.

For how this lines up with the Android side, see WINDOWS_ANDROID_PARITY.md.
